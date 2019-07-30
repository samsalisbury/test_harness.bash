#!/usr/bin/env bash

# test_harness.bash is a lightweight bash test harness, similar (ish) to BATS,
# except it is a single file, designed to be copied into your repo.
# Its interface and output are strongly influenced by 'go test' and the golang
# 'testing' package.
#
# To write a test, create an executable file called <filename>.test, which
# uses a bash shebang line, e.g. '#!/usr/bin/env bash' and then sources this file
# e.g. 'source test_harness.bash. You can then write tests in the following
# format (note each test must be in parentheses to make it a subshell).
#
#   #!/usr/bin/env bash
#
#   source test_harness.bash
#
#   (
#     begin_test some-unique-test-name
#     
#     [ $((1+1)) = 2 ] || error "maths is broken"
#     true || fatal "logic is broken"
#     
#     run some command you want to test
#   )
#
# After calling begin_test you will be in a fresh, empty working directory
# named .testdata/<test-file-name>/<test-name>/work so you can safely create
# files etc in the current directory.
# 
# Use 'run' to run arbitrary commands, ensuring their output is logged properly.
# if the command fails, the test is marked as failed.
# Use 'error' to fail the test with an error message, but allow it to continue.
# Use 'fatal' to fail the test with an error message immediately.
#
# Executing tests
#
# You can directly invoke the test files by calling ./<filename>.test, or
# invoke ./test_harness.bash to run all test files in the filesystem hierarchy
# rooted in the current directory.

set -euo pipefail

# SINGLE_FILE_MODE is true when we are sourcing this script in a *.test file.
SINGLE_FILE_MODE=true
[ "${BASH_SOURCE[*]}" != "${BASH_SOURCE[0]}" ] || SINGLE_FILE_MODE=false

# _indent is the current log indent level. It is only ever increased,
# we use subshells to run tests, so it starts out the same at the beginning
# of every test.
export _indent=""

export TESTDATA_ROOT="$PWD/.testdata"

export LOG_LEVEL="${LOG_LEVEL:-1}"
[ "${QUIET:-}"   != YES ] || LOG_LEVEL=0
[ "${VERBOSE:-}" != YES ] || LOG_LEVEL=1
[ "${DEBUG:-}"   != YES ] || LOG_LEVEL=2
  

setup_single_test_file() {
  export TEST_FILE_NAME="${0%.test}"
  TEST_FILE_NAME="${TEST_FILE_NAME#./}"  
 
  # SUITEDATA contains all the individual TESTDATA dirs, as well
  # as files with metadata about the test run for this test suite.
  export SUITEDATA="$TESTDATA_ROOT/$TEST_FILE_NAME"
  rm -rf "$SUITEDATA"
  mkdir -p "$SUITEDATA"
  _TESTCOUNTER="$SUITEDATA/test-count"
  _FAILCOUNTER="$SUITEDATA/fail-count"
}

# _println is an internal function, it prints a formatted line at the
# current indent.
# Parameters: 1: LEVEL, 2: FORMAT, *: FORMAT_ARGS
_println() { LEVEL="$1" FMT="$2"; shift 2
  test "$LEVEL" -gt "$LOG_LEVEL" || printf "%s$FMT\n" "$_indent" "$@"
}

# _println_withline is like _println but adds the file and line number.
# _println_withline should not be called from tests, only by logging functions.
# Parameters: 1: CALL_DEPTH, 2: LEVEL, 3: FORMAT, *: FORMAT_ARGS
_println_withline() { DEPTH="$1"; LEVEL="$2" FMT="$3"; shift 3
  LINEREF="${BASH_SOURCE[$DEPTH]#./}:${BASH_LINENO[$((DEPTH-1))]}"
  _println "$LEVEL" "$LINEREF: $FMT" "$@"
}

# Logging functions you can use in your tests.
debug() { _println_withline 2 2 "$@" >> "$TESTDATA/log"; }
# log uses level 0 because we either print the whole log or none of it at the end.
# If we are printing the log, then we want all log entries, whether printing was
# caused by failure or because we are in verbose mode.
log()   { _println_withline 2 0 "$@" >> "$TESTDATA/log"; }
error() { _println_withline 2 0 "$@" >> "$TESTDATA/log"; _add_error; }
fatal() { _println_withline 2 0 "$@" >> "$TESTDATA/log"; _add_error; exit 0; }

debug_noline() { _println 2 "$@" >> "$TESTDATA/log"; }
log_noline()   { _println 0 "$@" >> "$TESTDATA/log"; }
error_noline() { _println 0 "$@" >> "$TESTDATA/log"; _add_error; }
fatal_noline() { _println 0 "$@" >> "$TESTDATA/log"; _add_error; exit 0; }

