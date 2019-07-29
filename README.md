# simple-bash-tests

Simple bash tests is designed to be vendored into your project
by copying the file `test_header.bash` into your project,
and then sourcing it near the beginning of each test file.

## What?

Copy test_header.bash to your repo then
write executable test files that look like this file:

```bash
#!/usr/bin/env bash

source test_header.bash

# Each test must be in a subshell, wrapped in parentheses like this:
(
  # The first line of your test should be 'begin_test <test-name>'
  # Within a given test file, the <test-name> must be unique.
  begin_test some-test-name

  # Write arbitrary bash. You are in a new, empty working directory
  # so you can freely create new files etc as part of your tests.

  # Write assertions like this. The first arg is a description of
  # the fact you are asserting.
  assert "the thing works" [ "WORKS" = "WORKS" ]

  # You can add explicit errors like this:
  error "something bad happened"

  # Or add an error, and immediately fail the test like this:
  fatal "the world ended"

  # After a fatal call, nothing else will execute.
)

(
  begin_test some-other-test-name

  assert "this will fail" [ "WORKS?!" = "NO!" ]
)
```


## Why?

I wanted a simpler thing than BATS,
and wanted it to be trivial to vendor into your project
to avoid extra external dependencies.

## How?


