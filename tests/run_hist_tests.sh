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
#   - with movie_frames, the pressure movie's frames are the          #
#     snapshots nearest its times (worked out again in awk), named by  #
#     cycle, and plots_only draws them again byte for byte;            #
#   - with plot_every = 7, the frames are cycles 0, 7, 14, ... and the #
#     last, and the cells broken in the last frame are the run's       #
#     count;                                                           #
#   - with materials that carry T (eos = mie_gruneisen_t), the file    #
#     has TK after DMG, and a tracer's TK in it is the tracer file's,  #
#     to single precision, 298 K (T0) at t = 0;                        #
#   - with a burn (burn = hvrb), the file has XRN after TK (0 at t = #
#     0, 0 to 1, never falling), a tracer's XRN in it is the tracer    #
#     file's; and a burn that never starts (PI out of reach) gives the #
#     inert run's heartbeat, tracer rows and frames, bit for bit;      #
#   - a run stopped by cycle_max ends its file with status 2 and a     #
#     frame at that cycle;                                             #
#   - a deck with no snapshot keys writes no history file;             #
#   - plots_only = yes (no run): with a new colormap, color window and #
#     plot_dt it reports the same ranges as the run did, leaves the    #
#     run's files untouched and says the deck's plot_dt is not used;   #
#     a deck with a different mesh, or a folder without the run's      #
#     files, stops it with an error;                                   #
#   - plot_range: u6_boundary_boundary (RS, whose impact starts with   #
#     a 6% spike) with the default, robust, reports the spike above    #
#     the P range and tops the P colors at P_1 = 8.351 GPa (8.35 to    #
#     8.36); with full, no report, the colors top at the max, and the  #
#     P t-x diagram differs. The class run (no spike) keeps its full   #
#     range under robust.                                              #
#                                                                      #
#  Pictures (section 9 of a run): every run that finishes must write   #
#  exactly its pictures, by name (<title>.tx_u.bmp and .tx_p.bmp with  #
#  snapshots, <title>.tr_<tracer>.bmp per tracer, and as many          #
#  <title>.mv_p_<cycle>.bmp as the screen's pressure movie line says)  #
#  and size (t-x 1200 x 900, tracer plots and movie frames 800 x 600), #
#  and no other bitmap. A                                              #
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
#  bar below it (a slate outline, two different colors near its ends); #
#  its numbers: x and t rounded to -7 to 25 mm and 0 to 5 us, and ink  #
#  at the axis ends' and the color window's places.                    #
#  A tracer plot's frame: the bottom spine full slate (#2C3E50), its   #
#  inner edge a half shade (anti-aliased), the box's outer corner      #
#  pixel white (rounded); and the curve drawn: vermilion (#D55E00)     #
#  where u = 0 falls on the pdv plot's y axis, early on, before the    #
#  shock arrives; and the title BITWHIZ SCOPE VIEW above the box (the  #
#  stem of its first I slate, the gap after it white); and the axis    #
#  ends: the y axis's rounded to -0.1 and 2.1, and ink at all four     #
#  numbers' places, none in an empty margin.                           #
#                                                                      #
#  One line per case as it finishes, with a counter (tests/report.sh). #
#  A new case: begin, then exactly one pass or fail, and one more in   #
#  the plan below.                                                     #
#**********************************************************************#
BIN=${BIN:-./bin/bitwhiz}
BIN=$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")    # absolute
CHK=$(pwd)/bin/test_hist
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
. "$(dirname "$0")/report.sh"
plan 26 "history tests"

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
# cell $3 $4: its F lines into $1/frames, its B count into $1/broken,
# and what it found wrong (if anything) into $1/chk.fail.
check_file() {
   if ! "$CHK" "$1"/*.hist "$2" "$3" "$4" > "$1/chk.out"; then
      grep FAIL "$1/chk.out" | head -3 > "$1/chk.fail"; return 1
   fi
   grep '^F ' "$1/chk.out" > "$1/frames"
   awk '/^B / {print $2}' "$1/chk.out" > "$1/broken"
}

# A bitmap's width or height, from its header (int32 at byte 18 or 22).
bmp_dim() { od -An -t d4 -j "$2" -N 4 "$1" | tr -d ' '; }

# Folder $1 holds exactly the pictures its run should make, each a
# bitmap ("BM") of the right size: the t-x pair if it has a history
# file (or if $2 is "tx"), one plot per tracer in its tracer file, and
# the pressure movie's frames when its screen (screen.out) reports one,
# as many as it says (their names carry cycles, checked by the movie
# case). Prints what is wrong, if anything.
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
   nmv=$(sed -n 's/^ *Pressure movie *: \([0-9]*\) frames.*/\1/p' "$d/screen.out" 2>/dev/null)
   if [ -n "$nmv" ]; then
      if [ "$(cd "$d" && ls "$t".mv_p_*.bmp 2>/dev/null | wc -l | tr -d ' ')" != "$nmv" ]; then
         echo "pressure movie: not the $nmv frames the screen reports"
         return
      fi
      for f in $(cd "$d" && ls "$t".mv_p_*.bmp); do
         want="$want${want:+
}$f 800 600"
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
sums() { (cd "$1" && cksum *.hist *.tracers.csv *.heartbeat *.resolved 2>/dev/null); }

