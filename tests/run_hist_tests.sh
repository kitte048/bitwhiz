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
#   - with velocity profiles (xvel_profile, xvel_amplitude), frame 1's #
#     face velocities are the profiles' cell averages, momentum-       #
#     weighted onto the faces, from F computed here in awk, to single  #
#     precision; the screen reports each profile's velocity range;     #
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
#  exactly its pictures, by name (<title>.tx_u.bmp and .tx_p.bmp with  #
#  snapshots, <title>.tr_<tracer>.bmp per tracer) and size (t-x        #
#  1200 x 900, tracer plots 800 x 600), and no other bitmap. A         #
#  plots_only run with another colormap must redraw the t-x diagrams   #
#  differently and the tracer plots (no colormap) the same. The class  #
#  run's P t-x diagram must be in the lab frame with the white rule:   #
#  its plot area's corners white (untouched flyer and PMMA at t = 0,   #
#  no material at x = -7 mm by t_end), the impact plane x = 0 colored  #
#  just after t = 0, and the PMMA at x = 15 mm white just after t = 0  #
#  but colored near t_end (so t runs up, not down). Its u t-x diagram  #
#  must color what P leaves white: the moving flyer and the PMMA at    #
#  rest at t = 0 (no wave has reached them, but they have a velocity). #
#  The t-x diagram's frame: the bottom spine full slate, the box's     #
#  outer corner pixel white; the title BITWHIZ PRESSURE VIEW above it  #
#  (the stem of its first I slate, the gap after it white); the color  #
#  bar below it (a slate outline, two different colors near its ends). #
#  A tracer plot's frame: the bottom spine full slate (#2C3E50), its   #
#  inner edge a half shade (anti-aliased), the box's outer corner      #
#  pixel white (rounded); and the curve drawn: vermilion (#D55E00)     #
#  where u = 0 falls on the pdv plot's y axis, early on, before the    #
#  shock arrives; and the title BITWHIZ SCOPE VIEW above the box (the  #
#  stem of its first I slate, the gap after it white).                 #
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
# file (or if $2 is "tx"), and one plot per tracer in its tracer file.
# Prints what is wrong, if anything.
pics_ok() {
   local d=$1 t f w h want=""
   t=$(basename "$(ls "$d"/*.heartbeat "$d"/*.tracers.csv 2>/dev/null | head -1)")
   t=${t%%.*}
   if ls "$d"/*.hist > /dev/null 2>&1; then
      want="$t.tx_u.bmp 1200 900
$t.tx_p.bmp 1200 900"
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
         # (+0 makes every value a number: mawk leaves a field like
         # 1.5E-323, which underflows, as a string, and compares strings.)
         function rel(a, b) { a += 0; b += 0; d = a - b; if (d < 0) d = -d; s = (b < 0 ? -b : b); return d / (s > 1 ? s : 1) }
         NF != 12 { bad = "frames and tracer rows differ in number"; exit 1 }
         $2 != $8 { bad = "frame " NR " is cycle " $2 ", the tracer row cycle " $8; exit 1 }
         rel($4, $9) > 1e-6 || rel($5, $10) > 1e-6 || rel($6, $11) > 1e-6 || $7 != ($12 + 0 > 0 ? 1 : 0) {
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
# rule. The plot area is x = 42.5 to 1157.5 pixels across and
# y = 42.5 (t_end) to 817.5 (t = 0) down, inside the frame's spines;
# x (mm) is at x0 + (x - xmin)/(xmax - xmin)*1115 with xmin and xmax
# from the screen's "x across" line. Rows are counted from the bottom:
# row 85 is just after t = 0, row 838 just before t_end. Columns 60 and
# 1140 and rows 95 and 830 are near the plot area's corners, clear of
# the spines, the rounded corners and the ticks.
c=tx_p_class
f="$TMP/class_av/double_shock_2p00.tx_p.bmp"
if [ ! -f "$f" ]; then
   fail $c "no P t-x diagram"
else
   col() {   # the pixel column of x = $1 mm
      awk -F: -v x="$1" '/x across \(mm\)/ {split($2, v, " to "); x0 = v[1] + 0; x1 = v[2] + 0;
           print int(42.5 + (x - x0)/(x1 - x0)*1115) + 1}' "$TMP/class_av/screen.out"
   }
   i0=$(col 0); i15=$(col 15)
   if [ "$(pixel "$f" 60 95 1200)" != ffffff ] || [ "$(pixel "$f" 1140 95 1200)" != ffffff ] ||
      [ "$(pixel "$f" 60 830 1200)" != ffffff ]; then
      fail $c "a corner of the plot area is not white (bottom left, bottom right, top left)"
   elif [ -z "$i0" ] || [ "$(pixel "$f" "$i0" 85 1200)" = ffffff ]; then
      fail $c "the impact plane (column ${i0:-?}) is white just after t = 0"
   elif [ -z "$i15" ] || [ "$(pixel "$f" "$i15" 85 1200)" != ffffff ] ||
        [ "$(pixel "$f" "$i15" 838 1200)" = ffffff ]; then
      fail $c "the PMMA at x = 15 mm (column ${i15:-?}) is not white at t = 0 and colored near t_end"
   else
      npass=$((npass+1))
   fi
fi

# Case: the class run's u t-x diagram: colored where there is material,
# moving or not (the flyer and the PMMA at t = 0), white where there is
# none (beyond the PMMA's rear at t = 0, beyond the flyer's rear by
# t_end).
c=tx_u_class
f="$TMP/class_av/double_shock_2p00.tx_u.bmp"
if [ ! -f "$f" ]; then
   fail $c "no u t-x diagram"
elif [ "$(pixel "$f" 60 95 1200)" = ffffff ] || [ "$(pixel "$f" "$i15" 85 1200)" = ffffff ]; then
   fail $c "the moving flyer or the PMMA at rest is white at t = 0"
elif [ "$(pixel "$f" 1140 95 1200)" != ffffff ] || [ "$(pixel "$f" 60 830 1200)" != ffffff ]; then
   fail $c "a place with no material is not white"
else
   npass=$((npass+1))
fi

# Case: the t-x diagram's frame, title and color bar, in the scope
# view's style (module strokes). The box's outside edges are 40 and
# 1160 across, 40 and 820 down; its bottom spine, 2.5 pixels, fills
# rows 81 and 82 from the bottom and half of row 83; column 580 is
# clear of the ticks. The title BITWHIZ PRESSURE VIEW is centered over
# the box, cap height 16 centered on y = 20 (row 881): the stem of its
# first I (at x = 463.0, 2.2 pixels wide) fills column 463, and column
# 466, between I and T, is white. The color bar, 300 to 900 across and
# 842 to 860 down, has a 1.5-pixel slate outline (its top fills row 58)
# and the colormap inside, from 0 at the left to 1 at the right (row
# 50: two different colors near its ends, neither white).
c=tx_frame
f="$TMP/class_av/double_shock_2p00.tx_p.bmp"
lft=$(pixel "$f" 305 50 1200); rgt=$(pixel "$f" 895 50 1200)
if [ "$(pixel "$f" 580 81 1200)" != 503e2c ] || [ "$(pixel "$f" 580 82 1200)" != 503e2c ] ||
   [ "$(pixel "$f" 41 81 1200)" != ffffff ]; then
   fail $c "the bottom spine is not slate, or the box's outer corner pixel is not white"
elif [ "$(pixel "$f" 463 881 1200)" != 503e2c ] || [ "$(pixel "$f" 466 881 1200)" != ffffff ]; then
   fail $c "the title's first I is not where it belongs (slate stem, white gap)"
elif [ "$(pixel "$f" 600 58 1200)" != 503e2c ] || [ "$lft" = ffffff ] ||
     [ "$rgt" = ffffff ] || [ "$lft" = "$rgt" ]; then
   fail $c "the color bar: no slate outline, or no colormap inside ($lft to $rgt)"
else
   npass=$((npass+1))
fi

# Case: a tracer plot's frame (800 x 600, margin 40, spine 2.5 pixels).
# Rows from the bottom: the bottom spine covers rows 41 and 42 fully
# and half of row 43. Column 380 is clear of the ticks. Bytes are blue,
# green, red, as a bitmap stores them.
c=tr_frame
f="$TMP/class_av/double_shock_2p00.tr_pdv.bmp"
if [ ! -f "$f" ]; then
   fail $c "no pdv tracer plot"
elif [ "$(pixel "$f" 380 41 800)" != 503e2c ] || [ "$(pixel "$f" 380 42 800)" != 503e2c ]; then
   fail $c "the bottom spine is not slate (#2C3E50)"
elif [ "$(pixel "$f" 380 43 800)" != a89f96 ] || [ "$(pixel "$f" 380 44 800)" != ffffff ]; then
   fail $c "the spine's inner edge is not a half shade, then white (anti-aliasing)"
elif [ "$(pixel "$f" 41 41 800)" != ffffff ]; then
   fail $c "the box's outer corner pixel is not white (rounded corners)"
else
   npass=$((npass+1))
fi

# Case: the pdv curve. Until the first shock (about 2 us) the PDV
# velocity is 0, so at column 100 the curve is a 3-pixel line at the
# height of u = 0 on the plot's y axis (from the screen line "Tracer
# pdv u (km/s) : ..., y axis ylo to yhi"); its middle pixel must be
# full vermilion (bytes 00 5e d5: blue, green, red).
c=tr_curve
f="$TMP/class_av/double_shock_2p00.tr_pdv.bmp"
r0=$(awk -F'y axis ' '/Tracer pdv u \(km\/s\)/ {split($2, v, " to "); lo = v[1] + 0; hi = v[2] + 0;
     yb = 557.5; ya = 42.5; y = yb - (0 - lo)/(hi - lo)*(yb - ya); print 600 - int(y)}' "$TMP/class_av/screen.out")
found=""
for r in $((r0 - 1)) $r0 $((r0 + 1)); do
   [ "$(pixel "$f" 100 "$r" 800)" = 005ed5 ] && found=$r
done
if [ -z "$r0" ] || [ -z "$found" ]; then
   fail $c "no full-vermilion pixel at column 100 near row ${r0:-?} (u = 0)"
else
   npass=$((npass+1))
fi

# Case: the title, BITWHIZ SCOPE VIEW, 16 pixels tall, centered over the
# box in the 40-pixel margin. The stem of the first I (a straight
# stroke, 2.2 pixels wide, at x = 284.8) fills column 285 at mid-height
# (row 581 from the bottom); column 288, between I and T, is white.
c=tr_title
f="$TMP/class_av/double_shock_2p00.tr_pdv.bmp"
if [ "$(pixel "$f" 285 581 800)" != 503e2c ] || [ "$(pixel "$f" 288 581 800)" != ffffff ]; then
   fail $c "the title's first I is not where it belongs (slate stem, white gap)"
else
   npass=$((npass+1))
fi
against_tracer rs_order2 tests/decks/ok_method_rs.deck        0.05 impact
against_tracer rs_order1 tests/decks/ok_method_rs_order1.deck 0.05 impact

# Case: velocity profiles (xvel_profile, xvel_amplitude). Frame 1 is
# t = 0, so its face velocities (KMPS, real32) must be what the deck
# asks for: in each layer the profile's mean over every cell,
#    u = xvel + du*( fbar - 1 ),
#    fbar = ( F(xi_r) - F(xi_l) )/( ( F(1) - F(0) )*( xi_r - xi_l ) ),
# on the faces xi = j/zones, then momentum-weighted onto the faces
# (cell masses R0*width/zones). F here is the textbook one, written
# again in awk (linear: x + s(x^2 - x); Cauchy: 1/2 + atan(y)/pi), not
# taken from bitwhiz. The layers are tests/decks/ok_profile_hist.deck's.
c=profile_frame1
if run $c tests/decks/ok_profile_hist.deck; then
   d="$TMP/$c"
   f=$(ls "$d"/*.hist)
   hb=$(od -An -t d4 -j 12 -N 4 "$f" | tr -d ' ')
   kmax=$(od -An -t d4 -j 28 -N 4 "$f" | tr -d ' ')
   # Frame 1: time (8 bytes), cycle and frame (4 each), XPOS (kmax+1
   # real32), then KMPS (kmax+1 real32).
   od -An -v -t f4 -j $((hb + 16 + 4*(kmax + 1))) -N $((4*(kmax + 1))) "$f" |
      tr -s ' ' '\n' | grep -v '^$' > "$d/kmps"
   bad=$(awk -v kmax="$kmax" '
      function lin(x, s) { return x + s*(x*x - x) }
      function cau(x, x0, g) { return 0.5 + atan2((x - x0)/g, 1)/3.141592653589793 }
      function F(x, l) { return (kind[l] == "linear") ? lin(x, p1[l]) : cau(x, p1[l], p2[l]) }
      BEGIN {
         # name, R0, width, zones, xvel, du, kind, parameters
         split("2.78 1.187 2.78", R0, " "); split("2.0 3.0 1.0", W, " ")
         split("20 30 10", Z, " "); split("1.0 0.0 -0.3", U, " ")
         split("0.4 0.2 -0.3", DU, " ")
         split("linear linear cauchy", kind, " ")
         split("-0.5 1.0 0.5", p1, " "); split("0 0 0.1", p2, " ")
         k = 0
         for (l = 1; l <= 3; l++) {
            mass = F(1, l) - F(0, l)
            for (j = 1; j <= Z[l]; j++) {
               k++
               fbar = (F(j/Z[l], l) - F((j-1)/Z[l], l))/(mass/Z[l])
               u[k] = U[l] + DU[l]*(fbar - 1); m[k] = R0[l]*W[l]/Z[l]
            }
         }
         if (k != kmax) { print "the deck has " k " cells, the file " kmax; exit 1 }
      }
      { got[NR - 1] = $1 }
      END {
         if (NR != kmax + 1) { print "read " NR " face velocities, not " kmax + 1; exit 1 }
         for (i = 0; i <= kmax; i++) {
            if (i == 0) want = u[1]
            else if (i == kmax) want = u[kmax]
            else want = (m[i]*u[i] + m[i+1]*u[i+1])/(m[i] + m[i+1])
            e = got[i] - want; if (e < 0) e = -e
            a = want < 0 ? -want : want
            if (e > 3e-7*(a > 1 ? a : 1)) { print "face " i ": " got[i] " km/s, expected " want; exit 1 }
         }
      }' "$d/kmps")
   if ! check_file "$d" 1 1 1; then
      fail $c "test_hist (above)"
   elif [ -n "$bad" ]; then
      fail $c "$bad"
   elif ! grep -q 'Profile P1 (linear): u from  -0.1933 to   0.1933 km/s' "$d/screen.out"; then
      fail $c "the screen does not report P1's velocity range"
   else
      npass=$((npass+1))
   fi
else
   fail $c "the run did not finish"
fi

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
elif cmp -s "$d/double_shock_2p00.tx_u.bmp" "$TMP/class_av/double_shock_2p00.tx_u.bmp"; then
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
