path <- Sys.getenv("POLLBIAS_LIBRARY", ".r-library")
dir.create(path, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(normalizePath(path), .libPaths()))
packages <- c(
  "dplyr",
  "tidyr",
  "readr",
  "ggplot2",
  "stringr",
  "testthat",
  "lintr",
  "posterior",
  "jsonlite"
)
missing <- packages[
  !vapply(packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing)) {
  install.packages(
    missing,
    lib = path,
    repos = Sys.getenv("POLLBIAS_CRAN", "https://cloud.r-project.org"),
    Ncpus = 4
  )
}
stopifnot(all(vapply(packages, requireNamespace, logical(1), quietly = TRUE)))
