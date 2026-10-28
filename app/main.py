"""Spatial Disease Modeling with R (GHS): run parameterised Jupyter (R or Python) notebooks on a server and
serve the geospatial results (GeoJSON, heat-point JSON, GeoTIFF, HTML report) to a map viewer."""
import json, os, re, shutil, subprocess, sys, tempfile, threading, time, uuid, zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import nbformat
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

HOME = Path(os.environ.get("GEOEPI_HOME", "/srv/geoepi"))
DATA_DIR = Path(os.environ.get("GEOEPI_DATA", HOME / "data"))
JOBS_DIR = Path(os.environ.get("GEOEPI_JOBS", HOME / "jobs"))
NOTEBOOK_DIR = Path(os.environ.get("GEOEPI_NOTEBOOKS", Path(__file__).resolve().parent.parent / "notebooks"))
JOB_TIMEOUT = int(os.environ.get("JOB_TIMEOUT", 3600))      # whole notebook, seconds
CELL_TIMEOUT = int(os.environ.get("CELL_TIMEOUT", 1800))    # one cell, seconds
JOB_WORKERS = int(os.environ.get("JOB_WORKERS", 1))
MAX_UPLOAD_MB = int(os.environ.get("MAX_UPLOAD_MB", 500))
MAX_UNZIPPED_MB = int(os.environ.get("MAX_UNZIPPED_MB", 2000))
SAFE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,80}$")

for d in (DATA_DIR, JOBS_DIR):
    d.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Spatial Disease Modeling with R (GHS)")
pool = ThreadPoolExecutor(max_workers=JOB_WORKERS)
lock = threading.Lock()


# ---------- helpers ----------
def _check(name: str, what: str) -> str:
    if not SAFE.match(name or ""):
        raise HTTPException(400, f"Invalid {what} name")
    return name


def notebooks() -> list[dict]:
    out = []
    for p in sorted(NOTEBOOK_DIR.glob("*.ipynb")):
        nb = nbformat.read(p, as_version=4)
        title = p.stem
        for c in nb.cells:
            m = re.match(r"\s*#\s+(.+)", c.source) if c.cell_type == "markdown" else None
            if m:
                title = m.group(1).strip()
                break
        meta = {}
        if p.with_suffix(".json").exists():
            meta = json.loads(p.with_suffix(".json").read_text())
        out.append({"id": p.stem, "title": meta.get("title", title), "module": meta.get("module"),
                    "about": meta.get("about", ""), "requires": meta.get("requires", []),
                    "default_dataset": meta.get("default_dataset"), "handoff": meta.get("handoff", False),
                    "kernel": nb.metadata.get("kernelspec", {}).get("display_name", "?")})
    return out


def missing_files(ds: Path, requires: list[str]) -> list[str]:
    """Required names/globs not found anywhere under the dataset (handles one extra top folder)."""
    rel = [str(f.relative_to(ds)) for f in ds.rglob("*") if f.is_file()]
    miss = []
    for r in requires:
        pat = r if "*" in r else r
        if not any(Path(x).match(pat) or x.endswith("/" + r) or x == r for x in rel):
            miss.append(r)
    return miss


def datasets(notebook: str | None = None) -> list[dict]:
    req = []
    if notebook:
        req = next((n["requires"] for n in notebooks() if n["id"] == notebook), [])
    out = []
    for p in sorted(DATA_DIR.iterdir()):
        if p.is_dir() and SAFE.match(p.name):
            d = {"id": p.name, "files": sum(1 for f in p.rglob("*") if f.is_file())}
            if notebook:
                d["missing"] = missing_files(p, req)
            out.append(d)
    return out


def _job_path(job_id: str) -> Path:
    _check(job_id, "job")
    p = JOBS_DIR / job_id
    if not (p / "job.json").exists():
        raise HTTPException(404, "Job not found")
    return p


def _read(p: Path) -> dict:
    return json.loads((p / "job.json").read_text())


def _write(p: Path, job: dict):
    with lock:
        tmp = p / "job.json.tmp"
        tmp.write_text(json.dumps(job, indent=1))
        tmp.replace(p / "job.json")


def _outputs(p: Path) -> list[dict]:
    out = p / "outputs"
    if not out.exists():
        return []
    return [{"name": str(f.relative_to(out)), "bytes": f.stat().st_size}
            for f in sorted(out.rglob("*")) if f.is_file()]


# ---------- the runner ----------
def run_job(job_id: str):
    p = JOBS_DIR / job_id
    job = _read(p)
    job.update(status="running", started=time.time())
    _write(p, job)
    out_dir = p / "outputs"
    out_dir.mkdir(exist_ok=True)
    nb_path = NOTEBOOK_DIR / f"{job['notebook']}.ipynb"
    executed = p / "executed.ipynb"
    cmd = [sys.executable, "-m", "papermill", str(nb_path), str(executed),
           "-p", "data_dir", str(DATA_DIR / job["dataset"]),
           "-p", "out_dir", str(out_dir),
           "--cwd", str(p), "--execution-timeout", str(CELL_TIMEOUT),
           "--log-output", "--progress-bar"]
    try:
        with open(p / "run.log", "w") as log:
            r = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=JOB_TIMEOUT)
        ok = r.returncode == 0
        err = None if ok else f"Notebook failed (exit {r.returncode}); open the report or log"
    except subprocess.TimeoutExpired:
        ok, err = False, f"Timed out after {JOB_TIMEOUT} s"
    if executed.exists():  # build the report even if the run failed, so the error is visible
        subprocess.run([sys.executable, "-m", "jupyter", "nbconvert", "--to", "html",
                        "--output", "report.html", "--output-dir", str(out_dir), str(executed)],
                       capture_output=True, timeout=600)
    job.update(status="done" if ok else "failed", error=err, finished=time.time())
    _write(p, job)


