R := Rscript
IMAGE := rocker/verse:4.6.0
.NOTPARALLEL:

.PHONY: setup clean-data audit fit sensitivity validate simulate render test lint format check-likelihood ci ci-docker all

setup:
	$(R) scripts/setup.R

clean-data:
	$(R) scripts/clean.R

audit: clean-data
	$(R) scripts/audit.R

fit: clean-data
	$(R) scripts/fit.R

sensitivity: fit
	$(R) scripts/sensitivity.R

validate: sensitivity
	$(R) scripts/validate.R

check-likelihood:
	$(R) scripts/check-likelihood.R

simulate:
	$(R) scripts/simulate.R

render:
	$(R) scripts/render.R

test:
	$(R) scripts/test.R

lint:
	$(R) scripts/lint.R

format:
	$(R) -e 'source("scripts/common.R"); styler::cache_deactivate(); styler::style_dir("R"); styler::style_dir("scripts"); styler::style_dir("tests")'

ci: test lint
	$(R) scripts/verify.R

ci-docker:
	docker run --rm --platform linux/amd64 -v "$(CURDIR):/work" -w /work -e POLLBIAS_LIBRARY=/tmp/pollbias-library -e POLLBIAS_CRAN=https://packagemanager.posit.co/cran/__linux__/noble/latest $(IMAGE) bash -c 'Rscript scripts/setup-ci.R && make ci'

all: audit fit sensitivity validate check-likelihood simulate render ci
