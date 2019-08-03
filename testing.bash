#!/usr/bin/env bash

# testing.bash is a lightweight bash test harness, similar (ish) to BATS,
# except it is a single file, designed to be copied into your repo.
# Its interface and output are strongly influenced by 'go test' and the golang
# 'testing' package.
#
# To write a test, create an executable file called <filename>.test, which
# uses a bash shebang line, e.g. '#!/usr/bin/env bash' and then sources this file
# e.g. 'source testing.bash. You can then write tests in the following
# format (note each test must be in parentheses to make it a subshell).
#
#   #!/usr/bin/env bash
#
#   source testing.bash
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
# invoke ./testing.bash to run all test files in the filesystem hierarchy
# rooted in the current directory.

set -euo pipefail

show_help() {
NAME="$0"
MADE_WITH="Made with "
[[ "$0" = "./testing.bash" ]] && MADE_WITH=""
echo "Usage: $NAME [options] [path]
Options:
  -h --help        Show this help.
  -v               Verbose mode                             (sets VERBOSE=YES)
  -d               Debug mode                               (sets DEBUG=YES)
  -run <pattern>   Filter tests by regex <pattern>          (sets RUN=<pattern>)
  -list            List all tests (after -run filtering)    (sets LIST_ONLY=YES)
  -notime          Do not print test durations.             (sets NOTIME=YES)

echo BASH_SOURCE=${BASH_SOURCE[*]}

${MADE_WITH}testing.bash - simple bash test harness inspired by golang"

}

# TEST_PATHS are the paths to test (only relevant when calling this directly).
TEST_PATHS=

# Flags
while [ ! $# -eq 0 ]; do
  case "$1" in
    -h | --help)
      show_help; exit ;;
    -v)
      export VERBOSE=YES ;;
    -d)
      export DEBUG=YES ;;
    -run)
      shift; export RUN="$1" ;;
    -list)
      export LIST_ONLY=YES ;;
    -notime)
      export NOTIME=YES ;;
    *)
      TEST_PATHS="$TEST_PATHS $1" ;;
  esac
  shift
done

# SINGLE_FILE_MODE is true when we are sourcing this script in a *.test file.
SINGLE_FILE_MODE=true
[ "${BASH_SOURCE[*]}" != "${BASH_SOURCE[0]}" ] || SINGLE_FILE_MODE=false

$SINGLE_FILE_MODE && [ -n "$TEST_PATHS" ] && {
  echo "Unrecognised args for single file mode: $TEST_PATHS"
}

# _indent is the current log indent level. It is only ever increased,
# we use subshells to run tests, so it starts out the same at the beginning
# of every test.
export _indent=""

export TESTDATA_ROOT="$PWD/.testdata"

export LOG_LEVEL="${LOG_LEVEL:-0}"
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
  if test "$LEVEL" -gt "$LOG_LEVEL"; then return; fi
  printf "%s$FMT\n%s" "$_indent" "$*"
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

_HAS_RUN_TESTS=false

trap _handle_file_exit EXIT

