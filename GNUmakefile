SHELL := /usr/bin/env bash -euo pipefail -c

.PHONY: clean
clean:
	rm -rf $$(find . -type d -name .testdata)

fundamental_test:
	@cd test && ./$@ simple_pass.test
	@cd test && ./$@ simple_fail.test
	@cd test && ./$@ main.test

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

DOCKER_REPO := test-testing.bash
BASH_3 := 3.2.57
BASH_5 := 5.0.7

BASH_VERSION ?= $(BASH_3)
BASH_TAG := $(DOCKER_REPO)-$(BASH_VERSION):latest
DOCKER_BUILD := docker build --build-arg BASH_VERSION=$(BASH_VERSION) \
	-t $(BASH_TAG) -f test.Dockerfile .

.PHONY: test-in-docker
test-in-docker:
	$(DOCKER_BUILD)
	docker run $(BASH_TAG)

.PHONY: docker-shell
docker-shell:
	$(DOCKER_BUILD)
	docker run -it --rm $(BASH_TAG) /usr/local/bin/bash
