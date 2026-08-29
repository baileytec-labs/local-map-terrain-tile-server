@echo off
echo === Imagery PBF storage ===
for %%F in (data\imagery\pbf\*.osm.pbf) do (
    for /f "tokens=1-2" %%A in ('dir "%%F" /-C ^| findstr /R "^[0-9]"') do (
        echo %%A %%B
    )
)
echo.
echo Total:
dir /s /b data\imagery\pbf\*.osm.pbf 2>nul | findstr /R "." | findstr /R /C:"[0-9]" | findstr /R /C:"[0-9]" | findstr /R /C:"[0-9]" >nul || echo No PBF files found.
for %%F in (data\imagery\pbf\*.osm.pbf) do (
    set size=0
    for /f "tokens=1-2" %%A in ('dir "%%F" /-C ^| findstr /R "^[0-9]"') do (
        set size=%%A
    )
    echo   %%~nxF: !size! bytes
)
