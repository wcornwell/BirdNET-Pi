#!/usr/bin/env bash
#
# Copy a trained recognizer out of the OneDrive call_library into recognizers/,
# and stage it so the next push carries it to the Pi.
#
# Runs on the LAPTOP, not on the Pi. Deploy is: run this -> commit -> push ->
# `git pull` on the Pi -> pick the model in the web UI (Tools > Settings > Model).
# Dropping a .tflite in recognizers/ only adds it to the dropdown; it does not
# switch the running model.
#
#   ./tools/sync_recognizer.sh                 # newest .tflite in call_library
#   ./tools/sync_recognizer.sh --name run0-2-bn
#   ./tools/sync_recognizer.sh --list          # what's available, newest first
#   ./tools/sync_recognizer.sh --dry-run
#   ./tools/sync_recognizer.sh --commit        # also commit (never pushes)
#   ./tools/sync_recognizer.sh --keep 3        # keep 3 models instead of 2
#   ./tools/sync_recognizer.sh --no-prune      # keep every model already here
#
# The Pi keeps the 2 most recently deployed models -- the one it is running and
# one to fall back to -- and older ones are removed in the same commit. Set
# BIRDNETPI_HOST=user@host and the script will read the Pi's active MODEL over
# ssh and refuse to prune it; without it you get a warning instead of a check.
#
# Only .tflite models can run on the Pi. The Perch arm of a dual run emits .npz,
# which this script will not see and the Pi cannot load.

set -euo pipefail

CALL_LIBRARY="${CALL_LIBRARY:-$HOME/Library/CloudStorage/OneDrive-UNSW/call_library}"
SRC_DIR="$CALL_LIBRARY/recognizers"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="$REPO_ROOT/recognizers"

MODEL=""
DRY_RUN=0
DO_COMMIT=0
LIST_ONLY=0
KEEP=2
NO_PRUNE=0

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)    MODEL="${2:-}"; [[ -n "$MODEL" ]] || die "--name needs a model name"; shift 2 ;;
    --list)    LIST_ONLY=1; shift ;;
    --keep)    KEEP="${2:-}"; [[ "$KEEP" =~ ^[0-9]+$ ]] || die "--keep needs a number"; shift 2 ;;
    --no-prune) NO_PRUNE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --commit)  DO_COMMIT=1; shift ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         die "unknown argument: $1" ;;
  esac
done

[[ -d "$SRC_DIR" ]] || die "no recognizers dir at $SRC_DIR (set CALL_LIBRARY to override)"
# recognizers/ is not in the repo when it holds no models -- git tracks files, not
# directories, and pruning the last model takes the directory with it.
[[ -f "$REPO_ROOT/newinstaller.sh" ]] || die "$REPO_ROOT does not look like the BirdNET-Pi repo"
mkdir -p "$DEST_DIR"

# Newest first. -f keeps this to plain files; the dir also holds CSVs and caches.
models_by_date() {
  find "$SRC_DIR" -maxdepth 1 -type f -name '*.tflite' -print0 \
    | xargs -0 stat -f '%m %N' \
    | sort -rn \
    | while read -r epoch path; do
        printf '%s\t%s\n' "$(date -r "$epoch" '+%Y-%m-%d %H:%M')" "$(basename "$path" .tflite)"
      done
}

# Built once, then sliced with awk/parameter expansion rather than `head`: `head`
# closes the pipe early, and under `pipefail` that SIGPIPE fails the whole
# pipeline, which `set -e` turns into a silent exit 141.
listing="$(models_by_date)"
[[ -n "$listing" ]] || die "no .tflite files in $SRC_DIR"

if [[ $LIST_ONLY -eq 1 ]]; then
  printf '%s\n' "$listing" | awk 'NR<=20'
  exit 0
fi

if [[ -z "$MODEL" ]]; then
  first_line="${listing%%$'\n'*}"
  MODEL="${first_line#*$'\t'}"
fi

SRC_MODEL="$SRC_DIR/$MODEL.tflite"
[[ -f "$SRC_MODEL" ]] || die "no such model: $SRC_MODEL (try --list)"
[[ -f "$SRC_DIR/${MODEL}_Labels.txt" ]] \
  || die "$MODEL has no _Labels.txt — the Pi cannot load a model without its labels"

# An OneDrive file that is a cloud placeholder rather than a real download reads
# as a few KB. A real BirdNET head is tens of MB.
model_size="$(stat -f %z "$SRC_MODEL")"
(( model_size > 1000000 )) \
  || die "$MODEL.tflite is only ${model_size} bytes — not downloaded from OneDrive yet?"

printf 'model:  %s  (%s MB, %s)\n' "$MODEL" \
  "$(( model_size / 1000000 ))" "$(date -r "$SRC_MODEL" '+%Y-%m-%d %H:%M')"
printf 'from:   %s\n' "$SRC_DIR"
printf 'to:     %s\n\n' "$DEST_DIR"

