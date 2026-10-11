// generated with brms 2.23.0
functions {
  real period_density(vector y, vector mu, real sigma, real tau, real nu,
                    data array[] int group, data array[] real sampling_variance,
                    int student) {
  int n = num_elements(y);
  int g = max(group);
  array[g] int count = rep_array(0, g);
  array[n] int frequency = rep_array(0, n);
  vector[g] precision = rep_vector(0, g);
  vector[g] weighted_residual = rep_vector(0, g);
  vector[g] squared_residual = rep_vector(0, g);
  vector[n] variance = square(sigma) + to_vector(sampling_variance);
  vector[n] weights = inv(variance);
  vector[n] residual = y - mu;
  vector[n] weighted = residual .* weights;
  vector[n] squared = residual .* weighted;
  vector[g] correction;
  vector[g] quadratic;
  real log_det;
  real gamma_term = 0;
  for (i in 1:n) {
    int j = group[i];
    count[j] += 1;
    precision[j] += weights[i];
    weighted_residual[j] += weighted[i];
    squared_residual[j] += squared[i];
  }
  for (j in 1:g) frequency[count[j]] += 1;
  correction = 1 + square(tau) * precision;
  quadratic = squared_residual - square(tau) * square(weighted_residual) ./ correction;
  log_det = sum(log(variance)) + sum(log(correction));
  if (student) {
    for (m in 1:n) {
      if (frequency[m] > 0) gamma_term += frequency[m] * lgamma((nu + m) / 2.0);
    }
    return gamma_term - g * lgamma(nu / 2) -
      n / 2.0 * log(nu * pi()) - log_det / 2 -
      sum((nu + to_vector(count)) .* log1p(quadratic / nu)) / 2;
  }
  return -(n * log(2 * pi()) + log_det + sum(quadratic)) / 2;
}
real period_student_lpdf(vector y, vector mu, real sigma, real tau, real nu,
                         data array[] int group, data array[] real sampling_variance) {
  return period_density(y, mu, sigma, tau, nu, group, sampling_variance, 1);
}
real period_normal_lpdf(vector y, vector mu, real sigma, real tau,
                        data array[] int group, data array[] real sampling_variance) {
  return period_density(y, mu, sigma, tau, 0, group, sampling_variance, 0);
}
}
data {
  int<lower=1> N;  // total number of observations
  vector[N] Y;  // response variable
  // data for custom real vectors
  array[N] real vreal1;
  // data for custom integer vectors
  array[N] int vint1;
  int<lower=1> K;  // number of population-level effects
  matrix[N, K] X;  // population-level design matrix
  int<lower=1> Kc;  // number of population-level effects after centering
  // data for group-level effects of ID 1
  int<lower=1> N_1;  // number of grouping levels
  int<lower=1> M_1;  // number of coefficients per level
  array[N] int<lower=1> J_1;  // grouping indicator per observation
  // group-level predictor values
  vector[N] Z_1_1;
  int prior_only;  // should the likelihood be ignored?
}
transformed data {
  matrix[N, Kc] Xc;  // centered version of X without an intercept
  vector[Kc] means_X;  // column means of X before centering
  for (i in 2:K) {
    means_X[i - 1] = mean(X[, i]);
    Xc[, i - 1] = X[, i] - means_X[i - 1];
  }
}
parameters {
  vector[Kc] b;  // regression coefficients
  real Intercept;  // temporary intercept for centered predictors
  real<lower=0> sigma;  // dispersion parameter
  real<lower=0> tau;
  real<lower=2> nu;  // degrees of freedom or shape
  vector<lower=0>[M_1] sd_1;  // group-level standard deviations
  array[M_1] vector[N_1] z_1;  // standardized group-level effects
}
transformed parameters {
  vector[N_1] r_1_1;  // actual group-level effects
  // prior contributions to the log posterior
  real lprior = 0;
  r_1_1 = (sd_1[1] * (z_1[1]));
  lprior += normal_lpdf(b | 0, 20);
  lprior += normal_lpdf(Intercept | 0, 20);
  lprior += normal_lpdf(sigma | 0, 10)
    - 1 * normal_lccdf(0 | 0, 10);
  lprior += normal_lpdf(tau | 0, 5)
    - 1 * normal_lccdf(0 | 0, 5);
  lprior += exponential_lpdf(nu | 0.1)
    - 1 * exponential_lccdf(2 | 0.1);
  lprior += normal_lpdf(sd_1 | 0, 5)
    - 1 * normal_lccdf(0 | 0, 5);
}
model {
  // likelihood including constants
  if (!prior_only) {
    // initialize linear predictor term
    vector[N] mu = rep_vector(0.0, N);
    mu += Intercept + Xc * b;
    for (n in 1:N) {
      // add more terms to the linear predictor
      mu[n] += r_1_1[J_1[n]] * Z_1_1[n];
    }
    target += period_student_lpdf(Y | mu, sigma, tau, nu, vint1, vreal1);
  }
  // priors including constants
  target += lprior;
  target += std_normal_lpdf(z_1[1]);
}
generated quantities {
  // actual population-level intercept
  real b_Intercept = Intercept - dot_product(means_X, b);
}
