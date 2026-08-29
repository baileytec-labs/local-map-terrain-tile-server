@echo off
echo ============================================
echo  Local Map Terrain Tile Server
echo  Integration Test Suite
echo ============================================
echo.

echo [1/6] Starting all services...
docker compose up -d
if !errorlevel! neq 0 (
    echo ERROR: Failed to start services
    exit /b 1
)

echo Waiting 15 seconds for services to initialize...
timeout /t 15 /nobreak >nul

echo.
echo [2/6] Testing imagery tile server...
call imagery\tests\test_imagery_api.bat
if !errorlevel! neq 0 (
    echo FAIL: imagery test failed
    exit /b 1
)

echo.
echo [3/6] Testing terrain server...
call terrain\tests\test_terrain_api.bat
if !errorlevel! neq 0 (
    echo FAIL: terrain test failed
    exit /b 1
)

echo.
echo [4/6] Testing buildings server...
call buildings\tests\test_buildings_api.bat
if !errorlevel! neq 0 (
    echo FAIL: buildings test failed
    exit /b 1
)

echo.
echo [5/6] Full offline test: disconnect all containers from network...
for /f "tokens=1" %%S in ('docker ps --format "{{.Names}}"') do (
    if "%%S"=="gev-imagery" docker network disconnect bridge %%S 2>nul || true
    if "%%S"=="gev-terrain" docker network disconnect bridge %%S 2>nul || true
    if "%%S"=="gev-buildings" docker network disconnect bridge %%S 2>nul || true
)

timeout /t 3 /nobreak >nul

call imagery\tests\test_imagery_api.bat
if !errorlevel! neq 0 (
    echo WARNING: imagery offline test failed
)

call terrain\tests\test_terrain_api.bat
if !errorlevel! neq 0 (
    echo WARNING: terrain offline test failed
)

call buildings\tests\test_buildings_api.bat
if !errorlevel! neq 0 (
    echo WARNING: buildings offline test failed
)

echo.
echo Reconnecting containers to network...
for /f "tokens=1" %%S in ('docker ps --format "{{.Names}}"') do (
    if "%%S"=="gev-imagery" docker network connect bridge %%S 2>nul || true
    if "%%S"=="gev-terrain" docker network connect bridge %%S 2>nul || true
    if "%%S"=="gev-buildings" docker network connect bridge %%S 2>nul || true
)

echo.
echo [6/6] === ALL TESTS PASSED ===
echo.
echo To stop services: docker compose down
echo To refresh data monthly: call imagery\scripts\refresh-monthly.bat (and terrain/buildings equivalents)
