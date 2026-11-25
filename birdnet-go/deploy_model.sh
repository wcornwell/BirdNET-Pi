#!/usr/bin/env bash
#
# Copy a recognizer (.tflite + _Labels.txt) from recognizers/ to the Pi.
# Runs on the LAPTOP. It copies only; it does not edit the BirdNET-Go config or
# restart anything, because the config path and the Docker mounts are confirmed
# only after the first install. It prints the lines to set.
#
#   BIRDNETPI_HOST=wcornwell@100.77.3.46 birdnet-go/deploy_model.sh smithslake0-6-bn24
#
# Override the destination with PI_MODEL_DIR (default ~/birdnet-go-app/models).

set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

NAME="${1:-}"
[[ -n "$NAME" ]] || die "usage: deploy_model.sh <recognizer-name>   (e.g. smithslake0-6-bn24)"
HOST="${BIRDNETPI_HOST:-}"
[[ -n "$HOST" ]] || die "set BIRDNETPI_HOST=user@host (Tailscale address works from the work laptop)"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/recognizers"
DEST="${PI_MODEL_DIR:-~/birdnet-go-app/models}"

[[ -f "$SRC/$NAME.tflite" ]]      || die "no $SRC/$NAME.tflite (run tools/sync_recognizer.sh first)"
[[ -f "$SRC/${NAME}_Labels.txt" ]] || die "no ${NAME}_Labels.txt: a model cannot load without its labels"
[[ "$(stat -f %z "$SRC/$NAME.tflite")" -gt 1000000 ]] \
  || die "$NAME.tflite is tiny: not downloaded from OneDrive yet?"

ssh -o ConnectTimeout=8 "$HOST" "mkdir -p $DEST"
rsync -av --progress "$SRC/$NAME.tflite" "$SRC/${NAME}_Labels.txt" "$HOST:$DEST/"

cat <<EOF

copied to $HOST:$DEST. Now, on the Pi, set in the BirdNET-Go config
(paths as the container sees them, so check the mount):

  birdnet:
    modelpath: <models dir>/$NAME.tflite
    labelpath: <models dir>/${NAME}_Labels.txt

and restart BirdNET-Go. Leave latitude/longitude unset (see config.yaml).
EOF