# Logging functions for internal use (no line numbers, no errors, print direct).
_debug() { _println 2 "$@"; }
_log()   { _println 1 "$@"; }
_error() { _println 0 "$@"; }
_fatal() { _println 0 "$@"; exit 1; }

# Counter functions all use files to maintain counters. This is slow but allows
# us to count accross different subshells, which is important.
_count_read()  { cat "$1" 2> /dev/null || echo 0; }
_count_up()    { echo $(($(_count_read "$1") + 1)) > "$1"; }

# Test file scoped counters.
_add_test() { _count_up "$_TESTCOUNTER"; }
_test_count() { _count_read "$_TESTCOUNTER"; }
_add_fail() { _count_up "$_FAILCOUNTER"; }
_fail_count() { _count_read "$_FAILCOUNTER"; }


# _ERRCOUNTER is set by begin_test.
_add_error() { _count_up "$_ERRCOUNTER"; }
_error_count() { _count_read "$_ERRCOUNTER"; }

_match() { echo "$1" | grep -E "$2" > /dev/null >&1 || return 1; }

trap _handle_file_exit EXIT

_handle_file_exit() {
  CODE=$?
  $SINGLE_FILE_MODE || exit $CODE

  FAIL_COUNT="$(_fail_count)"
  [ "$FAIL_COUNT" = 0 ] || {
    _error FAIL
    _error "fail      $TEST_FILE_NAME" 
    exit 1
  }
  _log PASS
  _error "ok        $TEST_FILE_NAME" 
  exit 0
}

_handle_test_error() {
  DEPTH=1
  LINEREF="${BASH_SOURCE[$DEPTH]#./}"
  error_noline "Command failed: $1"
  _add_fail
}

# _handle_test_exit always overrides the exit code to zero so that further tests can run
# in spite of set -e. It first sniffs the exit code, as a non-zero test exit code must fail
# the test. It then checks the error count, increments the test fail count if necessary and
# prints the result.
_handle_test_exit() {
  TEST_EXIT_CODE=$?
  [ $TEST_EXIT_CODE = 0 ] || error_noline "Test body failed with exit code $TEST_EXIT_CODE"
  EC="$(_error_count)"
  [ "$EC" != 0 ] || {
    _log "--- PASS: $TEST_ID (TODO:time)"
    test "$LOG_LEVEL" -eq 0 || _dump_test_log
    exit 0
  }
  _add_fail
  _error "--- FAIL: $TEST_ID (TODO:time)"
  _dump_test_log
  exit 0
}

_dump_test_log() { LC_ALL=C sed 's/^/    /g' < "$TESTDATA/log"; }

begin_test() {
  # Determine test name and remove any old test data for this test.
  export TEST_NAME="$1"
  export TEST_ID="$TEST_FILE_NAME/$TEST_NAME"
  export TESTDATA="$SUITEDATA/$TEST_NAME"
  rm -rf "$TESTDATA"
  mkdir -p "$TESTDATA"
  touch "$TESTDATA/log"

  # Apply RUN filtering if any.
  [ -z "${RUN:-}" ] || match "TEST_ID" "$RUN" || {
    debug "=== NORUN $TEST_ID: Name does not match RUN='$RUN'"
    exit 0
  }
  _add_test; _log "=== RUN   $TEST_ID"

  trap '_handle_test_error "$BASH_COMMAND"' ERR
  trap _handle_test_exit EXIT

  export _ERRCOUNTER="$TESTDATA/error-count"
  
  TEST_WORKDIR="$TESTDATA/work"
  mkdir -p "$TEST_WORKDIR"
  
  cd "$TEST_WORKDIR"
}

# run runs the command in a subshell and captures the output in the log.
run() {
  echo "\$" "$@" >> "$TESTDATA/log"
  (
    exec >> "$TESTDATA/log" 2>&1
    "$@"
  )
}

run_all_test_files() {
  export TESTHARNESS="${BASH_SOURCE[0]}"
  # shellcheck disable=SC2044
  for F in $(find . -mindepth 1 -maxdepth 1 -name '*.test'); do
    [ -x "$F" ] || {
      _log "$F is not executable"
      continue
    }
    grep -F 'test_harness.bash' "$F" > /dev/null 2>&1 || {
      _log "$F does not mention test_harness.bash"
      continue
    }
    "$F"
  done
}

if $SINGLE_FILE_MODE; then setup_single_test_file; else run_all_test_files; fi