_handle_file_exit() {
  CODE=$?
  $SINGLE_FILE_MODE || exit $CODE

  if ! $_HAS_RUN_TESTS; then
    _HAS_RUN_TESTS=true
    if TESTS="$(declare -F | cut -d' ' -f3 | grep -E '^Test')"; then
      trap _handle_file_exit EXIT
      # shellcheck disable=SC2086
      run_tests $TESTS
    fi
  fi

  # Do not print status in list only mode.
  [[ "${LIST_ONLY:-}" = YES ]] && exit 0

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

run_tests() {
  for T in "$@"; do
  (
    # Because these tests run during the EXIT trap handler, we cannot define a
    # new EXIT handler. Therefore, we wrap the test in a function and handle
    # test exit using the RETURN trap instead.
    test_wrapper() {
      begin_test "$T"
      trap '_handle_test_exit' RETURN
      # If debug, print the name and location of this test func.
      [[ $LOG_LEVEL -gt 1 ]] && { shopt -s extdebug; declare -F "$T"; }
      $T
    }
    test_wrapper
  )
  done
  wait
}

_handle_test_error() {
  DEPTH=1
  LINEREF="${BASH_SOURCE[$DEPTH]#./}"
  error_noline "Command failed: $1"
  _add_error
}

if [[ "${NOTIME:-}" != YES ]]; then
# Sniff out gdate (GNU date as installed by homebrew on Mac), use that if available.
# GNU date allows microsecond accuracy, so is always preferable.
[ -z "${DATE_PROG:-}" ] && command -v gdate > /dev/null 2>&1 && DATE_PROG="gdate"
[ -z "${DATE_PROG:-}" ] && DATE_PROG="date"
# Generate a date using the selected program, so we can check if it supports %N.
TEST_DATE="$("$DATE_PROG" +%s%N)"
if [[ ${#TEST_DATE} -gt 13 ]]; then
now_nano() { $DATE_PROG +%s%N; } # Using high precision timing.
format_duration() {
  printf " (%.3fs)" "$(bc <<< "scale=3; (($END - $START) / 1000000000)")"
}
else
TIP="Try installing coreutils."
[[ "$(uname)" = Darwin ]] && TIP="Try 'brew install coreutils'."
echo "WARNING: Please install GNU date for high precision timers. $TIP" 1>&2
now_nano() { $DATE_PROG +%s000000000; } # Only second precision available.
format_duration() {
  printf " (%ss)" "$(bc <<< "scale=0; (($END - $START) / 1000000000000)")"
}
fi
start_timer() { now_nano > "$1"; }
read_timer() { END=$(now_nano) && START="$(cat "$1")" && format_duration; }
else
start_timer() { true; }
read_timer() { true; }
fi


# _handle_test_exit always overrides the exit code to zero so that further tests can run
# in spite of set -e. It first sniffs the exit code, as a non-zero test exit code must fail
# the test. It then checks the error count, increments the test fail count if necessary and
# prints the result.
_handle_test_exit() {
  TEST_EXIT_CODE=$?
  D="$(read_timer "$TESTDATA/start-time")"
  [ $TEST_EXIT_CODE = 0 ] || error_noline "Test body failed with exit code $TEST_EXIT_CODE"
  EC="$(_error_count)"
  [ "$EC" != 0 ] || {
    _log "--- PASS: $TEST_ID${D}"
    test "$LOG_LEVEL" -eq 0 || _dump_test_log
    exit 0
  }
  _add_fail
  _error "--- FAIL: $TEST_ID${D}"

  _dump_test_log
  exit 0
}

_dump_test_log() { LC_ALL=C sed 's/^/    /g' < "$TESTDATA/log"; }

match() { echo "$1" | grep -E "$2" > /dev/null 2>&1; }

begin_test() {
  # Determine test name and remove any old test data for this test.
  export TEST_NAME="$1"
  export TEST_ID="$TEST_FILE_NAME/$TEST_NAME"
  export TESTDATA="$SUITEDATA/$TEST_NAME"
  rm -rf "$TESTDATA"
  mkdir -p "$TESTDATA"
  touch "$TESTDATA/log"

  # Apply RUN filtering if any.
  [ -z "${RUN:-}" ] || match "$TEST_ID" "$RUN" || {
    debug "=== NOT RUNNING $TEST_ID: Name does not match RUN='$RUN'"
    exit 0
  }

  # In LIST_ONLY mode, just print the test ID and exit.
  [[ "${LIST_ONLY:-}" = YES ]] && { echo "$TEST_ID"; exit 0; }

  start_timer "$TESTDATA/start-time"
  _add_test; _log "=== RUN   $TEST_ID"

  export _ERRCOUNTER="$TESTDATA/error-count"

  trap '_handle_test_error "$BASH_COMMAND"' ERR
  trap _handle_test_exit EXIT
  
  TEST_WORKDIR="$TESTDATA/work"
  mkdir -p "$TEST_WORKDIR"
  
  cd "$TEST_WORKDIR"
}

# run runs the command supplied and captures the combined output in the log.
# It also exports the stdout, stderr and combined outputs in the variables
# STDOUT, STDERR and COMBINED respectively, and the exit code in EXIT_CODE.
run() {
  local OUTDIR="$TESTDATA/run/${BASH_LINENO[1]}-$1"
  [ ! -d "$OUTDIR" ] || fatal_noline "More than one 'run' on the same line."
  mkdir -p "$OUTDIR"
  _COM="$OUTDIR/combined"; _OUT="$OUTDIR/stdout"; _ERR="$OUTDIR/stderr"
  echo "\$" "$@" >> "$TESTDATA/log"
  # This odd construction ensures that the tee process redirects complete
  # before the script continues.
  { { "$@" 2> >(tee -a "$_COM" >> "$_ERR") > >(tee -a "$_COM" >> "$_OUT")
  } 3>&1 >&4 4>&- | cat; } 4>&1
  EXIT_CODE=$?
  cat "$_COM" >> "$TESTDATA/log"
  COMBINED="$(cat "$_COM")"
  STDOUT="$(cat "$_OUT")"
  STDERR="$(cat "$_ERR")"
  export COMBINED STDOUT STDERR EXIT_CODE
  return "$EXIT_CODE"
}

run_all_test_files() {
  export TESTING_BASH="${BASH_SOURCE[0]}"
  # shellcheck disable=SC2044
  for F in $(find . -mindepth 1 -maxdepth 1 -name '*.test'); do
    [ -x "$F" ] || {
      _log "$F is not executable"
      continue
    }
    grep -F 'testing.bash' "$F" > /dev/null 2>&1 || {
      _log "$F does not mention testing.bash"
      continue
    }
    "$F"
  done
}

if $SINGLE_FILE_MODE; then setup_single_test_file; else run_all_test_files; fi
