@echo off
setlocal

echo === Building elevation mosaic (GEBCO bathymetry + Copernicus DEM) ===
echo.

:: Ensure input files exist
if not exist data\terrain\bathymetry\gebco_2026.tif (
    echo ERROR: data\terrain\bathymetry\gebco_2026.tif not found.
    echo Run fetch-bathymetry.bat first.
    exit /b 1
)

if not exist data\terrain\dem\*.tif (
    echo ERROR: No DEM tiles found in data\terrain\dem\
    echo Run fetch-dem.bat first.
    exit /b 1
)

:: Step 1: Build VRT with bathymetry as base, DEM layered on top
:: NODATA=0 for GEBCO (0 means sea surface, DEM nodata shows bathymetry through)
echo [1/3] Building VRT mosaic...
gdalbuildvrt -srcnodata 0 data\terrain\mosaic.vrt ^
    data\terrain\bathymetry\gebco_2026.tif ^
    data\terrain\dem\*.tif

if !errorlevel! neq 0 (
    echo ERROR: gdalbuildvrt failed.
    exit /b 1
)

:: Step 2: Convert to Cloud-Optimized GeoTIFF (COG) for CTOD compatibility
:: ⚠ VERIFY: CTOD must support .vrt input, or this COG conversion is required.
echo [2/3] Converting to Cloud-Optimized GeoTIFF (COG)...
gdal_translate -of COG -co COMPRESS=DEFLATE data\terrain\mosaic.vrt data\terrain\mosaic.cog.tif

if !errorlevel! neq 0 (
    echo ERROR: gdal_translate failed.
    exit /b 1
)

:: Step 3: Verify COG structure
echo [3/3] Verifying COG structure...
gdalinfo -stats data\terrain\mosaic.cog.tif | findstr /I "LAYOUT=COG"
if !errorlevel! equ 0 (
    echo PASS: mosaic.cog.tif has valid COG layout.
) else (
    echo WARNING: mosaic.cog.tif may not have COG layout.
    echo Try re-running with: gdal_translate -of COG -co COMPRESS=DEFLATE data\terrain\mosaic.vrt data\terrain\mosaic.cog.tif
)

echo.
echo Mosaic build complete. Output: data\terrain\mosaic.cog.tif
endlocal