# Case: tracer_dt = plot_dt, so frames and tracer rows share their
# cycles; compare an interface tracer with the file at its face/cell.
against_tracer() {   # $1 case name, $2 deck, $3 dt, $4 tracer
   begin
   setkeys "$2" Output "plot_dt = $3" "tracer_dt = $3" > "$TMP/$1.deck"
   if ! run "$1" "$TMP/$1.deck"; then fail "$1" "the run did not finish"; return; fi
   local d="$TMP/$1" place
   place=$(tracer_place "$d" "$4")
   if ! check_file "$d" 1 $place; then fail "$1" "test_hist:"; detail < "$d/chk.fail"; return; fi
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
   pass "$1"
}

against_tracer class_av  input/me697_double_shock_2p00.deck 0.01 pdv

# Case: the class run's P t-x diagram (1200 x 900), lab frame and white
# rule. The plot area is x = 102.5 to 1137.5 pixels across and
# y = 42.5 (t_end) to 792.5 (t = 0) down, inside the frame's spines;
# x (mm) is at x0 + (x - xmin)/(xmax - xmin)*1035 with xmin and xmax
# from the screen's "x across" line (-7 to 25, rounded out). Rows are
# counted from the bottom: row 112 is just after t = 0, row 838 just
# before t_end. Columns 120 and 1120 and rows 120 and 830 are near the
# plot area's corners, clear of the spines, the rounded corners and the
# ticks; column 1120 is x = 24.4 mm, beyond the PMMA's rear at t = 0.
begin
c=tx_p_class
f="$TMP/class_av/double_shock_2p00.tx_p.bmp"
if [ ! -f "$f" ]; then
   fail $c "no P t-x diagram"
else
   col() {   # the pixel column of x = $1 mm
      awk -F: -v x="$1" '/x across \(mm\)/ {split($2, v, " to "); x0 = v[1] + 0; x1 = v[2] + 0;
           print int(102.5 + (x - x0)/(x1 - x0)*1035) + 1}' "$TMP/class_av/screen.out"
   }
   i0=$(col 0); i15=$(col 15)
   if [ "$(pixel "$f" 120 120 1200)" != ffffff ] || [ "$(pixel "$f" 1120 120 1200)" != ffffff ] ||
      [ "$(pixel "$f" 120 830 1200)" != ffffff ]; then
      fail $c "a corner of the plot area is not white (bottom left, bottom right, top left)"
   elif [ -z "$i0" ] || [ "$(pixel "$f" "$i0" 112 1200)" = ffffff ]; then
      fail $c "the impact plane (column ${i0:-?}) is white just after t = 0"
   elif [ -z "$i15" ] || [ "$(pixel "$f" "$i15" 112 1200)" != ffffff ] ||
        [ "$(pixel "$f" "$i15" 838 1200)" = ffffff ]; then
      fail $c "the PMMA at x = 15 mm (column ${i15:-?}) is not white at t = 0 and colored near t_end"
   else
      pass $c
   fi
fi

# Case: the class run's u t-x diagram: colored where there is material,
# moving or not (the flyer and the PMMA at t = 0), white where there is
# none (beyond the PMMA's rear at t = 0, beyond the flyer's rear by
# t_end).
begin
c=tx_u_class
f="$TMP/class_av/double_shock_2p00.tx_u.bmp"
if [ ! -f "$f" ]; then
   fail $c "no u t-x diagram"
elif [ "$(pixel "$f" 120 120 1200)" = ffffff ] || [ "$(pixel "$f" "$i15" 112 1200)" = ffffff ]; then
   fail $c "the moving flyer or the PMMA at rest is white at t = 0"
