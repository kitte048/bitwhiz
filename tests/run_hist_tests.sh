#!/usr/bin/env bash
#**********************************************************************#
#  History file and picture tests. Run from the bitwhiz folder,      #
#  after 'make':                                                       #
#                                                                      #
#     ./tests/run_hist_tests.sh                                        #
#                                                                      #
#  Each case runs a deck (some with a key or two changed) and checks   #
#  its <title>.hist with bin/test_hist, which reads it as              #
#  input/README.md, section 9, says to (sizes, tables, text, frames    #
#  numbered and in time order, faces in order, every value finite, P   #
#  = 0 and D = 0 at t = 0, D only 0 or 1, nframes and status filled    #
#  in). Then, case by case:                                            #
#                                                                      #
#   - with tracer_dt = plot_dt, the frames must be at exactly the      #
#     tracer rows' cycles, and an interface tracer's x, u, P and D     #
#     must be the file's values at its face and cell, to single        #
#     precision (this checks the snapshot rule, the slots, AV's u and  #
#     RS's u*, and the face and cell numbering);                       #
#   - with plot_every = 7, the frames are cycles 0, 7, 14, ... and the #
#     last, and the cells broken in the last frame are the run's       #
#     count;                                                           #
#   - a run stopped by cycle_max ends its file with status 2 and a     #
#     frame at that cycle;                                             #
#   - a deck with no snapshot keys writes no history file;             #
#   - plots_only = yes (no run): with a new colormap, color window and #
#     plot_dt it reports the same ranges as the run did, leaves the    #
#     run's files untouched and says the deck's plot_dt is not used;   #
#     a deck with a different mesh, or a folder without the run's      #
#     files, stops it with an error.                                   #
#                                                                      #
#  Pictures (section 9 of a run): every run that finishes must write   #
#  exactly its pictures, by name (<title>.xt_u.bmp and .xt_p.bmp with  #
#  snapshots, <title>.tr_<tracer>.bmp per tracer) and size (t-x        #
#  1200 x 900, tracer plots 800 x 600), and no other bitmap. A         #
#  plots_only run with another colormap must redraw the t-x diagrams   #
#  differently and the tracer plots (no colormap) the same. The class  #
#  run's P t-x diagram must be in the lab frame with the white rule:   #
#  its corners white (untouched flyer and PMMA at t = 0, no material   #
#  at x = -7 mm by t_end), the impact plane x = 0 colored just after   #
#  t = 0, and the PMMA at x = 15 mm white just after t = 0 but colored #
#  near t_end (so t runs up, not down).                                #
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

# The tracer file's CYCLE, XPOS, KMPS, GPA and DMG columns for tracer $2.
tracer_cols() {
   awk -F', *' -v t="$2" '
      NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i; next }
      NR == 2 || /^#/ { next }
      { print $(c["CYCLE"]), $(c["XPOS." t]), $(c["KMPS." t]), $(c["GPA." t]), $(c["DMG." t]) }
   ' "$1"/*.tracers.csv
}

