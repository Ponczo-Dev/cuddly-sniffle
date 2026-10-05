@echo off
rem ============================================================
rem  Uruchamia gre Minecraft Lua w LOVE (wersja portable).
rem  LOVE musi byc rozpakowany do folderu "love" obok tego pliku.
rem  Nie wymaga uprawnien administratora.
rem ============================================================
setlocal
cd /d "%~dp0"

rem Szukamy lovec.exe (wersja z konsola) albo love.exe w folderze love
rem (takze w podfolderze, np. love\love-11.5-win64\love.exe).
set "LOVE_EXE="
for /r "%~dp0love" %%F in (lovec.exe) do if not defined LOVE_EXE if exist "%%F" set "LOVE_EXE=%%F"
for /r "%~dp0love" %%F in (love.exe) do if not defined LOVE_EXE if exist "%%F" set "LOVE_EXE=%%F"
if not defined LOVE_EXE goto nolove

echo Uruchamiam: %LOVE_EXE%
"%LOVE_EXE%" "%~dp0game"
if errorlevel 1 pause
exit /b 0

:nolove
echo.
echo [BLAD] Nie znaleziono love.exe w folderze:
echo        %~dp0love
echo.
echo Co zrobic:
echo  1. Wejdz na https://love2d.org i pobierz "64-bit zipped" dla Windows
echo     plik love-11.5-win64.zip
echo  2. Rozpakuj zawartosc ZIP-a do folderu "love" obok run.bat
echo  3. Uruchom run.bat ponownie
echo.
pause
exit /b 1
