# BirdNET-Go deployment (Raspberry Pi 5)

Field deployment for the ecoacoustics recognizers: a Pi 5 running
[BirdNET-Go](https://github.com/tphakala/birdnet-go) with our custom BirdNET
`.tflite` recognizers.

- `birdnet-go/`: config template, rebuild steps (`SETUP.md`), model deploy script
- `recognizers/`: staged recognizers (`.tflite` + `_Labels.txt` + provenance CSVs)
- `tools/sync_recognizer.sh`: copy a recognizer from the OneDrive `call_library`

The previous BirdNET-Pi setup (a fork of Nachtzuster/BirdNET-Pi, deployed by
`git pull` on the Pi) is preserved on the `birdnet-pi` branch.
