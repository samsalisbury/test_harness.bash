SHELL := /usr/bin/env bash -euo pipefail -c

.PHONY:  fundamental_test
fundamental_test:
	@cd test && ./$@

# TESTS is each individual test file.
TESTS := $(shell cd test && find . -mindepth 1 -maxdepth 1 -type f -name '*.test')

$(TESTS): fundamental_test
	@cd test && $@

.PHONY: test
test: $(TESTS) ## test relies on all the tests passing individually, and then...
	@cd test && ../test_harness.bash ## runs them all again using the test_harness.bash.
