read_source <- function(path, dataset) {
  x <- readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    na = c("", "NA", "-", "#NUM!", "#VALUE!"),
    name_repair = "minimal",
    trim_ws = TRUE
  )
  if (dataset == "election") {
    stopifnot(identical(which(names(x) == "n"), c(5L, 21L)))
    names(x)[c(5, 21)] <- c("sample_text", "sample_size_derived")
  }
  names(x) <- trimws(names(x))
  x |> dplyr::mutate(source_row = dplyr::row_number() + 1L)
}

parse_poll_dates <- function(x) {
  parse_one <- function(value) {
    if (is.na(value)) {
      return(c(NA_character_, NA_character_))
    }
    value <- gsub("\\s+", "", value)
    single <- stringr::str_match(value, "^(\\d{1,2})/(\\d{1,2})/(\\d{2})$")
    same <- stringr::str_match(
      value,
      "^(\\d{1,2})/(\\d{1,2})-(\\d{1,2})/(\\d{2})$"
    )
    cross <- stringr::str_match(
      value,
      "^(\\d{1,2})/(\\d{1,2})-(\\d{1,2})/(\\d{1,2})/(\\d{2})$"
    )
    if (!is.na(single[1])) {
      parts <- as.integer(single[2:4])
      dates <- rep(sprintf("20%02d-%02d-%02d", parts[3], parts[1], parts[2]), 2)
    } else if (!is.na(same[1])) {
      parts <- as.integer(same[2:5])
      dates <- sprintf("20%02d-%02d-%02d", parts[4], parts[1], parts[2:3])
    } else if (!is.na(cross[1])) {
      parts <- as.integer(cross[2:6])
      years <- 2000L + c(parts[5] - as.integer(parts[1] > parts[3]), parts[5])
      dates <- sprintf("%04d-%02d-%02d", years, parts[c(1, 3)], parts[c(2, 4)])
    } else {
      return(c(NA_character_, NA_character_))
    }
    parsed <- as.Date(dates, format = "%Y-%m-%d")
    valid <- !is.na(parsed) & format(parsed, "%Y-%m-%d") == dates
    dates[!valid] <- NA_character_
    dates
  }
  values <- t(vapply(x, parse_one, character(2)))
  tibble::tibble(
    start_date = as.Date(values[, 1]),
    end_date = as.Date(values[, 2])
  )
}

normalize_house <- function(x) {
  x <- stringr::str_squish(x)
  dplyr::recode(
    x,
    "StrategicVision (R)" = "Strategic Vision (R)",
    "Fox/Rasmussen" = "FOX/Rasmussen",
    "Research 2000/DailyKos.com (D)" = "DailyKos.com (D)/Research 2000"
  )
}

