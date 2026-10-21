#!/usr/bin/env bash
#**********************************************************************#
#  Release tests: the optimized build must give the debug build's      #
#  answer, bit for bit. 'make release' runs this; by hand, from the    #
#  bitwhiz folder, after 'make' and 'make release':                    #
#                                                                      #
#     ./tests/run_release_tests.sh                                     #
#                                                                      #
#  Each deck below is run once on each build (one thread). A deck      #
#  passes if everything the release build prints from section 6 on,    #
#  every heartbeat line, every tracer row and the history file (byte   #
#  for byte) are IDENTICAL to the debug build's. Left out, as in the   #
#  OpenMP tests: the clock times, and the lines that name the build    #
#  itself (version, built, flags, and the history file's text block),  #
#  which are meant to differ.                                          #
#                                                                      #
#  Why identical, not "close": the two builds differ only in checks    #
#  and optimization, never in arithmetic (Makefile, NOTES at RFLAGS:   #
#  -ffp-contract=off, no -ffast-math). A difference in the last digit  #
#  means a flag changed the arithmetic, or the code reads something    #
#  it never set (the debug build fills those with NaN).                #
#**********************************************************************#
DEBUG=${DEBUG:-./bin/bitwhiz}
RELEASE=${RELEASE:-./bin/bitwhiz_release}
DEBUG=$(cd "$(dirname "$DEBUG")" && pwd)/$(basename "$DEBUG")         # absolute
RELEASE=$(cd "$(dirname "$RELEASE")" && pwd)/$(basename "$RELEASE")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
npass=0; nfail=0

DECKS="input/me697_double_shock_2p00.deck
tests/decks/ok_setup_counter.deck
tests/decks/ok_plate_spall.deck
tests/decks/ok_method_rs.deck
tests/decks/ok_method_rs_order1.deck"

fail() { echo "FAIL  $1: $2"; nfail=$((nfail+1)); }

# The three filters below are the OpenMP tests' (run_omp_tests.sh).
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

for deck in $DECKS; do
   name=$(basename "$deck" .deck)
   ok=1
   for b in debug release; do
      d="$TMP/$name/$b"; mkdir -p "$d"
      [ $b = debug ] && exe=$DEBUG || exe=$RELEASE
      # One thread, so this compares the builds and nothing else.
      awk '
         tolower($0) ~ /^[ \t]*num_threads[ \t]*=/ { next }
         { print }
         tolower($0) ~ /^[ \t]*begin[ \t]+run[ \t]*(#.*)?$/ { print "  num_threads = 1" }
      ' "$deck" > "$d/run.deck"
      if ! (cd "$d" && "$exe" run.deck > screen.out 2>&1); then
         fail "$deck" "the $b build's run did not finish"; ok=0
      fi
   done
   [ $ok -eq 1 ] || continue
   a="$TMP/$name/debug"; b="$TMP/$name/release"
   if ! grep -q 'optimized' "$b/screen.out"; then
      fail "$deck" "the release executable does not say it is optimized"; continue
   fi
   if ! diff <(results "$a/screen.out") <(results "$b/screen.out") > "$b/diff"; then
      fail "$deck" "the release build prints different results:"
      head -4 "$b/diff"; continue
   fi
   if ! diff <(beats "$(ls "$a"/*.heartbeat)") <(beats "$(ls "$b"/*.heartbeat)") > "$b/diff"; then
      fail "$deck" "the release build's heartbeat differs:"
      head -4 "$b/diff"; continue
   fi
   if ! diff <(rows "$a") <(rows "$b") > "$b/diff"; then
      fail "$deck" "the release build's tracer file differs:"
      head -4 "$b/diff" | cut -c1-120; continue
   fi
   if ! cmp -s <(hbody "$a") <(hbody "$b"); then
      fail "$deck" "the release build's history file differs"; continue
   fi
   npass=$((npass+1))
done

echo "release tests: $npass passed, $nfail failed (debug and release, bit for bit)"
[ $nfail -eq 0 ]
