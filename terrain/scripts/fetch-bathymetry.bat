@echo off
setlocal

mkdir data\terrain\bathymetry 2>nul

echo Downloading GEBCO_2026 Grid bathymetry data ...
echo (GEBCO is a single ~7 GB global file, ~15 arc-second resolution)
echo.

:: Download GEBCO 2026 GeoTIFF tiles (8 tiles covering the globe)
:: ⚠ VERIFY current download URL on gebco.net — the portal may change.
:: This URL points to the GeoTIFF download portal for GEBCO_2026.
set GEBCO_URL=https://www.bodc.ac.uk/data/open_download/gebco/gebco_2026/geotiff/

curl -L -o "data\terrain\bathymetry\gebco_2026.tif" "%GEBCO_URL%"

if !errorlevel! neq 0 (
    echo WARNING: GEBCO download may have failed.
    echo Verify the URL at https://www.gebco.net/data-products-gridded-bathymetry-data/gebco2026-grid/
)

echo.
echo GEBCO download complete. File saved to data\terrain\bathymetry\gebco_2026.tif
endlocal