# test_hist on folder $1's history file, expected status $2, face and
# cell $3 $4: its F lines into $1/frames, its B count into $1/broken.
check_file() {
   if ! "$CHK" "$1"/*.hist "$2" "$3" "$4" > "$1/chk.out"; then
      grep FAIL "$1/chk.out" | head -3; return 1
   fi
   grep '^F ' "$1/chk.out" > "$1/frames"
   awk '/^B / {print $2}' "$1/chk.out" > "$1/broken"
}

# A bitmap's width or height, from its header (int32 at byte 18 or 22).
bmp_dim() { od -An -t d4 -j "$2" -N 4 "$1" | tr -d ' '; }

# Folder $1 holds exactly the pictures its run should make, each a
# bitmap ("BM") of the right size: the t-x pair if it has a history
# file (or if $2 is "xt"), and one plot per tracer in its tracer file.
# Prints what is wrong, if anything.
pics_ok() {
   local d=$1 t f w h want=""
   t=$(basename "$(ls "$d"/*.heartbeat "$d"/*.tracers.csv 2>/dev/null | head -1)")
   t=${t%%.*}
   if ls "$d"/*.hist > /dev/null 2>&1; then
      want="$t.xt_u.bmp 1200 900
$t.xt_p.bmp 1200 900"
   fi
   if ls "$d"/*.tracers.csv > /dev/null 2>&1; then
      for f in $(sed -n 's/^# tracer [0-9]* \([^ ]*\) :.*/\1/p' "$d"/*.tracers.csv); do
         want="$want${want:+
}$t.tr_$f.bmp 800 600"
      done
   fi
   if [ "$(cd "$d" && ls *.bmp 2>/dev/null | sort)" != "$(echo "$want" | awk 'NF {print $1}' | sort)" ]; then
      echo "pictures: $(cd "$d" && ls *.bmp 2>/dev/null | tr '\n' ' ')(wanted: $(echo "$want" | awk '{print $1}' | tr '\n' ' '))"
      return
   fi
   echo "$want" | while read -r f w h; do
      [ -n "$f" ] || continue
      if [ "$(head -c 2 "$d/$f")" != BM ] || [ "$(bmp_dim "$d/$f" 18)" != "$w" ] ||
         [ "$(bmp_dim "$d/$f" 22)" != "$h" ] ||
         [ "$(wc -c < "$d/$f" | tr -d ' ')" != $((54 + 3*w*h)) ]; then
         echo "$f is not a $w x $h bitmap"
      fi
   done
}

# Pixel (i, r) of a 24-bit bitmap nx pixels wide, as 6 hex digits;
# i from the left, r from the BOTTOM (the first row in the file).
pixel() {   # $1 file, $2 i, $3 r, $4 nx
   od -An -t x1 -j $((54 + 3*(($3 - 1)*$4 + $2 - 1))) -N 3 "$1" | tr -d ' \n'
}

# A checksum of each of the run's own files in folder $1 (cksum is in
# every POSIX system; md5sum is not on macOS).
sums() { (cd "$1" && cksum *.hist *.tracers.csv *.heartbeat 2>/dev/null); }

# Case: tracer_dt = plot_dt, so frames and tracer rows share their
# cycles; compare an interface tracer with the file at its face/cell.
against_tracer() {   # $1 case name, $2 deck, $3 dt, $4 tracer
   setkeys "$2" Output "plot_dt = $3" "tracer_dt = $3" > "$TMP/$1.deck"
   if ! run "$1" "$TMP/$1.deck"; then fail "$1" "the run did not finish"; return; fi
   local d="$TMP/$1" place
   place=$(tracer_place "$d" "$4")
   if ! check_file "$d" 1 $place; then fail "$1" "test_hist (above)"; return; fi
   tracer_cols "$d" "$4" > "$d/rows"
   if ! paste -d' ' "$d/frames" "$d/rows" | awk '
         function rel(a, b) { d = a - b; if (d < 0) d = -d; s = (b < 0 ? -b : b); return d / (s > 1 ? s : 1) }
         NF != 12 { bad = "frames and tracer rows differ in number"; exit 1 }
         $2 != $8 { bad = "frame " NR " is cycle " $2 ", the tracer row cycle " $8; exit 1 }
         rel($4, $9) > 1e-6 || rel($5, $10) > 1e-6 || rel($6, $11) > 1e-6 || $7 != ($12 > 0 ? 1 : 0) {
            bad = "cycle " $2 ": x, u, P, D " $4 " " $5 " " $6 " " $7 " vs the tracer " $9 " " $10 " " $11 " " $12; exit 1 }
         END { if (bad != "") { print bad; exit 1 } }' > "$d/diff"; then
      fail "$1" "$(cat "$d/diff")"; return
   fi
   [ "$(wc -l < "$d/frames")" -eq "$(wc -l < "$d/rows")" ] ||
      { fail "$1" "frames and tracer rows differ in number"; return; }
   local bad
   bad=$(pics_ok "$d")
   [ -z "$bad" ] || { fail "$1" "$bad"; return; }
   npass=$((npass+1))
}

