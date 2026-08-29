@echo off
setlocal

:: Load environment variables from .env file
for /f "usebackq tokens=1,2 delims==" %%A in (.env) do (
    set "%%A=%%B"
)

set "SCOPE_TIER=%SCOPE_TIER%"

if "%SCOPE_TIER%"=="dev" (
    set "PARENT_URL=https://download.geofabrik.de/north-america/us/texas-latest.osm.pbf"
    set "PBF_FILE=parent.osm.pbf"
) else if "%SCOPE_TIER%"=="regional" (
    set "PARENT_URL=%REGIONAL_EXTRACT_URL%"
    set "PBF_FILE=%REGIONAL_NAME%.osm.pbf"
) else (
    set "PARENT_URL=https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf"
    set "PBF_FILE=planet.osm.pbf"
)

mkdir data\imagery\pbf 2>nul

if "%SCOPE_TIER%"=="dev" (
    echo Downloading parent extract: %PARENT_URL%
    curl -L -o "data\imagery\pbf\%PBF_FILE%" "%PARENT_URL%"

    echo Extracting bounding box: %DEV_BBOX_MINLON%,%DEV_BBOX_MINLAT%,%DEV_BBOX_MAXLON%,%DEV_BBOX_MAXLAT%
    osmium extract -b "%DEV_BBOX_MINLON%,%DEV_BBOX_MINLAT%,%DEV_BBOX_MAXLON%,%DEV_BBOX_MAXLAT%" ^
        "data\imagery\pbf\%PBF_FILE%" ^
        -o "data\imagery\pbf\%DEV_BBOX_NAME%.osm.pbf" --overwrite
) else if "%SCOPE_TIER%"=="regional" (
    echo Downloading regional extract: %PARENT_URL%
    curl -L -o "data\imagery\pbf\%PBF_FILE%" "%PARENT_URL%"
) else (
    echo Downloading planet extract: %PARENT_URL%
    curl -L -o "data\imagery\pbf\%PBF_FILE%" "%PARENT_URL%"
)

echo Done. PBF file saved to data\imagery\pbf\
endlocal
