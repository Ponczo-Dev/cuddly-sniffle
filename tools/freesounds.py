#!/usr/bin/env python3
"""Buduje game/freesounds/ z darmowych dźwięków i muzyki VoxeLibre.

Użycie: python3 tools/freesounds.py <ścieżka do klonu VoxeLibre>
(https://codeberg.org/mineclonia... / https://github.com/VoxeLibre/VoxeLibre)

Pliki dostają nazwy jak w Minecrafcie (dig/grass1.ogg, mob/zombie/say1.ogg),
dzięki czemu gra używa ich tak samo jak dźwięków z instalacji Minecrafta.
"""
import os
import shutil
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "VoxeLibre"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "freesounds")

SND = "mods/CORE/mcl_sounds/sounds/"
MOB = "mods/ENTITIES/mobs_mc/sounds/"
MUS = "mods/PLAYER/mcl_music/sounds/"

def v(base, n):
    """Warianty base.1.ogg ... base.n.ogg"""
    return [f"{base}.{i}.ogg" for i in range(1, n + 1)]

# grupa (bez numeru i rozszerzenia) -> lista plików źródłowych
MAP = {
    # kopanie i stawianie
    "dig/stone": [SND + f for f in v("default_place_node_hard", 2) + v("default_dug_node", 2)],
    "dig/wood": [SND + f for f in v("default_dig_choppy", 3)],
    "dig/grass": [SND + f for f in v("default_place_node", 3)],
    "dig/gravel": [SND + f for f in v("default_gravel_dug", 3)],
    "dig/sand": [SND + f for f in v("default_sand_footstep", 3)],
    "dig/snow": [SND + f for f in v("pedology_snow_soft_footstep", 4)],
    "dig/cloth": [SND + f for f in v("mcl_sounds_cloth", 4)],
    "random/glass": [SND + f for f in v("default_break_glass", 3)],
    # uderzenia w blok podczas kopania
    "hit/stone": [SND + f for f in v("default_dig_cracky", 3)],
    "hit/wood": [SND + f for f in v("default_dig_choppy", 3)],
    "hit/grass": [SND + "default_dig_crumbly.ogg"],
    "hit/sand": [SND + "default_dig_crumbly.ogg"],
    "hit/snow": [SND + "default_dig_crumbly.ogg"],
    "hit/gravel": [SND + f for f in v("default_gravel_dig", 2)],
    "hit/cloth": [SND + "default_dig_snappy.ogg"],
    # kroki
    "step/grass": [SND + f for f in v("default_grass_footstep", 3)],
    "step/gravel": [SND + f for f in v("default_gravel_footstep", 4) + v("default_dirt_footstep", 2)],
    "step/stone": [SND + f for f in v("default_hard_footstep", 3)],
    "step/wood": [SND + f for f in v("default_wood_footstep", 2)],
    "step/sand": [SND + f for f in v("default_sand_footstep", 3)],
    "step/snow": [SND + f for f in v("pedology_snow_soft_footstep", 4)],
    "step/cloth": [SND + f for f in v("mcl_sounds_cloth", 4)],
    "step/ladder": [SND + f for f in v("default_wood_footstep", 2)],
    # zdarzenia
    "random/pop": ["mods/ENTITIES/mcl_item_entity/sounds/item_drop_pickup.ogg"],
    "random/click": ["mods/ITEMS/REDSTONE/mesecons_button/sounds/mesecons_button_push.ogg"],
    "damage/hit": [SND + "player_damage.ogg"],
    "random/explode": ["mods/ITEMS/mcl_tnt/sounds/tnt_explode.ogg"],
    "random/fuse": ["mods/ITEMS/mcl_tnt/sounds/tnt_ignite.ogg"],
    "random/fizz": [SND + f for f in v("default_cool_lava", 3)],
    "random/bow": ["mods/ITEMS/mcl_bows/sounds/mcl_bows_bow_shoot.ogg"],
    "random/bowhit": ["mods/ITEMS/mcl_bows/sounds/mcl_bows_hit_other.ogg"],
    "random/throw": ["mods/ITEMS/mcl_throwing/sounds/mcl_throwing_throw.ogg"],
    "random/eat": ["mods/PLAYER/mcl_hunger/sounds/" + f for f in v("mcl_hunger_bite", 2)],
    "random/orb": ["mods/HUD/mcl_experience/sounds/mcl_experience.ogg"],
    "random/levelup": ["mods/HUD/mcl_experience/sounds/mcl_experience_level_up.ogg"],
    "random/door_open": ["mods/ITEMS/mcl_doors/sounds/doors_door_open.ogg",
                         "mods/ITEMS/mcl_doors/sounds/doors_door_close.ogg"],
    "random/chestopen": ["mods/ITEMS/mcl_chests/sounds/default_chest_open.ogg"],
    "random/chestclosed": ["mods/ITEMS/mcl_chests/sounds/default_chest_close.ogg"],
    "random/splash": [SND + "mcl_sounds_place_node_water.ogg"],
    "item/bucket/fill": [SND + "mcl_sounds_dug_water.ogg"],
    "damage/fallsmall": [SND + "player_falling_damage.ogg"],
    "damage/fallbig": [SND + "player_falling_damage.ogg"],
    "random/break": [SND + "default_tool_breaks.ogg"],
    "mob/sheep/shear": ["mods/ITEMS/mcl_tools/sounds/mcl_tools_shears_cut.ogg"],
    "fire/ignition": ["mods/ITEMS/mcl_fire/sounds/fire_flint_and_steel.ogg"],
    "fire/fire": ["mods/ITEMS/mcl_fire/sounds/" + f for f in v("fire_fire", 3)],
    "ambient/weather/thunder": ["mods/ENVIRONMENT/lightning/sounds/" + f for f in v("lightning_thunder", 3)],
    "ambient/weather/rain": ["mods/ENVIRONMENT/mcl_weather/sounds/weather_rain.ogg"],
    "tile/piston/out": ["mods/ITEMS/REDSTONE/mesecons_pistons/sounds/piston_extend.ogg"],
    "random/drink": ["mods/ITEMS/mcl_potions/sounds/mcl_potions_drinking.ogg"],
    "block/brewing_stand/brew": ["mods/ITEMS/mcl_brewing/sounds/mcl_brewing_complete.ogg"],
    "block/enchantment_table/enchant": ["mods/ITEMS/mcl_enchanting/sounds/mcl_enchanting_enchant.%d.ogg" % i
                                        for i in range(3)],
    "block/end_portal/endportal": ["mods/ITEMS/mcl_portals/sounds/mcl_portals_open_end_portal.ogg"],
    "portal/travel": ["mods/ITEMS/mcl_portals/sounds/mcl_portals_teleport.ogg"],
    # moby
    "mob/pig/say": [MOB + "mobs_pig.ogg"],
    "mob/pig/death": [MOB + "mobs_pig_angry.ogg"],
    "mob/cow/say": [MOB + "mobs_mc_cow.ogg"],
    "mob/cow/hurt": [MOB + "mobs_mc_cow_hurt.ogg"],
    "mob/sheep/say": [MOB + "mobs_sheep.ogg"] + [MOB + f for f in v("mobs_mc_sheep_random", 2)],
    "mob/sheep/hurt": [MOB + "mobs_mc_sheep_damage.ogg"],
    "mob/chicken/say": [MOB + f for f in v("mobs_mc_chicken_buck", 3)],
    "mob/chicken/hurt": [MOB + "mobs_mc_chicken_hurt.ogg"],
    "mob/wolf/bark": [MOB + f for f in v("mobs_mc_wolf_bark", 3)],
    "mob/wolf/hurt": [MOB + f for f in v("mobs_mc_wolf_hurt", 3)],
    "mob/wolf/death": [MOB + "mobs_mc_wolf_death.ogg"],
    "mob/zombie/say": [MOB + "mobs_mc_zombie_growl.ogg"],
    "mob/zombie/hurt": [MOB + "mobs_mc_zombie_hurt.ogg"],
    "mob/zombie/death": [MOB + "mobs_mc_zombie_death.ogg"],
    "mob/skeleton/say": [MOB + f for f in v("mobs_mc_skeleton_random", 2)],
    "mob/skeleton/hurt": [MOB + "mobs_mc_skeleton_hurt.ogg"],
    "mob/skeleton/death": [MOB + "mobs_mc_skeleton_death.ogg"],
    "mob/spider/say": [MOB + "mobs_mc_spider_random.ogg"],
    "mob/spider/hurt": [MOB + f for f in v("mobs_mc_spider_hurt", 3)],
    "mob/spider/death": [MOB + "mobs_mc_spider_death.ogg"],
    "mob/creeper/say": [MOB + "mobs_mc_creeper_hurt.ogg"],
    "mob/creeper/death": [MOB + "mobs_mc_creeper_death.ogg"],
    "mob/ghast/moan": [MOB + "mobs_eerie.ogg"],
    "mob/ghast/fireball": [MOB + "mobs_fireball.ogg"],
    "mob/zombiepig/zpig": [MOB + "mobs_mc_zombiepig_random.1.ogg"],
    "mob/zombiepig/zpighurt": [MOB + f for f in v("mobs_mc_zombiepig_hurt", 3)],
    "mob/zombiepig/zpigdeath": [MOB + f for f in v("mobs_mc_zombiepig_death", 2)],
    "mob/endermen/idle": [MOB + "mobs_mc_enderman_random.1.ogg"],
    "mob/endermen/hit": [MOB + f for f in v("mobs_mc_enderman_hurt", 3)],
    "mob/endermen/death": [MOB + "mobs_mc_enderman_death.ogg"],
    "mob/endermen/portal": [MOB + "mobs_mc_enderman_teleport_src.ogg"],
    "mob/blaze/breathe": [MOB + "vl_elemental_fire_breath.ogg"],
    "mob/blaze/hit": [MOB + "vl_elemental_fire_hurt.ogg"],
    "mob/blaze/death": [MOB + "vl_elemental_fire_died.ogg"],
    "mob/enderdragon/growl": [MOB + "mobs_mc_ender_dragon_attack.ogg"],
    "mob/enderdragon/hit": [MOB + "mobs_mc_ender_dragon_shoot.ogg"],
}

