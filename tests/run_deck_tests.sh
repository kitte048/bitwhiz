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
#  its resolved deck (<title>.resolved, written by the run) is run in  #
#  turn and must resolve to the same statements (comments aside).      #
#  Every run is in its own scratch folder, so nothing is left in the   #
#  bitwhiz folder.                                                     #
#                                                                      #
#  One line per test as it finishes, with a counter (tests/report.sh). #
#**********************************************************************#
BIN=${BIN:-./bin/bitwhiz}
BIN=$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")    # absolute
ROOT=$(pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
. "$(dirname "$0")/report.sh"

# The tests: the decks in tests/decks/ and input/, then the 4
# command-line cases at the end.
n=4
for deck in tests/decks/*.deck input/*.deck; do
   [ -e "$deck" ] && n=$((n+1))
done
plan $n "deck tests"

# Run deck $1 (a path from the bitwhiz folder) in the empty folder $2;
# its screen goes to $2/screen, and its exit status is returned.
run_in() {
   rm -rf "$2"; mkdir -p "$2"
   (cd "$2" && "$BIN" "$ROOT/$1" > screen 2>&1)
}
# A deck's statements only: no comments, no blank lines.
statements() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' | grep -v '^$'; }

roundtrip() {   # $1 = a deck that ran cleanly in $TMP/r1
   local r1 r2
   r1=$(ls "$TMP"/r1/*.resolved 2>/dev/null)
   [ -n "$r1" ] && [ "$(echo "$r1" | wc -l)" -eq 1 ] || { fail "$1" "no resolved deck (<title>.resolved) written"; return 1; }
   rm -rf "$TMP/r2"; mkdir -p "$TMP/r2"
   (cd "$TMP/r2" && "$BIN" "$r1" > screen 2>&1) || { fail "$1" "resolved deck does not read back"; return 1; }
   r2=$(ls "$TMP"/r2/*.resolved 2>/dev/null)
   if [ -z "$r2" ] || ! diff <(statements < "$r1") <(statements < "$r2") > /dev/null; then
      fail "$1" "resolved deck changes when read back"; return 1
   fi
   return 0
}

for deck in tests/decks/*.deck; do
   begin
   expect=$(head -1 "$deck" | tr -d '\r' | sed -n 's/^# expect: //p')
   if [ -z "$expect" ]; then fail "$deck" "no '# expect:' line"; continue; fi
   run_in "$deck" "$TMP/r1"; rc=$?; out=$(cat "$TMP/r1/screen")
   if echo "$out" | grep -qE 'Backtrace|SIGFPE|SIGSEGV|Fortran runtime|At line [0-9]+ of file'; then
      fail "$deck" "the program crashed"; continue
   fi
   if [ "$expect" = "ok" ]; then
      if [ $rc -ne 0 ]; then fail "$deck" "expected a clean read, got:"; echo "$out" | grep error | head -3 | detail; continue; fi
      roundtrip "$deck" || continue
   else
      if [ $rc -eq 0 ]; then fail "$deck" "expected an error, but it read cleanly"; continue; fi
      if ! echo "$out" | grep -qF -- "$expect"; then
         fail "$deck" "expected \"$expect\", got:"; echo "$out" | grep error | head -3 | detail; continue
      fi
   fi
   pass "$deck"
done

for deck in input/*.deck; do
   [ -e "$deck" ] || continue
   begin
   if ! run_in "$deck" "$TMP/r1"; then fail "$deck" "does not read cleanly"; continue; fi
   roundtrip "$deck" && pass "$deck"
done

# Command-line cases: no file to read, or a bad thing in place of a deck.
# Each must stop cleanly (exit code not 0) with the message shown.
: > "$TMP/empty.deck"
cmdline() {   # $1 = the argument, $2 = part of the expected message
   begin
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

summary
