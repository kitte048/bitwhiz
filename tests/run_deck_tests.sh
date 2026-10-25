#!/usr/bin/env bash
#**********************************************************************#
#  Deck reader tests.  Run from the bitwhiz folder, after 'make':      #
#                                                                      #
#     ./tests/run_deck_tests.sh                                        #
#                                                                      #
#  Every deck in tests/decks/ starts with a line                       #
#     # expect: ok                    (must read cleanly), or          #
#     # expect: <part of a message>   (must fail, with that message)   #
#  Every "ok" deck, and every deck in input/, is also round-tripped:   #
#  its resolved deck is read back in and must resolve to the same      #
#  statements (comments aside).                                        #
#                                                                      #
#  One line per test as it finishes, so a long run can be watched:     #
#     [ 37/134] ok    tests/decks/bad_cfl.deck              0.1 s      #
#     [126/134] FAIL  input/foo.deck: <what went wrong>                #
#  then the totals and the time taken.                                 #
#**********************************************************************#
BIN=${BIN:-./bin/bitwhiz}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
npass=0; nfail=0

# The tests, counted up front for the counter: the decks in tests/decks/
# and input/, then the 4 command-line cases at the end.
ntest=4
for deck in tests/decks/*.deck input/*.deck; do
   [ -e "$deck" ] && ntest=$((ntest+1))
done
itest=0; w=${#ntest}

# The clock, in seconds: to 1 us where the shell or date can say it,
# else whole seconds (macOS date has no %N).
now() {
   if [ -n "${EPOCHREALTIME:-}" ]; then echo "$EPOCHREALTIME" | tr ',' '.'; return; fi
   t=$(date +%s.%N 2>/dev/null)
   case $t in *[!0-9.]*|'') date +%s ;; *) echo "$t" ;; esac
}
start() { itest=$((itest+1)); t0=$(now); }   # at the start of each test
pass() {   # $1 = the test
   dt=$(awk -v a="$t0" -v b="$(now)" 'BEGIN { printf "%.1f", b - a }')
   printf "[%*d/%d] ok    %-40s %6s s\n" "$w" "$itest" "$ntest" "$1" "$dt"
   npass=$((npass+1))
}
fail() { printf "[%*d/%d] FAIL  %s: %s\n" "$w" "$itest" "$ntest" "$1" "$2"; nfail=$((nfail+1)); }

# The resolved deck, as printed between its header and "End bitwhiz".
resolved() { awk '/^#\*+#$/ && !on {on=1} on {print} /^End bitwhiz/ && on {exit}'; }
# Its statements only: no comments, no blank lines.
statements() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' | grep -v '^$'; }

roundtrip() {   # $1 = a deck that reads cleanly
   "$BIN" "$1" | resolved > "$TMP/r1.deck"
   "$BIN" "$TMP/r1.deck" > "$TMP/out2" 2>&1 || { fail "$1" "resolved deck does not read back"; return 1; }
   resolved < "$TMP/out2" > "$TMP/r2.deck"
   if ! diff <(statements < "$TMP/r1.deck") <(statements < "$TMP/r2.deck") > /dev/null; then
      fail "$1" "resolved deck changes when read back"; return 1
   fi
   return 0
}

for deck in tests/decks/*.deck; do
   start
   expect=$(head -1 "$deck" | tr -d '\r' | sed -n 's/^# expect: //p')
   if [ -z "$expect" ]; then fail "$deck" "no '# expect:' line"; continue; fi
   out=$("$BIN" "$deck" 2>&1); rc=$?
   if echo "$out" | grep -qE 'Backtrace|SIGFPE|SIGSEGV|Fortran runtime|At line [0-9]+ of file'; then
      fail "$deck" "the program crashed"; continue
   fi
   if [ "$expect" = "ok" ]; then
      if [ $rc -ne 0 ]; then fail "$deck" "expected a clean read, got:"; echo "$out" | grep error | head -3; continue; fi
      roundtrip "$deck" || continue
   else
      if [ $rc -eq 0 ]; then fail "$deck" "expected an error, but it read cleanly"; continue; fi
      if ! echo "$out" | grep -qF -- "$expect"; then
         fail "$deck" "expected \"$expect\", got:"; echo "$out" | grep error | head -3; continue
      fi
   fi
   pass "$deck"
done

for deck in input/*.deck; do
   [ -e "$deck" ] || continue
   start
   if ! "$BIN" "$deck" > /dev/null 2>&1; then fail "$deck" "does not read cleanly"; continue; fi
   roundtrip "$deck" && pass "$deck"
done

# Command-line cases: no file to read, or a bad thing in place of a deck.
# Each must stop cleanly (exit code not 0) with the message shown.
: > "$TMP/empty.deck"
cmdline() {   # $1 = the argument, $2 = part of the expected message
   start
   out=$("$BIN" "$1" 2>&1); rc=$?
   if [ $rc -eq 0 ] || ! echo "$out" | grep -qF -- "$2"; then
      fail "bitwhiz '$1'" "expected \"$2\""
   else
      pass "bitwhiz '$1'"
   fi
}
cmdline ""                   "usage"
cmdline "no_such_file.deck"  "cannot open the deck file"
cmdline "tests"              "is a folder, not a deck file"
cmdline "$TMP/empty.deck"    "the deck file is empty"

echo "deck tests: $npass passed, $nfail failed ($SECONDS s)"
[ $nfail -eq 0 ]
