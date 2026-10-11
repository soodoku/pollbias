source("scripts/common.R")
functions <- paste(readLines("stan/period_likelihood.stan"), collapse = "\n")
code <- paste0(
  "functions {\n", functions, "\n}\n",
  "data { int<lower=1> N; vector[N] y; vector[N] mu; ",
  "array[N] int group; array[N] real variance; real sigma; real tau; real nu; }\n",
  "generated quantities { real student = period_student_lpdf(y | mu, sigma, tau, nu, ",
  "group, variance); real normal = period_normal_lpdf(y | mu, sigma, tau, group, variance); }"
)
writeLines(code, "cache/likelihood_test.stan")
model <- cmdstanr::cmdstan_model("cache/likelihood_test.stan")
set.seed(20261011)
for (tau in c(0, 0.7, 5)) {
  for (group in list(c(1L, 1L, 2L, 3L, 3L), 1:5)) {
    data <- list(
      N = 5L, y = rnorm(5), mu = rnorm(5), group = group,
      variance = c(0, 1, 0.5, 2, 0), sigma = 1.3, tau = tau, nu = 7
    )
    fit <- model$sample(
      data = data, fixed_param = TRUE, chains = 1, iter_sampling = 1,
      refresh = 0, seed = 20261011
    )
    actual <- as.numeric(fit$draws(c("student", "normal"), format = "matrix"))
    expected <- c(0, 0)
    for (g in unique(group)) {
      i <- which(group == g)
      scale <- diag(data$sigma^2 + data$variance[i], nrow = length(i)) + data$tau^2
      expected <- expected + c(
        mvtnorm::dmvt(data$y[i], delta = data$mu[i], sigma = scale, df = data$nu),
        mvtnorm::dmvnorm(data$y[i], mean = data$mu[i], sigma = scale, log = TRUE)
      )
    }
    stopifnot(max(abs(actual - expected)) < 1e-4)
  }
}
message("Stan block likelihood agrees with mvtnorm in six cases.")