@app.on_event("startup")
def recover():
    for p in JOBS_DIR.iterdir():
        if (p / "job.json").exists():
            j = _read(p)
            if j["status"] == "running":
                j.update(status="failed", error="Server restarted during the run")
                _write(p, j)
            elif j["status"] == "queued":
                pool.submit(run_job, p.name)


# ---------- API ----------
class JobIn(BaseModel):
    notebook: str
    dataset: str


@app.get("/api/notebooks")
def api_notebooks():
    return notebooks()


@app.get("/api/datasets")
def api_datasets(notebook: str | None = None):
    return datasets(notebook)


@app.post("/api/datasets")
async def upload_dataset(name: str = Form(...), file: UploadFile = File(...)):
    _check(name, "dataset")
    dest = DATA_DIR / name
    if dest.exists():
        raise HTTPException(409, "A dataset with that name already exists")
    if not (file.filename or "").lower().endswith(".zip"):
        raise HTTPException(400, "Upload a .zip file")
    with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as tmp:
        size = 0
        while chunk := await file.read(1 << 20):
            size += len(chunk)
            if size > MAX_UPLOAD_MB << 20:
                os.unlink(tmp.name)
                raise HTTPException(413, f"Larger than {MAX_UPLOAD_MB} MB")
            tmp.write(chunk)
    stage = None
    try:
        with zipfile.ZipFile(tmp.name) as z:
            if sum(i.file_size for i in z.infolist()) > MAX_UNZIPPED_MB << 20:
                raise HTTPException(413, "Unzipped size too large")
            stage = Path(tempfile.mkdtemp(dir=DATA_DIR, prefix=".incoming-"))
            root = stage.resolve()
            for i in z.infolist():  # block path traversal (zip-slip)
                target = (stage / i.filename).resolve()
                if root != target and root not in target.parents:
                    raise HTTPException(400, "Unsafe path inside zip")
            z.extractall(stage)
        entries = [e for e in stage.iterdir() if e.name != "__MACOSX"]
        src = entries[0] if len(entries) == 1 and entries[0].is_dir() else stage
        shutil.move(str(src), dest)  # flatten a single top-level folder
    except zipfile.BadZipFile:
        raise HTTPException(400, "Not a valid zip file")
    finally:
        os.unlink(tmp.name)
        if stage:
            shutil.rmtree(stage, ignore_errors=True)
    return {"id": name}


@app.post("/api/jobs", status_code=202)
def create_job(body: JobIn):
    _check(body.notebook, "notebook")
    _check(body.dataset, "dataset")
    if not (NOTEBOOK_DIR / f"{body.notebook}.ipynb").exists():
        raise HTTPException(404, "Unknown notebook")
    if not (DATA_DIR / body.dataset).is_dir():
        raise HTTPException(404, "Unknown dataset")
    req = next((n["requires"] for n in notebooks() if n["id"] == body.notebook), [])
    miss = missing_files(DATA_DIR / body.dataset, req)
    if miss:
        raise HTTPException(422, "Dataset is missing: " + ", ".join(miss))
    job_id = uuid.uuid4().hex[:12]
    p = JOBS_DIR / job_id
    p.mkdir()
    job = {"id": job_id, "notebook": body.notebook, "dataset": body.dataset,
           "status": "queued", "created": time.time(), "error": None}
    _write(p, job)
    pool.submit(run_job, job_id)
    return job


@app.get("/api/jobs")
def list_jobs():
    jobs = [_read(p) for p in JOBS_DIR.iterdir() if (p / "job.json").exists()]
    return sorted(jobs, key=lambda j: j["created"], reverse=True)[:50]


def _progress(p: Path):
    f = p / "run.log"
    if not f.exists():
        return None
    with open(f, "rb") as fh:
        fh.seek(max(0, f.stat().st_size - 4000))
        m = re.findall(r"(\d+)/(\d+) \[", fh.read().decode("utf-8", "ignore"))
    return {"done": int(m[-1][0]), "total": int(m[-1][1])} if m else None


@app.get("/api/jobs/{job_id}")
def get_job(job_id: str):
    p = _job_path(job_id)
    return {**_read(p), "files": _outputs(p), "progress": _progress(p)}


class FromJob(BaseModel):
    job_id: str
    name: str


@app.post("/api/datasets/from-job")
def dataset_from_job(body: FromJob):
    """Chain modules: turn a finished run's outputs/handoff/ folder into a dataset."""
    _check(body.name, "dataset")
    src = _job_path(body.job_id) / "outputs" / "handoff"
    if not src.is_dir():
        raise HTTPException(404, "This run has no hand-off folder")
    dest = DATA_DIR / body.name
    if dest.exists():
        raise HTTPException(409, "A dataset with that name already exists")
    shutil.copytree(src, dest)
    return {"id": body.name}


@app.get("/api/jobs/{job_id}/log")
def get_log(job_id: str):
    f = _job_path(job_id) / "run.log"
    return FileResponse(f, media_type="text/plain") if f.exists() else {"log": ""}


@app.get("/api/jobs/{job_id}/download.zip")
def download(job_id: str):
    p = _job_path(job_id)
    base = Path(tempfile.mkdtemp()) / f"geoepi_{job_id}"
    return FileResponse(shutil.make_archive(str(base), "zip", p / "outputs"),
                        filename=f"geoepi_{job_id}.zip")


@app.get("/results/{job_id}/{path:path}")
def result_file(job_id: str, path: str):
    out = (_job_path(job_id) / "outputs").resolve()
    f = (out / path).resolve()
    if out not in f.parents or not f.is_file():
        raise HTTPException(404)
    return FileResponse(f)


app.mount("/", StaticFiles(directory=Path(__file__).parent / "static", html=True), name="static")
