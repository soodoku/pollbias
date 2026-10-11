source("scripts/common.R")
polls <- read_csv("results/polls.csv", show_col_types = FALSE)
stopifnot(
  nrow(polls) == 3976L,
  !anyDuplicated(polls[c("dataset", "source_row")])
)
for (dataset_name in c("approval", "election")) {
  path <- paste0("results/", dataset_name, "_houses.csv")
  estimates <- read_csv(path, show_col_types = FALSE)
  diagnostic <- read_csv(
    paste0("results/", dataset_name, "_diagnostics.csv"),
    show_col_types = FALSE
  )
  stopifnot(
    all(diagnostic$passed),
    all(is.finite(estimates$estimate)),
    all(estimates$lower <= estimates$upper),
    all(estimates$rhat <= 1.01),
    all(estimates$ess_bulk >= 400),
    all(estimates$ess_tail >= 400),
    abs(mean(estimates$estimate[estimates$reference])) < 1e-8,
    sum(estimates$n_polls) ==
      sum(polls$dataset == dataset_name & is.na(polls$exclusion))
  )
  sensitivity <- read_csv(
    paste0("results/", dataset_name, "_sensitivity.csv"),
    show_col_types = FALSE
  )
  expected <- c(
    "screen", "flexible", "nonoverlap", "four_week", "wider_prior", "sample_size",
    paste0("omit_large_", 1:3),
    if (dataset_name == "approval") {
      c("smooth_only", "long_fieldwork", "date_conflicts")
    } else {
      c("national", "mccain")
    }
  )
  validation <- read_csv(paste0("results/", dataset_name, "_holdout_diagnostics.csv"),
    show_col_types = FALSE
  )
  holdout <- read_csv(paste0("results/", dataset_name, "_holdout.csv"), show_col_types = FALSE)
  stopifnot(
    all(is.finite(unlist(holdout[c("rmse", "mae", "mean_interval_width_95")]))),
    holdout$predictive_coverage_95 >= 0, holdout$predictive_coverage_95 <= 1,
    holdout$prediction_draws >= 4000,
    all(sensitivity$diagnostics_passed),
    setequal(unique(sensitivity$specification), expected), all(validation$passed)
  )
}
simulation <- read_csv("results/simulation.csv", show_col_types = FALSE)
stopifnot(
  setequal(unique(simulation$replicate), 1:10),
  all(table(simulation$replicate) == 8),
  all(simulation$diagnostics_passed), mean(simulation$covered) >= 0.8,
  sqrt(mean(simulation$error^2)) < 1.5
)
sim_diagnostics <- read_csv("results/simulation_diagnostics.csv", show_col_types = FALSE)
stopifnot(setequal(sim_diagnostics$replicate, 1:10), all(sim_diagnostics$passed))
cat("Published estimates, uncertainty, and sample counts verified.\n")
