#**********************************************************************#
#  The test scripts' report: one line per test as it finishes, so a    #
#  long run can be watched. Sourced (not run) by run_deck_tests.sh,    #
#  run_omp_tests.sh, run_hist_tests.sh and run_release_tests.sh:       #
#                                                                      #
#     . "$(dirname "$0")/report.sh"                                    #
#                                                                      #
#     plan N "deck tests"   before the tests: how many, and the label  #
#     begin                 as each test starts (counter and clock)    #
#     pass NAME             it passed                                  #
#     fail NAME REASON      it failed, and why (once per test)         #
#     detail                a filter: indents what a test prints under #
#                           its FAIL line (a diff, error messages)     #
#     summary [NOTE]        the totals; returns 1 if any test failed,  #
#                           or if the count is not the plan's          #
#                                                                      #
#  What it prints:                                                     #
#                                                                      #
#     deck tests: 129 to run                                           #
#     [  1/129] pass  tests/decks/bad_begin_extra.deck          0.1 s  #
#     [ 37/129] FAIL  tests/decks/bad_cfl.deck: <why>                  #
#     ...                                                              #
#     deck tests: 128 passed, 1 failed (96 s)                          #
#                                                                      #
#**********************************************************************#
npass=0; nfail=0; itest=0; ntest=0; nwid=1; label=tests

plan() {     # $1 = the number of tests, $2 = the label
   ntest=$1; label=$2; nwid=${#ntest}
   echo "$label: $ntest to run"
}

# The clock, in seconds: to 1 us where the shell, date or perl can say
# it, else whole seconds. (bash 5 has EPOCHREALTIME; macOS has bash 3.2
# and a date without %N, but it has perl.)
now() {
   if [ -n "${EPOCHREALTIME:-}" ]; then echo "$EPOCHREALTIME" | tr ',' '.'; return; fi
   local t
   t=$(date +%s.%N 2>/dev/null)
   case $t in
      *[!0-9.]*|'') perl -MTime::HiRes=time -e 'printf "%.6f\n", time' 2>/dev/null ||
                    date +%s ;;
      *) echo "$t" ;;
   esac
}

begin() { itest=$((itest+1)); t0=$(now); }

pass() {     # $1 = the test
   local dt
   dt=$(awk -v a="$t0" -v b="$(now)" 'BEGIN { printf "%.1f", b - a }')
   printf "[%*d/%d] pass  %-48s %6s s\n" "$nwid" "$itest" "$ntest" "$1" "$dt"
   npass=$((npass+1))
}

fail() {     # $1 = the test, $2 = what went wrong
   printf "[%*d/%d] FAIL  %s: %s\n" "$nwid" "$itest" "$ntest" "$1" "$2"
   nfail=$((nfail+1))
}

detail() { sed 's/^/         /'; }

summary() {  # $1 = a note for the totals line (optional)
   echo "$label: $npass passed, $nfail failed ($SECONDS s)${1:+; $1}"
   if [ $((npass + nfail)) -ne "$ntest" ]; then
      echo "$label: FAIL  $((npass + nfail)) tests reported, the plan was $ntest"
      return 1
   fi
   [ "$nfail" -eq 0 ]
}
