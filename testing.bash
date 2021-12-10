#!/usr/bin/env bash

# testing.bash is a lightweight bash test harness, similar (ish) to BATS,
# except it is a single file, designed to be copied into your repo.
# Its interface and output are strongly influenced by 'go test' and the golang
# 'testing' package.
#
# To write a test, create an executable file called <filename>.test, which
# uses a bash shebang line, e.g. '#!/usr/bin/env bash' and then sources this file
# e.g. 'source testing.bash. You can then write tests as functions with names
# beginning with "Test":
#
#   #!/usr/bin/env bash
#
#   source testing.bash
#
#   TestExample() {
#     [ $((1+1)) = 2 ] || error "maths is broken"
#     true || fatal "logic is broken"
#     run some command you want to test
#   }
#
# Each test is run in a fresh, empty working directory
# named .testdata/<test-file-name>/<test-name>/work so you can safely create
# files and directories in the current directory.
# 
# Use 'run' to run arbitrary commands, ensuring their output is logged properly.
# if the command fails, the test is marked as failed.
# Use 'mustrun' in a similar way to 'run' except that failures are treated as
# fatal, and immediately end the test.
# Use 'error' to fail the test with an error message, but allow it to continue.
# Use 'fatal' to fail the test with an error message immediately.
#
# Executing tests
#
# You can directly invoke the test files by calling ./<filename>.test, or
# invoke ./testing.bash to run all test files in the filesystem hierarchy
# rooted in the current directory.


if ! ${TESTING_BASH_SOURCED:-false}; then

# Never export TESTING_BASH_SOURCED because we sometimes need to spawn additional
# instances of testing.bash which need to themselves also source testing.bash.
TESTING_BASH_SOURCED=true

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
  -x               Bash set -x
  -run <pattern>   Filter tests by regex <pattern>          (sets RUN=<pattern>)
  -list            List all tests (after -run filtering)    (sets LIST_ONLY=YES)
  -notime          Do not print test durations.             (sets NOTIME=YES)

echo BASH_SOURCE=${BASH_SOURCE[*]}

${MADE_WITH}testing.bash - simple bash test harness inspired by golang"
}

# TEST_PATHS are the paths to test (only relevant when calling this directly).
TEST_PATHS=()

# Flags
while [ ! $# -eq 0 ]; do
  case "$1" in
    -h | --help)
      show_help; exit ;;
    -v)
      export VERBOSE=YES ;;
    -d)
      export DEBUG=YES ;;
    -x)
      export DEBUG=YES && set -x;;
    -run)
      shift
      [[ -n "${1:-}" ]] || { echo '-run flag requires argument'; exit 1; }
      export RUN="$1" ;;
    -list)
      export LIST_ONLY=YES ;;
    -notime)
      export NOTIME=YES ;;
    *)
      TEST_PATHS+=("$1") ;;
  esac
  shift
done

# SINGLE_FILE_MODE is true when we are sourcing this script in a *.test file.
SINGLE_FILE_MODE=true
[ "${BASH_SOURCE[*]}" != "${BASH_SOURCE[0]}" ] || SINGLE_FILE_MODE=false

$SINGLE_FILE_MODE && [[ "${TEST_PATHS:-}" != "" ]] && {
  echo "Unrecognised args for single file mode: ${TEST_PATHS[*]}"
}

