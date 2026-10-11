prepare_model_data <- function(polls, k = NULL) {
  dataset <- unique(polls$dataset)
  stopifnot(length(dataset) == 1L)
  if (is.null(k)) k <- if (dataset == "approval") 60L else 15L
  polls <- polls |>
    dplyr::mutate(
      house = factor(house),
      geography = factor(geography),
      screen = factor(screen),
      house_period = factor(house_period),
      period_id = as.integer(house_period),
      sampling_variance = 0,
      post_september_11 = pmin(1, pmax(
        0, as.numeric(end_date - as.Date("2001-09-11")) + 1
      ) / (as.numeric(end_date - start_date) + 1)),
      response = outcome - ifelse(dataset == "approval", 50, 0),
      time = time - 5
    )
  basis <- splines::ns(
    polls$time,
    knots = c(2.5, 3, 3.5),
    Boundary.knots = c(2, 4)
  )
  for (j in seq_len(ncol(basis))) {
    polls[[paste0("geo_basis_", j)]] <- basis[, j]
  }
  boundary <- if (dataset == "approval") c(-4, 4) else c(2, 4)
  knots <- seq(boundary[1], boundary[2], length.out = k - 1L)
  basis <- splines::bs(
    polls$time,
    degree = 3, knots = knots[-c(1, length(knots))],
    Boundary.knots = boundary
  )
  for (j in seq_len(ncol(basis))) {
    polls[[paste0("time_basis_", j)]] <- basis[, j]
  }
  polls
}

model_formula <- function(
  dataset,
  k = NULL,
  screen = FALSE,
  geography = TRUE,
  approval_break = TRUE
) {
  if (is.null(k)) {
    k <- if (dataset == "approval") 60L else 15L
  }
  response <- "response | vint(period_id) + vreal(sampling_variance)"
  terms <- c(paste0("time_basis_", seq_len(k)), "(1 | house)")
  if (dataset == "approval" && approval_break) {
    terms <- c(terms, "post_september_11")
  }
  if (dataset == "election" && geography) {
    terms <- c(
      terms,
      "geography",
      paste0(
        "(0 + ",
        paste0("geo_basis_", 1:4, collapse = " + "),
        " || geography)"
      )
    )
  }
  if (screen) {
    terms <- c(terms, "screen")
  }
  brms::bf(stats::as.formula(paste(
    response,
    "~",
    paste(terms, collapse = " + ")
  )))
}

model_priors <- function(weighted = FALSE, scale = 1) {
  priors <- c(
    brms::set_prior(sprintf("normal(0, %g)", 20 * scale), class = "Intercept"),
    brms::set_prior(sprintf("normal(0, %g)", 20 * scale), class = "b"),
    brms::set_prior(sprintf("normal(0, %g)", 5 * scale), class = "sd"),
    brms::set_prior(sprintf("normal(0, %g)", 10 * scale), class = "sigma"),
    brms::set_prior(sprintf("normal(0, %g)", 5 * scale), class = "tau")
  )
  if (!weighted) {
    priors <- c(
      priors,
      brms::set_prior("exponential(0.1)", class = "nu", lb = 2)
    )
  }
  priors
}

fit_house_model <- function(
  polls,
  name,
  k = NULL,
  screen = FALSE,
  weighted = FALSE,
  prior_scale = 1,
  approval_break = TRUE,
  chains = 4,
  iter = 2000,
  warmup = 1000,
  prior_only = FALSE,
  adapt_delta = 0.95,
  seed = 20261011L
) {
  dataset <- unique(polls$dataset)
  stopifnot(
    length(dataset) == 1L,
    !anyNA(polls$outcome),
    !anyNA(polls$midpoint)
  )
  data <- prepare_model_data(polls, k)
  if (weighted) data$sampling_variance <- data$sampling_se^2
  formula <- model_formula(
    dataset,
    k,
    screen,
    nlevels(data$geography) > 1,
    approval_break
  )
  brms::brm(
    formula,
    data = data,
    family = period_family(weighted),
    stanvars = brms::stanvar(
      scode = paste(readLines("stan/period_likelihood.stan"), collapse = "\n"),
      block = "functions"
    ),
    prior = model_priors(weighted, prior_scale),
    backend = "cmdstanr",
    chains = chains,
    cores = min(chains, 2),
    iter = iter,
    warmup = warmup,
    seed = seed,
    refresh = 250,
    init = 0,
    control = list(
      adapt_delta = adapt_delta, max_treedepth = 13,
      metric = if (dataset == "approval") "dense_e" else "diag_e"
    ),
    sample_prior = if (prior_only) "only" else "no",
    file = file.path("cache", name),
    file_refit = "on_change"
  )
}

center_house_draws <- function(draws, reference) {
  draws <- array(as.numeric(draws), dim(draws), dimnames(draws))
  stopifnot(length(reference) > 0, all(reference %in% dimnames(draws)[[3]]))
  center <- apply(draws[, , reference, drop = FALSE], c(1, 2), mean)
  for (j in seq_len(dim(draws)[3])) {
    draws[, , j] <- draws[, , j] - center
  }
  posterior::as_draws_array(draws)
}

summarise_house_draws <- function(draws) {
  posterior::summarise_draws(
    draws, mean, sd,
    ~ stats::quantile(.x, c(0.025, 0.975)),
    rhat = posterior::rhat,
    ess_bulk = posterior::ess_bulk,
    ess_tail = posterior::ess_tail
  ) |>
    tibble::as_tibble() |>
    dplyr::rename(house = variable, estimate = mean, lower = `2.5%`, upper = `97.5%`)
}

