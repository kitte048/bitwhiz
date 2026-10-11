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
#**********************************************************************#
BIN=${BIN:-./bin/bitwhiz}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
npass=0; nfail=0

fail() { echo "FAIL  $1: $2"; nfail=$((nfail+1)); }

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
   npass=$((npass+1))
done

for deck in input/*.deck; do
   [ -e "$deck" ] || continue
   if ! "$BIN" "$deck" > /dev/null 2>&1; then fail "$deck" "does not read cleanly"; continue; fi
   roundtrip "$deck" && npass=$((npass+1))
done

echo "deck tests: $npass passed, $nfail failed"
[ $nfail -eq 0 ]
