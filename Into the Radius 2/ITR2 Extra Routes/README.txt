===============================================================
 ITR2 Extra Routes
 Two level transitions Into the Radius 2 does not have
===============================================================

WHAT IT DOES

  Outskirts -> Facility
  Forest    -> Outskirts

Both are on by default. Either can be switched off in config.txt.

You travel them exactly the way you travel any route: shake the Pyotr's
hand, walk the route, step into the transition zone. The mod changes
where a transition leads and nothing else, so the game performs the
whole transition itself - the fog, your inventory, and putting you on
the proper arrival marker.


OUTSKIRTS -> FACILITY

Outskirts has no way back to the Facility. This gives it one, by taking
over one of the two routes Outskirts already has to Forest. Outskirts
keeps the other, so no connection is lost. Use the Pyotr on the RGD
road.


FOREST -> OUTSKIRTS

Coming back from the Facility you land in Forest, and the nearest way
onward to Outskirts is right across the map. This puts one near where
you land, at the Peninsula gate.

Note what it replaces: Forest has no spare route near that gate, so this
takes over Forest -> Peninsula. Peninsula is still directly reachable
from the Facility, so you keep access to it - you lose only the direct
Forest link.

Set forest_to_outskirts = 0 in config.txt if you would rather keep that
link instead.


REQUIREMENTS

  UE4SS for Into the Radius 2.
  Developed and tested against UE4SS v3.0.1 Beta.

  Lua only. No game assets are replaced.


INSTALL

  Copy the "ITR2ExtraRoutes" folder into

      IntoTheRadius2\Content\Paks\LuaMods\

  To uninstall, delete that folder. The routes revert immediately on the
  next level load.


CONFIG

  config.txt has two switches, 1 for on and 0 for off. It is re-read
  once a second, so you can change them while the game is running.

  There is deliberately no way to define your own routes. A route needs
  a destination and a matching arrival marker in that destination, and
  getting either wrong drops you somewhere unintended with no way for
  the mod to catch it. The two routes here are fixed and tested.


NOTES

  Nothing is written to your save. Transition actors are rebuilt every
  time a level loads, so uninstalling restores the game exactly.

  No gameplay, mission or progression state is touched - only where two
  existing transitions lead.
