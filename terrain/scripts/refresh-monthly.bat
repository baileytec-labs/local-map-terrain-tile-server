@echo off
echo === Terrain monthly refresh ===

echo [1/4] Fetching Copernicus DEM tiles...
call terrain\scripts\fetch-dem.bat
if !errorlevel! neq 0 (
    echo ERROR: fetch-dem failed
    exit /b 1
)

echo [2/4] Fetching GEBCO bathymetry...
call terrain\scripts\fetch-bathymetry.bat
if !errorlevel! neq 0 (
    echo ERROR: fetch-bathymetry failed
    exit /b 1
)

echo [3/4] Building elevation mosaic...
call terrain\scripts\build-mosaic.bat
if !errorlevel! neq 0 (
    echo ERROR: build-mosaic failed
    exit /b 1
)

echo [4/4] Restarting terrain service...
docker compose restart gev-terrain
if !errorlevel! neq 0 (
    echo ERROR: restart failed
    exit /b 1
)

echo Monthly refresh complete.
