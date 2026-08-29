@echo off
setlocal

:: Load environment variables from .env file
for /f "usebackq tokens=1,2 delims==" %%A in (.env) do (
    set "%%A=%%B"
)

if "%SCOPE_TIER%"=="" (
    echo FAIL: SCOPE_TIER not set
    exit /b 1
)

echo PASS: scope tier = %SCOPE_TIER%
endlocal
