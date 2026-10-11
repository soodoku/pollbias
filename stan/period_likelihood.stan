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
