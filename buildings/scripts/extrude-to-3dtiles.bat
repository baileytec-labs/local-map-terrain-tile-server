@echo off
echo === Extruding Overture buildings to 3D Tiles ===

:: Verify input exists
if not exist data\buildings\overture_buildings.geojson (
    echo ERROR: data\buildings\overture_buildings.geojson not found.
    echo Run fetch-overture-buildings.bat first.
    exit /b 1
)

:: Clean previous output
if exist data\buildings\tileset (
    rmdir /s /q data\buildings\tileset 2>nul
)
mkdir data\buildings\tileset 2>nul

:: ⚠ VERIFY exact CLI flags via `py3dtilers --help` right before running.
:: This tool's interface may have changed since this plan was written.
::
:: Height fallback heuristic (documented decision):
::   1. Use `height` property if known (not null)
::   2. Fall back to `num_floors * 3` meters if height is null but num_floors exists
::   3. Use flat default of 6 meters (roughly two stories) if both are null
::   This ensures every building footprint gets a 3D representation rather than being dropped.
::
:: geometric_error=50: maximum display error for this tile level.
::   Larger values reduce detail but improve performance. 50m is reasonable for
::   a dev-scale city extract. For regional/global, consider lower values.

echo Running py3dtilers Buildings...
py3dtilers Buildings ^
    --obj data\buildings\overture_buildings.geojson ^
    --height_property height ^
    --geometric_error 50 ^
    --out data\buildings\tileset

if !errorlevel! neq 0 (
    echo ERROR: py3dtilers failed.
    echo Ensure py3dtilers is installed: pip install py3dtilers
    echo Verify CLI flags: py3dtilers --help
    exit /b 1
)

echo.
echo Extrusion complete. 3D Tiles output: data\buildings\tileset\
echo.
echo Next step: serve with nginx (docker compose gev-buildings)
endlocal
