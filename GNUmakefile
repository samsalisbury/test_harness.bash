SHELL := /usr/bin/env bash -euo pipefail -c

.PHONY: clean
clean:
	rm -rf $$(find . -type d -name .testdata)

FUNDAMENTAL := cd test && ./fundamental_test

fundamental: fundamental_pass fundamental_fail fundamental_main

fundamental_pass:
	@$(FUNDAMENTAL) simple_pass.test

fundamental_fail:
	@$(FUNDAMENTAL) simple_fail.test

fundamental_main:
	@$(FUNDAMENTAL) main.test

BASH3=bash3 bash3.2 bash3.2.57

bash3 bash3.2 bash3.2.57: BASH_VERSION=3.2.57
bash3 bash3.2 bash3.2.57: docker/test

bash4 bash4.4 bash4.4.23: BASH_VERSION=4.4.23
bash4 bash4.4 bash4.4.23: docker/test

bash4.0 bash4.0.44: BASH_VERSION=4.0.44
bash4.0 bash4.0.44: docker/test

bash5 bash5.1 bash5.1.12: BASH_VERSION=5.1.12
bash5 bash5.1 bash5.1.12: docker/test

bash5.0 bash5.0.7: BASH_VERSION=5.0.7
bash5.0 bash5.0.7: docker/test

docker/test:
	\
		echo "FROM bash:$(BASH_VERSION)" > test.Dockerfile; \
		echo "RUN apk add make bc coreutils" >> test.Dockerfile; \
		TAG=testing.bash$(BASH_VERSION) && \
		docker build \
			--tag $$TAG \
			--file test.Dockerfile . && \
		docker run \
			-v "$$PWD":/testing.bash $$TAG \
			bash -c 'cd /testing.bash && make fundamental'


TESTS_SHOULDPASS := $(shell cd test && find . -mindepth 1 -maxdepth 1 -type f -name '*.test' -not -name '*_fail.test')
TESTS_SHOULDFAIL := $(shell cd test && find . -mindepth 1 -maxdepth 1 -type f -name '*_fail.test')

$(info TESTS_SHOULDPASS=$(TESTS_SHOULDPASS))
$(info TESTS_SHOULDFAIL=$(TESTS_SHOULDFAIL))
#$(error exiting)

$(TESTS_SHOULDPASS):
	@cd test && if ! (./$@ -v | sed -E 's/^/make $@: /g'); then \
		echo "ERROR: $@ should have passed."; exit 1; \
	fi

$(TESTS_SHOULDFAIL):
	@cd test && if (./$@ -v | sed -E 's/^/make $@: /g'); then \
		echo "ERROR: $@ should have failed."; exit 1; \
	fi

.PHONY: test-singles-shouldpass
test-singles-shouldpass: $(TESTS_SHOULDPASS)
	@echo "All passing singles passed appropriately."

.PHONY: test-singles-shouldfail
test-singles-shouldfail: $(TESTS_SHOULDFAIL)
	@echo "All failing singles failed appropriately."

.PHONY: test-singles
test-singles: test-singles-shouldpass test-singles-shouldfail
	@echo "All single test failes passed and failed appropriately."

.PHONY: test-alls-shouldpass
test-alls-shouldpass:
	@cd test && if ! (../testing.bash -v $(TESTS_SHOULDPASS)); then \
		echo "Running all passing tests should have passed."; exit 1; \
	fi | sed -E 's/^/make $@: /g'
	@echo "Running all passing tests passed appropriately."

.PHONY: test-alls-shouldfail
test-alls-shouldfail:
	@cd test && if (../testing.bash -v $(TESTS_SHOULDFAIL)); then \
		echo "Running all failing tests should have failed."; exit 1; \
	fi | sed -E 's/^/make $@: /g'
	@echo "Running all failing tests failed appropriately."

.PHONY: test-alls
test-alls: test-alls-shouldpass test-alls-shouldfail
	@echo "Running all tests via testing.bash passed and failed appropriately."

.PHONY: test
test: fundamental_test test-singles test-alls ## test relies on all the tests passing individually, and then...
	@echo "All tests passed and failed appropriately."

.PHONY: shellcheck
shellcheck:
	@find -E . -regex '^.*\.(test|bash)$$' -not -regex '^.*/.testdata/.*$$' | xargs shellcheck
	@echo "shellcheck ok"

