#!/usr/bin/env bash
#**********************************************************************#
#  History file tests. Run from the bitwhiz folder, after 'make':      #
#                                                                      #
#     ./tests/run_hist_tests.sh                                        #
#                                                                      #
#  Each case runs a deck (some with a key or two changed) and checks   #
#  its <title>.hist with bin/test_hist, which reads it as              #
#  input/README.md, section 9, says to (sizes, tables, text, frames    #
#  numbered and in time order, faces in order, every value finite, P   #
#  = 0 at t = 0, nframes and status filled in). Then, case by case:   #
#                                                                      #
#   - with tracer_dt = plot_dt, the frames must be at exactly the      #
#     tracer rows' cycles, and an interface tracer's x, u and P must   #
#     be the file's values at its face and cell, to single precision   #
#     (this checks the snapshot rule, the slots, AV's u and RS's u*,   #
#     and the face and cell numbering);                                #
#   - with plot_every = 7, the frames are cycles 0, 7, 14, ... and the #
#     last;                                                            #
#   - a run stopped by cycle_max ends its file with status 2 and a     #
#     frame at that cycle;                                             #
#   - a deck with no snapshot keys writes no history file.            #
#**********************************************************************#
BIN=${BIN:-./bin/bitwhiz}
BIN=$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")    # absolute
CHK=$(pwd)/bin/test_hist
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
npass=0; nfail=0

fail() { echo "FAIL  $1: $2"; nfail=$((nfail+1)); }

# A copy of a deck with "key = value" lines put first in a block (any
# lines of the same keys anywhere in the deck are dropped). The block
# must be in the deck. Usage: setkeys deck block 'key = value' ...
setkeys() {
   local deck=$1 block=$2; shift 2
   local keys="" lines="" l
   for l in "$@"; do keys="$keys ${l%% *}"; lines="$lines${lines:+\\n}  $l"; done
   awk -v block="$block" -v keys="$keys" -v lines="$lines" '
      BEGIN { n = split(keys, k, " "); for (i = 1; i <= n; i++) drop[tolower(k[i])] = 1 }
      { w = tolower($1) }
      (w in drop) && $2 == "=" { next }
      { print }
      tolower($0) ~ "^[ \t]*begin[ \t]+" tolower(block) "[ \t]*(#.*)?$" { print lines }
   ' "$deck"
}

# Run a deck in its own folder. Usage: run name deck-text-file
run() {
   mkdir -p "$TMP/$1"
   cp "$2" "$TMP/$1/run.deck"
   (cd "$TMP/$1" && "$BIN" run.deck > screen.out 2>&1)
}

# The tracer named $2 in folder $1: its face (in the history file's
# numbering, from 1) and its cell, from the tracer file's trailer.
# Only for a tracer on a face (an interface).
tracer_place() {
   local line
   line=$(grep "^# tracer [0-9]* $2 :" "$1"/*.tracers.csv)
   echo "$line" | sed -E 's/.*on face ([0-9]+); cell values from cell ([0-9]+).*/\1 \2/' |
      awk '{ print $1 + 1, $2 }'
}

# The tracer file's CYCLE, XPOS, KMPS and GPA columns for tracer $2.
tracer_cols() {
   awk -F', *' -v t="$2" '
      NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i; next }
      NR == 2 || /^#/ { next }
      { print $(c["CYCLE"]), $(c["XPOS." t]), $(c["KMPS." t]), $(c["GPA." t]) }
   ' "$1"/*.tracers.csv
}

# Case: tracer_dt = plot_dt, so frames and tracer rows share their
# cycles; compare an interface tracer with the file at its face/cell.
against_tracer() {   # $1 case name, $2 deck, $3 dt, $4 tracer
   setkeys "$2" Output "plot_dt = $3" "tracer_dt = $3" > "$TMP/$1.deck"
   if ! run "$1" "$TMP/$1.deck"; then fail "$1" "the run did not finish"; return; fi
   local d="$TMP/$1" place
   place=$(tracer_place "$d" "$4")
   if ! "$CHK" "$d"/*.hist 1 $place > "$d/frames"; then
      fail "$1" "test_hist:"; grep FAIL "$d/frames" | head -3; return
   fi
   tracer_cols "$d" "$4" > "$d/rows"
   if ! paste -d' ' "$d/frames" "$d/rows" | awk '
         function rel(a, b) { d = a - b; if (d < 0) d = -d; s = (b < 0 ? -b : b); return d / (s > 1 ? s : 1) }
         NF != 10 { bad = "frames and tracer rows differ in number"; exit 1 }
         $2 != $7 { bad = "frame " NR " is cycle " $2 ", the tracer row cycle " $7; exit 1 }
         rel($4, $8) > 1e-6 || rel($5, $9) > 1e-6 || rel($6, $10) > 1e-6 {
            bad = "cycle " $2 ": x, u, P " $4 " " $5 " " $6 " vs the tracer " $8 " " $9 " " $10; exit 1 }
         END { if (bad != "") { print bad; exit 1 } }' > "$d/diff"; then
      fail "$1" "$(cat "$d/diff")"; return
   fi
   [ "$(wc -l < "$d/frames")" -eq "$(wc -l < "$d/rows")" ] ||
      { fail "$1" "frames and tracer rows differ in number"; return; }
   npass=$((npass+1))
}

against_tracer class_av  input/me697_double_shock_2p00.deck 0.01 pdv
against_tracer rs_order2 tests/decks/ok_method_rs.deck        0.05 impact
against_tracer rs_order1 tests/decks/ok_method_rs_order1.deck 0.05 impact

# Case: plot_every = 7 (the deck's own setting): cycles 0, 7, 14, ...
# and the last.
c=plot_every
if run $c tests/decks/ok_plate_spall.deck; then
   d="$TMP/$c"
   last=$(grep '^ *Cycles  ' "$d/screen.out" | awk -F: '{print $2+0}')
   if ! "$CHK" "$d"/*.hist 1 1 1 > "$d/frames"; then
      fail $c "test_hist:"; grep FAIL "$d/frames" | head -3
   elif ! diff <(awk '{print $2}' "$d/frames") \
               <(awk -v n="$last" 'BEGIN { for (i = 0; i < n; i += 7) print i; print n }') > /dev/null; then
      fail $c "the frames are not cycles 0, 7, 14, ... and the last ($last)"
   else
      npass=$((npass+1))
   fi
else
   fail $c "the run did not finish"
fi

# Case: stopped at cycle_max = 100: status 2, the last frame at 100.
c=cycle_max
setkeys input/me697_double_shock_2p00.deck Run "cycle_max = 100" > "$TMP/$c.deck"
run $c "$TMP/$c.deck"                       # stops early; exit code not 0
d="$TMP/$c"
if ! "$CHK" "$d"/*.hist 2 1 1 > "$d/frames"; then
   fail $c "test_hist:"; grep FAIL "$d/frames" | head -3
elif [ "$(tail -1 "$d/frames" | awk '{print $2}')" != 100 ]; then
   fail $c "the last frame is not cycle 100"
else
   npass=$((npass+1))
fi

# Case: no snapshot keys, no history file.
c=no_snapshots
if run $c tests/decks/ok_setup_counter.deck; then
   if ls "$TMP/$c"/*.hist > /dev/null 2>&1; then
      fail $c "a history file was written"
   elif ! grep -q 'History file *: none' "$TMP/$c/screen.out"; then
      fail $c "the screen does not say there is no history file"
   else
      npass=$((npass+1))
   fi
else
   fail $c "the run did not finish"
fi

echo "history tests: $npass passed, $nfail failed"
[ $nfail -eq 0 ]
