source("scripts/common.R")
source("R/models.R")
suppressPackageStartupMessages(library(brms))
all_polls <- read_csv("results/polls.csv", show_col_types = FALSE)
polls <- all_polls |> filter(is.na(exclusion))
args <- commandArgs(trailingOnly = TRUE)
datasets <- if (length(args)) args[1] else c("approval", "election")
requested <- if (length(args) > 1) args[-1] else NULL
output_dir <- if (length(requested)) "cache" else "results"
stopifnot(all(datasets %in% c("approval", "election")))
for (dataset_name in datasets) {
  data <- polls |> filter(dataset == dataset_name)
  primary <- readRDS(paste0("cache/", dataset_name, "_primary.rds"))
  reference <- house_support(data) |>
    filter(reference) |>
    pull(house)
  specifications <- list(
    screen = list(data = data, screen = TRUE),
    flexible = list(
      data = data,
      k = if (dataset_name == "approval") 90L else 25L
    ),
    nonoverlap = list(data = thin_overlapping(data)),
    four_week = list(data = mutate(
      data,
      house_period = paste(
        house, as.integer(midpoint - as.Date("2000-01-03")) %/% 28, sep = "::"
      )
    )),
    wider_prior = list(data = data, prior_scale = 2),
    sample_size = list(
      data = filter(data, !is.na(sampling_se)),
      weighted = TRUE
    )
  )
  largest <- data |>
    count(house, sort = TRUE) |>
    slice_head(n = 3) |>
    pull(house)
  omitted_houses <- stats::setNames(largest, paste0("omit_large_", seq_along(largest)))
  for (i in seq_along(largest)) {
    specifications[[paste0("omit_large_", i)]] <- list(
      data = filter(data, house != largest[i])
    )
  }
  if (dataset_name == "election") {
    specifications$national <- list(
      data = filter(data, geography == "National")
    )
    specifications$mccain <- list(data = mutate(data, outcome = mccain))
  } else {
    specifications$smooth_only <- list(data = data, approval_break = FALSE)
    specifications$long_fieldwork <- list(data = filter(
      all_polls, dataset == "approval",
      is.na(exclusion) | exclusion == "unverified_long_fieldwork"
    ))
    week_checks <- read_csv("results/approval_week_checks.csv", show_col_types = FALSE)
    uncertain_rows <- week_checks |>
      filter(is.na(discrepancy) | abs(discrepancy) > 5) |>
      pull(source_row)
    specifications$date_conflicts <- list(data = filter(data, !source_row %in% uncertain_rows))
  }
  if (length(requested)) {
    stopifnot(all(requested %in% names(specifications)))
    specifications <- specifications[requested]
  }
  results <- list()
  diagnostics <- list()
  for (name in names(specifications)) {
    fit_name <- paste(dataset_name, name, sep = "_")
    spec <- specifications[[name]]
    subset <- spec$data
    spec$data <- NULL
    fit <- do.call(
      fit_house_model,
      c(
        list(
          polls = subset,
          name = fit_name
        ),
        spec
      )
    )
    estimates <- house_estimates(fit, subset, reference)
    check <- check_fit(fit, estimates$estimates, strict = FALSE)
    if (!check$passed) {
      fit_name <- paste(dataset_name, name, "extended", sep = "_")
      fit <- do.call(
        fit_house_model,
        c(
          list(
            polls = subset,
            name = fit_name,
            iter = 8000,
            warmup = 4000,
            adapt_delta = 0.99
          ),
          spec
        )
      )
      estimates <- house_estimates(fit, subset, reference)
      check <- check_fit(fit, estimates$estimates, strict = FALSE)
    }
    comparison <- house_estimates(
      primary,
      data,
      estimates$reference
    )$estimates |>
      select(house, primary_estimate = estimate)
    results[[name]] <- estimates$estimates |>
      left_join(comparison, by = "house", relationship = "one-to-one") |>
      mutate(
        specification = name,
        omitted_house = coalesce(unname(omitted_houses[name]), "none"),
        difference = estimate - primary_estimate,
        n_reference = length(estimates$reference),
        diagnostics_passed = check$passed
      )
    diagnostics[[name]] <- mutate(
      check,
      specification = name, fit_file = paste0("cache/", fit_name, ".rds")
    )
    write_csv(
      bind_rows(results),
      file.path(output_dir, paste0(dataset_name, "_sensitivity.csv"))
    )
    write_csv(
      bind_rows(diagnostics),
      file.path(output_dir, paste0(dataset_name, "_sensitivity_diagnostics.csv"))
    )
  }
  if (!all(bind_rows(diagnostics)$passed)) {
    stop("Sensitivity diagnostics need review")
  }
}
