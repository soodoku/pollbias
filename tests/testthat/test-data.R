testthat::test_that("date strings handle single-day, cross-month, and cross-year polls", {
  dates <- parse_poll_dates(c(
    "09/22/08",
    "10/27-28/08",
    "9/29-10/1/08",
    "12/30-1/2/08"
  ))
  testthat::expect_equal(
    as.character(dates$start_date),
    c("2008-09-22", "2008-10-27", "2008-09-29", "2007-12-30")
  )
  testthat::expect_equal(
    as.character(dates$end_date),
    c("2008-09-22", "2008-10-28", "2008-10-01", "2008-01-02")
  )
  invalid <- parse_poll_dates(c("2/30-31/08", "unknown", NA_character_))
  testthat::expect_true(all(is.na(invalid$start_date)))
})

testthat::test_that("source schema and all rows are preserved", {
  a <- clean_polls(
    file.path(project_root, "data/bushfav_merged.csv"),
    "approval"
  )
  e <- clean_polls(
    file.path(project_root, "data/collapsed polls_pollster.csv"),
    "election"
  )
  testthat::expect_equal(nrow(a$polls), 1644L)
  testthat::expect_equal(nrow(e$polls), 2332L)
  testthat::expect_named(e$raw, unique(names(e$raw)))
  testthat::expect_equal(
    e$polls$outcome,
    as.numeric(e$raw$mccain) - as.numeric(e$raw$obama)
  )
  testthat::expect_true(all(is.na(e$polls$sample_size[
    e$raw$sample_size_derived == "0"
  ])))
  testthat::expect_equal(e$polls$sample_size[e$polls$source_row == 1810], 31148)
  testthat::expect_equal(
    as.character(e$polls$end_date[e$polls$source_row == 141]),
    "2008-10-01"
  )
  testthat::expect_true(all(a$polls$screen[is.na(a$raw$lv)] == "unknown"))
  testthat::expect_equal(sum(!is.na(a$polls$exclusion)), 9L)
  testthat::expect_equal(sum(!is.na(e$polls$exclusion)), 3L)
})

testthat::test_that("aliases do not merge sponsors or modes", {
  testthat::expect_equal(
    normalize_house(c(" Rasmussen ", "Fox/Rasmussen", "Zogby (Internet)")),
    c("Rasmussen", "FOX/Rasmussen", "Zogby (Internet)")
  )
})

testthat::test_that("nonoverlapping selection does not cross house or geography", {
  data <- tibble::tibble(
    house = c("a", "a", "a", "b"),
    geography = "National",
    source_row = 1:4,
    start_date = as.Date(c(
      "2008-01-01",
      "2008-01-02",
      "2008-01-04",
      "2008-01-02"
    )),
    end_date = as.Date(c(
      "2008-01-03",
      "2008-01-03",
      "2008-01-05",
      "2008-01-03"
    ))
  )
  testthat::expect_setequal(thin_overlapping(data)$source_row, c(1L, 3L, 4L))
})

testthat::test_that("disconnected house comparisons remain separate", {
  x <- tibble::tibble(
    house = c("a", "b", "b", "c", "d"),
    cell = c("x", "x", "y", "y", "z")
  )
  groups <- comparison_components(x)
  testthat::expect_equal(dplyr::n_distinct(groups$component), 2L)
  testthat::expect_equal(
    groups$component[groups$house == "a"],
    groups$component[groups$house == "c"]
  )
})


testthat::test_that("holdout predictions use new periods and supported geographies", {
  polls <- tibble::tibble(
    source_row = 1:6, midpoint = as.Date("2008-01-01") + 0:5,
    geography = c("National", "National", "State", "National", "National", "New"),
    house_period = c("a::1", "b::1", "c::1", "a::1", "b::2", "d::2")
  )
  split <- validation_split(polls, fraction = 0.5)
  testthat::expect_equal(split$train$source_row, 1:3)
  testthat::expect_equal(split$holdout$source_row, 5L)
  testthat::expect_equal(split$unsupported_geography_polls, 1L)
  testthat::expect_equal(split$existing_period_polls, 1L)
})
