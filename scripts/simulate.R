source("scripts/common.R")
source("R/models.R")
suppressPackageStartupMessages(library(brms))
args <- commandArgs(trailingOnly = TRUE)
smoke <- identical(args, "smoke")
selected <- length(args) > 0 && !smoke
repetitions <- if (selected) as.integer(args) else seq_len(if (smoke) 1L else 10L)
stopifnot(!anyNA(repetitions), all(repetitions %in% 1:10))
results <- list()
diagnostics <- list()
for (replicate in repetitions) {
  set.seed(9100 + replicate)
  n <- 600
  houses <- paste0("house_", 1:8)
  house <- sample(houses[1:7], n, replace = TRUE)
  house[1:4] <- houses[8]
  house_id <- match(house, houses)
  midpoint <- as.Date("2007-01-01") + sample(0:640, n, replace = TRUE)
  geography <- ifelse(
    runif(n) < 0.85,
    ifelse(house_id %% 2 == 0, "A", "B"),
    "C"
  )
  truth <- stats::setNames(c(-3, -2, -1, 0, 1, 2, 3, 4), houses)
  month <- format(midpoint, "%Y-%m")
  fortnight <- as.integer(midpoint - as.Date("2000-01-03")) %/% 14
  house_period <- paste(house, fortnight, sep = "::")
  period_effect <- stats::setNames(
    rnorm(length(unique(house_period)), 0, 0.6),
    unique(house_period)
  )
  trend <- sin(as.numeric(midpoint - min(midpoint)) / 150) * 3
  outcome <- truth[house] +
    c(A = -12, B = 12, C = 0)[geography] +
    trend +
    period_effect[house_period] +
    rt(n, df = 8) * 1.5
  data <- tibble(
    dataset = "election",
    source_row = seq_len(n),
    house,
    geography,
    screen = sample(
      c("likely_voters", "registered_voters", "unknown"),
      n,
      replace = TRUE
    ),
    midpoint,
    start_date = midpoint - 1,
    end_date = midpoint + 1,
    time = as.numeric(midpoint - as.Date("2000-01-01")) / 365.25,
    month,
    house_period,
    outcome = as.numeric(outcome),
    sample_size = sample(c(500, 1000, NA), n, replace = TRUE)
  )
  fit <- fit_house_model(
    data,
    paste0("simulation_", if (smoke) "smoke_" else "full_", replicate),
    k = 10,
    iter = 4000,
    warmup = 2000,
    adapt_delta = 0.99,
    seed = 9100 + replicate
  )
  prediction <- predict_polls(fit, ndraws = 20)
  stopifnot(identical(dim(prediction), c(20L, as.integer(n))), all(is.finite(prediction)))
  newdata <- data[1:10, ]
  newdata$house[1] <- "unseen_house"
  newdata$house_period[1] <- "unseen_house::new_period"
  new_prediction <- predict_polls(
    fit,
    newdata = prepare_model_data(newdata, k = 10), ndraws = 20,
    allow_new_levels = TRUE, sample_new_levels = "gaussian"
  )
  stopifnot(identical(dim(new_prediction), c(20L, 10L)), all(is.finite(new_prediction)))
  estimates <- house_estimates(fit, data)
  diagnostic <- check_fit(fit, estimates$estimates, strict = TRUE)
  diagnostics[[replicate]] <- mutate(diagnostic, replicate = replicate)
  ref_mean <- mean(truth[estimates$reference])
  results[[replicate]] <- estimates$estimates |>
    mutate(
      replicate = replicate,
      truth = truth[house] - ref_mean,
      covered = truth >= lower & truth <= upper,
      error = estimate - truth,
      diagnostics_passed = diagnostic$passed
    )
  path <- if (smoke) {
    "cache/simulation_smoke.csv"
  } else if (selected) {
    "cache/simulation_partial.csv"
  } else {
    "results/simulation.csv"
  }
  write_csv(bind_rows(results), path)
  write_csv(bind_rows(diagnostics), sub("\\.csv$", "_diagnostics.csv", path))
}
combined <- bind_rows(results)
print(
  combined |>
    summarise(
      coverage = mean(covered),
      rmse = sqrt(mean(error^2)),
      max_absolute_error = max(abs(error))
    )
)
if (!selected) {
  stopifnot(mean(combined$covered) >= 0.80, sqrt(mean(combined$error^2)) < 1.5)
}