against_tracer class_av  input/me697_double_shock_2p00.deck 0.01 pdv

# Case: the class run's P t-x diagram (1200 x 900), lab frame and white
# rule. x = 0 is column floor((0 - xmin)/dx) + 1, with xmin and xmax
# (the image's edges) from the screen's "x across" line.
c=xt_p_class
f="$TMP/class_av/double_shock_2p00.xt_p.bmp"
if [ ! -f "$f" ]; then
   fail $c "no P t-x diagram"
else
   col() {   # the pixel column of x = $1 mm
      awk -F: -v x="$1" '/x across \(mm\)/ {split($2, v, " to "); x0 = v[1] + 0; x1 = v[2] + 0;
           print int((x - x0)/((x1 - x0)/1200)) + 1}' "$TMP/class_av/screen.out"
   }
   i0=$(col 0); i15=$(col 15)
   if [ "$(pixel "$f" 1 1 1200)" != ffffff ] || [ "$(pixel "$f" 1200 1 1200)" != ffffff ] ||
      [ "$(pixel "$f" 1 900 1200)" != ffffff ]; then
      fail $c "a corner is not white (bottom left, bottom right, top left)"
   elif [ -z "$i0" ] || [ "$(pixel "$f" "$i0" 5 1200)" = ffffff ]; then
      fail $c "the impact plane (column ${i0:-?}) is white just after t = 0"
   elif [ -z "$i15" ] || [ "$(pixel "$f" "$i15" 5 1200)" != ffffff ] ||
        [ "$(pixel "$f" "$i15" 880 1200)" = ffffff ]; then
      fail $c "the PMMA at x = 15 mm (column ${i15:-?}) is not white at t = 0 and colored near t_end"
   else
      npass=$((npass+1))
   fi
fi
against_tracer rs_order2 tests/decks/ok_method_rs.deck        0.05 impact
against_tracer rs_order1 tests/decks/ok_method_rs_order1.deck 0.05 impact

