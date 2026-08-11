===============================================================
 ITR2 Custom Level Routes
 A direct Outskirts -> Facility route, and any route you like
===============================================================

WHAT IT DOES

Out of the box it gives Town (Outskirts) a direct route to the Hub
(Facility), which the game does not otherwise have.

It does this by retargeting one of the two routes Town already has to
Forest. Town keeps a Forest route through the other one, so nothing is
lost - you simply gain a way home.

There is a second, OPTIONAL route in the config, switched off by
default: a Forest -> Town link much closer to the Hub gate. Coming back
from the Hub you land in Forest at the Facility gate, and the nearest
way onward to Town is about 870 m across the map. Enabling it moves
that to about 350 m.

Unlike the first route, this one has a cost: it takes over the
Forest -> Peninsula link, because Forest has nothing spare near the Hub
gate. Peninsula is still directly reachable from the Hub. That is a
good trade for most people but not everyone, which is why you opt in.

You travel it exactly as you always would: shake the local Pyotr's
hand, walk the route, step into the transition zone. You come out at
the Hub gate instead of Forest.

Because it changes only the destination, the game runs its own
transition: the fog stage, the inventory handoff, and putting you on
the proper arrival marker. Nothing is reimplemented.

The config is general, so you can wire up any pair of maps you want.


REQUIREMENTS

  UE4SS for Into the Radius 2.
  Developed and tested against UE4SS v3.0.1 Beta.

  Lua only. No game assets are replaced.


INSTALL

  Copy the "ITR2CustomRoutes" folder into

      IntoTheRadius2\Content\Paks\LuaMods\

  To uninstall, delete that folder.


HOW IT WORKS

  Every level transition in this game is an actor carrying four pieces
  of data: the destination level, which arrival marker to land on, the
  trigger that gates it, and whether it is a same-map shuffle.

  This mod finds a transition by its gate tag and rewrites the first
  two. That is the entire mod.

      retarget = <gate tag> | <destination level> | <arrival marker>

  Nothing is written to the save. Transition actors are rebuilt every
  time a level loads, so removing the mod restores the game exactly.


MAKING YOUR OWN ROUTES

  config.txt lists every level tag, arrival marker and gate tag
  measured in game, with the map each marker physically sits in.

  Set debug = 1 and the log will tell you which transition you are
  standing nearest to and where it currently leads. That is how the
  reference list was built, and it is the fastest way to find the tags
  for a route the list does not cover.

  Two rules worth respecting:

    - The arrival marker must exist in the destination level. Point a
      route at a marker that is not there and you will travel and land
      somewhere unintended.

    - Prefer retargeting a route the map has a duplicate of. Town has
      two to Forest, which is why the default costs nothing. Taking
      over a map's only route to somewhere removes that connection.


NOTES

  Tags starting Level.Radius.<Map>.GateLocal are same-map shuttles, not
  level changes. Retargeting one of those is untested.

  Save games are not touched. Nothing is written to the game's files.
