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
fork.* Only the BirdNET backbone's `.tflite` is deployable here. The Perch arm emits an
`.npz` classifier head, and no runtime we have found can serve it on the device — not
this stack, not birdnet-go. See "Frameworks evaluated" before assuming that has changed.

Who owns what across the sibling repos, and the seams worth not crossing:
`../ECOACOUSTICS.md` (the current list is `../repos.txt`). Do not copy their tables here;
one copy stays true, N copies do not.

## Deploying a new recognizer

Models are trained elsewhere and land in the shared OneDrive `call_library/recognizers/`.
The Pi has no access to that, so the model is vendored into this repo and travels by git:

```bash
./tools/sync_recognizer.sh --list     # what's available, newest first
./tools/sync_recognizer.sh            # copy the newest, stage it
./tools/sync_recognizer.sh --name <recognizer>
```

It copies `<name>.tflite`, `<name>_Labels.txt` and the provenance CSVs, skips files that
are already identical, and stages the rest. It never pushes. Then commit, push, and
`git pull` on the Pi.

**Copying a model in does not switch the running model.** `scripts/config.php` globs
`recognizers/*.tflite` to build the dropdown; the active one is the `MODEL` config value,
chosen in the web UI under Tools → Settings. A model needs its `_Labels.txt` beside it or
it will not load (`scripts/utils/helpers.py`, `scripts/utils/models.py`).

**`MODEL=` in `birdnet.conf` is the only source of truth for what is running.** Switching
models in the web UI writes that file and leaves no commit, so a deploy commit message
records *intent at deploy time*, not current state. Ask the device:

```bash
ssh wcornwell@100.77.3.46 'sed -n "s/^MODEL=//p" ~/BirdNET-Pi/birdnet.conf'
```

`recognizers/` keeps two models — current + rollback — and the sync prunes the rest.
Which two is a `git ls-files recognizers/` away; which of them is live is the command
above. Do not restate either here.

Two things that look wrong and are not, so nobody "fixes" them:

- `/etc/birdnet/birdnet.conf` is a **symlink** to `~/BirdNET-Pi/birdnet.conf` — the same
  file by two names. `tools/sync_recognizer.sh` reads the in-repo path, and its
  refuse-to-prune-the-active-model check works.
- Pruning `recognizers/` bounds the **checkout**, not the repository. See "Rewriting
  history" for what that costs and `tools/strip_old_recognizers.sh` for the fix.

## Never re-clone on the Pi

Irreplaceable state lives **inside** the repo directory on the device and is gitignored,
so it exists nowhere else:

- `scripts/birds.db` — the detection record, going back to the first deployment
- `birdnet.conf` — the live config, including `MODEL`
- `include_species_list.txt`, `exclude_species_list.txt`, `whitelist_species_list.txt`
- `templates/*.service` — the generated systemd units, symlinked into
  `/usr/lib/systemd/system`
- `birdnet/` — the venv
- `scripts/wikipedia.db`, `scripts/flickr.db` — image caches (rebuildable, unlike the rest)

`git status --porcelain --ignored` on the device lists the current set. A fresh clone
destroys all of it. If history is ever rewritten (below), recover **in place**, never by
re-cloning:

```bash
cd ~/BirdNET-Pi && git fetch origin && git reset --hard origin/main
```

Back up `scripts/birds.db` and `birdnet.conf` off-device before any such operation.

## Rewriting history here — read first

The old recognizers were stripped from history on 2026-08-02 (454 MB → 278 MB). If you
are ever tempted to do that again, know this: **`git filter-repo` rewrites every commit
SHA in this repo**, not only commits touching the paths you remove. A no-op run — removing
a path that exists nowhere — still produces a different root commit. Because this is a
fork, that severs SHA continuity with `upstream`, and `git merge upstream/main` starts
reporting "unrelated histories" with thousands of commits behind.

Verifying that the paths you strip are fork-only does **not** prevent this; the paths are
irrelevant to it. The repair, which costs nothing and changes no file:

```bash
git merge -s ours --allow-unrelated-histories upstream/main
```

That records upstream as merged with our tree untouched, and normal merges work again.
Commit `ccfba376` is exactly that repair. `filter-repo` also drops remotes, so `upstream`
must be re-added before the repair can run. Confirm ancestry survived with
`git rev-list --count main..upstream/main`, which should report `0`.

