@echo off
echo === Imagery monthly refresh ===

echo [1/3] Fetching OSM extract...
call imagery\scripts\fetch-extract.bat
if %errorlevel% neq 0 (
    echo ERROR: fetch-extract failed
    exit /b 1
)

echo [2/3] Running tile server import...
docker compose run --rm gev-imagery import
if %errorlevel% neq 0 (
    echo ERROR: import failed
    exit /b 1
)

echo [3/3] Restarting imagery service...
docker compose restart gev-imagery
if %errorlevel% neq 0 (
    echo ERROR: restart failed
    exit /b 1
)

echo Monthly refresh complete.
