# Minecraft Lua (era Beta)

Klon Minecrafta w stylu Java Edition Beta 1.0–1.8, napisany w Lua na frameworku
[LÖVE 11.5](https://love2d.org). Działa na Windows 10 **bez uprawnień administratora**.
Wszystkie tekstury, modele i dźwięki są generowane w kodzie, więc nie potrzeba żadnych plików graficznych.
Plan projektu i zasady pracy z AI są w [`MASTER_PROMPT.md`](MASTER_PROMPT.md).

**Stan: fazy 0–10 z planu ukończone + rozszerzenia: redstone i tłoki, tory i wagoniki, łódki, płotki, Nether z portalem, opuszczone kopalnie i wioski.**

## Instalacja (jednorazowo, bez admina)

1. Pobierz projekt: na GitHubie **Code → Download ZIP** i rozpakuj, np. na Pulpit.
2. **LÖVE:** ze strony [love2d.org](https://love2d.org) pobierz *64-bit zipped*
   (`love-11.5-win64.zip`). Rozpakuj jego zawartość do folderu `love\` w projekcie.
   Jeśli Windows blokuje pliki: prawy klik na ZIP → Właściwości → „Odblokuj” → OK,
   i dopiero wtedy rozpakuj.
3. **Lua do testów (opcjonalnie):** skopiuj swój `lua.exe` do folderu `lua\`
   (razem z plikiem `.dll`, jeśli leży obok). Możesz też wpisać ścieżkę w `LUA_CUSTOM` w `test.bat`.

```
minecraft-lua\
  love\        <- love.exe + pliki .dll z ZIP-a LÖVE
  lua\         <- Twój lua.exe (tylko do testów)
  game\        <- kod gry
  run.bat      <- uruchamia grę
  test.bat     <- uruchamia testy logiki
```

Zapisy światów i ustawienia trafiają do `%APPDATA%\LOVE\minecraft-lua\`.

## Sterowanie

| Klawisz | Akcja |
|---|---|
| W A S D | ruch |
| Mysz | rozglądanie się |
| Spacja | skok / pływanie w górę. Podwójne wciśnięcie w trybie kreatywnym: latanie |
| Shift | kucanie (nie spadasz z krawędzi), w locie w dół |
| Ctrl + W albo podwójne W | sprint (zużywa głód) |
| LPM | kopanie / atak |
| PPM | stawianie bloku, używanie (drzwi, skrzynia, piec, stół, łóżko), jedzenie, łuk, blokowanie mieczem |
| ŚPM | wybór wskazanego bloku (w kreatywnym daje stos) |
| 1–9, kółko myszy | wybór slotu na pasku |
| E | ekwipunek (w kreatywnym: wszystkie bloki) |
| Q / Ctrl+Q | wyrzuć 1 / cały stos |
| T albo / | czat i komendy |
| Esc | pauza (opcje, zapis i wyjście) |
| F1 | ukryj HUD |
| F2 | zrzut ekranu (do folderu zapisu) |
| F3 | ekran debugowania (pozycja, biom, światło, FPS) |
| F5 | widok z trzeciej osoby |
| F11 | pełny ekran |

W oknach ekwipunku działają: LPM (cały stos), PPM (połowa albo po 1), Shift+klik (szybkie przeniesienie),
przeciąganie ze stosem (rozłożenie po slotach), Q nad slotem (wyrzuć), 1–9 nad slotem (zamiana z paskiem).

## Co jest w grze

- **Świat:** nieskończony teren z ziarna (seed). Biomy: równiny, las, pustynia, tajga, tundra, bagno,
  góry, ocean, plaża. Do tego jaskinie, wąwozy, jeziora lawy na dnie, rudy na właściwych wysokościach,
  drzewa (dąb, brzoza, świerk), trawa, kwiaty, kaktusy, trzcina, dynie, glina oraz lochy ze spawnerem i skrzyniami.
- **Światło:** światło nieba i bloków (0–15), płynne cieniowanie, ambient occlusion,
  cykl dnia i nocy (20 minut), wschody i zachody słońca, słońce, księżyc, gwiazdy, chmury.
- **Pogoda:** deszcz, śnieg w zimnych biomach (pokrywa śniegu, zamarzanie wody), burze z piorunami.
- **Przetrwanie (Beta 1.8):** 20 punktów zdrowia, głód z nasyceniem i zmęczeniem, regeneracja,
  obrażenia od upadku, tonięcia, lawy, ognia, kaktusa i próżni. Pancerz (skóra, żelazo, złoto, diament),
  doświadczenie z kulek, śmierć z wypadaniem przedmiotów i odrodzenie (także w łóżku).
- **Walka:** ciosy krytyczne w locie, blokowanie mieczem, łuk ładowany przytrzymaniem, odrzut.
- **Moby:** świnia, krowa (dojenie), owca (strzyżenie, kolory), kurczak (jajka), wilk (oswajanie kością),
  zombie, szkielet z łukiem, pająk, creeper (wybucha, piorun go ładuje) i enderman (teleport,
  nie patrz mu w oczy). Rozmnażanie zwierząt, spawn potworów w ciemności, palenie się w słońcu.
- **Ekwipunek:** 36 slotów + 4 sloty pancerza, crafting 2×2 i 3×3 (ponad 100 receptur),
  piec z paliwem, skrzynie pojedyncze i podwójne.
- **Bloki i mechaniki:** woda i lawa płyną (źródła, obsydian, bruk), piasek i żwir spadają, liście opadają,
  pszenica rośnie na nawodnionym polu, mączka kostna, sadzonki wyrastają w drzewa, TNT,
  krzesiwo i ogień, drzwi, łóżko, drabiny, pochodnie, wiadra.
- **Tryby:** przetrwanie, kreatywny (latanie, wszystkie bloki), hardcore.
- **Menu:** lista światów, tworzenie świata (nazwa, ziarno, tryb), usuwanie, opcje (zasięg widzenia,
  pole widzenia, czułość, głośność, skala GUI, trudność), autozapis co minutę.
- **Redstone (Beta 1.7):** przewód (moc 0–15), pochodnia redstone (negacja), dźwignia, przycisk,
  płyta naciskowa, przekaźnik (opóźnienie 1–4, PPM zmienia), lampa. Sterowane mechanizmy: drzwi, TNT,
  tłok i lepki tłok (pcha do 12 bloków).
- **Transport:** tory (łączą się same, zakręty, wzniesienia), tory zasilane i z czujnikiem, wagonik
  (PPM wsiadasz, W popychasz, shift wysiadasz), łódka (W/S/A/D na wodzie).
- **Nether:** portal z obsydianu (rama 4×5, wnętrze 2×3) zapalany krzesiwem. Po drugiej stronie
  netherrack, morze lawy, jasnogłaz, piasek dusz, ghasty z kulami ognia i zombie pigmeni.
  1 blok w Netherze = 8 bloków w świecie.
- **Struktury:** lochy ze spawnerem, opuszczone kopalnie (korytarze, podpory, tory, pajęczyny, skrzynie),
  wioski (puste jak w Beta 1.8: studnia, drogi, domy, kuźnia ze skrzynią, pola, biblioteka, wieża).
  Komenda `/locate village` albo `/locate mineshaft` pokazuje najbliższą.
- **Dźwięki:** kopanie i kroki zależne od materiału, głosy mobów, wybuchy, deszcz. Wszystkie wygenerowane w kodzie.

## Komendy czatu

`/help`, `/time set day|night|<liczba>`, `/gamemode survival|creative`, `/give <nazwa|id> [ilość]`,
`/tp <x> <y> <z>`, `/weather clear|rain|thunder`, `/summon <mob>`, `/difficulty 0-3`,
`/xp <ilość>`, `/locate village|mineshaft`, `/seed`, `/kill`, `/heal`, `/clear`, `/spawnpoint`.

Przykład: `/give diamond_pickaxe`, `/give torch 64`, `/summon creeper`, `/give piston 4`, `/give rail 64`, `/give obsidian 10`, `/give flint_and_steel`.

## Parametry uruchomienia (do testów)

W `run.bat` można dopisać parametry po `"%~dp0game"`:

| Parametr | Działanie |
|---|---|
| `--play` | od razu tymczasowy świat w trybie przetrwania (bez zapisu) |
| `--creative` | to samo w trybie kreatywnym |
| `--seed=123` | ziarno dla `--play` / `--creative` |
| `--boot` | ekran testowy z Fazy 0 |

## Typowe problemy

| Objaw | Rozwiązanie |
|---|---|
| `run.bat`: „Nie znaleziono love.exe” | LÖVE nie jest rozpakowany do `love\`. Sprawdź, czy `love.exe` leży w `love\` albo w podfolderze. |
| `test.bat`: „Nie znaleziono lua.exe” | Skopiuj `lua.exe` do `lua\` albo uzupełnij `LUA_CUSTOM` w `test.bat`. |
| Niskie FPS | Esc → Opcje → zmniejsz „Zasięg widzenia” (np. do 4) i wyłącz chmury. |
| Niebieski ekran błędu LÖVE | Skopiuj cały tekst błędu (Ctrl+C w oknie błędu) i wklej do AI. |
| Windows SmartScreen blokuje `love.exe` | „Więcej informacji” → „Uruchom mimo to” albo „Odblokuj” we Właściwościach ZIP-a. |

## Struktura kodu

```
game\
  conf.lua, main.lua     okno LÖVE, pętla 20 TPS, menedżer stanów
  core\                  czysta logika BEZ love.* (testowana przez lua.exe)
    game.lua             sesja gry: tick, kopanie, stawianie, przedmioty, pogoda, sen
    world.lua chunk.lua  świat i chunki 16x128x16 (tablice bajtów, FFI w LuaJIT)
    worldgen.lua noise.lua trees.lua   generator świata
    lighting.lua         światło nieba i bloków (BFS)
    mesher.lua           bloki -> trójkąty (culling, AO, płynne światło)
    blocks.lua items.lua recipes.lua   rejestry bloków, przedmiotów i receptur
    blocklogic.lua       zachowania bloków (ciecze, rośliny, drzwi, łóżka...)
    redstone.lua rails.lua vehicles.lua   redstone i tłoki, tory, wagonik i łódka
    nethergen.lua portal.lua structures.lua   Nether, portal, kopalnie i wioski
    player.lua physics.lua raycast.lua   ruch i kolizje
    survival.lua mobs.lua entities.lua   zdrowie/głód, moby, byty, wybuchy
    inventory.lua container.lua furnace.lua   ekwipunek i okna
    save.lua fs.lua serialize.lua options.lua commands.lua
    mat4.lua frustum.lua rng.lua bit.lua bytearray.lua util.lua clock.lua strict.lua
  render\                grafika i dźwięk (love.*)
    chunkrenderer.lua shader.lua camera.lua atlas.lua texturegen.lua
    models.lua icons.lua itemart.lua sky.lua particles.lua weather.lua
    hud.lua gui.lua sound.lua
  ui\                    okna: ekwipunek, kreatywny, pauza, opcje, śmierć, czat
  states\                menu, ładowanie, gra (+ ekran testowy Fazy 0)
  tests\                 testy logiki (test.bat)
```

Kod działa jednocześnie w LuaJIT (LÖVE) i w zwykłym Lua 5.1–5.4. Testy (`test.bat`) sprawdzają
między innymi crafting, ekwipunek, piec, kopanie, fizykę, głód, światło, ciecze, moby i zapis chunków.
