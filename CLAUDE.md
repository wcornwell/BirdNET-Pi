# BirdNET-Go deployment

Field deployment repo for the Pi 5 running [BirdNET-Go](https://github.com/tphakala/birdnet-go).
This repo holds config templates, deploy scripts and the staged `.tflite` recognizers.
It contains no application code. The previous BirdNET-Pi fork (Nachtzuster/BirdNET-Pi,
deployed by `git pull` on the Pi) is on the **`birdnet-pi` branch**; its old
instructions, including "never re-clone on the Pi" and the history-rewrite warning, are
in that branch's `CLAUDE.md`.

Why the switch: the Pi's SD card died (2026-11) and was rebuilt with BirdNET-Go.

## Where this repo sits

One of the ecoacoustic repos in `~/Documents/ecoacoustics/`. **This repo owns field
deployment**: running a recognizer on the device. It does **not** own training,
curation, or evaluation; it is a consumer of recognizers, never a producer. Who owns
what across the sibling repos: `../ECOACOUSTICS.md` (list: `../repos.txt`). Do not copy
their tables here.

## Deploying a recognizer

Models are trained elsewhere and land in the shared OneDrive `call_library/recognizers/`.

```bash
./tools/sync_recognizer.sh --list          # what is available, newest first
./tools/sync_recognizer.sh                 # stage the newest into recognizers/
BIRDNETPI_HOST=wcornwell@<pi-tailscale-address> birdnet-go/deploy_model.sh <name>   # copy to the Pi
```

`deploy_model.sh` copies only, into `~/birdnet-go-app/data/models` on the Pi. Then set
`birdnet.modelpath` / `birdnet.labelpath` (as `/data/models/<name>.tflite`) in
`~/birdnet-go-app/config/config.yaml` and `sudo systemctl restart birdnet-go`. The stock
model runs as ONNX there, so confirm a `.tflite` loads (`docker logs birdnet-go`). A model needs its `_Labels.txt` beside it. The Pi is
reached over Tailscale (see `tailscale status`), not `.local`: the work laptop cannot
reach the home LAN.

Do not commit new `.tflite` files to `main` as a deploy mechanism; they are about 35 MB
each and every one stays in history. Deploy is scp/rsync, not `git pull`.

## What runs and what does not

- Custom BirdNET `*-bn24.tflite` / `*-bn.tflite` (fused 48 kHz / 3 s audio-to-logits):
  works, via `birdnet.modelpath` + `birdnet.labelpath`.
- Stock BirdNET+ 3.0 and stock Perch v2: work, as comparisons.
- Custom Perch heads (`*-ph.npz`) and `*-bn30.npz`: **cannot load.** See below.

### Why custom Perch heads cannot run (assessed 2026-08-31, re-check before reopening)

BirdNET-Go's Perch support is stock Perch v2 with the native 14,795-class head, the
configuration `soundscape-eval/CLAUDE.md` rejected ("can't be thresholded to a FP budget
and collapses to ~0 recall there"). Our `.npz` heads will not load:

- `Perch.Predict` reads the logits port and discards the 1536-d embedding port; no API,
  CLI or export exposes it.
- A custom-head slot exists (`internal/inference/onnx/custom_classifier.go`) but its only
  consumer is the bat pipeline, hardcoded to BirdNET v2.4's 1024-d embeddings at 48 kHz/3 s.
- The model registry is a compiled-in Go map; `model-catalog.json` cannot add architectures.

Escape hatch if Perch-at-the-edge is revisited: `perch_head/inference.py::Head` is a
two-layer MLP, so fusing it onto a converted Perch ONNX is graph surgery, not retraining.
Gated on whether ONNX embeddings match the TF2 SavedModel ones the head was trained on.
That is **producer** work for `perch-head`, never here.

### The one silent-corruption trap: range filter

BirdNET-Go's default range filter emits scores aligned to *stock* BirdNET 2.4's label
order and pairs them index-by-index with whatever label file you supply. Our label files
are shorter and ordered differently, so with latitude/longitude set, species filtering
goes wrong **with no error**. Leave coordinates unset for custom models, or use the v3
geomodel (`birdnet.rangefilter.model: "v3"` with `rangefilter.labelspath`), which matches
by scientific name. (The old BirdNET-Pi was immune because `get_meta_model()` returned
`None` for custom models.)

## State and backups

The BirdNET-Go config and detection database live on the Pi's card, nowhere else. The
previous card died with its `birds.db`. Back up the config and database off the device
regularly. Rebuild steps: `birdnet-go/SETUP.md`.