# muzyka: folder -> utwory (bez numerów w nazwach, bo cyfry na końcu tworzą grupy)
MUSIC = {
    "music/menu": ["DarkReaven-calmed_cube", "DarkReaven-slow_piano_cubico"],
    "music/game": ["Jester-Hailing_Forest", "DarkReaven-sweet_piano_8bit", "DarkReaven-nostalgic_block",
                   "exhale_and_tim_unwin-farmer", "Herowl-Home_in_the_Wilderness",
                   "DarkReaven-what_we_will_build_next", "DarkReaven-magic_of_the_forest"],
    "music/game/nether": ["DarkReaven-memories_from_below", "DarkReaven-traitor"],
    "music/game/end": ["DarkReaven-calmed_cube_in_space"],
}

# pliki z informacjami o autorach i licencjach (kopiowane do licenses/)
LICENSES = {
    "VoxeLibre-LEGAL.md": "LEGAL.md",
    "VoxeLibre-CREDITS.md": "CREDITS.md",
    "mcl_sounds-README.txt": "mods/CORE/mcl_sounds/README.txt",
    "mobs_mc-LICENSE-media.md": "mods/ENTITIES/mobs_mc/LICENSE-media.md",
    "mcl_bows-README.txt": "mods/ITEMS/mcl_bows/README.txt",
    "mcl_hunger-README.md": "mods/PLAYER/mcl_hunger/README.md",
    "mcl_experience-README.md": "mods/HUD/mcl_experience/README.md",
    "mcl_experience-attributes.txt": "mods/HUD/mcl_experience/sounds/attributes.txt",
    "mcl_weather-README.md": "mods/ENVIRONMENT/mcl_weather/README.md",
    "lightning-README.md": "mods/ENVIRONMENT/lightning/README.md",
    "mcl_tnt-README.txt": "mods/ITEMS/mcl_tnt/README.txt",
    "mcl_chests-README.md": "mods/ITEMS/mcl_chests/README.md",
    "mcl_chests-attributions.txt": "mods/ITEMS/mcl_chests/sounds/attributions.txt",
    "mcl_doors-README.txt": "mods/ITEMS/mcl_doors/README.txt",
    "mcl_potions-README.txt": "mods/ITEMS/mcl_potions/README.txt",
    "mcl_enchanting-attributions.txt": "mods/ITEMS/mcl_enchanting/sounds/attributions.txt",
    "mcl_portals-README.md": "mods/ITEMS/mcl_portals/README.md",
    "mcl_portals-LICENSE.txt": "mods/ITEMS/mcl_portals/LICENSE",
    "mesecons_button-README.md": "mods/ITEMS/REDSTONE/mesecons_button/README.md",
    "mcl_throwing-README.md": "mods/ITEMS/mcl_throwing/README.md",
    "mcl_tools-README.md": "mods/ITEMS/mcl_tools/README.md",
    "mcl_item_entity-README.txt": "mods/ENTITIES/mcl_item_entity/README.txt",
    "mcl_item_entity-Attributes.txt": "mods/ENTITIES/mcl_item_entity/sounds/Attributes.txt",
    "mcl_fire-README.txt": "mods/ITEMS/mcl_fire/README.txt",
}

