testthat::test_that("posterior centering propagates reference uncertainty", {
  testthat::skip_if_not_installed("posterior")
  x <- array(
    seq_len(24),
    c(4, 2, 3),
    dimnames = list(NULL, NULL, c("a", "b", "c"))
  )
  centered <- center_house_draws(posterior::as_draws_array(x), c("a", "c"))
  testthat::expect_equal(
    unname(apply(centered[, , c("a", "c")], c(1, 2), mean)),
    matrix(0, 4, 2)
  )
  testthat::expect_equal(
    as.numeric(centered[, , "a"] - centered[, , "b"]),
    as.numeric(x[, , "a"] - x[, , "b"])
  )
  testthat::expect_error(center_house_draws(x, character()))
})

testthat::test_that("sampling variance includes candidate covariance", {
  e <- clean_polls(
    file.path(project_root, "data/collapsed polls_pollster.csv"),
    "election"
  )$polls
  expected <- sqrt((0.57 + 0.39 - (0.57 - 0.39)^2) / 452) * 100
  testthat::expect_equal(e$sampling_se[1], expected)
})

testthat::test_that("house diagnostic columns are named and required", {
  set.seed(19)
  draws <- posterior::as_draws_array(array(
    rnorm(800), c(100, 4, 2),
    dimnames = list(NULL, NULL, c("a", "b"))
  ))
  estimates <- summarise_house_draws(draws)
  testthat::expect_true(all(c("rhat", "ess_bulk", "ess_tail") %in% names(estimates)))
  testthat::expect_true(all(is.finite(estimates$rhat)))
  testthat::expect_error(check_fit(NULL, tibble::tibble(house = "a")), "Missing")
})

testthat::test_that("spline prediction uses the same knots as training", {
  polls <- clean_polls(file.path(project_root, "data/bushfav_merged.csv"), "approval")$polls |>
    dplyr::filter(is.na(exclusion))
  full <- prepare_model_data(polls)
  subset <- prepare_model_data(polls[100:200, ])
  basis <- paste0("time_basis_", 1:60)
  testthat::expect_equal(full[100:200, basis], subset[basis])
})


testthat::test_that("encoded house names and subset references stay aligned", {
  set.seed(23)
  draws <- array(rnorm(800), c(100, 4, 2), dimnames = list(
    NULL, NULL, c("r_house[Alpha.Poll,Intercept]", "r_house[Beta,Intercept]")
  ))
  polls <- tibble::tibble(
    house = c("Alpha Poll", "Beta"), month = "2008-01", geography = "National",
    start_date = as.Date("2008-01-01"), end_date = as.Date("2008-01-02")
  )
  result <- house_estimates(posterior::as_draws_array(draws), polls, polls$house)
  testthat::expect_setequal(result$estimates$house, polls$house)
  testthat::expect_true(all(result$estimates$reference))
  testthat::expect_equal(mean(result$estimates$estimate), 0, tolerance = 1e-12)
})


testthat::test_that("event exposure respects inclusive fieldwork dates", {
  polls <- tibble::tibble(
    dataset = "approval", house = "a", geography = "National", screen = "unknown",
    house_period = c("a", "b", "c"), outcome = 50,
    start_date = as.Date(c("2001-09-08", "2001-09-10", "2001-09-11")),
    end_date = as.Date(c("2001-09-10", "2001-09-13", "2001-09-13")),
    time = 1.7
  )
  testthat::expect_equal(prepare_model_data(polls)$post_september_11, c(0, 0.75, 1))
})
