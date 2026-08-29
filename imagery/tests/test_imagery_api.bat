@echo off
setlocal

:: Load environment variables from .env file
for /f "usebackq tokens=1,2 delims==" %%A in (.env) do (
    set "%%A=%%B"
)

set BASE=http://localhost:8080

:: Compute tile coordinates for the dev bbox center
:: Center of Austin bbox: lon = (-97.85 + -97.55) / 2 = -97.7
:: Center of Austin bbox: lat = (30.10 + 30.45) / 2 = 30.275
set Z=12
set /a X=686
set Y=1655

echo Testing imagery tile at z=%Z% x=%X% y=%Y%...

curl -s -o %TEMP%\tile.png -w "%%{http_code}" "%BASE%/tile/%Z%/%X%/%Y%.png" > %TEMP%\status.txt
set /p STATUS=<%TEMP%\status.txt

if "%STATUS%"=="200" (
    echo PASS: imagery tile served (HTTP 200)
) else (
    echo FAIL: imagery tile HTTP status = %STATUS%
    exit /b 1
)

echo PASS: imagery tile API test complete
endlocal
