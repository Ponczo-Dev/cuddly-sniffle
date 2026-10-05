# Minecraft Lua (era Beta)

Klon Minecrafta w stylu Java Edition Beta 1.0–1.8, pisany w Lua na frameworku
[LÖVE 11.5](https://love2d.org). Działa na Windows 10 **bez uprawnień administratora**.
Plan projektu i zasady pracy z AI są w [`MASTER_PROMPT.md`](MASTER_PROMPT.md).

**Obecny etap: Faza 0 (setup) ukończona.**

## Instalacja (jednorazowo, bez admina)

1. Pobierz projekt: na GitHubie **Code → Download ZIP** i rozpakuj, np. na Pulpit.
2. **LÖVE:** ze strony [love2d.org](https://love2d.org) pobierz *64-bit zipped*
   (`love-11.5-win64.zip`). Rozpakuj jego zawartość do folderu `love\` w projekcie.
   Jeśli Windows blokuje pliki: prawy klik na ZIP → Właściwości → „Odblokuj” → OK,
   i dopiero wtedy rozpakuj.
3. **Lua do testów:** skopiuj swój `lua.exe` do folderu `lua\` w projekcie
   (razem z plikiem `.dll`, jeśli leży obok, np. `lua54.dll`).
   Możesz też wpisać ścieżkę do niego w linii `LUA_CUSTOM` w `test.bat`.

```
minecraft-lua\
  love\        <- love.exe + pliki .dll z ZIP-a LÖVE
  lua\         <- Twój lua.exe
  game\        <- kod gry
  run.bat      <- uruchamia grę
  test.bat     <- uruchamia testy
```

## Uruchamianie

| Plik | Co robi |
|---|---|
| `run.bat` | Uruchamia grę w LÖVE (z konsolą na komunikaty `print`). |
| `test.bat` | Uruchamia testy logiki gry przez `lua.exe`. Na końcu pokazuje `Wynik: X OK, 0 BLAD`. |

### Faza 0: co powinno być widać

- Niebieskie okno „MINECRAFT LUA - Faza 0” z obracającym się sześcianem.
- Informacje: wersja LÖVE (11.x), Lua (LuaJIT), karta graficzna, **Depth buffer: 24 bit**.
- Licznik ticków rośnie o 20 na sekundę. FPS w prawym górnym rogu.
- Klawisze: **ESC** wyjście, **F11** pełny ekran, **F3** pokaż/ukryj FPS.
- `test.bat` kończy się linią `Wynik: 23 OK, 0 BLAD`.

### Typowe problemy

| Objaw | Rozwiązanie |
|---|---|
| `run.bat`: „Nie znaleziono love.exe” | LÖVE nie jest rozpakowany do `love\`. Sprawdź, czy `love.exe` leży w `love\` albo w podfolderze. |
| `test.bat`: „Nie znaleziono lua.exe” | Skopiuj `lua.exe` do `lua\` albo uzupełnij `LUA_CUSTOM` w `test.bat`. |
| Brak pliku `lua54.dll` | Twój `lua.exe` potrzebuje biblioteki .dll. Skopiuj ją obok `lua.exe`. |
| Czerwony napis „brak depth buffera” | Zaktualizuj sterownik karty graficznej. Bez tego 3D z Fazy 1 nie zadziała. |
| Niebieski ekran błędu LÖVE | Skopiuj cały tekst błędu (Ctrl+C w oknie błędu) i wklej do AI. |
| Windows SmartScreen blokuje `love.exe` | „Więcej informacji” → „Uruchom mimo to” albo „Odblokuj” we Właściwościach ZIP-a. |

## Struktura kodu

```
game\
  conf.lua            konfiguracja okna LÖVE (depth buffer 24, vsync, konsola)
  main.lua            pętla gry: zegar 20 TPS + menedżer stanów + skróty F3/F11
  core\               czysta logika BEZ love.* (testowana przez lua.exe)
    strict.lua        błąd przy literówce w nazwie zmiennej globalnej
    bit.lua           operacje bitowe zgodne z LuaJIT i Lua 5.1–5.4
    util.lua          clamp, lerp, round, floorDiv...
    config.lua        wszystkie stałe (20 TPS, chunk 16x16x128, FOV...)
    clock.lua         stały krok czasowy (fixed timestep) + interpolacja
  states\
    manager.lua       przełączanie stanów gry
    boot.lua          ekran testowy Fazy 0
  tests\
    run_all.lua       uruchamia wszystkie testy
    testlib.lua       mini-framework asercji
    test_*.lua        testy modułów
```

Kod działa jednocześnie w LuaJIT (LÖVE) i w zwykłym Lua 5.1–5.4. Bez operatorów
bitowych `& | << >>`, bez `//`, bez `utf8`. Szczegóły w `MASTER_PROMPT.md`.
