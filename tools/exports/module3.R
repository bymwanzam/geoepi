
# ESDA: annual incidence, cluster persistence, change, residuals, bivariate map, 24-month series
safe("esda map", {
  mo  <- widen_months(dplyr::mutate(panel, inc = dplyr::if_else(reported & !flag_outlier, incidence_1000, NA_real_)), "inc", "inc")
  att <- sf::st_drop_geometry(web) |> dplyr::select(adm2_code, inc_2024, cases_2024, months_reported, population, type, months_hh)
  d <- web_districts(districts) |>
    dplyr::left_join(att, by = "adm2_code") |>
    dplyr::left_join(dplyr::select(change, adm2_code, y2023, y2024, ratio, log_ratio), by = "adm2_code") |>
    dplyr::left_join(sf::st_drop_geometry(res_map) |> dplyr::select(adm2_code, mean_resid), by = "adm2_code") |>
    dplyr::left_join(dplyr::select(aug, adm2_code, bi_class), by = "adm2_code") |>
    dplyr::left_join(mo$wide, by = "adm2_code")
  write_geojson(d, "esda_districts")
  persist_cols <- list("Persistent high cluster" = "#B2182B", "Seasonal high cluster" = "#EF8A62", "Persistent low cluster" = "#2166AC",
                       "Seasonal low cluster" = "#67A9CF", "No stable cluster" = "#E0E0E0")
  add_layer(id = "esda", title = "ESDA: incidence, clusters, change", kind = "choropleth", file = "esda_districts.geojson",
    fields = list(
      list(field = "inc_2024",  label = "Annual incidence 2024 (per 1,000)", type = "numeric"),
      list(field = "type",      label = "LISA cluster persistence, 2023-24", type = "category", colors = persist_cols),
      list(field = "log_ratio", label = "Change 2024 vs 2023 (log2 ratio)", type = "numeric"),
      list(field = "mean_resid", label = "Unexplained by reference model (mean residual)", type = "numeric"),
      list(field = "months_hh", label = "Months in a high-high cluster", type = "numeric"),
      list(field = "bi_class",  label = "Aug 2024: rain last month x incidence (1 low, 3 high)", type = "category")))
  add_layer(id = "monthly", title = "Monthly incidence per 1,000, 2023-24", kind = "choropleth", file = "esda_districts.geojson",
    series = list(list(id = "inc", label = "Usable months only", fields = mo$fields))) })
safe("moran table", readr::write_csv(mi, file.path(out_dir, "moran_monthly.csv")))
