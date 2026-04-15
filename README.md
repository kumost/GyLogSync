# GyLogSync

Batch tool for iPhone ProRes RAW stabilization workflow with [GyLog](https://apps.apple.com/app/gylog/id6502541443) gyro data.

## Downloads

- **[GyLogSync v3.2](https://github.com/kumost/GyLogSync/releases/tag/v3.2)** — Recommended. Requires [Gyroflow Desktop](https://gyroflow.xyz/) for sync.
- **[GyLogSync Direct (β)](https://github.com/kumost/GyLogSync/releases/tag/v3.2-direct)** — Beta. Gyroflow Desktop not required, but sync accuracy may vary.

## GyLogSync v3.2

- ProRes RAW timing fix (VFR → CFR)
- Log splitting — splits one .gcsv session into per-clip .gcsv files
- Audio trimming — trims audio recording to match each video clip

Source code: [`v3.2/`](v3.2/)

## GyLogSync Direct (β)

All v3.2 features plus:
- Automatic .gyroflow file generation (no Gyroflow Desktop needed)

Source code: [`direct/`](direct/)

## Workflow

### v3.2 (Recommended)
1. Record ProRes RAW video + gyro data (.gcsv) with GyLog iOS app
2. Drop files into GyLogSync → fixes timing + outputs per-clip .gcsv + trimmed audio
3. Open the .mov and .gcsv in **Gyroflow Desktop** for sync and stabilization
4. Load the .gyroflow file into DaVinci Resolve via Gyroflow OFX plugin

### Direct (β)
1. Record ProRes RAW video + gyro data (.gcsv) with GyLog iOS app
2. Drop files into GyLogSync Direct → fixes timing + outputs .gcsv + .gyroflow + trimmed audio
3. Load the .gyroflow file directly into DaVinci Resolve via Gyroflow OFX plugin

## Requirements

- macOS 12 Monterey or later
- Blackmagic Camera app (recommended: set Reference Source to **Internal**)

## License

GPL v3.0 — See [LICENSE](LICENSE)