**Decision (2026-10-08): keep committing the `.tflite`, strip superseded ones periodically.**
Committing the model is how the newest recognizer reaches the Pi, so the growth is
accepted and bounded by a periodic strip instead. Every model ever committed stays in
history until stripped, because pruning `recognizers/` only changes the checkout — about
35 MB per deploy. The first strip (2026-08-02) was a one-off and the repo was back above
its pre-strip size within a month.

```bash
./tools/strip_old_recognizers.sh             # report: what goes, how much it saves
./tools/strip_old_recognizers.sh --execute   # rewrite history in this clone; never pushes
```

It keeps whatever is in `recognizers/` at HEAD and strips every other `recognizers/` path
from history, then does the `merge -s ours` repair above and checks
`main..upstream/main` is `0`. It writes a backup bundle first and prints the force-push and
Pi commands without running them. Tested on a clone: 824 MB → 344 MB, tree byte-identical.

Run it when `du -sh .git` passes ~600 MB, or after a batch of deploys. Finishing is
manual and ordered: back up `birds.db` and `birdnet.conf` off the Pi, `git push
--force-with-lease origin main`, then reset the Pi **in place** ("Never re-clone on the
Pi"). Anyone else with a clone must re-clone or reset too.

Do **not** strip the remaining bulk: `model/*.tflite` and the two `tflite_runtime` wheels
are upstream's files, and stripping upstream paths is precisely what severs ancestry. The
script only ever touches `recognizers/`.

## Frameworks evaluated

### birdnet-go — assessed 2026-08-31, not adopted

[tphakala/birdnet-go](https://github.com/tphakala/birdnet-go) was assessed because it
advertises Perch v2 on-device, which would have closed the gap
`soundscape-eval/CLAUDE.md` records as "a separate, deferred project".

**Verdict: migration is cheap, but it cannot run our Perch head.** Its Perch support is
stock Perch v2 with the native 14,795-class head — the exact configuration
`soundscape-eval/CLAUDE.md` already rejected as non-deployable, because that head "can't
be thresholded to a FP budget and collapses to ~0 recall there". Our `.npz` heads will not
load.

The blocker was architectural rather than a missing config, so re-check these three before
re-opening the question:

- `Perch.Predict` reads the logits output port and **discards the 1536-d embedding port**.
  No embedding is exposed by any API, CLI, or export.
- An embeddings-in / logits-out custom-head slot does exist
  (`internal/inference/onnx/custom_classifier.go`) and ships in production — but its only
  consumer is the **bat** pipeline, hardcoded to BirdNET v2.4's 1024-d embeddings at
  48 kHz/3 s.
- The model registry is a compiled-in Go map with fixed per-model input specs;
  `model-catalog.json` cannot introduce a new architecture.

What migration *would* buy, if the reason is ever something other than Perch: per-species
dynamic thresholds, high-overlap corroboration ("Deep Detection"), hot-reload config, a
range filter that works with custom labels, multi-model per audio source, and retirement
of this fork's maintenance burden. Our recognizers are fused 48 kHz/3 s audio→logits
graphs, which is exactly what its `birdnet.modelpath` slot expects — they would drop in
with two config lines.

**If we ever do migrate, the one silent-corruption trap:** birdnet-go's default range
filter emits scores positionally aligned to *stock* BirdNET v2.4's label order and pairs
them index-by-index against whatever label file you supply. Our label files are far
shorter and in a different order, so with lat/lon set, species filtering goes wrong with
no error. We are immune today only because `get_meta_model()` returns `None` for custom
models (`scripts/utils/models.py`) — the coordinates in `birdnet.conf` are inert here. The
fix would be unset coordinates, or the v3 geomodel
(`birdnet.rangefilter.model: "v3"` + `rangefilter.labelspath`), which matches by
scientific name.

**The escape hatch, if Perch-at-the-edge is revisited.** `perch_head/inference.py::Head`
is a two-layer MLP, so fusing it onto a converted Perch ONNX is graph surgery, not
retraining, and Perch is realtime-capable on a Pi 5. That would make Perch deployable
regardless of framework. It is gated on one unknown — whether ONNX-derived embeddings
match the Kaggle TF2 SavedModel ones the head was trained on — and it is **producer**
work: it belongs in `perch-head`, never here.
