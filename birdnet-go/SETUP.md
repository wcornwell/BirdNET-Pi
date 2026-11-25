# Rebuilding the BirdNET-Go Pi

Target: Raspberry Pi 5, USB microphone, high-endurance microSD (64 GB).

1. **Card.** Test a new card with F3 (`f3write` / `f3read` on a formatted volume)
   before trusting it. A card reporting a tiny wrong size, or running hot, is dead.
2. **Flash** Raspberry Pi OS Lite **64-bit** with Raspberry Pi Imager. Set hostname
   `birdnetpi1`, user `wcornwell`, your SSH public key, and the Wi-Fi network.
3. **Hardware.** Official 27 W (5 V / 5 A) supply and the Active Cooler.
4. **Tailscale** (the work laptop cannot reach the home LAN, only the tailnet):
   `curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up`
5. **BirdNET-Go.** Run the install script from the project README
   (https://github.com/tphakala/birdnet-go). Choose the USB mic, language, and a
   web password. Leave latitude/longitude unset while using a custom model.
6. **Config.** Merge the keys in `config.yaml` into the generated config. Record
   the real config path here once known: `TODO`.
7. **Model.** `tools/sync_recognizer.sh`, then
   `BIRDNETPI_HOST=wcornwell@<tailscale-ip> birdnet-go/deploy_model.sh <name>`.
8. **Retention.** Set a clip retention policy (by age or free space) so the card
   does not fill.

Back up the BirdNET-Go config and database off the device regularly. The previous
BirdNET-Pi card died with its detection database on it.

Verify: dashboard at `http://<host>:8080` shows detections; container logs show
the model loaded; CPU under ~70% sustained and temperature under ~75 °C.
