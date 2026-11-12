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
#      for character, and so is the tracer file (if the deck has     #
#      tracers), every row to the last digit, and so is the history  #
#      file (if the deck has snapshots), byte for byte. Only the     #
#      clock times are left out: wall and CPU time, the heartbeat's  #
#      wall column, the time stamps and wall time in the files'      #
#      headers and the tracer file's trailer, and the history file's #
#      text block (it names the build and the start time). The run's #
#      pictures (section 9) must be the same files, byte for byte.   #
#                                                                      #
#  Why identical, not "close": every cell gets the same arithmetic on  #
#  any thread, and what the threads combine (minimums, maximums,       #
#  counts) does not depend on the order (maincode section 7). A        #
#  difference in the last digit means a race condition.               #
#                                                                      #
#  A serial build (make OMPFLAGS=) or a one-processor machine has      #
#  nothing to compare, so the script says so and passes.               #
#                                                                      #
#  One line per deck and thread count as it finishes, with a counter   #
#  (tests/report.sh); the first count's time includes the 1-thread     #
#  run it is compared with.                                            #
#**********************************************************************#
BIN=${BIN:-./bin/bitwhiz}
BIN=$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")    # absolute
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
. "$(dirname "$0")/report.sh"

DECKS="input/me697_double_shock_2p00.deck
tests/decks/ok_setup_counter.deck
tests/decks/ok_plate_spall.deck
tests/decks/ok_method_rs.deck
tests/decks/ok_method_rs_order1.deck
tests/decks/ok_profile_hist.deck
tests/decks/ok_temperature.deck
tests/decks/ok_temperature_rs.deck
tests/decks/ok_hvrb.deck
tests/decks/ok_hvrb_rs.deck
tests/decks/ok_tcas.deck
tests/decks/ok_tcas_rs.deck
tests/decks/ok_ffire.deck
tests/decks/ok_ffire_rs.deck"

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

# Everything printed from section 6 on, without the clock times and
# without section 8 (the files' sizes on disk: the files hold build and
# clock lines, which are meant to differ).
results() {   # $1 = screen output
   awk '/ 6\. Initialization/ {on=1} / 8\. Output files/ {on=0}
        / 9\. Pictures/ {on=1} /run end/ {on=0} on' "$1" |
      grep -vE 'Wall time|wall clock|CPU time|Threads in the time loop'
}
# The heartbeat, without time stamps, build lines and the wall column.
beats() {     # $1 = heartbeat file
   grep -vE '^# (started|ended|version|built|flags)' "$1" |
      awk '/^#/ {print; next} {$NF=""; print}'
}

# The tracer file, without the trailer's time stamps, build lines and
# wall time (and with no file at all, nothing).
rows() {      # $1 = folder of one run
   f=$(ls "$1"/*.tracers.csv 2>/dev/null) || return 0
   grep -vE '^# (started|ended|version|built|flags|cycles)' "$f"
}

# The history file without its text block (build lines and clock
# times, which differ between any two runs): bytes 0 to header_bytes -
# text_bytes, then every frame. No file, no output.
hbody() {     # $1 = folder of one run
   f=$(ls "$1"/*.hist 2>/dev/null) || return 0
   hb=$(od -An -t d4 -j 12 -N 4 "$f" | tr -d ' ')
   tb=$(od -An -t d4 -j 52 -N 4 "$f" | tr -d ' ')
   head -c $((hb - tb)) "$f"
   tail -c +$((hb + 1)) "$f"
}

# The pictures (section 9 of a run): the same files, byte for byte.
# Prints the first difference, if any.
pics_same() {  # $1, $2 = folders of two runs
   a=$(cd "$1" && ls *.bmp 2>/dev/null | tr '\n' ' ')
   b=$(cd "$2" && ls *.bmp 2>/dev/null | tr '\n' ' ')
   [ "$a" = "$b" ] || { echo "different pictures: $a / $b"; return; }
   for f in $a; do
      cmp -s "$1/$f" "$2/$f" || { echo "$f differs"; return; }
   done
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

plan $(( $(echo "$DECKS" | wc -w) * $(echo $counts | wc -w) )) "omp tests"

for deck in $DECKS; do
   name=$(basename "$deck" .deck)
   ref="$TMP/$name/t1"; first=1
   for n in $counts; do
      begin
      t="$deck, $n threads"
      if [ $first -eq 1 ]; then        # the 1-thread run, to compare with
         first=0; mkdir -p "$ref"
         with_threads "$deck" 1 > "$ref/run.deck"
         (cd "$ref" && "$BIN" run.deck > screen.out 2>&1) || touch "$ref/failed"
      fi
      if [ -f "$ref/failed" ]; then
         fail "$t" "the run on 1 thread did not finish (nothing to compare)"; continue
      fi
      d="$TMP/$name/t$n"; mkdir -p "$d"
      with_threads "$deck" "$n" > "$d/run.deck"
      if ! (cd "$d" && "$BIN" run.deck > screen.out 2>&1); then
         fail "$t" "the run did not finish"; continue
      fi
      used=$(grep 'Threads in the time loop' "$d/screen.out" | awk -F: '{print $2+0}')
      if [ "$used" != "$n" ]; then
         fail "$t" "the time loop used ${used:-?} threads"; continue
      fi
      if ! diff <(results "$ref/screen.out") <(results "$d/screen.out") > "$d/diff" ; then
         fail "$t" "prints different results than 1 thread:"
         head -4 "$d/diff" | detail; continue
      fi
      hb1=$(ls "$ref"/*.heartbeat); hbn=$(ls "$d"/*.heartbeat)
      if ! diff <(beats "$hb1") <(beats "$hbn") > "$d/diff" ; then
         fail "$t" "the heartbeat differs from 1 thread:"
         head -4 "$d/diff" | detail; continue
      fi
      if ! diff <(rows "$ref") <(rows "$d") > "$d/diff" ; then
         fail "$t" "the tracer file differs from 1 thread:"
         head -4 "$d/diff" | cut -c1-120 | detail; continue
      fi
      if ! cmp -s <(hbody "$ref") <(hbody "$d"); then
         fail "$t" "the history file differs from 1 thread"; continue
      fi
      bad=$(pics_same "$ref" "$d")
      if [ -n "$bad" ]; then
         fail "$t" "$bad"; continue
      fi
      pass "$t"
   done
done

summary "threads:$counts; $nprocs processors"
