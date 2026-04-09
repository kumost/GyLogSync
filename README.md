# GyLogSync v3

macOS app for batch synchronization of GyroLogger GCSV data with video files, producing `.gyroflow` files automatically.

## Features

- Drag & drop videos and GCSV gyro logs
- Automatically slices master GCSV log to match each video's time range
- Optical flow synchronization (using gyroflow-core) to compute precise gyro-video offsets
- Exports `.gyroflow` files ready for use in DaVinci Resolve, Final Cut Pro, etc.
- Crash-safe subprocess isolation for videos with insufficient motion
- Timestamp-based fallback when optical flow fails
- Fully self-contained binary (no external dependencies required)

## Requirements

- macOS 13.0 or later (Apple Silicon)

## Building from Source

### Prerequisites

- Rust toolchain (`rustup`)
- Swift 5.7+
- OpenCV 4.x (`brew install opencv`)
- Homebrew

### Build Steps

```bash
# 1. Build the Rust bridge
cd rust-bridge
cargo build --release
cd ..

# 2. Copy the static library
mkdir -p lib
cp rust-bridge/target/release/libgylogsync_bridge.a lib/

# 3. Copy OpenCV static libraries
mkdir -p lib_static
for lib in core imgproc features2d flann calib3d video optflow ximgproc; do
    cp /opt/homebrew/opt/opencv/lib/libopencv_${lib}.a lib_static/
done
cp /opt/homebrew/opt/opencv/lib/libade.a lib_static/
cp /opt/homebrew/opt/opencv/lib/libittnotify.a lib_static/
cp /opt/homebrew/opt/opencv/lib/libtegra_hal.a lib_static/
cp /opt/homebrew/lib/libtbb.a lib_static/
for f in libkleidicv.a libkleidicv_hal.a libkleidicv_thread.a; do
    cp /opt/homebrew/opt/opencv/lib/$f lib_static/
done

# 4. Build Swift targets
swift build -c release --product GyLogSync
swift build -c release --product GyroflowSyncHelper
```

## Usage

1. Launch `GyLogSync`
2. Drag & drop a folder containing `.mov` videos and `.gcsv` gyro logs
3. Click **Sync**
4. `.gyroflow` files are generated next to each video

## License

This project is licensed under the **GNU General Public License v3.0** (GPL-3.0).

This project uses [gyroflow-core](https://github.com/gyroflow/gyroflow) which is licensed under GPL-3.0.

## Credits

- [Gyroflow](https://gyroflow.xyz/) — Core stabilization and synchronization engine
- [OpenCV](https://opencv.org/) — Computer vision (optical flow, essential matrix)
- [GyroLogger](https://kumoinc.com/gylog) — iOS gyro logging app by Kumo, Inc.
