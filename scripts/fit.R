source("scripts/common.R")
source("R/models.R")
suppressPackageStartupMessages(library(brms))
polls <- read_csv("results/polls.csv", show_col_types = FALSE) |>
  filter(is.na(exclusion))
args <- commandArgs(trailingOnly = TRUE)
datasets <- if (length(args)) args else c("approval", "election")
for (dataset_name in datasets) {
  data <- polls |> filter(dataset == dataset_name)
  fit <- fit_house_model(data, paste0(dataset_name, "_primary"), adapt_delta = 0.99)
  result <- house_estimates(fit, data)
  diagnostics <- check_fit(fit, result$estimates, strict = FALSE)
  can_extend <- with(
    diagnostics,
    !passed & min_bfmi >= 0.3 & divergences == 0 & treedepth_hits == 0
  )
  if (can_extend) {
    fit <- fit_house_model(data, paste0(dataset_name, "_primary_extended"),
      iter = 4000, warmup = 2000, adapt_delta = 0.99
    )
    result <- house_estimates(fit, data)
    diagnostics <- check_fit(fit, result$estimates, strict = FALSE)
    if (diagnostics$passed) saveRDS(fit, paste0("cache/", dataset_name, "_primary.rds"))
  }
  write_csv(diagnostics, paste0("results/", dataset_name, "_diagnostics.csv"))
  if (!diagnostics$passed) {
    stop("Primary model failed diagnostics: ", dataset_name)
  }
  write_csv(result$estimates, paste0("results/", dataset_name, "_houses.csv"))
  saveRDS(result$draws, paste0("cache/", dataset_name, "_house_draws.rds"))
  writeLines(
    trimws(brms::stancode(fit), which = "right"),
    paste0("results/", dataset_name, "_model.stan")
  )
  jsonlite::write_json(
    list(
      r_version = as.character(getRversion()),
      cmdstan = as.character(cmdstanr::cmdstan_version()),
      packages = as.list(vapply(
        c("brms", "cmdstanr", "dplyr", "posterior"),
        function(x) as.character(utils::packageVersion(x)), character(1)
      ))
    ), paste0("results/", dataset_name, "_runtime.json"),
    pretty = TRUE, auto_unbox = TRUE
  )
  writeLines(
    trimws(capture.output(sessionInfo()), which = "right"),
    paste0("results/", dataset_name, "_session_info.txt")
  )
  print(result$estimates |> filter(house == "Rasmussen"))
}
