#!/bin/sh
#**********************************************************************#
#  Run every deck in input/, each in its own folder, to look at the    #
#  results after a code change: 'make runs' calls this.                #
#                                                                      #
#     sh src/utils/run_decks.sh <bitwhiz executable> [<folder>]        #
#                                                                      #
#  The folder (runs/ by default) is emptied first, then each deck      #
#  runs in <folder>/<deck name>/, beside its own copy of the deck,     #
#  so all of a run's files land there (heartbeat, resolved deck,       #
#  tracer and history files, pictures) and the screen goes to          #
#  screen.txt. input/ is never written. One line per deck as it        #
#  finishes: its exit status, wall time (bitwhiz's own), how many      #
#  files it wrote and their size; then the total. Exit status 1 if     #
#  any deck failed (they all run anyway).                              #
#                                                                      #
#  runs/ is in .gitignore, and 'make tidy' (so 'make clean') removes   #
#  it.                                                                 #
#                                                                      #
#  D. E. Kittell (with Claude), 11/03/26.                              #
#**********************************************************************#
exe=$1
out=${2:-runs}
if [ -z "$exe" ] || [ ! -x "$exe" ]; then
   echo "usage: sh src/utils/run_decks.sh <bitwhiz executable> [<folder>]"
   exit 1
fi
exe=$(cd "$(dirname "$exe")" && pwd)/$(basename "$exe")   # absolute: runs cd
#*** The folder is emptied with rm -rf, so it must be a plain name in
#*** this folder: no path, not . or .., not input, src or tests.
case $out in
   */*|.|..|input|src|tests|doc|bin|build|'')
      echo "run_decks.sh: \"$out\" is not a folder name it may empty"
      exit 1 ;;
esac

rm -rf "$out"
mkdir -p "$out"
echo "runs: $(ls input/*.deck | wc -l | tr -d ' ') decks with $exe, into $out/"
nbad=0
for deck in input/*.deck; do
   name=$(basename "$deck" .deck)
   d=$out/$name
   mkdir -p "$d"
   cp "$deck" "$d/"
   if (cd "$d" && "$exe" "$name.deck" > screen.txt 2>&1); then
      how=ok
   else
      how=FAILED
      nbad=$((nbad + 1))
   fi
   wall=$(awk '/wall clock/ {print $4}' "$d/screen.txt")
   nf=$(ls "$d" | wc -l | tr -d ' ')
   kb=$(du -sk "$d" | awk '{print $1}')
   printf '   %-28s %-7s %8s s  %3s files  %6.1f MB\n' "$name" "$how" \
      "${wall:-?}" "$nf" "$(echo "$kb" | awk '{print $1/1024}')"
done
kb=$(du -sk "$out" | awk '{print $1}')
printf 'runs: %s failed; %.1f MB in %s/ (make tidy removes it)\n' "$nbad" \
   "$(echo "$kb" | awk '{print $1/1024}')" "$out"
[ "$nbad" -eq 0 ]