elif [ "$(pixel "$f" 1120 120 1200)" != ffffff ] || [ "$(pixel "$f" 120 830 1200)" != ffffff ]; then
   fail $c "a place with no material is not white"
else
   pass $c
fi

# Case: the t-x diagram's frame, title and color bar, in the scope
# view's style (module strokes). The box's outside edges are 100 and
# 1140 across, 40 and 795 down; its bottom spine, 2.5 pixels, fills
# rows 106 and 107 from the bottom and half of row 108; column 580 is
# clear of the ticks. The title BITWHIZ PRESSURE VIEW is centered on
# the page, cap height 16 centered on y = 20 (row 881): the stem of its
# first I (at x = 463.0, 2.2 pixels wide) fills column 463, and column
# 466, between I and T, is white. The color bar, 300 to 900 across and
# 842 to 860 down, has a 1.5-pixel slate outline (its top fills row 58)
# and the colormap inside, from 0 at the left to 1 at the right (row
# 50: two different colors near its ends, neither white).
begin
c=tx_frame
f="$TMP/class_av/double_shock_2p00.tx_p.bmp"
lft=$(pixel "$f" 305 50 1200); rgt=$(pixel "$f" 895 50 1200)
if [ "$(pixel "$f" 580 106 1200)" != 503e2c ] || [ "$(pixel "$f" 580 107 1200)" != 503e2c ] ||
   [ "$(pixel "$f" 101 106 1200)" != ffffff ]; then
   fail $c "the bottom spine is not slate, or the box's outer corner pixel is not white"
elif [ "$(pixel "$f" 463 881 1200)" != 503e2c ] || [ "$(pixel "$f" 466 881 1200)" != ffffff ]; then
   fail $c "the title's first I is not where it belongs (slate stem, white gap)"
elif [ "$(pixel "$f" 600 58 1200)" != 503e2c ] || [ "$lft" = ffffff ] ||
     [ "$rgt" = ffffff ] || [ "$lft" = "$rgt" ]; then
   fail $c "the color bar: no slate outline, or no colormap inside ($lft to $rgt)"
else
   pass $c
fi

# Case: a tracer plot's frame (800 x 600; the box 100 pixels from the
# left, 60 from the right, 40 from the top and 70 from the bottom;
# spine 2.5 pixels). Rows from the bottom: the bottom spine covers rows
# 71 and 72 fully and half of row 73. Column 380 is clear of the ticks.
# Bytes are blue, green, red, as a bitmap stores them.
begin
c=tr_frame
f="$TMP/class_av/double_shock_2p00.tr_pdv.bmp"
if [ ! -f "$f" ]; then
   fail $c "no pdv tracer plot"
elif [ "$(pixel "$f" 380 71 800)" != 503e2c ] || [ "$(pixel "$f" 380 72 800)" != 503e2c ]; then
   fail $c "the bottom spine is not slate (#2C3E50)"
elif [ "$(pixel "$f" 380 73 800)" != a89f96 ] || [ "$(pixel "$f" 380 74 800)" != ffffff ]; then
   fail $c "the spine's inner edge is not a half shade, then white (anti-aliasing)"
elif [ "$(pixel "$f" 101 71 800)" != ffffff ]; then
   fail $c "the box's outer corner pixel is not white (rounded corners)"
else
   pass $c
fi

# Case: the pdv curve. Until the first shock (about 2 us) the PDV
# velocity is 0, so at column 150 (t = 0.37 us) the curve is a 3-pixel
# line at the
# height of u = 0 on the plot's y axis (from the screen line "Tracer
# pdv u (km/s) : ..., y axis ylo to yhi"); its middle pixel must be
# full vermilion (bytes 00 5e d5: blue, green, red).
begin
c=tr_curve
f="$TMP/class_av/double_shock_2p00.tr_pdv.bmp"
r0=$(awk -F'y axis ' '/Tracer pdv u \(km\/s\)/ {split($2, v, " to "); lo = v[1] + 0; hi = v[2] + 0;
     yb = 527.5; ya = 42.5; y = yb - (0 - lo)/(hi - lo)*(yb - ya); print 600 - int(y)}' "$TMP/class_av/screen.out")
found=""
for r in $((r0 - 1)) $r0 $((r0 + 1)); do
   [ "$(pixel "$f" 150 "$r" 800)" = 005ed5 ] && found=$r
done
if [ -z "$r0" ] || [ -z "$found" ]; then
   fail $c "no full-vermilion pixel at column 150 near row ${r0:-?} (u = 0)"
else
   pass $c
fi

