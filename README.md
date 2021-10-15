# testing.bash [![CircleCI](https://circleci.com/gh/samsalisbury/testing.bash.svg?style=svg)](https://circleci.com/gh/samsalisbury/testing.bash)

Simple bash test harness and runner with minimal dependencies.

Benefits:

* No installation required.
* Single file, can be trivially vendored into your project.
* Minimal dependencies: bash, grep, coreutils(tee, cat date, printf)
* Works out-of-the-box on Linux and macOS (Windows support not yet tested.)
* Either run a single test file by direct invocation,
  or target specific files or directories.

## What?

A single file to `source` into other bash files, to make writing bash tests easy.
`testing.bash` can also be invoked itself to locate and run all tests defined in a
directory hirarchy.

This project is heavily inspired by `go test` and the golang `testing` package.

## Why?

Having recently had to write an inordinate amount of bash scripts, I began to miss my
safe place writing Go tests, and thus this project was born.

I also wanted a lightweight script I could trivially vendor into any projects that require
this kind of test.

## How?

Vendor this into your project by copying the single file `testing.bash`,
then write executable test files like this:

```bash
#!/usr/bin/env bash

source testing.bash

TestReadmeExample() {
  # Write arbitrary bash. You are in a new, empty working directory
  # so you can freely create new files etc as part of your tests.

  # Use the `run` helper to run any commands that produce output on stderr or
  # stdout, so you can inspect the output. This also keeps your test output neat,
  # allowing minimal output for tests that pass, whilst showing full transcripts
  # for tests that fail.
  run echo 123

  # Use the `log` helper to write explicit logs to the test outputs, only shown
  # in VERBOSE mode, or when a test fails.
  log "Something interesting happened here."

  # You can add explicit errors like this:
  error "something bad happened"

  # Ideally, make errors conditional on bad things happening, e.g.:
  false || error "oh dear"

  # Or add an error, and immediately fail the test like this:
  fatal "the world ended"

  # After a fatal call, nothing else will execute.
)
```

