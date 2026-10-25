#!/bin/sh
#**********************************************************************#
#  Copy a tagged release of bitwhiz into the nanoHUB tool's clone,     #
#  as its src/bitwhiz/ folder, so the copy on nanoHUB is always       #
#  exactly a tag of this repository and is never edited by hand.      #
#                                                                      #
#  Usage, from anywhere inside this repository:                        #
#                                                                      #
#     sh src/utils/export_nanohub.sh <tag> <nanoHUB clone>             #
#     sh src/utils/export_nanohub.sh v1.0.2 ~/Documents/Academic/bitwhiz
#                                                                      #
#  What it does:                                                       #
#   - checks that <tag> exists here, and that <nanoHUB clone> is the   #
#     tool's git clone (it has middleware/invoke and src/bitwhiz/)     #
#     with no uncommitted changes;                                     #
#   - writes every file of <tag> into <clone>/src/bitwhiz/, with       #
#     git's file modes, except doc/ (the equation sheets, not          #
#     published; set DOC=yes to include them), and a VERSION file      #
#     holding the tag, which the build's banner prints (the clone is   #
#     not this repository, so git describe cannot say);                #
#   - lists files that are in <clone>/src/bitwhiz/ but not in the tag  #
#     (removed or renamed since): it never deletes anything, you do;   #
#   - shows what changed in the clone, and the commands to commit,     #
#     tag and push it. It does not commit or push.                     #
#                                                                      #
#  The rule this serves: fixes are made here (branch shock), tagged,   #
#  and exported; never made in the nanoHUB clone first.                #
#                                                                      #
#  D. E. Kittell (with Claude), 10/23/26; VERSION file, 10/24/26.      #
#**********************************************************************#
set -e

if [ $# -ne 2 ]; then
   echo "usage: sh src/utils/export_nanohub.sh <tag> <nanoHUB clone>"
   exit 1
fi
tag=$1
dest=$2
DOC=${DOC:-no}

# This repository (the script may be run from any folder inside it).
repo=$(git rev-parse --show-toplevel 2>/dev/null) || {
   echo "error: run this from inside the bitwhiz repository"; exit 1; }

# The tag must exist here.
if ! git -C "$repo" rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
   echo "error: no tag $tag in $repo (git tag -l lists them)"; exit 1
fi

# The destination must be the tool's clone, clean.
if [ ! -f "$dest/middleware/invoke" ] || [ ! -d "$dest/src/bitwhiz" ]; then
   echo "error: $dest is not the nanoHUB tool's clone (no middleware/invoke"
   echo "       or src/bitwhiz/)"; exit 1
fi
if [ -n "$(git -C "$dest" status --porcelain)" ]; then
   echo "error: $dest has uncommitted changes; commit or set them aside first:"
   git -C "$dest" status --short; exit 1
fi

# The tag's files (doc/ left out unless DOC=yes), with their modes.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git -C "$repo" ls-tree -r "$tag" |
   { if [ "$DOC" = yes ]; then cat; else grep -v '	doc/'; fi; } > "$tmp/list"
cut -f2 "$tmp/list" | LC_ALL=C sort > "$tmp/tag"

# Export: unpack the tag in a scratch folder, then copy each file over
# its old copy (cp writes into an existing file rather than replacing
# it, which also works where deleting is not allowed) and set its mode
# as git records it (755 or 644).
mkdir "$tmp/x"
git -C "$repo" archive "$tag" | tar -x -f - -C "$tmp/x"
while read -r mode type hash path; do
   mkdir -p "$dest/src/bitwhiz/$(dirname "$path")"
   cp "$tmp/x/$path" "$dest/src/bitwhiz/$path"
   if [ "$mode" = 100755 ]; then
      chmod 755 "$dest/src/bitwhiz/$path"
   else
      chmod 644 "$dest/src/bitwhiz/$path"
   fi
done < "$tmp/list"
printf '%s\n' "$tag" > "$dest/src/bitwhiz/VERSION"
chmod 644 "$dest/src/bitwhiz/VERSION"

# Files the clone has under src/bitwhiz/ that the tag does not.
# (VERSION is written here, not taken from the tag.)
git -C "$dest" ls-files src/bitwhiz | sed 's|^src/bitwhiz/||' |
   grep -vx VERSION | LC_ALL=C sort > "$tmp/clone"
LC_ALL=C comm -13 "$tmp/tag" "$tmp/clone" > "$tmp/stale"

echo "Exported $tag ($(git -C "$repo" rev-parse --short "$tag^{commit}")) into $dest/src/bitwhiz/"
if [ -s "$tmp/stale" ]; then
   echo
   echo "These files are in the clone but not in $tag (removed or renamed"
   echo "since). Remove them before committing:"
   sed 's|^|   git rm src/bitwhiz/|' "$tmp/stale"
fi
echo
if [ -z "$(git -C "$dest" status --porcelain)" ]; then
   if [ -s "$tmp/stale" ]; then
      echo "Nothing else changed: once those are removed, the clone holds $tag."
   else
      echo "Nothing changed: the clone already holds $tag."
   fi
else
   echo "Changed in the clone:"
   git -C "$dest" status --short
   echo
   echo "To publish it (one push: nanoHUB may block an address that pushes"
   echo "often), from $dest:"
   echo "   git add -A src/bitwhiz"
   echo "   git commit -m \"bitwhiz $tag\""
   echo "   git tag $tag"
   echo "   git push origin master $tag"
   echo
   echo "Then, on the tool's status page, \"Wait! I've made more changes\""
   echo "tells nanoHUB the new code is ready to install."
fi
