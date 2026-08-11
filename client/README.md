# NexusRoom desktop client

This directory contains the Electron desktop client for NexusRoom.

Install dependencies and run the checks with:

```powershell
npm ci
npm run build
```

Create the Windows x64 ZIP release with:

```powershell
npm run package:win
```

The packaged application keeps its `data` directory beside `NexusRoom.exe`.
The WireGuard helper source and runtime files are under `native/wg-helper`.
