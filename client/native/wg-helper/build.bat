@echo off
REM Build nexusroom-wg.exe with embedded UAC manifest
REM Requires: Go 1.22+, go-winres (go install github.com/tc-hib/go-winres@latest)

cd /d "%~dp0"

echo [1/3] Generating Windows resource (UAC manifest)...
go-winres make

echo [2/3] Building nexusroom-wg.exe...
set CGO_ENABLED=0
set GOOS=windows
set GOARCH=amd64
go build -ldflags="-s -w" -o nexusroom-wg.exe .

if errorlevel 1 (
    echo Build FAILED
    exit /b 1
)

echo [3/3] Done! Output: nexusroom-wg.exe
echo.
echo Copy nexusroom-wg.exe and wintun.dll to the Flutter build output directory.
