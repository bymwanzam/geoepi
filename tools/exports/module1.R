
# Topic 1: case spot map and heat maps
safe("cases", { write_geojson(wgs(dplyr::select(cases_sf, dplyr::any_of("date"))), "cases_points")
  add_layer(id = "cases", title = "Confirmed cases (Bolgatanga)", kind = "points", file = "cases_points.geojson") })
safe("kde 500", { heat_export(im_df(d500 * 1e6), "kde_500m")
  add_layer(id = "kde500", title = "Case density, sigma 500 m (per km2)", kind = "heat", file = "kde_500m.heat.json") })
safe("kde 1000", { heat_export(im_df(d1000 * 1e6), "kde_1000m")
  add_layer(id = "kde1000", title = "Case density, sigma 1000 m (per km2)", kind = "heat", file = "kde_1000m.heat.json") })
safe("relrisk", { heat_export(im_df(rr), "relative_risk")
  add_layer(id = "rr", title = "Relative risk vs population (1 = average)", kind = "heat", file = "relative_risk.heat.json") })

# Topic 2: district maps (rates, LISA, Gi*, scan cluster)
safe("districts", {
  d <- map_df |> sf::st_simplify(preserveTopology = TRUE, dTolerance = 200) |> wgs() |>
    dplyr::select(dplyr::any_of(c("adm2_name", "region", "cases", "population", "rate_raw", "rate_eb_local",
                                  "death_eb_local", "lisa_lab", "gi_z", "gi_lab", "in_cluster")))
  if ("in_cluster" %in% names(d)) d$in_cluster <- ifelse(d$in_cluster, "Most likely cluster", "Outside")
  write_geojson(d, "districts_epi")
  add_layer(id = "districts", title = "District malaria maps", kind = "choropleth", file = "districts_epi.geojson",
    fields = list(
      list(field = "rate_eb_local",  label = "Smoothed incidence per 1,000", type = "numeric"),
      list(field = "rate_raw",       label = "Raw incidence per 1,000",      type = "numeric"),
      list(field = "death_eb_local", label = "Smoothed deaths per 100,000",  type = "numeric"),
      list(field = "lisa_lab",       label = "Local Moran (LISA) clusters",  type = "category"),
      list(field = "gi_lab",         label = "Getis-Ord Gi* hot / cold spots", type = "category"),
      list(field = "in_cluster",     label = "Kulldorff most likely cluster", type = "category"))) })

# Topic 3: interpolated prevalence surfaces
safe("idw", { heat_export(pts_df(idw_out, "var1.pred"), "prevalence_idw")
  add_layer(id = "idw", title = "Prevalence, IDW", kind = "heat", file = "prevalence_idw.heat.json") })
safe("kriging", { heat_export(pts_df(kr, "var1.pred"), "prevalence_kriging")
  kr$sd <- sqrt(kr$var1.var); heat_export(pts_df(kr, "sd"), "prevalence_kriging_sd")
  add_layer(id = "kr", title = "Prevalence, kriging", kind = "heat", file = "prevalence_kriging.heat.json")
  add_layer(id = "krsd", title = "Kriging standard deviation", kind = "heat", file = "prevalence_kriging_sd.heat.json") })

# Topic 4: priority index
safe("priority", {
  p <- map_idx |> sf::st_simplify(preserveTopology = TRUE, dTolerance = 200) |> wgs() |>
    dplyr::select(adm2_name, region, index_ahp, index_equal, index_burden, class_ahp, robust)
  p$class_ahp <- as.character(p$class_ahp)
  p$robust <- ifelse(p$robust, "Top 20 under all weightings", "Other")
  write_geojson(p, "priority_index")
  add_layer(id = "priority", title = "Priority index", kind = "choropleth", file = "priority_index.geojson",
    fields = list(
      list(field = "index_ahp",    label = "Priority index (AHP weights)", type = "numeric"),
      list(field = "index_burden", label = "Priority index (burden-heavy)", type = "numeric"),
      list(field = "class_ahp",    label = "Priority class (AHP)", type = "category"),
      list(field = "robust",       label = "Robust top 20", type = "category"))) })

# Topic 5: environment by district
safe("environment", {
  e <- d_env |> sf::st_simplify(preserveTopology = TRUE, dTolerance = 0.002) |>
    dplyr::select(adm2_name, rain_mm_mean, temp_c_mean, ndvi_mean, elev_mean, suit_mean)
  write_geojson(e, "district_environment")
  terra::writeRaster(suit, file.path(out_dir, "suitable_months.tif"), overwrite = TRUE)
  add_layer(id = "env", title = "District environment", kind = "choropleth", file = "district_environment.geojson",
    fields = list(
      list(field = "suit_mean",    label = "Suitable transmission months", type = "numeric"),
      list(field = "rain_mm_mean", label = "Mean monthly rain (mm)", type = "numeric"),
      list(field = "temp_c_mean",  label = "Mean temperature (C)", type = "numeric"),
      list(field = "ndvi_mean",    label = "NDVI", type = "numeric"),
      list(field = "elev_mean",    label = "Elevation (m)", type = "numeric"))) })
