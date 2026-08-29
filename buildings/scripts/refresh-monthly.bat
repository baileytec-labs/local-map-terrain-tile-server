@echo off
echo === Buildings monthly refresh ===

echo [1/3] Fetching Overture Maps buildings...
call buildings\scripts\fetch-overture-buildings.bat
if !errorlevel! neq 0 (
    echo ERROR: fetch-overture-buildings failed
    exit /b 1
)

echo [2/3] Extruding to 3D Tiles...
call buildings\scripts\extrude-to-3dtiles.bat
if !errorlevel! neq 0 (
    echo ERROR: extrude-to-3dtiles failed
    exit /b 1
)

echo [3/3] Restarting buildings service...
docker compose restart gev-buildings
if !errorlevel! neq 0 (
    echo ERROR: restart failed
    exit /b 1
)

echo Monthly refresh complete.
