===============================================================
 ITR2 Fog Tweaks
 Per-map control of the distance haze in Into the Radius 2
===============================================================

WHAT IT DOES

Thins the global height fog, separately for every map, and lets you
tune it while the game is running.

Each map is configured on its own, because their fog is nothing alike.
Peninsula ships at 500x the Hub's density; Forest looks thin on paper
but carries the heaviest volumetric layer in the game. One global
setting cannot serve both, so each map has its own section.

It leaves everything else alone: fog splines, the fog walls at map
edges, swamp fog cards and the fog anomaly are meshes and particles,
not this system, and are untouched.


REQUIREMENTS

  UE4SS installed for Into the Radius 2.


INSTALL

  Copy the "ITR2FogTweaks" folder into

      IntoTheRadius2\Content\Paks\LuaMods\

  so that you end up with

      ...\LuaMods\ITR2FogTweaks\enabled.txt
      ...\LuaMods\ITR2FogTweaks\config.txt
      ...\LuaMods\ITR2FogTweaks\Scripts\main.lua

  To uninstall, delete that folder.


CONFIGURING

  Edit config.txt inside the mod folder. It is re-read once a second
  while the game runs, so you can change a value, save, and see the
  result in the headset a second later without reloading anything.

  Sensible defaults for every map are already set. Every key is
  documented in the file itself.

  The two you will reach for most:

    density      a multiplier on the fog the game asks for. Preserves
                 the time-of-day and weather variation, just thinner.

    max_opacity  a cap on how opaque fog can ever get. 0.70 means
                 distant terrain always stays 30 percent visible, no
                 matter what the weather does. The most direct control
                 if what you want is to see the horizon.

  Set ab_seconds to 10 and the mod will alternate itself on and off
  every ten seconds so you can see exactly what it is doing. Set it
  back to 0 when you are done.

  F8 toggles the mod on and off manually, but UE4SS keybinds only
  register when the game's desktop window has focus, so ab_seconds is
  the practical one while wearing a headset.


authored.txt

  The mod writes this file next to the config as it meets each map. It
  records the values the game itself uses, so you can see what you are
  scaling against, and its first two columns are valid section names
  for config.txt. Visit a map you want to tune, then read that file.

  Do not delete it while the game is running.


NOTES

  Fog density is not a fixed number. The game's sky controller drives
  it continuously with the time of day and the weather, and during a
  fog event it can multiply by more than a hundred. This mod scales the
  controller's own writes as they happen rather than fighting them, so
  the weather still moves and there is no flicker. The density_max key
  is an absolute ceiling for those events, since a multiplier alone
  cannot bound them.

  Maps are identified by their internal folder name. Outskirts is
  "Town". authored.txt always shows the correct name.

  Save games are not touched. Nothing is written to the game's files.
