#!/usr/bin/env bash

set -euo pipefail

SINGLE_FILE_MODE=true
[ "${BASH_SOURCE[*]}" != "${BASH_SOURCE[0]}" ] || SINGLE_FILE_MODE=false

# _indent is the current log indent level. It is only ever increased,
# we use subshells to run tests, so it starts out the same at the beginning
# of every test.
export _indent=""

export TEST_FILE_NAME="${0%.test}"
TEST_FILE_NAME="${TEST_FILE_NAME#./}"

export LOG_LEVEL=0
[ "${QUIET:-}"   != YES ] || LOG_LEVEL=0
[ "${VERBOSE:-}" != YES ] || LOG_LEVEL=1
[ "${DEBUG:-}"   != YES ] || LOG_LEVEL=2

export TESTDATA_ROOT="$PWD/.testdata"

# SUITEDATA contains all the individual test SUITEDATA dirs, as well
# as files with metadata about the test run.
export SUITEDATA="$TESTDATA_ROOT/$TEST_FILE_NAME"
rm -rf "$SUITEDATA"
mkdir -p "$SUITEDATA"

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
log()   { _println_withline 2 1 "$@" >> "$TESTDATA/log"; }
error() { _println_withline 2 0 "$@" >> "$TESTDATA/log"; _add_error; }
fatal() { _println_withline 2 0 "$@" >> "$TESTDATA/log"; _add_error; exit 0; }

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
_TESTCOUNTER="$SUITEDATA/test-count"
_add_test() { _count_up "$_TESTCOUNTER"; }
_test_count() { _count_read "$_TESTCOUNTER"; }
_FAILCOUNTER="$SUITEDATA/fail-count"
_add_fail() { _count_up "$_FAILCOUNTER"; }
_fail_count() { _count_read "$_FAILCOUNTER"; }


# _ERRCOUNTER is set by begin_test.
_add_error() { _count_up "$_ERRCOUNTER"; }
_error_count() { _count_read "$_ERRCOUNTER"; }

_match() { echo "$1" | grep -E "$2" > /dev/null >&1 || return 1; }

trap _handle_file_exit EXIT

_handle_file_exit() {
  $SINGLE_FILE_MODE && {
    FAIL_COUNT="$(_fail_count)"
    [ "$FAIL_COUNT" = 0 ] || {
      _error FAIL
      _error "fail      $TEST_FILE_NAME" 
      exit 1
    }
    _log PASS
    _error "ok        $TEST_FILE_NAME" 
  }
}

_handle_test_error() {
  DEPTH=1
  LINEREF="${BASH_SOURCE[$DEPTH]#./}:$1"
  echo "_handle_test_error:$LINEREF:$2"
}

_handle_test_exit() {
  TEST_EXIT_CODE=$?
  [ $TEST_EXIT_CODE = 0 ] || error "Test body failed with exit code $TEST_EXIT_CODE"
  EC="$(_error_count)"
  [ "$EC" != 0 ] || {
    _log "--- PASS: $TEST_ID (TODO:time)"
    test "$LOG_LEVEL" -eq 0 || _dump_test_log
    exit 1
  }
  _error "--- FAIL: $TEST_ID (TODO:time)"
  _dump_test_log
}

_dump_test_log() { sed 's/^/    /g' < "$TESTDATA/log"; }

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

run_all_test_files() {
  # shellcheck disable=SC2044
  for F in $(find . -mindepth 1 -maxdepth 1 -name '*.test'); do "$F"; done
}

$SINGLE_FILE_MODE || run_all_test_files

#echo "BASH_SOURCE=${BASH_SOURCE[*]}"
