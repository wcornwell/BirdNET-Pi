#!/usr/bin/env bash
#
# Remove superseded recognizers from git HISTORY, keeping every file that is in
# recognizers/ at HEAD. Pruning recognizers/ only changes the checkout; each deploy
# leaves ~35 MB of .tflite in .git forever, so run this periodically.
#
#   ./tools/strip_old_recognizers.sh              # report only: what would go, how much it saves
#   ./tools/strip_old_recognizers.sh --execute    # rewrite history in THIS clone (never pushes)
#
# What --execute does, in order:
#   1. refuses unless the tree is clean and HEAD is on main
#   2. writes a full backup bundle outside the repo (path printed)
#   3. git filter-repo --invert-paths over every recognizers/ path that is NOT at HEAD
#   4. re-adds origin and upstream (filter-repo drops remotes)
#   5. merge -s ours upstream/main -- the repair that keeps `git merge upstream/main`
#      working (see CLAUDE.md "Rewriting history here"); checks main..upstream/main is 0
#   6. expires the reflog and gc's, then prints the size before/after
# It prints the push and Pi commands but runs neither. Both are deliberate human steps:
# the push is a force-push, and the Pi must be reset IN PLACE, never re-cloned.
#
# Only paths under recognizers/ are ever stripped. model/ and the tflite_runtime wheels
# are upstream's files; stripping them is what severs ancestry.

set -euo pipefail

EXECUTE=0
case "${1:-}" in
  "")        ;;
  --execute) EXECUTE=1 ;;
  -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)         printf 'error: unknown argument: %s\n' "$1" >&2; exit 1 ;;
esac

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
[[ -f newinstaller.sh ]] || die "$REPO_ROOT does not look like the BirdNET-Pi repo"
git filter-repo --version >/dev/null 2>&1 || die "git-filter-repo not installed (pip install git-filter-repo)"
git remote get-url upstream >/dev/null 2>&1 || die "no 'upstream' remote; add Nachtzuster/BirdNET-Pi first"
ORIGIN_URL="$(git remote get-url origin)"
UPSTREAM_URL="$(git remote get-url upstream)"

keep="$(mktemp)"; strip="$(mktemp)"; trap 'rm -f "$keep" "$strip"' EXIT
git ls-tree -r --name-only HEAD -- recognizers/ | sort > "$keep"
git log --all --name-only --pretty=format: -- recognizers/ | sed '/^$/d' | sort -u \
  | comm -23 - "$keep" > "$strip"

if [[ ! -s "$strip" ]]; then
  echo "nothing to strip: every recognizers/ path in history is at HEAD."
  exit 0
fi

# Size of the blobs that are only reachable via stripped paths (on-disk, compressed).
saved=0
while read -r path; do
  while read -r blob; do
    s="$(git cat-file --batch-check='%(objectsize:disk)' <<<"$blob")"
    saved=$((saved + s))
  done < <(git log --all --format= --raw --no-abbrev -- "$path" | awk '{print $4}' | grep -v '^0*$' | sort -u)
done < "$strip"

echo "keep (at HEAD):"; sed 's/^/  /' "$keep" | grep -E '\.tflite$' || true
echo "strip: $(wc -l < "$strip" | tr -d ' ') paths, roughly $((saved / 1000000)) MB of blobs"
echo ".git now: $(du -sh .git | cut -f1)"
if [[ $EXECUTE -eq 0 ]]; then
  echo "dry run; re-run with --execute to rewrite history in this clone."
  exit 0
fi

[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die "working tree has uncommitted changes"
[[ "$(git rev-parse --abbrev-ref HEAD)" == main ]] || die "not on main"
git fetch -q upstream
before="$(du -sh .git | cut -f1)"

bundle="${TMPDIR:-/tmp}/BirdNET-Pi-pre-strip-$(date +%Y%m%d-%H%M%S).bundle"
git bundle create "$bundle" --all >/dev/null 2>&1
echo "backup: $bundle"

git filter-repo --force --invert-paths --paths-from-file "$strip" >/dev/null 2>&1
# filter-repo drops origin (and sometimes more), so set both whether or not they survived.
for r in origin:"$ORIGIN_URL" upstream:"$UPSTREAM_URL"; do
  git remote get-url "${r%%:*}" >/dev/null 2>&1 \
    && git remote set-url "${r%%:*}" "${r#*:}" || git remote add "${r%%:*}" "${r#*:}"
done
git fetch -q upstream
git merge -s ours --allow-unrelated-histories --no-edit upstream/main >/dev/null
behind="$(git rev-list --count main..upstream/main)"
[[ "$behind" == 0 ]] || die "main..upstream/main is $behind, expected 0; restore from $bundle"

git reflog expire --expire=now --all
git gc -q --prune=now --aggressive
echo ".git: $before -> $(du -sh .git | cut -f1)"
cat <<EOF

History rewritten locally. Nothing has been pushed. To finish:

  git push --force-with-lease origin main

  # then on the Pi, IN PLACE (never re-clone). Back up first:
  #   cp ~/BirdNET-Pi/scripts/birds.db ~/BirdNET-Pi/birdnet.conf <off-device>
  cd ~/BirdNET-Pi && git fetch origin && git reset --hard origin/main
  git reflog expire --expire=now --all && git gc --prune=now
EOF
