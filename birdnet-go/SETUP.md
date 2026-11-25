# Rebuilding the BirdNET-Go Pi

Target: Raspberry Pi 5, USB microphone, high-endurance microSD (64 GB).

1. **Card.** Test a new card with F3 (`f3write` / `f3read` on a formatted volume)
   before trusting it. A card reporting a tiny wrong size, or running hot, is dead.
2. **Flash** Raspberry Pi OS Lite **64-bit** with Raspberry Pi Imager. Set hostname
   `birdnetpi1`, user `wcornwell`, your SSH public key, and the Wi-Fi network.
3. **Hardware.** Official 27 W (5 V / 5 A) supply and the Active Cooler.
4. **Tailscale** (the work laptop cannot reach the home LAN, only the tailnet):
   `curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up`
5. **BirdNET-Go.** Download `install.sh` from the project
   (https://github.com/tphakala/birdnet-go), read it, copy it to the Pi and run it.
   Non-interactive: `BIRDNET_LATITUDE=.. BIRDNET_LONGITUDE=.. BIRDNET_LOCALE=en-uk
   BIRDNET_AUDIO_FORMAT=flac BIRDNET_TELEMETRY=false bash install.sh --silent`
   (`en-uk` or `en-us` only; the default clip format is lossy `aac`).
   The first run installs Docker, adds you to the `docker` group and exits asking
   for a fresh login: start a **new SSH session and run it again**.
   Leave latitude/longitude unset while using a custom model.
6. **Config.** The generated config is `~/birdnet-go-app/config/config.yaml`
   (data in `~/birdnet-go-app/data`, models in `data/models`). Merge the keys in
   `config.yaml` here into it. The installer's silent mode cannot select a local
   sound card, so set the audio source by hand (`device: "Yeti Nano, USB Audio"`)
   and restart: `sudo systemctl restart birdnet-go`.
7. **Model.** `tools/sync_recognizer.sh`, then
   `BIRDNETPI_HOST=wcornwell@<tailscale-ip> birdnet-go/deploy_model.sh <name>`.
8. **Retention.** Set a clip retention policy (by age or free space) so the card
   does not fill.

Back up the BirdNET-Go config and database off the device regularly. The previous
BirdNET-Pi card died with its detection database on it.

**No sound / no spectrogram while the service is healthy?** Check the Yeti Nano's
physical mute button first. Muted, it sends all-zero samples while ALSA still
reports capture as running.

Verify: dashboard at `http://<host>:8080` shows detections; container logs show
the model loaded; CPU under ~70% sustained and temperature under ~75 °C.
