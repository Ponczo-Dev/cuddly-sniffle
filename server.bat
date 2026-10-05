@echo off
rem ============================================================
rem  Serwer dedykowany Minecraft Lua (Windows), bez okna gry.
rem  Przyklad:  server.bat --world=serwer --port=25565
rem  Opcje: --world=Nazwa --port=25565 --seed=123 --mode=survival^|creative
rem         --difficulty=0-3 --max=8
rem  Komendy w tym oknie: help, list, say, kick, save, stop
rem ============================================================
setlocal
cd /d "%~dp0"

rem lovec.exe ma konsole, w ktorej da sie wpisywac komendy serwera
set "LOVE_EXE="
for /r "%~dp0love" %%F in (lovec.exe) do if not defined LOVE_EXE if exist "%%F" set "LOVE_EXE=%%F"
for /r "%~dp0love" %%F in (love.exe) do if not defined LOVE_EXE if exist "%%F" set "LOVE_EXE=%%F"
if not defined LOVE_EXE goto nolove

echo Uruchamiam serwer: %LOVE_EXE%
"%LOVE_EXE%" "%~dp0game" --server %*
pause
exit /b 0

:nolove
echo.
echo [BLAD] Nie znaleziono love.exe ani lovec.exe w folderze:
echo        %~dp0love
echo Rozpakuj tam love-11.5-win64.zip ze strony https://love2d.org
echo.
pause
exit /b 1