# Case: the title, BITWHIZ SCOPE VIEW, 16 pixels tall, centered on the
# page in the 40-pixel top margin (where it was before the box's sides
# moved in for the numbers). The stem of the first I (a straight
# stroke, 2.2 pixels wide, at x = 284.8) fills column 285 at mid-height
# (row 581 from the bottom); column 288, between I and T, is white.
begin
c=tr_title
f="$TMP/class_av/double_shock_2p00.tr_pdv.bmp"
if [ "$(pixel "$f" 285 581 800)" != 503e2c ] || [ "$(pixel "$f" 288 581 800)" != ffffff ]; then
   fail $c "the title's first I is not where it belongs (slate stem, white gap)"
else
   pass $c
fi

# Case: the axis ends. The pdv plot's y axis is rounded out to clean
# ends, -0.1 to 2.1 km/s (the data, 0 to 1.9921, padded 5 %), as the
# screen reports; the numbers are drawn (some slate ink) where they
# belong: xlo and xhi under the box's bottom corners (x = 102.5 and
# 737.5, rows 49-61 from the bottom), ylo and yhi left of its left side
# (columns 70-90, level with the plot area's bottom and top), and
# nothing beyond them in the margins (columns 1-60, rows 1-40).
ink() {   # $1 file, $2 $3 columns, $4 $5 rows from the bottom: any not white?
   local r
   for r in $(seq "$4" "$5"); do
      od -v -An -t x1 -j $((54 + 3*((r - 1)*800 + $2 - 1))) -N $((3*($3 - $2 + 1))) "$1" |
         tr -s ' \n' '\n' | grep -qv -e '^ff$' -e '^$' && return 0
   done
   return 1
}
begin
c=tr_numbers
f="$TMP/class_av/double_shock_2p00.tr_pdv.bmp"
if ! grep -q 'Tracer pdv u (km/s).*y axis -0.1 to 2.1$' "$TMP/class_av/screen.out"; then
   fail $c "the pdv plot's y axis is not -0.1 to 2.1 on the screen"
elif ! ink "$f" 97 108 49 61; then
   fail $c "no number under the box's bottom-left corner (xlo)"
elif ! ink "$f" 732 743 49 61; then
   fail $c "no number under the box's bottom-right corner (xhi)"
elif ! ink "$f" 70 90 67 79; then
   fail $c "no number left of the plot area's bottom (ylo)"
elif ! ink "$f" 70 90 552 564; then
   fail $c "no number left of the plot area's top (yhi)"
elif ink "$f" 1 60 1 40; then
   fail $c "ink in the bottom-left margin, where nothing is drawn"
else
   pass $c
fi

# Case: the t-x diagram's numbers. The screen gives the axes rounded out
# to clean ends, x -7 to 25 mm and t 0 to 5 us; the numbers are drawn
# where they belong: x's under the box's bottom corners (x = 102.5 and
# 1137.5, rows 83-95 from the bottom), t's left of its left side
# (columns 60-90, level with the plot area's bottom and top), and the
# color window's ends beside the bar's (the low end's label ending at
# x = 290, the high end's starting at 910, rows 43-55); nothing in the
# page's bottom-left corner.
ink1200() {   # as ink, on a 1200-pixel-wide picture
   local r
   for r in $(seq "$4" "$5"); do
      od -v -An -t x1 -j $((54 + 3*((r - 1)*1200 + $2 - 1))) -N $((3*($3 - $2 + 1))) "$1" |
         tr -s ' \n' '\n' | grep -qv -e '^ff$' -e '^$' && return 0
   done
   return 1
}
begin
c=tx_numbers
f="$TMP/class_av/double_shock_2p00.tx_p.bmp"
if ! grep -q 'x across (mm) *: -7.0 to 25.0$' "$TMP/class_av/screen.out" ||
   ! grep -q 't up (us) *: 0.0 to 5.0$' "$TMP/class_av/screen.out"; then
   fail $c "the screen does not give the axes as -7 to 25 mm and 0 to 5 us"
elif ! ink1200 "$f" 95 110 83 95 || ! ink1200 "$f" 1125 1150 83 95; then
   fail $c "no number under a bottom corner of the box (x ends)"
elif ! ink1200 "$f" 60 90 102 114 || ! ink1200 "$f" 60 90 852 864; then
   fail $c "no number left of the plot area's bottom or top (t ends)"
elif ! ink1200 "$f" 240 290 43 55 || ! ink1200 "$f" 910 960 43 55; then
   fail $c "no number beside the color bar's ends"