def main():
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    rows = []
    for group, files in sorted(MAP.items()):
        single = len(files) == 1
        for i, f in enumerate(files, 1):
            dst = f"{group}.ogg" if single else f"{group}{i}.ogg"
            os.makedirs(os.path.dirname(os.path.join(OUT, dst)), exist_ok=True)
            shutil.copyfile(os.path.join(SRC, f), os.path.join(OUT, dst))
            rows.append((dst, f))
    for folder, tracks in MUSIC.items():
        os.makedirs(os.path.join(OUT, folder), exist_ok=True)
        for t in tracks:
            src = MUS + t + ".ogg"
            name = t.lower().replace("-", "_").rstrip("0123456789_") + ".ogg"
            dst = folder + "/" + name
            shutil.copyfile(os.path.join(SRC, src), os.path.join(OUT, dst))
            rows.append((dst, src))
    os.makedirs(os.path.join(OUT, "licenses"), exist_ok=True)
    for dst, src in LICENSES.items():
        shutil.copyfile(os.path.join(SRC, src), os.path.join(OUT, "licenses", dst))
    shutil.copyfile(os.path.join(SRC, "LICENSE.txt"), os.path.join(OUT, "licenses", "VoxeLibre-LICENSE-GPLv3.txt"))
    with open(os.path.join(OUT, "FILES.md"), "w", encoding="utf-8") as fh:
        fh.write("# Skąd jest każdy plik\n\n")
        fh.write("Plik w tym folderze ← oryginalny plik w repozytorium VoxeLibre "
                 "(https://github.com/VoxeLibre/VoxeLibre). Pliki zostały tylko przemianowane.\n\n")
        for dst, src in rows:
            fh.write(f"- `{dst}` ← `{src}`\n")
    print(f"{len(rows)} plików -> {OUT}")

if __name__ == "__main__":
    main()
