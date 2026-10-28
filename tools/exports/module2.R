
# Data-quality maps and the district-month incidence series from the finished panel
safe("data quality", {
  pn <- panel |> dplyr::mutate(usable = reported & !flag_outlier,
                               inc = dplyr::if_else(usable, incidence_1000, NA_real_))
  dq <- pn |> dplyr::group_by(adm2_code) |>
    dplyr::summarise(months_reported = sum(reported, na.rm = TRUE),
                     pct_usable = 100 * mean(usable, na.rm = TRUE),
                     reporting_rate_mean = mean(reporting_rate, na.rm = TRUE),
                     months_flagged = sum(dplyr::if_any(dplyr::starts_with("flag_"), ~ .x %in% TRUE)),
                     confirmed_total = sum(confirmed, na.rm = TRUE),
                     incidence_mean = mean(inc, na.rm = TRUE), .groups = "drop")
  mo <- widen_months(pn, "inc", "inc")
  d  <- web_districts(districts) |> dplyr::left_join(dq, by = "adm2_code") |> dplyr::left_join(mo$wide, by = "adm2_code")
  write_geojson(d, "panel_districts")
  add_layer(id = "quality", title = "Data quality of the panel", kind = "choropleth", file = "panel_districts.geojson",
    fields = list(
      list(field = "pct_usable",          label = "Usable district-months (%)", type = "numeric"),
      list(field = "months_reported",     label = "Months reported (of 24)", type = "numeric"),
      list(field = "months_flagged",      label = "Months with a validation flag", type = "numeric"),
      list(field = "reporting_rate_mean", label = "Mean reporting rate (%)", type = "numeric"),
      list(field = "incidence_mean",      label = "Mean monthly incidence per 1,000", type = "numeric"),
      list(field = "confirmed_total",     label = "Confirmed cases, 24 months", type = "numeric")))
  add_layer(id = "monthly", title = "Monthly incidence per 1,000", kind = "choropleth", file = "panel_districts.geojson",
    series = list(list(id = "inc", label = "Usable months only", fields = mo$fields))) })

# Hand-off: the files Modules 3, 4 and 5 expect, so the next run can use this run as its dataset
safe("handoff", {
  h <- file.path(out_dir, "handoff"); dir.create(h, showWarnings = FALSE, recursive = TRUE)
  readr::write_rds(panel, file.path(h, "panel.rds"))
  readr::write_csv(panel, file.path(h, "panel.csv"))
  if (exists("dictionary")) readr::write_csv(dictionary, file.path(h, "data_dictionary.csv"))
  file.copy(file.path(data_dir, "ghana_districts.gpkg"), file.path(h, "ghana_districts.gpkg"), overwrite = TRUE)
  message("Hand-off folder ready: ", paste(list.files(h), collapse = ", ")) })