clean_polls <- function(path, dataset) {
  raw <- read_source(path, dataset)
  if (dataset == "approval") {
    dates <- raw |>
      dplyr::transmute(
        start_date = as.Date(start_date, "%m/%d/%y"),
        end_date = as.Date(end_date, "%m/%d/%y")
      )
    sample_size <- readr::parse_double(raw$n)
    outcome <- readr::parse_double(raw$approve)
    geography <- rep("National", nrow(raw))
    screen <- dplyr::case_when(
      raw$lv == "1" ~ "likely_voters",
      raw$rv == "1" ~ "registered_voters",
      TRUE ~ "unknown"
    )
  } else {
    dates <- parse_poll_dates(raw$dates)
    sample_size <- suppressWarnings(readr::parse_number(raw$sample_text))
    outcome <- readr::parse_double(raw$mccain) - readr::parse_double(raw$obama)
    geography <- raw$state
    screen <- dplyr::case_when(
      stringr::str_detect(raw$sample_text, "LV$") ~ "likely_voters",
      stringr::str_detect(raw$sample_text, "RV$") ~ "registered_voters",
      stringr::str_detect(raw$sample_text, "A$") ~ "adults",
      TRUE ~ "unknown"
    )
  }
  polls <- tibble::tibble(
    dataset = dataset,
    source_row = raw$source_row,
    house_raw = raw$organization,
    house = normalize_house(raw$organization),
    geography = geography,
    screen = screen,
    sample_size = dplyr::if_else(sample_size > 0, sample_size, NA_real_),
    outcome = outcome
  ) |>
    dplyr::bind_cols(dates) |>
    dplyr::mutate(
      midpoint = start_date + as.integer((end_date - start_date) / 2),
      duration = as.integer(end_date - start_date) + 1L,
      month = format(midpoint, "%Y-%m"),
      time = as.numeric(midpoint - as.Date("2000-01-01")) / 365.25,
      fortnight = as.integer(midpoint - as.Date("2000-01-03")) %/% 14,
      house_period = paste(house, fortnight, sep = "::"),
      exclusion = dplyr::case_when(
        is.na(start_date) | is.na(end_date) ~ "unresolved_date",
        end_date < start_date ~ "reversed_dates",
        duration > 30 ~ "unverified_long_fieldwork",
        dataset == "election" & start_date < as.Date("2007-01-01") ~ "outside_election_window",
        dataset == "election" & end_date > as.Date("2008-11-04") ~ "outside_election_window",
        dataset == "approval" & start_date < as.Date("2001-01-20") ~ "outside_presidency",
        dataset == "approval" & end_date > as.Date("2009-01-20") ~ "outside_presidency",
        is.na(outcome) ~ "missing_outcome",
        dataset == "approval" &
          (outcome < 0 | outcome > 100) ~ "invalid_outcome",
        abs(outcome) > 100 ~ "invalid_outcome",
        TRUE ~ NA_character_
      )
    )
  if (dataset == "election") {
    polls$mccain <- readr::parse_double(raw$mccain)
    polls$obama <- readr::parse_double(raw$obama)
    invalid <- polls$mccain < 0 |
      polls$obama < 0 |
      polls$mccain + polls$obama > 100
    polls$exclusion[invalid] <- "invalid_candidate_shares"
    polls$sampling_se <- sqrt(
      pmax(0, (polls$mccain + polls$obama) / 100 - (polls$outcome / 100)^2) /
        polls$sample_size
    ) *
      100
  } else {
    polls$sampling_se <- sqrt(
      (polls$outcome / 100) * (1 - polls$outcome / 100) / polls$sample_size
    ) *
      100
  }
  stopifnot(nrow(polls) == nrow(raw), !anyDuplicated(polls$source_row))
  list(raw = raw, polls = polls)
}

house_support <- function(polls) {
  polls |>
    dplyr::group_by(house) |>
    dplyr::summarise(
      n_polls = dplyr::n(),
      n_months = dplyr::n_distinct(month),
      n_geographies = dplyr::n_distinct(geography),
      first_date = min(start_date),
      last_date = max(end_date),
      .groups = "drop"
    ) |>
    dplyr::mutate(reference = n_polls >= 10 & n_months >= 3)
}

thin_overlapping <- function(polls) {
  polls |>
    dplyr::arrange(end_date, start_date, source_row) |>
    dplyr::group_by(house, geography) |>
    dplyr::group_modify(function(.x, .y) {
      keep <- logical(nrow(.x))
      previous_end <- as.Date("1900-01-01")
      for (i in seq_len(nrow(.x))) {
        if (.x$start_date[i] > previous_end) {
          keep[i] <- TRUE
          previous_end <- .x$end_date[i]
        }
      }
      .x[keep, ]
    }) |>
    dplyr::ungroup()
}

validation_split <- function(polls, fraction = 0.8) {
  stopifnot(fraction > 0, fraction < 1, !anyNA(polls$midpoint))
  cutoff <- as.Date(
    stats::quantile(as.numeric(polls$midpoint), fraction),
    origin = "1970-01-01"
  )
  train <- polls |> dplyr::filter(midpoint <= cutoff)
  future <- polls |> dplyr::filter(midpoint > cutoff)
  supported <- future |> dplyr::filter(geography %in% train$geography)
  holdout <- supported |> dplyr::filter(!house_period %in% train$house_period)
  stopifnot(nrow(train) > 0, nrow(holdout) > 0)
  list(
    train = train, holdout = holdout, cutoff = cutoff,
    unsupported_geography_polls = nrow(future) - nrow(supported),
    existing_period_polls = nrow(supported) - nrow(holdout)
  )
}
