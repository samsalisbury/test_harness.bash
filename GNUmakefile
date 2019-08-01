SHELL := /usr/bin/env bash -euo pipefail -c

.PHONY: clean
clean:
	rm -rf $$(find . -type d -name .testdata)


.PHONY:  fundamental_test
fundamental_test:
	@cd test && ./$@

# TESTS is each individual test file.
TESTS := $(shell cd test && find . -mindepth 1 -maxdepth 1 -type f -name '*.test')

$(TESTS): fundamental_test
	@cd test && ./$@

.PHONY: test-singles
test-singles: $(TESTS)

.PHONY: test-alls
test-alls: ## Run all tests using test_harness.bash
	@cd test && ../test_harness.bash

.PHONY: test
test: test-singles test-alls ## test relies on all the tests passing individually, and then...

.PHONY: shellcheck
shellcheck:
	@find -E . -regex '^.*\.(test|bash)$$' -not -regex '^.*/.testdata/.*$$' | xargs shellcheck
	@echo "shellcheck ok"

