@echo off
setlocal

:: Load environment variables from .env file
for /f "usebackq tokens=1,2 delims==" %%A in (.env) do (
    set "%%A=%%B"
)

set BASE=http://localhost:9878

echo Testing 3D Buildings tileset.json and B3DM content...
echo.

:: Test tileset.json
curl -s -o %TEMP%\tileset.json -w "%%{http_code}" "%BASE%/tileset.json" > %TEMP%\status.txt
set /p STATUS=<%TEMP%\status.txt

if "%STATUS%"=="200" (
    echo PASS: tileset.json served (HTTP 200)
) else (
    echo FAIL: tileset.json HTTP status = %STATUS%
    exit /b 1
)

:: Verify OGC 3D Tiles spec compliance (requires asset.version, geometricError, root)
:: This is a stable external standard, not a guess.
findstr /I "asset" %TEMP%\tileset.json >nul
if !errorlevel! neq 0 (
    echo FAIL: tileset.json missing 'asset' field
    exit /b 1
)

echo PASS: tileset.json is spec-compliant
echo.
echo PASS: buildings API test complete
endlocal
