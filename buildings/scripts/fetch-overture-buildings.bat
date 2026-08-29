@echo off
setlocal

:: Load environment variables from .env file
for /f "usebackq tokens=1,2 delims==" %%A in (.env) do (
    set "%%A=%%B"
)

:: ⚠ VERIFY the current release string at docs.overturemaps.org/getting-data/duckdb
:: before running — Overture's release path is a versioned date that changes monthly.
:: Format: YYYY-MM-DD.0 (e.g., 2026-01-01.0)
set RELEASE=2026-01-01.0

echo Downloading Overture Maps buildings for dev bbox...
echo Bbox: %DEV_BBOX_MINLON%,%DEV_BBOX_MINLAT%,%DEV_BBOX_MAXLON%,%DEV_BBOX_MAXLAT%
echo Release: %RELEASE%
echo.

mkdir data\buildings 2>nul

:: Query Overture Maps Parquet data via DuckDB, filter by bbox, export as GeoJSON
:: Uses DuckDB's range-request capability over HTTP — no full 176 GB download needed.
:: Height fallback: height if known, else num_floors * 3, else flat default of 6m.
duckdb -c "
INSTALL spatial;
INSTALL httpfs;
LOAD spatial;
LOAD httpfs;
SET s3_region='us-west-2';
COPY (
  SELECT id, height, num_floors, geometry
  FROM read_parquet('s3://overturemaps-us-west-2/release/%RELEASE%/theme=buildings/type=building/*', filename=true, hive_partitioning=1)
  WHERE bbox.xmin > %DEV_BBOX_MINLON% AND bbox.xmax < %DEV_BBOX_MAXLON%
    AND bbox.ymin > %DEV_BBOX_MINLAT% AND bbox.ymax < %DEV_BBOX_MAXLAT%
) TO 'data\buildings\overture_buildings.geojson' WITH (FORMAT GDAL, DRIVER 'GeoJSON');
"

if !errorlevel! neq 0 (
    echo ERROR: DuckDB query failed.
    echo Verify release string at docs.overturemaps.org/getting-data/duckdb
    exit /b 1
)

echo.
echo Overture buildings download complete.
echo Output: data\buildings\overture_buildings.geojson
endlocal