elif ink1200 "$f" 1 60 1 40; then
   fail $c "ink in the page's bottom-left corner, where nothing is drawn"
else
   pass $c
fi
against_tracer rs_order2 tests/decks/ok_method_rs.deck        0.05 impact
against_tracer rs_order1 tests/decks/ok_method_rs_order1.deck 0.05 impact

# Case: materials that carry T (tests/decks/ok_temperature.deck: MatX and
# PMMA with eos = mie_gruneisen_t, Al without). Everything above holds
# with TK in the file; then TK at the tracer's cell is the tracer file's
# TK, to single precision, at every frame, 298 K (T0) at t = 0.
against_tracer temperature tests/decks/ok_temperature.deck 0.05 pdv
begin
c=temperature_tk
d="$TMP/temperature"
if [ ! -f "$d/chk.out" ]; then
   fail $c "no run (see the case above)"
else
   awk '/^T / {print $2, $3}' "$d/chk.out" > "$d/tk_hist"
   awk -F', *' 'NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i; next }
      NR == 2 || /^#/ { next } { print $(c["CYCLE"]), $(c["TK.pdv"]) }' \
      "$d"/*.tracers.csv > "$d/tk_trc"
   if [ ! -s "$d/tk_hist" ]; then
      fail $c "the history file has no TK (no T lines from test_hist)"
   elif ! paste -d' ' "$d/tk_hist" "$d/tk_trc" | awk '
         function rel(a, b) { a += 0; b += 0; d = a - b; if (d < 0) d = -d; return d / (b > 1 ? b : 1) }
         NF != 4 || $1 != $3 || rel($2, $4) > 1e-6 { exit 1 }
         NR == 1 && rel($2, 298) > 0 { exit 1 }
         END { if (NR < 2) exit 1 }'; then
      fail $c "TK in the history file is not the tracer file's TK (or not 298 K at t = 0)"
   else
      pass $c
   fi
fi

# Case: a burn (tests/decks/ok_hvrb.deck: MatX burns, HVRB with
# ideal-gas products). Everything above holds with XRN in the file
# (test_hist: 0 at t = 0, 0 to 1, never falling); then XRN at the
# tracer's cell is the tracer file's XRN, to single precision, at every
# frame: 0 at t = 0, and 1 by the end (the PDV cell, MatX's last, burns
# out once the detonation reaches it).
against_tracer hvrb tests/decks/ok_hvrb.deck 0.05 pdv
begin
c=hvrb_xrn
d="$TMP/hvrb"
if [ ! -f "$d/chk.out" ]; then
   fail $c "no run (see the case above)"
else
   awk '/^X / {print $2, $3}' "$d/chk.out" > "$d/x_hist"
   awk -F', *' 'NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i; next }
      NR == 2 || /^#/ { next } { print $(c["CYCLE"]), $(c["XRN.pdv"]) }' \
      "$d"/*.tracers.csv > "$d/x_trc"
   if [ ! -s "$d/x_hist" ]; then
      fail $c "the history file has no XRN (no X lines from test_hist)"
   elif ! paste -d' ' "$d/x_hist" "$d/x_trc" | awk '
         function ab(a, b) { a += 0; b += 0; d = a - b; return d < 0 ? -d : d }
         NF != 4 || $1 != $3 || ab($2, $4) > 1e-6 { exit 1 }
         NR == 1 && $2 + 0 != 0 { exit 1 }
         { last = $2 + 0 }
         END { if (NR < 2 || last != 1) exit 1 }'; then
      fail $c "XRN in the history file is not the tracer file's XRN (or not 0 at t = 0 and 1 at the end)"
   else
      pass $c
   fi
fi

# Case: the inert limit (tests/decks/ok_hvrb_inert.deck: ok_temperature's
# deck with a burn in MatX whose threshold PI no pressure reaches). No
# cell ever burns, and every cell takes the inert path, so the run is
# the temperature case's, bit for bit: every heartbeat line (but the
# deck's name and title, and the clock), every tracer row with its XRN
# columns left out, and every history frame with its XRN left out
# (XRN is the last variable, so a frame is the inert frame, then XRN).
begin
c=hvrb_inert
setkeys tests/decks/ok_hvrb_inert.deck Output "plot_dt = 0.05" \
   "tracer_dt = 0.05" > "$TMP/hvrb_inert.deck"
d0="$TMP/temperature"
d="$TMP/hvrb_inert"
beats() {     # $1 = heartbeat file: no clock, build, deck or title lines
   grep -vE '^# (started|ended|version|built|flags|deck|title)' "$1" |
      awk '/^#/ {print; next} {$NF=""; print}'
}
nox() {       # $1 = tracer file: the data rows, XRN columns left out
   awk -F', *' 'NR == 1 { for (i = 1; i <= NF; i++) keep[i] = ($i !~ /^XRN\./) }
      NR <= 2 || /^#/ { next }
      { s = ""; for (i = 1; i <= NF; i++) if (keep[i]) s = s (s == "" ? "" : ",") $i; print s }' "$1"
}
i32() { od -An -t d4 -j "$2" -N 4 "$1" | tr -d ' '; }   # int32 at byte $2
frames() {    # $1 = history file, $2 = bytes of each frame to keep
   local h f n k
   h=$(i32 "$1" 12); f=$(i32 "$1" 16); n=$(i32 "$1" 20)
   for k in $(seq 0 $((n - 1))); do
      tail -c +$((h + k*f + 1)) "$1" | head -c "$2" | cksum
   done
}
if [ ! -f "$d0/chk.out" ]; then
   fail $c "no inert run (see the temperature case)"
elif ! run hvrb_inert "$TMP/hvrb_inert.deck"; then
   fail $c "the run did not finish"
elif grep -q 'First cell to react *: [0-9]' "$d/screen.out"; then
   fail $c "a cell burnt (PI should be out of reach)"
elif ! diff <(beats "$d0"/*.heartbeat) <(beats "$d"/*.heartbeat) > /dev/null; then
   fail $c "the heartbeat differs from the inert run's"
elif ! diff <(nox "$d0"/*.tracers.csv) <(nox "$d"/*.tracers.csv) > /dev/null; then
   fail $c "the tracer rows (XRN left out) differ from the inert run's"
elif ! diff <(frames "$d0"/*.hist "$(i32 "$d0"/*.hist 16)") \
            <(frames "$d"/*.hist "$(i32 "$d0"/*.hist 16)") > /dev/null; then
   fail $c "the history frames (XRN left out) differ from the inert run's"
else
   pass $c
fi

# Case: velocity profiles (xvel_profile, xvel_amplitude). Frame 1 is
# t = 0, so its face velocities (KMPS, real32) must be what the deck
# asks for: in each layer the profile's mean over every cell,
#    u = xvel + du*( fbar - 1 ),
#    fbar = ( F(xi_r) - F(xi_l) )/( ( F(1) - F(0) )*( xi_r - xi_l ) ),
# on the faces xi = j/zones, then momentum-weighted onto the faces
# (cell masses R0*width/zones). F here is the textbook one, written
# again in awk (linear: x + s(x^2 - x); Cauchy: 1/2 + atan(y)/pi), not
# taken from bitwhiz. The layers are tests/decks/ok_profile_hist.deck's.
begin
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
      pass $c
   fi
else
   fail $c "the run did not finish"
fi

# Case: plot_every = 7 (the deck's own setting): cycles 0, 7, 14, ...
# and the last; the plate spalls, and the last frame's broken cells
# are the run's count.
begin
c=plot_every
if run $c tests/decks/ok_plate_spall.deck; then
   d="$TMP/$c"
   last=$(grep '^ *Cycles  ' "$d/screen.out" | awk -F: '{print $2+0}')
   nbrk=$(grep 'Cells broken by the end' "$d/screen.out" | awk -F: '{print $2+0}')
   if ! check_file "$d" 1 1 1; then
      fail $c "test_hist:"; detail < "$d/chk.fail"
   elif ! diff <(awk '{print $2}' "$d/frames") \
               <(awk -v n="$last" 'BEGIN { for (i = 0; i < n; i += 7) print i; print n }') > /dev/null; then
      fail $c "the frames are not cycles 0, 7, 14, ... and the last ($last)"
   elif [ -z "$nbrk" ] || [ "$nbrk" -eq 0 ] || [ "$(cat "$d/broken")" != "$nbrk" ]; then
      fail $c "broken cells in the last frame: $(cat "$d/broken"), the run: ${nbrk:-none}"
   else
      pass $c
   fi
else
   fail $c "the run did not finish"
fi

# Case: stopped at cycle_max = 100: status 2, the last frame at 100.
begin
c=cycle_max
setkeys input/me697_double_shock_2p00.deck Run "cycle_max = 100" > "$TMP/$c.deck"
run $c "$TMP/$c.deck"                       # stops early; exit code not 0
d="$TMP/$c"
if ! check_file "$d" 2 1 1; then
   fail $c "test_hist:"; detail < "$d/chk.fail"
elif [ "$(tail -1 "$d/frames" | awk '{print $2}')" != 100 ]; then
   fail $c "the last frame is not cycle 100"
else
   pass $c
fi

# Case: no snapshot keys, no history file.
begin
c=no_snapshots
if run $c tests/decks/ok_setup_counter.deck; then
   if ls "$TMP/$c"/*.hist > /dev/null 2>&1; then
      fail $c "a history file was written"
   elif ls "$TMP/$c"/*.bmp > /dev/null 2>&1; then
      fail $c "a picture was written (no snapshots, no tracers)"
   elif ! grep -q 'History file *: none' "$TMP/$c/screen.out"; then
      fail $c "the screen does not say there is no history file"
   else
      pass $c
   fi
else
   fail $c "the run did not finish"
fi

# Case: tracers but no snapshots: tracer plots only, no t-x diagrams.
begin
c=tracers_only
setkeys tests/decks/ok_method_rs.deck Output "plot_dt = 0" "plot_every = 0" > "$TMP/$c.deck"
if ! run $c "$TMP/$c.deck"; then
   fail $c "the run did not finish"
elif ls "$TMP/$c"/*.hist > /dev/null 2>&1; then
   fail $c "a history file was written"
elif bad=$(pics_ok "$TMP/$c") && [ -n "$bad" ]; then
   fail $c "$bad"
else
   pass $c
fi

# Cases: plots_only = yes, in a copy of the class_av run's folder.
# The ranges it reports must be the run's own (same numbers, read the
# same way), and the run's files must not change (its resolved deck
# among them: plots_only writes none).
ranges() { grep -E '^ +(x across|t up|u in the run|P in the run|Rows|Tracer [a-z_]+ u )' "$1"; }
begin
c=plots_only
d="$TMP/$c"; mkdir -p "$d"
cp "$TMP"/class_av/*.hist "$TMP"/class_av/*.tracers.csv "$TMP"/class_av/*.heartbeat \
   "$TMP"/class_av/*.resolved "$d"/
before=$(sums "$d")
setkeys "$TMP/class_av.deck" Run "plots_only = yes" > "$TMP/$c.1"
setkeys "$TMP/$c.1" Output "colormap = inferno" "plot_p_lo = 0.1" \
   "plot_p_hi = 0.6" "plot_dt = 0.5" "tracer_dt = 0.5" > "$TMP/$c.deck"
if ! run $c "$TMP/$c.deck"; then
   fail $c "the plots_only run did not finish:"; grep 'bitwhiz:' "$d/screen.out" | head -3 | detail
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
   pass $c
fi

# The same folder, a deck with a different mesh: an error, no change.
begin
c=plots_only_other_mesh
setkeys "$TMP/plots_only.deck" Stack "resolution = 30" > "$TMP/$c.deck"
if run plots_only "$TMP/$c.deck"; then
   fail $c "a history file from another mesh was accepted"
elif ! grep -q 'was not made by this deck: 945 cells, not 810' "$d/screen.out"; then
   fail $c "the error does not say what differs"
elif [ "$(sums "$d")" != "$before" ]; then
   fail $c "it changed the run's files"
else
   pass $c
fi

# A folder without the run's files: an error naming them.
begin
c=plots_only_no_files
if run $c "$TMP/plots_only.deck"; then
   fail $c "it finished without the run's files"
elif ! grep -q 'cannot open double_shock_2p00.hist' "$TMP/$c/screen.out" ||
     ! grep -q 'cannot open double_shock_2p00.tracers.csv' "$TMP/$c/screen.out"; then
   fail $c "the errors do not name the missing files"
else
   pass $c
fi


# Case: plot_range. The RS impact of u6_boundary_boundary starts with a
# spike (8.88 GPa for about 50 cycles; P_1 = 8.351). robust (the
# default) must leave it above the P colors and say so; full must not.
# The class run has no spike: robust keeps its range (no report).
begin
c=plot_range
top() { awk -F: '/P colors \(GPa\)/ {split($2, v, " to "); print v[2] + 0}' "$1"; }
if ! run ${c}_robust input/u6_boundary_boundary.deck; then
   fail $c "the robust run did not finish"
else
   setkeys input/u6_boundary_boundary.deck Output "plot_range = full" > "$TMP/$c.deck"
   if ! run ${c}_full "$TMP/$c.deck"; then
      fail $c "the full run did not finish"
   else
      r="$TMP/${c}_robust"; f="$TMP/${c}_full"
      tr=$(top "$r/screen.out"); tf=$(top "$f/screen.out")
      pmax=$(awk -F: '/P in the run \(GPa\)/ {split($2, v, " to "); print v[2] + 0}' "$f/screen.out")
      if ! grep -q 'Color ranges *: robust' "$r/screen.out" ||
         ! grep -q 'P above the range (GPa) *: up to' "$r/screen.out"; then
         fail $c "robust does not report the spike above the P range"
      elif ! awk -v t="$tr" 'BEGIN { exit !(t > 8.35 && t < 8.36) }'; then
         fail $c "robust: the P colors top at ${tr:-?} GPa, not P_1 (8.35 to 8.36)"
      elif grep -q 'above the range' "$f/screen.out" || [ "$tf" != "$pmax" ]; then
         fail $c "full: the P colors top at ${tf:-?}, not the max ${pmax:-?} (or a report)"
      elif cmp -s "$r/u6_boundary_boundary.tx_p.bmp" "$f/u6_boundary_boundary.tx_p.bmp"; then
         fail $c "the P t-x diagram is the same with robust and full"
      elif grep -q 'above the range' "$TMP/class_av/screen.out"; then
         fail $c "robust trimmed the class run, which has no spike"
      else
         pass $c
      fi
   fi
fi


# Case: movie (tests/decks/ok_movie_frames.deck: plot_every = 10, t_end
# = 1.0, movie_frames = 5). The frames must be the snapshots nearest the
# 5 times spread evenly from 0 to the last snapshot's, t_last*m/4, the
# earlier of two equally near, each once: worked out again here in awk
# from the file's own frame times (test_hist's F lines), not taken from
# bitwhiz. Each is run.mv_p_<cycle in six digits>.bmp, 800 x 600, and
# there is no other movie picture; and a plots_only run must draw every
# one of them again, byte for byte.
begin
c=movie
if run $c tests/decks/ok_movie_frames.deck; then
   d="$TMP/$c"
   if ! check_file "$d" 1 1 1; then
      fail $c "test_hist:"; detail < "$d/chk.fail"
   else
      want=$(awk -v nmov=5 '
         { n++; cyc[n] = $2; t[n] = $3 + 0 }
         END {
            j = 1; last = 0
            for (m = 0; m < nmov; m++) {
               tm = t[n]*m/(nmov - 1)
               while (j < n) {
                  a = t[j+1] - tm; if (a < 0) a = -a
                  b = t[j] - tm;   if (b < 0) b = -b
                  if (a < b) j++; else break
               }
               if (j != last) { printf "%06d\n", cyc[j] % 1000000; last = j }
            }
         }' "$d/frames")
      got=$(cd "$d" && ls run.mv_*.bmp 2>/dev/null | sed 's/^run\.mv_p_\(.*\)\.bmp$/\1/')
      bad=""
      [ "$got" = "$want" ] || bad="movie frames $(echo "$got" | tr '\n' ' ')(wanted $(echo "$want" | tr '\n' ' '))"
      if [ -z "$bad" ]; then
         for f in "$d"/run.mv_p_*.bmp; do
            if [ "$(head -c 2 "$f")" != BM ] || [ "$(bmp_dim "$f" 18)" != 800 ] ||
               [ "$(bmp_dim "$f" 22)" != 600 ] ||
               [ "$(wc -c < "$f" | tr -d ' ')" != $((54 + 3*800*600)) ]; then
               bad="$(basename "$f") is not an 800 x 600 bitmap"; break
            fi
         done
      fi
      if [ -z "$bad" ]; then
         e="$TMP/${c}_again"; mkdir -p "$e"
         cp "$d"/*.hist "$d"/*.heartbeat "$e"/
         setkeys tests/decks/ok_movie_frames.deck Run "plots_only = yes" > "$TMP/$c.deck"
         if ! run ${c}_again "$TMP/$c.deck"; then
            bad="the plots_only run did not finish"
         else
            for f in "$d"/run.mv_p_*.bmp; do
               cmp -s "$f" "$e/$(basename "$f")" ||
                  { bad="plots_only drew $(basename "$f") differently"; break; }
            done
         fi
      fi
      if [ -n "$bad" ]; then fail $c "$bad"
      elif [ "$(echo "$want" | wc -l | tr -d ' ')" -ne 5 ]; then
         fail $c "$(echo "$want" | wc -l | tr -d ' ') frames, not 5"
      else
         pass $c
      fi
   fi
else
   fail $c "the run did not finish"
fi

summary