# Everything the training run emitted under this name: the model, the labels the
# Pi needs, and the params / sample_counts / validation_metrics that record where
# it came from. Naming is not uniform across runs (_Params.csv on older models,
# .birdnet.train-params.csv on newer ones), so take the whole prefix.
copied=()
unchanged=()
shopt -s nullglob
for src in "$SRC_DIR/$MODEL".* "$SRC_DIR/${MODEL}_"*; do
  [[ -f "$src" ]] || continue
  name="$(basename "$src")"
  dest="$DEST_DIR/$name"

  if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
    unchanged+=("$name")
    continue
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    printf '  would copy  %s\n' "$name"
  else
    # 755 matches the mode the existing recognizers are tracked with.
    install -m 755 "$src" "$dest"
    printf '  copied      %s\n' "$name"
  fi
  copied+=("$name")
done
shopt -u nullglob

for name in "${unchanged[@]:-}"; do
  [[ -n "$name" ]] && printf '  unchanged   %s\n' "$name"
done

if [[ ${#copied[@]} -gt 0 && $DRY_RUN -eq 0 ]]; then
  git -C "$REPO_ROOT" add -- "${copied[@]/#/recognizers/}"
fi

# ---------------------------------------------------------------- prune -----
#
# Keep the KEEP most recently deployed models, drop the rest. Two is the useful
# number: the one the Pi is running, and the one to fall back to. Each model is
# ~37 MB, the Pi carries the whole repo on an SD card, and the web UI lists every
# .tflite it finds -- so an unpruned recognizers/ is both bulk and clutter.
#
# "Most recently deployed" is commit time, not mtime: mtime is set by whatever
# order files were copied and says nothing about what was actually shipped. A
# model that is staged but not yet committed is the newest by definition.
prune_candidates() {
  local f name ts
  for f in "$DEST_DIR"/*.tflite; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f" .tflite)"
    ts="$(git -C "$REPO_ROOT" log -1 --format=%at -- "recognizers/$name.tflite" 2>/dev/null || true)"
    [[ -n "$ts" ]] || ts=9999999999
    printf '%s\t%s\n' "$ts" "$name"
  done | sort -rn | awk -v keep="$KEEP" 'NR>keep {print $2}'
}

if [[ $NO_PRUNE -eq 1 ]]; then
  doomed=""
else
  doomed="$(prune_candidates)"
fi

if [[ -n "$doomed" ]]; then
  # The active model must survive. The laptop cannot know which that is, so ask
  # the Pi when we can reach it; when we cannot, say plainly what is going.
  active=""
  if [[ -n "${BIRDNETPI_HOST:-}" ]]; then
    active="$(ssh -o ConnectTimeout=8 -o BatchMode=yes "$BIRDNETPI_HOST" \
      "sed -n 's/^MODEL=//p' ~/BirdNET-Pi/birdnet.conf" 2>/dev/null || true)"
  fi

  printf '\nprune (keeping the %d most recently deployed):\n' "$KEEP"
  while read -r name; do
    [[ -n "$name" ]] || continue
    if [[ -n "$active" && "$name" == "$active" ]]; then
      die "refusing to prune $name — the Pi is running it (MODEL=$active in birdnet.conf)"
    fi
    printf '  remove      %s\n' "$name"
  done <<< "$doomed"

  if [[ -n "$active" ]]; then
    printf '  (Pi is running %s — kept)\n' "$active"
  else
    printf '  ⚠ could not read the Pi'"'"'s active MODEL%s.\n' \
      "${BIRDNETPI_HOST:+ at $BIRDNETPI_HOST}"
    printf '    Check none of the above is in use before pushing. Set BIRDNETPI_HOST\n'
    printf '    (e.g. user@host) to have this checked automatically.\n'
  fi

  if [[ $DRY_RUN -eq 0 ]]; then
    while read -r name; do
      [[ -n "$name" ]] || continue
      shopt -s nullglob
      for f in "$DEST_DIR/$name".* "$DEST_DIR/${name}_"*; do
        rel="recognizers/$(basename "$f")"
        if git -C "$REPO_ROOT" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
          git -C "$REPO_ROOT" rm --quiet -- "$rel"
        else
          rm -f "$f"
        fi
      done
      shopt -u nullglob
    done <<< "$doomed"
  fi
fi

if [[ $DRY_RUN -eq 1 ]]; then
  printf '\ndry run — nothing written, nothing staged.\n'
  exit 0
fi

if [[ ${#copied[@]} -eq 0 && -z "$doomed" ]]; then
  printf '\nnothing to do — %s is already up to date here.\n' "$MODEL"
  exit 0
fi

printf '\nstaged: %d file(s) added' "${#copied[@]}"
[[ -n "$doomed" ]] && printf ', %d model(s) removed' "$(printf '%s\n' "$doomed" | grep -c .)"
printf '.\n'

if [[ $DO_COMMIT -eq 1 ]]; then
  git -C "$REPO_ROOT" commit --quiet -m "deploy $MODEL recognizer" -- recognizers/
  printf 'committed. Push when ready, then `git pull` on the Pi.\n'
else
  printf 'Commit and push when ready, then `git pull` on the Pi.\n'
fi