house_estimates <- function(fit, polls, reference_houses = NULL) {
  support <- house_support(polls)
  if (is.null(reference_houses)) {
    reference_houses <- support$house[support$reference]
  }
  available <- intersect(reference_houses, support$house)
  if (length(available) < 2L) {
    stop("At least two reference houses are required")
  }
  support$reference <- support$house %in% available
  draws <- posterior::as_draws_array(fit)
  vars <- grep(
    "^r_house\\[.*,Intercept\\]$",
    posterior::variables(draws),
    value = TRUE
  )
  draws <- posterior::subset_draws(draws, variable = vars)
  encoded <- sub(
    "^r_house\\[(.*),Intercept\\]$",
    "\\1",
    vars
  )
  house_names <- levels(factor(polls$house))
  house_keys <- gsub("[[:space:]]", ".", house_names)
  stopifnot(!anyDuplicated(house_keys), all(encoded %in% house_keys))
  posterior::variables(draws) <- house_names[match(encoded, house_keys)]
  draws <- center_house_draws(draws, available)
  estimates <- summarise_house_draws(draws) |>
    dplyr::left_join(support, by = "house", relationship = "one-to-one")
  list(estimates = estimates, draws = draws, reference = available)
}

check_fit <- function(fit, estimates, strict = TRUE) {
  required <- c("rhat", "ess_bulk", "ess_tail")
  if (!all(required %in% names(estimates))) {
    stop("Missing or non-finite house diagnostics")
  }
  if (!all(is.finite(as.matrix(estimates[required])))) {
    stop("Missing or non-finite house diagnostics")
  }
  sampler <- brms::nuts_params(fit)
  parameters <- posterior::summarise_draws(
    posterior::as_draws_array(fit), rhat = posterior::rhat
  )
  parameters <- parameters |> dplyr::filter(variable != "lp__")
  energy <- sampler |>
    dplyr::filter(Parameter == "energy__") |>
    dplyr::group_by(Chain) |>
    dplyr::summarise(bfmi = mean(diff(Value)^2) / stats::var(Value))
  result <- tibble::tibble(
    min_bfmi = min(energy$bfmi),
    divergences = sum(sampler$Value[sampler$Parameter == "divergent__"]),
    treedepth_hits = sum(
      sampler$Value[sampler$Parameter == "treedepth__"] >= 13
    ),
    max_rhat = max(parameters$rhat, na.rm = TRUE),
    house_max_rhat = max(estimates$rhat),
    house_min_bulk_ess = min(estimates$ess_bulk),
    house_min_tail_ess = min(estimates$ess_tail)
  )
  result$passed <- with(
    result,
    min_bfmi >= 0.3 &
      divergences == 0 &
      treedepth_hits == 0 &
      max_rhat <= 1.01 &
      house_max_rhat <= 1.01 &
      house_min_bulk_ess >= 400 &
      house_min_tail_ess >= 400
  )
  if (strict && !result$passed) {
    stop("Model diagnostics failed; inspect the saved fit")
  }
  result
}

period_family <- function(weighted = FALSE) {
  parameters <- c("mu", "sigma", "tau")
  if (!weighted) parameters <- c(parameters, "nu")
  brms::custom_family(
    if (weighted) "period_normal" else "period_student",
    dpars = parameters,
    links = c("identity", rep("log", length(parameters) - 1L)),
    lb = if (weighted) c(NA, 0, 0) else c(NA, 0, 0, 2),
    type = "real", vars = c("vint1", "vreal1"), loop = FALSE
  )
}

predict_polls <- function(fit, newdata = NULL, ndraws = 400, expected = FALSE, ...) {
  draws <- posterior::as_draws_matrix(fit)
  ids <- sort(sample.int(nrow(draws), min(ndraws, nrow(draws))))
  mu <- brms::posterior_linpred(fit, newdata = newdata, draw_ids = ids, ...)
  if (expected) {
    return(mu)
  }
  data <- if (is.null(newdata)) fit$data else newdata
  groups <- as.integer(factor(data$period_id))
  for (j in seq_along(ids)) {
    draw <- stats::setNames(as.numeric(draws[ids[j], ]), colnames(draws))
    shock <- rnorm(max(groups), sd = draw["tau"])[groups]
    noise <- rnorm(nrow(data), sd = sqrt(draw["sigma"]^2 + data$sampling_variance))
    scale <- if ("nu" %in% names(draw)) {
      sqrt(rchisq(max(groups), df = draw["nu"]) / draw["nu"])[groups]
    } else {
      1
    }
    mu[j, ] <- mu[j, ] + (shock + noise) / scale
  }
  mu
}


approval_break_predictions <- function(polls, fit, smooth_fit) {
  stopifnot(
    all(polls$dataset == "approval"),
    identical(fit$data$response, polls$outcome - 50),
    identical(smooth_fit$data$response, polls$outcome - 50)
  )
  tibble::tibble(
    source_row = polls$source_row, house = polls$house, midpoint = polls$midpoint,
    observed = polls$outcome,
    `With break` = 50 + colMeans(predict_polls(fit, ndraws = 400, expected = TRUE)),
    `Smooth only` = 50 + colMeans(predict_polls(smooth_fit, ndraws = 400, expected = TRUE))
  ) |>
    dplyr::filter(midpoint >= as.Date("2001-08-01"), midpoint <= as.Date("2001-10-15")) |>
    tidyr::pivot_longer(c(`With break`, `Smooth only`), names_to = "model", values_to = "fitted") |>
    dplyr::mutate(residual = observed - fitted)
}
