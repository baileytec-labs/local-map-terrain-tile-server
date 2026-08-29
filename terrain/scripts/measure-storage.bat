@echo off
echo === Terrain storage ===
echo.
echo DEM tiles:
if exist data\terrain\dem\*.tif (
    dir /s /b data\terrain\dem\*.tif 2>nul | findstr /R "."
    for /f "delims=" %%F in ('dir /s /b data\terrain\dem\*.tif 2^>nul') do (
        echo   %%~nxF: %%~zF bytes
    )
) else (
    echo   No DEM tiles found.
)

echo.
echo Bathymetry:
if exist data\terrain\bathymetry\gebco_2026.tif (
    for /f "delims=" %%F in ('dir /s /b data\terrain\bathymetry\gebco_2026.tif 2^>nul') do (
        echo   gebco_2026.tif: %%~zF bytes
    )
) else (
    echo   No bathymetry found.
)

echo.
echo Mosaic COG:
if exist data\terrain\mosaic.cog.tif (
    for /f "delims=" %%F in ('dir /s /b data\terrain\mosaic.cog.tif 2^>nul') do (
        echo   mosaic.cog.tif: %%~zF bytes
    )
) else (
    echo   No mosaic found.
)