# Case: plot_every = 7 (the deck's own setting): cycles 0, 7, 14, ...
# and the last; the plate spalls, and the last frame's broken cells
# are the run's count.
c=plot_every
if run $c tests/decks/ok_plate_spall.deck; then
   d="$TMP/$c"
   last=$(grep '^ *Cycles  ' "$d/screen.out" | awk -F: '{print $2+0}')
   nbrk=$(grep 'Cells broken by the end' "$d/screen.out" | awk -F: '{print $2+0}')
   if ! check_file "$d" 1 1 1; then
      fail $c "test_hist (above)"
   elif ! diff <(awk '{print $2}' "$d/frames") \
               <(awk -v n="$last" 'BEGIN { for (i = 0; i < n; i += 7) print i; print n }') > /dev/null; then
      fail $c "the frames are not cycles 0, 7, 14, ... and the last ($last)"
   elif [ -z "$nbrk" ] || [ "$nbrk" -eq 0 ] || [ "$(cat "$d/broken")" != "$nbrk" ]; then
      fail $c "broken cells in the last frame: $(cat "$d/broken"), the run: ${nbrk:-none}"
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
if ! check_file "$d" 2 1 1; then
   fail $c "test_hist (above)"
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
   elif ls "$TMP/$c"/*.bmp > /dev/null 2>&1; then
      fail $c "a picture was written (no snapshots, no tracers)"
   elif ! grep -q 'History file *: none' "$TMP/$c/screen.out"; then
      fail $c "the screen does not say there is no history file"
   else
      npass=$((npass+1))
   fi
else
   fail $c "the run did not finish"
fi

# Case: tracers but no snapshots: tracer plots only, no t-x diagrams.
c=tracers_only
setkeys tests/decks/ok_method_rs.deck Output "plot_dt = 0" "plot_every = 0" > "$TMP/$c.deck"
if ! run $c "$TMP/$c.deck"; then
   fail $c "the run did not finish"
elif ls "$TMP/$c"/*.hist > /dev/null 2>&1; then
   fail $c "a history file was written"
elif bad=$(pics_ok "$TMP/$c") && [ -n "$bad" ]; then
   fail $c "$bad"
else
   npass=$((npass+1))
fi

# Cases: plots_only = yes, in a copy of the class_av run's folder.
# The ranges it reports must be the run's own (same numbers, read the
# same way), and the run's files must not change.
ranges() { grep -E '^ +(x across|t up|u in the run|P in the run|Rows|Tracer [a-z_]+ u )' "$1"; }
c=plots_only
d="$TMP/$c"; mkdir -p "$d"
cp "$TMP"/class_av/*.hist "$TMP"/class_av/*.tracers.csv "$TMP"/class_av/*.heartbeat "$d"/
before=$(sums "$d")
setkeys "$TMP/class_av.deck" Run "plots_only = yes" > "$TMP/$c.1"
setkeys "$TMP/$c.1" Output "colormap = inferno" "plot_p_lo = 0.1" \
   "plot_p_hi = 0.6" "plot_dt = 0.5" "tracer_dt = 0.5" > "$TMP/$c.deck"
if ! run $c "$TMP/$c.deck"; then
   fail $c "the plots_only run did not finish:"; grep 'bitwhiz:' "$d/screen.out" | head -3
elif [ "$(sums "$d")" != "$before" ]; then
   fail $c "it changed the run's files"
elif ! diff <(ranges "$TMP/class_av/screen.out") <(ranges "$d/screen.out") > /dev/null; then
   fail $c "its ranges differ from the run's"
elif ! grep -q 'Colormap *: inferno' "$d/screen.out" ||
     ! grep -q 'P colors (GPa).*(window 0.1 to 0.6)' "$d/screen.out" ||
     ! grep -q 'not used: the frames in the file are' "$d/screen.out"; then
   fail $c "it does not report the new colormap, window or plot_dt"
elif grep -qE '^ +[3-8]\. ' "$d/screen.out"; then
   fail $c "it printed run sections (it must go from 2 to 9)"
elif bad=$(pics_ok "$d") && [ -n "$bad" ]; then
   fail $c "$bad"
elif cmp -s "$d/double_shock_2p00.xt_u.bmp" "$TMP/class_av/double_shock_2p00.xt_u.bmp"; then
   fail $c "with colormap = inferno the u t-x diagram is the same as viridis's"
elif ! cmp -s "$d/double_shock_2p00.tr_pdv.bmp" "$TMP/class_av/double_shock_2p00.tr_pdv.bmp"; then
   fail $c "the pdv tracer plot changed with the colormap"
else
   npass=$((npass+1))
fi

# The same folder, a deck with a different mesh: an error, no change.
c=plots_only_other_mesh
setkeys "$TMP/plots_only.deck" Stack "resolution = 30" > "$TMP/$c.deck"
if run plots_only "$TMP/$c.deck"; then
   fail $c "a history file from another mesh was accepted"
elif ! grep -q 'was not made by this deck: 945 cells, not 810' "$d/screen.out"; then
   fail $c "the error does not say what differs"
elif [ "$(sums "$d")" != "$before" ]; then
   fail $c "it changed the run's files"
else
   npass=$((npass+1))
fi

# A folder without the run's files: an error naming them.
c=plots_only_no_files
if run $c "$TMP/plots_only.deck"; then
   fail $c "it finished without the run's files"
elif ! grep -q 'cannot open double_shock_2p00.hist' "$TMP/$c/screen.out" ||
     ! grep -q 'cannot open double_shock_2p00.tracers.csv' "$TMP/$c/screen.out"; then
   fail $c "the errors do not name the missing files"
else
   npass=$((npass+1))
fi

echo "history tests: $npass passed, $nfail failed"
[ $nfail -eq 0 ]
