===============================================================
 ITR2 Distortion Zone Visibility
 Removes the thick red haze inside distortion zones
===============================================================

WHAT IT DOES

Distortion zones fill your entire view with dense red fog the moment
you step inside one. This mod removes that screen effect so you can
actually see where you are going.

It deliberately leaves the zone itself fully visible. The dome, the
particles and the red light are all untouched, so a zone still looks
exactly as it should from the outside and you can still tell at a
glance that you are standing in one. Only the full-screen haze goes.

Nothing about the zone's behaviour changes. It is still as dangerous as
it always was, and the anti-distortion helmet still works normally.


REQUIREMENTS

  UE4SS installed for Into the Radius 2.


INSTALL

  Copy the "ITR2DistortionZoneVisibility" folder into

      IntoTheRadius2\Content\Paks\LuaMods\

  so that you end up with

      ...\LuaMods\ITR2DistortionZoneVisibility\enabled.txt
      ...\LuaMods\ITR2DistortionZoneVisibility\config.txt
      ...\LuaMods\ITR2DistortionZoneVisibility\Scripts\main.lua

  To uninstall, delete that folder.


CONFIGURING

  Edit config.txt inside the mod folder. It is re-read once a second
  while the game runs, so changes apply without reloading anything.

  Out of the box only the distortion zone haze is removed. The config
  also lists the other five post process effects the game puts on your
  camera, each of which can be switched off the same way by adding a
  line. The one most people will want is the second:

      blendable_off = VisionPP_DistorsionHelmet

  which removes the mask overlay drawn when you wear the
  anti-distortion helmet. It is commented out by default, since that is
  a bigger change than the haze and not everyone wants it.

  Set enabled = 0 to leave the game completely stock without
  uninstalling.


A NOTE ON WHY THERE IS NO SLIDER

  The haze is a post process material on the player's camera, and the
  game switches it between weight 0 and weight 1. Unreal applies a
  material of this kind at full strength for any weight above zero, so
  0.01 and 1.0 render identically and only exactly 0 removes it. There
  is no partial setting available; this is on or off by nature, not by
  choice.


NOTES

  The effect is suppressed five times a second against a cached list,
  so there is no flash of red on the frame you cross into a zone.

  Effects are only ever held down, never switched on. If the game has
  an effect at zero the mod leaves it there, so nothing can appear
  somewhere it should not.

  Save games are not touched. Nothing is written to the game's files.
