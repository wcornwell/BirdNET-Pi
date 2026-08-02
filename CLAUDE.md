# BirdNET-Pi

Fork of [Nachtzuster/BirdNET-Pi](https://github.com/Nachtzuster/BirdNET-Pi). The code
here runs **on the Pi**, not on the laptop: continuous recording, on-device inference,
the web UI. The local checkout is an editing surface — deploy is push here, then
`git pull` on the device.

## Where this repo sits

One of the ecoacoustic repos in `~/Documents/ecoacoustics/`. **This repo owns field
deployment**: running a recognizer on the device and holding the deployed `.tflite` in
`recognizers/`. It does **not** own training, curation, or evaluation — it is a consumer
of recognizers, never a producer.

The invariant across those repos: *one library, two backbones; only caches and venvs
fork.* Only the BirdNET backbone's `.tflite` is deployable here — the Perch arm emits
`.npz`, which the Pi cannot load.

Who owns what across the eight repos, and the seams worth not crossing:
`../ECOACOUSTICS.md`. Do not copy its tables here; one copy stays true, N copies do not.

## Deploying a new recognizer

Models are trained elsewhere and land in the shared OneDrive `call_library/recognizers/`.
The Pi has no access to that, so the model is vendored into this repo and travels by git:

```bash
./tools/sync_recognizer.sh --list     # what's available, newest first
./tools/sync_recognizer.sh            # copy the newest, stage it
./tools/sync_recognizer.sh --name run0-2-bn
```

It copies `<name>.tflite`, `<name>_Labels.txt` and the provenance CSVs, skips files that
are already identical, and stages the rest. It never pushes. Then commit, push, and
`git pull` on the Pi.

**Copying a model in does not switch the running model.** `scripts/config.php` globs
`recognizers/*.tflite` to build the dropdown; the active one is the `MODEL` config value,
chosen in the web UI under Tools → Settings. A model needs its `_Labels.txt` beside it or
it will not load (`scripts/utils/helpers.py`, `scripts/utils/models.py`).

Each vendored model is ~37 MB and stays in git history permanently — see the open
question about pruning in `../ECOACOUSTICS.md`.
