@echo off
setlocal

:: Load environment variables from .env file
for /f "usebackq tokens=1,2 delims==" %%A in (.env) do (
    set "%%A=%%B"
)

set BASE=http://localhost:9877

echo Testing terrain layer.json and tile API...
echo.

:: Test layer.json
curl -s -o %TEMP%\layer.json -w "%%{http_code}" "%BASE%/tiles/gev-terrain/layer.json" > %TEMP%\status.txt
set /p STATUS=<%TEMP%\status.txt

if "%STATUS%"=="200" (
    echo PASS: layer.json served (HTTP 200)
) else (
    echo FAIL: layer.json HTTP status = %STATUS%
    exit /b 1
)

:: Test terrain tile
curl -s -o %TEMP%\tile.terrain -w "%%{http_code}" "%BASE%/tiles/gev-terrain/2/2/1.terrain" > %TEMP%\status.txt
set /p STATUS=<%TEMP%\status.txt

if "%STATUS%"=="200" (
    echo PASS: terrain tile served (HTTP 200)
) else (
    echo FAIL: terrain tile HTTP status = %STATUS%
    exit /b 1
)

:: Verify tile is non-trivial size
for %%F in (%TEMP%\tile.terrain) do (
    set size=%%~zF
    if !size! LSS 100 (
        echo FAIL: terrain tile suspiciously small (!size! bytes)
        exit /b 1
    )
    echo PASS: terrain tile size is !size! bytes (valid)
)

echo.
echo PASS: terrain API test complete
endlocal
