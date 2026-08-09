# Game Mods

Source for my released game mods.

## Into the Radius 2

UE4SS Lua mods. Neither replaces any game asset — they read and adjust
values at runtime — so they carry no `.pak` files and cannot conflict
with asset mods at the file level.

| Mod | What it does |
|---|---|
| [ITR2 Fog Tweaks](Into%20the%20Radius%202/ITR2%20Fog%20Tweaks) | Per-map control of the global height fog (the distance haze), tunable live while the game runs |
| [ITR2 Distortion Zone Visibility](Into%20the%20Radius%202/ITR2%20Distortion%20Zone%20Visibility) | Removes the thick red screen haze inside distortion zones, leaving the zone itself fully visible |

Each mod folder contains its `README.txt` (install and configuration),
`NEXUS_DESCRIPTION.txt` (requirements and compatibility), and the
install-ready folder that gets dropped into
`IntoTheRadius2\Content\Paks\LuaMods\`.

### Requirements

UE4SS for Into the Radius 2. Developed against UE4SS v3.0.1 Beta and
Steam build 24024260 (Unreal Engine 5.5.4, Oculus fork).

### Notes on how these work

Both mods read the game's own values at runtime rather than hardcoding
numbers, so they adapt to whatever a given map or update presents.

`ITR2 Fog Tweaks` hooks the fog component's setters and scales the sky
controller's writes in flight, rather than overwriting fog on a timer —
writing on a timer fights the controller and produces visible flicker at
the timer's period.

`ITR2 Distortion Zone Visibility` holds a camera post-process blendable
weight at zero. It only ever holds values down, never sets them up, so
an effect the game has switched off can never be switched on by the mod.

Both stop touching game objects during level transitions and on quit.
Reading UObjects while a world is being torn down reads freed memory,
which Lua's `pcall` cannot catch.
