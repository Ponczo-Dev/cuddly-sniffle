@echo off
rem ============================================================
rem  Uruchamia testy logiki gry przez zwykle lua.exe (bez grafiki).
rem  Polozenie lua.exe:
rem   - folder "lua" obok tego pliku (zalecane), albo
rem   - obok tego pliku, albo
rem   - wpisz pelna sciezke w linii LUA_CUSTOM ponizej.
rem ============================================================
setlocal
cd /d "%~dp0"

rem Wpisz tu sciezke, jesli lua.exe lezy gdzie indziej, np.
rem set "LUA_CUSTOM=C:\Users\Ja\Desktop\lua\lua.exe"
set "LUA_CUSTOM="

set "LUA_EXE="
if defined LUA_CUSTOM if exist "%LUA_CUSTOM%" set "LUA_EXE=%LUA_CUSTOM%"
for %%N in (lua.exe lua54.exe lua5.4.exe lua53.exe lua5.3.exe lua51.exe luajit.exe) do (
  if not defined LUA_EXE if exist "%~dp0lua\%%N" set "LUA_EXE=%~dp0lua\%%N"
  if not defined LUA_EXE if exist "%~dp0%%N" set "LUA_EXE=%~dp0%%N"
)
if not defined LUA_EXE (
  where lua.exe >nul 2>&1
  if not errorlevel 1 set "LUA_EXE=lua.exe"
)
if not defined LUA_EXE goto nolua

echo Lua: %LUA_EXE%
echo.
pushd "%~dp0game"
"%LUA_EXE%" tests\run_all.lua
set "RESULT=%errorlevel%"
popd

echo.
if "%RESULT%"=="0" echo Wszystkie testy przeszly.
if not "%RESULT%"=="0" echo Sa bledy w testach - skopiuj je i wklej do AI.
pause
exit /b %RESULT%

:nolua
echo.
echo [BLAD] Nie znaleziono lua.exe.
echo.
echo Co zrobic:
echo  1. Skopiuj swoj lua.exe do folderu "lua" obok test.bat
echo     jesli obok lua.exe lezy plik .dll, np. lua54.dll, skopiuj go tez
echo  2. albo wpisz pelna sciezke w linii LUA_CUSTOM w pliku test.bat
echo.
pause
exit /b 1
