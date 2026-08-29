@echo off
echo === Buildings storage ===
if exist data\buildings\overture_buildings.geojson (
    for /f "delims=" %%F in ('dir /s /b data\buildings\overture_buildings.geojson 2^>nul') do (
        echo overture_buildings.geojson: %%~zF bytes
    )
) else (
    echo overture_buildings.geojson: not found
)

if exist data\buildings\tileset (
    echo.
    echo 3D Tiles output:
    dir /s /b data\buildings\tileset\ 2>nul | findstr /R "."
    for /f "delims=" %%F in ('dir /s /b data\buildings\tileset\* 2^>nul') do (
        echo   %%~nxF: %%~zF bytes
    )
) else (
    echo.
    echo 3D Tiles output: not generated yet
)
