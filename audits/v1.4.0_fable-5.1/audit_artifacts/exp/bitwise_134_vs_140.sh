#!/usr/bin/env bash
# Audit: run every pre-1.4.0 deck on bitwhiz v1.3.4 and v1.4.0 and compare
# heartbeat, tracer rows, history body, pictures and the screen's results,
# bit for bit (clock/build lines excluded, as tests/run_omp_tests.sh does).
OLD=/home/claude/audit/ref134/v134/src/bitwhiz
NEW=/home/claude/audit/repo/bitwhiz
EXE_OLD=${EXE_OLD:-$OLD/bin/bitwhiz}
EXE_NEW=${EXE_NEW:-$NEW/bin/bitwhiz}
OUT=/home/claude/audit/exp/bitwise; rm -rf $OUT; mkdir -p $OUT
cd $NEW
DECKS=$(ls input/*.deck tests/decks/ok_*.deck | grep -v tcas)
results() { awk '/ 6\. Initialization/ {on=1} / 8\. Output files/ {on=0} / 9\. Pictures/ {on=1} /run end/ {on=0} on' "$1" | grep -vE 'Wall time|wall clock|CPU time|Threads in the time loop'; }
beats()   { grep -vE '^# (started|ended|version|built|flags)' "$1" | awk '/^#/ {print; next} {$NF=""; print}'; }
rows()    { f=$(ls "$1"/*.tracers.csv 2>/dev/null) || return 0; grep -vE '^# (started|ended|version|built|flags|cycles)' "$f"; }
hbody()   { f=$(ls "$1"/*.hist 2>/dev/null) || return 0; hb=$(od -An -t d4 -j 12 -N 4 "$f" | tr -d ' '); tb=$(od -An -t d4 -j 52 -N 4 "$f" | tr -d ' '); head -c $((hb - tb)) "$f"; tail -c +$((hb + 1)) "$f"; }
npass=0; nfail=0
for d in $DECKS; do
   name=$(basename $d .deck)
   for v in old new; do
      mkdir -p $OUT/$v/$name; cp $d $OUT/$v/$name/
   done
   ( cd $OUT/old/$name && $EXE_OLD $(basename $d) > screen.txt 2>&1 )
   ( cd $OUT/new/$name && $EXE_NEW $(basename $d) > screen.txt 2>&1 )
   ok=1; why=""
   cmp -s <(results $OUT/old/$name/screen.txt) <(results $OUT/new/$name/screen.txt) || { ok=0; why="$why screen"; }
   cmp -s <(beats $OUT/old/$name/*.heartbeat) <(beats $OUT/new/$name/*.heartbeat) || { ok=0; why="$why heartbeat"; }
   cmp -s <(rows $OUT/old/$name) <(rows $OUT/new/$name) || { ok=0; why="$why tracers"; }
   cmp -s <(hbody $OUT/old/$name) <(hbody $OUT/new/$name) || { ok=0; why="$why hist"; }
   for f in $(cd $OUT/old/$name && ls *.bmp 2>/dev/null); do cmp -s $OUT/old/$name/$f $OUT/new/$name/$f || { ok=0; why="$why $f"; }; done
   cmp -s <(grep -v '^#' $OUT/old/$name/*.resolved) <(grep -v '^#' $OUT/new/$name/*.resolved) || why="$why (resolved-deck text differs)"
   if [ $ok = 1 ]; then npass=$((npass+1)); echo "same  $name$why"; else nfail=$((nfail+1)); echo "DIFF  $name:$why"; fi
done
echo "bit-for-bit v1.3.4 vs v1.4.0: $npass same, $nfail differ"
