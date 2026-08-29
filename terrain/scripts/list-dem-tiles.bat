@echo off
setlocal

:: Load environment variables from .env file
for /f "usebackq tokens=1,2 delims==" %%A in (.env) do (
    set "%%A=%%B"
)

echo === Listing Copernicus DEM tiles in S3 bucket ===
echo (Showing first 20 entries for naming convention verification)
echo.
aws s3 ls s3://copernicus-dem-30m/ --no-sign-request | head -20
echo.
echo Pattern as of 2026: Copernicus_DSM_COG_10_^<N^|S^>^<lat^>_00_^<E^|W^>^<lon^>_00_DEM
echo.
echo === Computing DEM tiles covering dev bbox ===
echo Bbox: %DEV_BBOX_MINLON%,%DEV_BBOX_MINLAT%,%DEV_BBOX_MAXLON%,%DEV_BBOX_MAXLAT%
echo.
echo For dev Austin bbox, expected: 1 tile (Copernicus_DSM_COG_10_N30_W098_00_DEM)
echo.
echo To list actual matching tiles:
echo   aws s3 ls s3://copernicus-dem-30m/ --no-sign-request ^| findstr "COG_10_N30_W098"
echo.
echo Save matching tile names to data\terrain\dem_tiles.txt for fetch script.
endlocal
