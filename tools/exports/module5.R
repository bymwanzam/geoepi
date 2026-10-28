
# Forecasts: monthly forecast vs observed (shared scale), skill by district, July priority, CV folds
safe("forecast map", {
  fc <- widen_months(test, "pred_st", "fc"); ob <- widen_months(test, "incidence_1000", "ob")
  d <- web_districts(districts) |> dplyr::left_join(fc$wide, by = "adm2_code") |> dplyr::left_join(ob$wide, by = "adm2_code")
  if (exists("err")) d <- dplyr::left_join(d, dplyr::select(err, adm2_code, mae_st, bias_st, interval_width = width), by = "adm2_code")
  jul <- test |> dplyr::filter(month == lubridate::ymd("2024-07-01")) |>
    dplyr::transmute(adm2_code, forecast_july = pred_st, observed_july = incidence_1000,
                     confidence = dplyr::case_when(width < 8 ~ "high", width < 16 ~ "medium", TRUE ~ "low"))
  d <- dplyr::left_join(d, jul, by = "adm2_code")
  if (exists("test_c")) d <- dplyr::left_join(d, test_c |> dplyr::filter(month == lubridate::ymd("2024-07-01")) |>
                                              dplyr::select(adm2_code, p_high_july = p_high), by = "adm2_code")
  if (exists("train") && "fold_space" %in% names(train))
    d <- dplyr::left_join(d, train |> dplyr::distinct(adm2_code, fold_space) |> dplyr::mutate(cv_fold = paste("Fold", fold_space)) |>
                            dplyr::select(adm2_code, cv_fold), by = "adm2_code")
  write_geojson(d, "forecast_districts")
  add_layer(id = "forecast", title = "Monthly forecast vs observed (per 1,000)", kind = "choropleth", file = "forecast_districts.geojson",
    series = list(list(id = "fc", label = "Forecast (spatio-temporal)", fields = fc$fields),
                  list(id = "ob", label = "Observed", fields = ob$fields)))
  flds <- list(
    list(field = "confidence",    label = "July forecast confidence", type = "category",
         colors = list(high = "#2A7F62", medium = "#E6A23C", low = "#C43D2A")),
    list(field = "forecast_july", label = "July forecast (per 1,000)", type = "numeric"),
    list(field = "mae_st",        label = "Forecast error, Jul-Dec (MAE)", type = "numeric"),
    list(field = "bias_st",       label = "Forecast bias, Jul-Dec", type = "numeric"),
    list(field = "interval_width", label = "Width of the 90% interval", type = "numeric"),
    list(field = "p_high_july",   label = "Probability of a high month (forest)", type = "numeric"),
    list(field = "cv_fold",       label = "Spatial cross-validation fold", type = "category"))
  flds <- Filter(function(f) f$field %in% names(d), flds)
  add_layer(id = "skill", title = "Forecast skill and priority", kind = "choropleth", file = "forecast_districts.geojson",
            source = "forecast_july2024.gpkg", fields = flds) })
safe("scores", if (exists("scores")) readr::write_csv(scores, file.path(out_dir, "model_scores.csv")))
