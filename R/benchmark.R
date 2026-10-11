comparison_components <- function(polls) {
  edges <- polls |> dplyr::distinct(house, cell)
  houses <- sort(unique(edges$house))
  component <- stats::setNames(seq_along(houses), houses)
  repeat {
    old <- component
    for (cell in unique(edges$cell)) {
      members <- edges$house[edges$cell == cell]
      component[members] <- min(component[members])
    }
    if (identical(component, old)) break
  }
  tibble::tibble(house = names(component), component = unname(component))
}

fit_benchmark <- function(polls) {
  polls <- polls |> dplyr::mutate(cell = paste(geography, month, sep = "::"))
  components <- comparison_components(polls)
  polls <- polls |>
    dplyr::left_join(components, by = "house", relationship = "many-to-one")
  support <- house_support(polls)
  estimates <- lapply(split(polls, polls$component), function(data) {
    if (dplyr::n_distinct(data$house) < 2) {
      return(NULL)
    }
    data$house <- factor(data$house)
    data$cell <- factor(data$cell)
    formula <- if (nlevels(data$cell) > 1) {
      outcome ~ house + cell
    } else {
      outcome ~ house
    }
    fit <- stats::lm(formula, data)
    newdata <- data.frame(
      house = levels(data$house),
      cell = levels(data$cell)[1]
    )
    values <- stats::predict(fit, newdata)
    reference <- newdata$house %in% support$house[support$reference]
    if (sum(reference) < 2) {
      return(NULL)
    }
    tibble::tibble(
      house = newdata$house,
      benchmark = values - mean(values[reference]),
      component = unique(data$component),
      matrix_rank = fit$rank,
      matrix_columns = ncol(stats::model.matrix(fit)),
      max_leverage = max(stats::hatvalues(fit)),
      condition_number = kappa(stats::model.matrix(fit))
    )
  }) |>
    dplyr::bind_rows()
  list(estimates = estimates, components = components)
}

overlap_support <- function(polls) {
  polls <- polls |> dplyr::mutate(cell = paste(geography, month, sep = "::"))
  cells <- polls |>
    dplyr::group_by(cell) |>
    dplyr::summarise(n_houses = dplyr::n_distinct(house), .groups = "drop")
  polls |>
    dplyr::left_join(cells, by = "cell", relationship = "many-to-one") |>
    dplyr::group_by(house) |>
    dplyr::summarise(
      shared_cell_polls = sum(n_houses >= 2),
      shared_cell_fraction = mean(n_houses >= 2),
      .groups = "drop"
    )
}
