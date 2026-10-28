# Spatial Disease Modeling with R (GHS)

Runs the five Spatial Epidemiology modules (R notebooks) on a server and shows their maps in a browser.

## Start
Docker: `mkdir -p data && cp -r module1_data module2_data ... data/ && docker compose up --build -d` -> http://SERVER:8000
Ubuntu: `sudo deploy/install_ubuntu.sh` (put nginx + TLS + login in front), data in `/srv/geoepi/data/`.
First Docker build installs the R packages (10-20 min). Each module has its own data folder (or upload a .zip in the page).

## Using it
Pick a module and a compatible dataset (incompatible ones are greyed out with the missing files listed), press Run.
Progress shows in the run list. When done: map layers (switchable fields, time slider for monthly/forecast layers),
the executed report with all infographics, output files, and "Download all".
**Export:** the layer panel has *Export this view* (PNG or JPEG, 1x/2x/3x, optional OpenStreetMap basemap) and *All maps (ZIP)*,
which renders every layer, field, month and forecast as its own image. Title, run info and legends are drawn into each image.
**Chaining:** a finished Module 2 run offers "Use outputs as a dataset" -> creates the data folder Modules 3, 4, 5 expect.

## What changed in the notebooks (tools/prepare_notebooks.py)
Colab downloads/installs/paths removed; `data_dir`/`out_dir` are papermill parameters; Module 4's output-only infographics
embedded so they survive a re-run; Module 2's hand-written `R/*.R` step (manual exercise) is skipped when absent;
an export cell writes GeoJSON, heat JSON, GeoTIFF and `layers.json`. Re-run the script after editing a Colab notebook:
`python tools/prepare_notebooks.py /path/to/colab/notebooks notebooks/`

## Adding a notebook
Parameters cell tagged `parameters` (`data_dir`, `out_dir`), outputs + `layers.json` in `out_dir`, plus `notebooks/<id>.json`
(`title`, `requires`, ...). Layer kinds: `points`, `heat`, `choropleth` (`fields` or `series` groups).

## Security
Only admin-placed notebooks run; users upload data only. Add authentication before exposing beyond a trusted network.

## Tests
`pip install -r requirements.txt && python tests/test_api.py && node tests/test_lib.js`
Image export: `npm i canvas` then `node tests/test_export.js OUT RUN3 RUN4 RUN5` (folders holding exported run outputs)
R side: `Rscript tests/make_synthetic.R /tmp/syn` then run a notebook with papermill (see tests/).
