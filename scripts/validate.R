source("scripts/common.R")
source("R/models.R")
suppressPackageStartupMessages(library(brms))
polls <- read_csv("results/polls.csv", show_col_types = FALSE) |>
  filter(is.na(exclusion))
args <- commandArgs(trailingOnly = TRUE)
datasets <- if (length(args)) args else c("approval", "election")
for (dataset_name in datasets) {
  prediction_seed <- 20261011L + 1000L * match(dataset_name, c("approval", "election"))
  set.seed(prediction_seed)
  data <- polls |> filter(dataset == dataset_name)
  fit <- readRDS(paste0("cache/", dataset_name, "_primary.rds"))
  if (dataset_name == "approval") {
    specifications <- read_csv(
      "results/approval_sensitivity_diagnostics.csv",
      show_col_types = FALSE
    )
    smooth_path <- specifications |>
      filter(specification == "smooth_only") |>
      pull(fit_file)
    stopifnot(length(smooth_path) == 1L, file.exists(smooth_path))
    write_csv(
      approval_break_predictions(data, fit, readRDS(smooth_path)),
      "results/approval_break_predictions.csv"
    )
  }
  set.seed(prediction_seed + 1L)
  prediction <- predict_polls(fit, ndraws = 400)
  observed <- fit$data$response
  bounds <- if (dataset_name == "approval") c(-50, 50) else c(-100, 100)
  checks <- tibble(
    statistic = c("mean", "sd", "minimum", "maximum"),
    observed = c(mean(observed), sd(observed), min(observed), max(observed)),
    lower = vapply(
      list(mean, sd, min, max),
      function(f) quantile(apply(prediction, 1, f), 0.025),
      numeric(1)
    ),
    upper = vapply(
      list(mean, sd, min, max),
      function(f) quantile(apply(prediction, 1, f), 0.975),
      numeric(1)
    )
  )
  write_csv(checks, paste0("results/", dataset_name, "_predictive_checks.csv"))
  write_csv(tibble(
    fraction_outside_bounds = mean(prediction < bounds[1] | prediction > bounds[2])
  ), paste0("results/", dataset_name, "_posterior_bounds.csv"))
  set.seed(prediction_seed + 2L)
  residual <- data |>
    mutate(
      residual = observed - colMeans(predict_polls(fit, ndraws = 400, expected = TRUE))
    ) |>
    arrange(house, geography, midpoint) |>
    group_by(house, geography) |>
    mutate(
      lag_residual = lag(residual),
      lag_days = as.numeric(midpoint - lag(midpoint)),
      same_period = house_period == lag(house_period)
    ) |>
    ungroup()
  correlations <- lapply(c(7, 14, 30, 60), function(days) {
    x <- residual |> filter(!is.na(lag_residual), lag_days <= days)
    x |>
      group_by(same_period) |>
      summarise(
        window_days = days, pairs = n(), correlation = cor(residual, lag_residual),
        .groups = "drop"
      ) |>
      mutate(block_comparison = if_else(same_period, "within fortnight", "between fortnights")) |>
      select(window_days, block_comparison, pairs, correlation)
  }) |>
    bind_rows()
  write_csv(
    correlations,
    paste0("results/", dataset_name, "_residual_dependence.csv")
  )
  p <- bayesplot::ppc_dens_overlay(observed, prediction[1:40, ]) +
    labs(
      x = if (dataset_name == "approval") {
        "Bush approval minus 50 (percentage points)"
      } else {
        "McCain minus Obama (percentage points)"
      },
      y = "Density",
      title = if (dataset_name == "approval") "Bush approval" else "2008 election"
    ) +
    theme_minimal() +
    theme(
      plot.margin = margin(8, 12, 8, 16),
      axis.title.y = element_text(margin = margin(r = 8))
    )
  ggsave(
    paste0("figs/", dataset_name, "_predictive.png"),
    p,
    width = 8,
    height = 4,
    dpi = 160
  )
  prior <- fit_house_model(
    data,
    paste0(dataset_name, "_prior"),
    prior_only = TRUE
  )
  set.seed(prediction_seed + 3L)
  prior_prediction <- predict_polls(prior, ndraws = 400)
  write_csv(
    tibble(
      lower_95 = quantile(prior_prediction, 0.025),
      upper_95 = quantile(prior_prediction, 0.975),
      fraction_outside_bounds = mean(
        prior_prediction < bounds[1] | prior_prediction > bounds[2]
      )
    ),
    paste0("results/", dataset_name, "_prior_checks.csv")
  )
  split <- validation_split(data)
  train <- split$train
  holdout <- split$holdout
  for (iterations in c(2000L, 4000L, 8000L)) {
    fit_name <- paste0(dataset_name, "_holdout", if (iterations > 2000) paste0("_", iterations))
    validation_fit <- fit_house_model(
      train, fit_name,
      iter = iterations, warmup = iterations / 2,
      adapt_delta = if (iterations == 2000) 0.95 else 0.99
    )
    validation_estimates <- house_estimates(validation_fit, train)
    validation_diagnostics <- check_fit(
      validation_fit, validation_estimates$estimates,
      strict = FALSE
    ) |>
      mutate(fit_file = paste0("cache/", fit_name, ".rds"))
    write_csv(validation_diagnostics, paste0("results/", dataset_name, "_holdout_diagnostics.csv"))
    if (validation_diagnostics$passed) break
  }
  if (!validation_diagnostics$passed) stop("Holdout model diagnostics failed")
  set.seed(prediction_seed + 4L)
  n_prediction_draws <- nrow(posterior::as_draws_matrix(validation_fit))
  pred <- predict_polls(
    validation_fit,
    newdata = prepare_model_data(holdout),
    ndraws = n_prediction_draws,
    allow_new_levels = TRUE,
    sample_new_levels = "gaussian"
  )
  target <- holdout$outcome - if (dataset_name == "approval") 50 else 0
  validation <- tibble(
    cutoff = split$cutoff,
    n_train = nrow(train),
    n_holdout = nrow(holdout),
    prediction_draws = n_prediction_draws,
    unsupported_geography_polls = split$unsupported_geography_polls,
    existing_period_polls = split$existing_period_polls,
    rmse = sqrt(mean((target - colMeans(pred))^2)),
    mae = mean(abs(target - colMeans(pred))),
    mean_interval_width_95 = mean(
      apply(pred, 2, quantile, 0.975) - apply(pred, 2, quantile, 0.025)
    ),
    predictive_coverage_95 = mean(
      target >= apply(pred, 2, quantile, 0.025) &
        target <= apply(pred, 2, quantile, 0.975)
    )
  )
  write_csv(validation, paste0("results/", dataset_name, "_holdout.csv"))
}
