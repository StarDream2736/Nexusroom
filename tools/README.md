# FFmpeg Binary

Place `ffmpeg.exe` in this directory for the screen capture streaming feature.

## Download

Download a **static build** (no DLL dependencies) from one of these sources:

- **Recommended**: https://www.gyan.dev/ffmpeg/builds/
  - Download the "essentials" build (`ffmpeg-release-essentials.zip`)
  - Extract `ffmpeg.exe` from the `bin/` folder into this directory

- Alternative: https://github.com/BtbN/FFmpeg-Builds/releases
  - Download `ffmpeg-master-latest-win64-gpl.zip`
  - Extract `ffmpeg.exe` from the `bin/` folder

## Minimal Build

For a smaller binary (~30MB instead of ~80MB), you can build FFmpeg from source
with only the required components:

```bash
./configure \
  --enable-gpl \
  --enable-libx264 \
  --enable-nvenc \
  --disable-doc \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-network \
  --enable-protocol=file \
  --enable-protocol=pipe
```

## Verification

After placing `ffmpeg.exe` here, rebuild the Flutter app. CMake will
automatically bundle it alongside `Nexusroom.exe`.

```powershell
# Verify the binary works:
.\ffmpeg.exe -version
```
