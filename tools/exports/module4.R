
# Disease mapping: SIR, posterior relative risk, uncertainty, exceedance probability, risk classes
safe("disease map", {
  rr_cols <- list("High risk, certain: act" = "#B2182B", "High risk, uncertain: investigate" = "#F4A582",
                  "Not high, certain: routine" = "#D1E5F0", "Not high, uncertain: watch" = "#92C5DE")
  a <- ann |> dplyr::select(dplyr::any_of(c("adm2_code", "O", "E", "SIR", "RR_mean", "RR_lo", "RR_hi", "ci_width",
                                            "p_gt1", "p_gt15", "class", "res_nb", "eco_zone")))
  extra <- NULL
  if (exists("sp") && inherits(sp, "sf")) extra <- sf::st_drop_geometry(sp) |>
    dplyr::transmute(adm2_code, spatial_effect_before = exp(before), spatial_effect_after = exp(after))
  d <- web_districts(districts) |> dplyr::select(-dplyr::any_of("eco_zone")) |> dplyr::left_join(a, by = "adm2_code")
  if (!is.null(extra)) d <- dplyr::left_join(d, extra, by = "adm2_code")
  write_geojson(d, "disease_map")
  add_layer(id = "dm", title = "Bayesian disease map, 2024", kind = "choropleth", file = "disease_map.geojson",
    source = "malaria_rr_2024.gpkg",
    fields = list(
      list(field = "RR_mean",  label = "Posterior mean relative risk", type = "numeric"),
      list(field = "SIR",      label = "Crude SIR (observed / expected)", type = "numeric"),
      list(field = "class",    label = "Risk and certainty", type = "category", colors = rr_cols),
      list(field = "p_gt15",   label = "Probability that RR exceeds 1.5", type = "numeric"),
      list(field = "p_gt1",    label = "Probability that RR exceeds 1", type = "numeric"),
      list(field = "ci_width", label = "Width of the 95% credible interval", type = "numeric"),
      list(field = "res_nb",   label = "Negative-binomial Pearson residual", type = "numeric"),
      list(field = "spatial_effect_before", label = "Spatial effect, no covariates", type = "numeric"),
      list(field = "spatial_effect_after",  label = "Spatial effect after eco-zone", type = "numeric"))) })
