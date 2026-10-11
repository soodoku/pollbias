dir.create(".r-library", showWarnings = FALSE)
.libPaths(c(normalizePath(".r-library"), .libPaths()))
if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", repos = "https://cloud.r-project.org")
}
renv::restore(lockfile = "renv.lock", library = ".r-library", prompt = FALSE)
source("scripts/common.R")
if (!length(Sys.glob("cache/cmdstan-*")) && !nzchar(Sys.getenv("CMDSTAN"))) {
  cmdstanr::install_cmdstan(dir = "cache", version = "2.40.0", cores = 4)
}
