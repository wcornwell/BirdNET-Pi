#!/usr/bin/env bash
#
# Copy a recognizer (.tflite + _Labels.txt) from recognizers/ to the Pi.
# Runs on the LAPTOP. It copies only; it does not edit the BirdNET-Go config or
# restart anything, because the config path and the Docker mounts are confirmed
# only after the first install. It prints the lines to set.
#
#   BIRDNETPI_HOST=wcornwell@<pi-tailscale-address> birdnet-go/deploy_model.sh smithslake0-6-bn24
#
# Destination on the Pi defaults to ~/birdnet-go-app/data/models, which the container
# sees as /data/models. Override with PI_MODEL_DIR.

set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

NAME="${1:-}"
[[ -n "$NAME" ]] || die "usage: deploy_model.sh <recognizer-name>   (e.g. smithslake0-6-bn24)"
HOST="${BIRDNETPI_HOST:-}"
[[ -n "$HOST" ]] || die "set BIRDNETPI_HOST=user@host (Tailscale address works from the work laptop)"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/recognizers"
DEST="${PI_MODEL_DIR:-~/birdnet-go-app/data/models}"

[[ -f "$SRC/$NAME.tflite" ]]      || die "no $SRC/$NAME.tflite (run tools/sync_recognizer.sh first)"
[[ -f "$SRC/${NAME}_Labels.txt" ]] || die "no ${NAME}_Labels.txt: a model cannot load without its labels"
[[ "$(stat -f %z "$SRC/$NAME.tflite")" -gt 1000000 ]] \
  || die "$NAME.tflite is tiny: not downloaded from OneDrive yet?"

ssh -o ConnectTimeout=8 "$HOST" "mkdir -p $DEST"
rsync -av --progress "$SRC/$NAME.tflite" "$SRC/${NAME}_Labels.txt" "$HOST:$DEST/"

cat <<EOF

copied to $HOST:$DEST. Now set in ~/birdnet-go-app/config/config.yaml
on the Pi (paths as the container sees them):

  birdnet:
    modelpath: /data/models/$NAME.tflite
    labelpath: /data/models/${NAME}_Labels.txt

then: sudo systemctl restart birdnet-go
Leave latitude/longitude unset with a custom model (see config.yaml).
NOTE: the stock model runs as ONNX on the Pi; confirm a .tflite loads
(check docker logs birdnet-go) before relying on it.
EOF
