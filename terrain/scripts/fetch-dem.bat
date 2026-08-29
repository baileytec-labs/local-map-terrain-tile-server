@echo off
setlocal

:: Load environment variables from .env file
for /f "usebackq tokens=1,2 delims==" %%A in (.env) do (
    set "%%A=%%B"
)

mkdir data\terrain\dem 2>nul

if not exist data\terrain\dem_tiles.txt (
    echo WARNING: data\terrain\dem_tiles.txt not found.
    echo Run list-dem-tiles.bat first to generate the tile list.
    echo Falling back to known Austin tile: Copernicus_DSM_COG_10_N30_W098_00_DEM
    echo Copernicus_DSM_COG_10_N30_W098_00_DEM > data\terrain\dem_tiles.txt
)

echo Downloading DEM tiles from Copernicus DEM GLO-30 (s3://copernicus-dem-30m/) ...
echo.

for /f "usebackq delims=" %%T in (data\terrain\dem_tiles.txt) do (
    echo Downloading: %%T
    aws s3 cp --no-sign-request "s3://copernicus-dem-30m/%%T/%%T.tif" "data\terrain\dem\%%T.tif"
    if !errorlevel! neq 0 (
        echo ERROR: Failed to download %%T
    )
)

echo.
echo DEM download complete. Files saved to data\terrain\dem\
endlocal