$SINGLE_FILE_MODE || { [[ ${#TEST_PATHS} -ne 0 ]] || { show_help; exit 1; }; }

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
  printf "%s$FMT\n" "$_indent" "$@"
}
export HELPER_DEPTH=0
# _println_withline is like _println but adds the file and line number.
# _println_withline should not be called from tests, only by logging functions.
# Parameters: 1: CALL_DEPTH, 2: LEVEL, 3: FORMAT, *: FORMAT_ARGS
_println_withline() { DEPTH="$1"; LEVEL="$2" FMT="$3"; shift 3
  set +o functrace
  # For some reason when using helper funcs, we need to add some extra depth.
  # I would like to understand exactly what is going on here.
  DEPTH=$((DEPTH+2))
  DEPTH=2
  HELPER_DEPTH="${HELPER_DEPTH:-0}"
  DEPTH=$((DEPTH+HELPER_DEPTH))
  LINEREF="${BASH_SOURCE[$DEPTH]#./}:${BASH_LINENO[$((DEPTH-1))]}"
  _println "$LEVEL" "$LINEREF: $FMT" "$@"
}

# helper indicates that the function which calls it is a helper, meaning line
# numbers reported for logs should be those of the calling function.
helper() {
  (( HELPER_DEPTH+=2 ))
  trap unhelper RETURN
}
unhelper() {
  (( HELPER_DEPTH != 0 )) || {
    trap - RETURN # Once we hit a zero helper depth, remove the trap.
    return
  }
  (( HELPER_DEPTH-- ))
}

# Logging functions you can use in your tests.
debug() { _println_withline ${DEPTH:-0} 2 "$@" >> "$TESTDATA/log"; }
# log uses level 0 because we either print the whole log or none of it at the end.
# If we are printing the log, then we want all log entries, whether printing was
# caused by failure or because we are in verbose mode.
log()   { _println_withline ${DEPTH:-0} 0 "$@" >> "$TESTDATA/log"; }
error() { _println_withline ${DEPTH:-0} 0 "$@" >> "$TESTDATA/log"; _add_error; }
fatal() { _println_withline ${DEPTH:-0} 0 "$@" >> "$TESTDATA/log"; _add_error; exit 0; }
skip()  { _println_withline ${DEPTH:-0} 0 "$@" >> "$TESTDATA/log"; _add_skip; exit 0; }

debug_noline() { _println 2 "$@" >> "$TESTDATA/log"; }
log_noline()   { _println 0 "$@" >> "$TESTDATA/log"; }
error_noline() { _println 0 "$@" >> "$TESTDATA/log"; _add_error; }
fatal_noline() { _println 0 "$@" >> "$TESTDATA/log"; _add_error; exit 0; }

# Logging functions for internal use (no line numbers, no errors, print direct).
_debug() { _println 2 "$@"; }
_log()   { _println 1 "$@"; }
_error() { _println 0 "$@"; }
_fatal() { _println 0 "$@"; exit 0; }

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
test_failed() { [[ "$(_error_count)" -ne 0 ]]; }

# _SKIPCOUNTER is set by begin_test.
_add_skip() { _count_up "$_SKIPCOUNTER"; }
_skip_count() { _count_read "$_SKIPCOUNTER"; }
test_skipped() { [[ "$(_skip_count)" -ne 0 ]]; }

_match() { echo "$1" | grep -E "$2" > /dev/null >&1 || return 1; }

_HAS_RUN_TESTS=false

trap _handle_file_exit EXIT

_handle_file_exit() {
  CODE=$?
  $SINGLE_FILE_MODE || exit $CODE
  [[ $CODE = 0 ]]  || exit $CODE

  if ! $_HAS_RUN_TESTS; then
    _HAS_RUN_TESTS=true
    # Get all the functions named Test...
    if TESTS="$(declare -F | cut -d' ' -f3 | grep -E '^Test')"; then
      # Arrange test by their order in the source code (i.e. sort by line number).
      # shellcheck disable=SC2086 # We want word-splitting for $TESTS.
      TESTS="$(shopt -s extdebug && declare -F $TESTS | sort -k2n | cut -d' ' -f1 )"
      trap _handle_file_exit EXIT
      # shellcheck disable=SC2086
      run_tests $TESTS
    fi
  fi

  # Do not print status in list only mode.
  [[ "${LIST_ONLY:-}" = YES ]] && exit 0

  TEST_COUNT="$(_test_count)"
  if [[ "$TEST_COUNT" = 0 ]]; then
    _error "ok        $TEST_FILE_NAME [no tests run]"
    exit $CODE
  fi

  # Dump test_count in debug mode.k
  [[ $LOG_LEVEL -gt 1 ]] && { echo "Tests run: $TEST_COUNT"; }

  FAIL_COUNT="$(_fail_count)"
  [ "$FAIL_COUNT" = 0 ] || {
    _error FAIL
    _error "fail      $TEST_FILE_NAME" 
    exit 1
  }
  _error PASS
  _error "ok        $TEST_FILE_NAME" 
  exit 0
}

error_trap() {
  # Hack to get proper line number for failing commands in old versions of Bash.
  export CUR_LINE_NO=
  export PREV_LINE_NO=
  # Simply using this DEBUG trap fixes the BASH_COMMAND var in _handle_test_error below.
  #if (( ${BASH_VERSION%%.*} <= 3 )) || [[ ${BASH_VERSION%.*} = 4.0 ]]; then
    set -o functrace
    trap 'PREV_LINE_NO=$CUR_LINE_NO; CUR_LINE_NO=$LINENO' DEBUG
  #fi
  # End hack.
  
  trap '_handle_test_error "$BASH_COMMAND" "${BASH_LINENO}" "$PREV_LINE_NO" "$?"' ERR
}

run_tests() {
  for T in "$@"; do
    # Because these tests run during the EXIT trap handler, we cannot define a
    # new EXIT handler. Therefore, we wrap the test in a function and handle
    # test exit using the RETURN trap instead.
    test_wrapper() {
      set_test_info "$T"
      # If debug, print the name and location of this test func. 
      [[ $LOG_LEVEL -gt 1 ]] && { shopt -s extdebug; declare -F "$T"; }
      error_trap
      trap '_handle_test_exit' EXIT
      begin_test "$T"
	  set -E +e
      $T
      return $?
    }
	( test_wrapper; )
  done
  wait
}

_handle_test_error() {
  COMMAND="$1"
  LINE_NUM="${3:-$2}"
  DEPTH=1
  LINEREF="${BASH_SOURCE[$DEPTH]#./}"
  if [ "$LINEREF" = "../testing.bash" ]; then return 0; fi
  error_noline "$LINEREF:$LINE_NUM: Command failed with exit code $4: $COMMAND"
  _add_error
  exit 0
}

if [[ "${NOTIME:-}" == YES ]]; then
	start_timer() { true; }
	read_timer() { true; }
else
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
fi


# _handle_test_exit always overrides the exit code to zero so that further tests can run
# in spite of set -e. It first sniffs the exit code, as a non-zero test exit code must fail
# the test. It then checks the error count, increments the test fail count if necessary and
# prints the result.
_handle_test_exit() {
  TEST_EXIT_CODE=$?
  D="$(read_timer "$TESTDATA/start-time")"
  [ $TEST_EXIT_CODE = 0 ] || error_noline "Test body failed with exit code $TEST_EXIT_CODE"
  if test_failed; then
    _add_fail
    _error "--- FAIL: $TEST_ID${D}"
    _dump_test_log
  elif test_skipped; then
    _log "--- SKIP: $TEST_ID${D}"
    test "$LOG_LEVEL" -eq 0 || _dump_test_log
  else
    _log "--- PASS: $TEST_ID${D}"
    test "$LOG_LEVEL" -eq 0 || _dump_test_log
  fi
  exit 0
}

_dump_test_log() { LC_ALL=C sed 's/^/    /g' < "$TESTDATA/log"; }

match() { echo "$1" | grep -E "$2" > /dev/null 2>&1; }

set_test_info() {
  # Determine test name and remove any old test data for this test.
  export TEST_NAME="$1"
  export TEST_ID="$TEST_FILE_NAME/$TEST_NAME"
  export TESTDATA="$SUITEDATA/$TEST_NAME"
  rm -rf "$TESTDATA"
  mkdir -p "$TESTDATA"
  touch "$TESTDATA/log"
  export _ERRCOUNTER="$TESTDATA/error-count"
  export _SKIPCOUNTER="$TESTDATA/skip-count"

  # Apply RUN filtering if any.
  [ -z "${RUN:-}" ] || match "$TEST_ID" "$RUN" || {
    debug "=== NOT RUNNING $TEST_ID: Name does not match RUN='$RUN'"
    exit 0
  }

  # In LIST_ONLY mode, just print the test ID and exit.
  if [[ "${LIST_ONLY:-}" = YES ]]; then echo "$TEST_ID"; exit 0; fi
}

begin_test() {
  set_test_info "$1"

  start_timer "$TESTDATA/start-time"
  _add_test; _log "=== RUN   $TEST_ID"

  #trap '_handle_test_error "$BASH_COMMAND" "${BASH_LINENO}" "$PREV_LINE_NO" "$?"' ERR
  #trap _handle_test_exit EXIT
  
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
  EXIT_CODE=0
  set -e +Eo pipefail
  { { "$@" 2> >(tee -a "$_COM" >> "$_ERR") > >(tee -a "$_COM" >> "$_OUT")
  } 3>&1 >&4 4>&- | cat; } 4>&1
  #EXIT_CODE=${PIPESTATUS[0]}
  for EC in $? "${PIPESTATUS[@]}"; do
    if [[ $EC != "0" ]]; then EXIT_CODE=$EC; fi
  done
  cat "$_COM" >> "$TESTDATA/log"
  COMBINED="$(cat "$_COM")"
  STDOUT="$(cat "$_OUT")"
  STDERR="$(cat "$_ERR")"
  export COMBINED STDOUT STDERR EXIT_CODE
  export COMBINED_FILE="$_COM" STDOUT_FILE="$_OUT" STDERR_FILE="$_ERR"
}

# mustrun is like run except if the command fails, it is a fatal error.
mustrun() {
  run "$@"
  (( EXIT_CODE == 0 )) || {
    helper
    fatal "Command failed with exit code $EXIT_CODE"
  }
}

run_test_files() {
  if [[ "${TEST_PATHS[*]}" = "./..." ]]; then
    run_all_test_files
    exit 0
  fi
  if [[ ${#TEST_PATHS[@]} -ne 0 ]]; then
    for F in "${TEST_PATHS[@]}"; do
      ( cd "$(dirname "$F")" && ./"$(basename "$F")"; )
    done
    exit 0
  fi
}

run_all_test_files() {
  # shellcheck disable=SC2044
  for F in $(find . -type f -mindepth 1 -name '*.test' -not -path '*/.*'); do
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

if $SINGLE_FILE_MODE; then setup_single_test_file; else run_test_files; fi

fi # End TESTING_BASH_SOURCED check.
