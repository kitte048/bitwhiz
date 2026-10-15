#!/usr/bin/env bash
#**********************************************************************#
#  OpenMP tests: threads must give the serial answer, bit for bit.     #
#  Run from the bitwhiz folder, after 'make':                          #
#                                                                      #
#     ./tests/run_omp_tests.sh                                         #
#                                                                      #
#  Each deck below is run on 1 thread, then on 2, 3, 4 and 8 threads   #
#  (as many of those as the machine has processors for; bitwhiz never  #
#  runs more threads than processors). Every run sets                  #
#  omp_min_zones = 0, so the threads are used even on small meshes.    #
#  A threaded run passes if                                            #
#    - it really used the threads it asked for, and                    #
#    - everything it prints from section 6 on (t = 0 totals, the       #
#      progress lines, errors, tension, breaks, ...) and every         #
#      heartbeat line are IDENTICAL to the 1-thread run, character     #
#      for character. Only the clock times are left out: wall and     #
#      CPU time, and the heartbeat's wall column and time stamps.     #
#                                                                      #
#  Why identical, not "close": every cell gets the same arithmetic on  #
#  any thread, and what the threads combine (minimums, maximums,       #
#  counts) does not depend on the order (maincode section 7). A        #
#  difference in the last digit means a race condition.               #
#                                                                      #
#  A serial build (make OMPFLAGS=) or a one-processor machine has      #
#  nothing to compare, so the script says so and passes.               #
#**********************************************************************#
BIN=${BIN:-./bin/bitwhiz}
BIN=$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")    # absolute
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
npass=0; nfail=0

DECKS="input/me697_double_shock_2p00.deck
tests/decks/ok_setup_counter.deck
tests/decks/ok_plate_spall.deck"

fail() { echo "FAIL  $1: $2"; nfail=$((nfail+1)); }

# The thread counts to try: 2, 3, 4, 8, but no more than the processors.
# (NPROCS=8 ./tests/run_omp_tests.sh overrides the count; only useful
# with a test build of bitwhiz that does not cap threads at processors.)
nprocs=${NPROCS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}
counts=""
for n in 2 3 4 8; do
   [ "$n" -le "$nprocs" ] && counts="$counts $n"
done

# A copy of a deck with the Run block asking for n threads and
# omp_min_zones = 0 (any num_threads / omp_min_zones lines in the deck
# are replaced). Begin Run is found whatever its letter case.
with_threads() {   # $1 = deck, $2 = n
   awk -v n="$2" '
      tolower($0) ~ /^[ \t]*(num_threads|omp_min_zones)[ \t]*=/ { next }
      { print }
      tolower($0) ~ /^[ \t]*begin[ \t]+run[ \t]*(#.*)?$/ {
         print "  num_threads = " n
         print "  omp_min_zones = 0"
      }' "$1"
}

# Everything printed from section 6 on, without the clock times.
results() {   # $1 = screen output
   awk '/ 6\. Initialization/ {on=1} /run end/ {on=0} on' "$1" |
      grep -vE 'Wall time|wall clock|CPU time|Threads in the time loop'
}
# The heartbeat, without time stamps, build lines and the wall column.
beats() {     # $1 = heartbeat file
   grep -vE '^# (started|ended|version|built|flags)' "$1" |
      awk '/^#/ {print; next} {$NF=""; print}'
}

# Is OpenMP compiled in? (Section 3 of any run says so.)
probe=$(cd "$TMP" && "$BIN" "$OLDPWD/tests/decks/ok_setup_one_layer.deck" 2>&1)
if ! echo "$probe" | grep -q 'OpenMP compiled in *: yes'; then
   echo "omp tests: serial build (no OpenMP), nothing to compare"
   exit 0
fi
if [ -z "$counts" ]; then
   echo "omp tests: one processor, nothing to compare"
   exit 0
fi

for deck in $DECKS; do
   name=$(basename "$deck" .deck)
   for n in 1 $counts; do
      d="$TMP/$name/t$n"; mkdir -p "$d"
      with_threads "$deck" "$n" > "$d/run.deck"
      if ! (cd "$d" && "$BIN" run.deck > screen.out 2>&1); then
         fail "$deck" "the run on $n thread(s) did not finish"
         touch "$d/failed"
      fi
   done
   ref="$TMP/$name/t1"
   [ -f "$ref/failed" ] && continue           # nothing to compare against
   for n in $counts; do
      d="$TMP/$name/t$n"
      [ -f "$d/failed" ] && continue           # already reported
      used=$(grep 'Threads in the time loop' "$d/screen.out" | awk -F: '{print $2+0}')
      if [ "$used" != "$n" ]; then
         fail "$deck" "asked for $n threads, the time loop used ${used:-?}"; continue
      fi
      if ! diff <(results "$ref/screen.out") <(results "$d/screen.out") > "$d/diff" ; then
         fail "$deck" "$n threads print different results than 1 thread:"
         head -4 "$d/diff"; continue
      fi
      hb1=$(ls "$ref"/*.heartbeat); hbn=$(ls "$d"/*.heartbeat)
      if ! diff <(beats "$hb1") <(beats "$hbn") > "$d/diff" ; then
         fail "$deck" "$n threads: the heartbeat differs from 1 thread:"
         head -4 "$d/diff"; continue
      fi
      npass=$((npass+1))
   done
done

echo "omp tests: $npass passed, $nfail failed (threads:$counts; $nprocs processors)"
[ $nfail -eq 0 ]
