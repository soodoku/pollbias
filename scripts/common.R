library_path <- Sys.getenv("POLLBIAS_LIBRARY", ".r-library")
if (dir.exists(library_path)) {
  .libPaths(c(normalizePath(library_path), .libPaths()))
}
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
})
source("R/data.R")
cmdstan_dirs <- Sys.glob("cache/cmdstan-*")
if (length(cmdstan_dirs) && !nzchar(Sys.getenv("CMDSTAN"))) {
  Sys.setenv(CMDSTAN = normalizePath(tail(sort(cmdstan_dirs), 1)))
}
dir.create("results", showWarnings = FALSE)
dir.create("cache", showWarnings = FALSE)
