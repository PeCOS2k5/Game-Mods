===============================================================
 ITR2 NVG Field of View
 Widens the night vision goggle view in Into the Radius 2
===============================================================

WHAT IT DOES

The night vision goggles show a small circle of image surrounded by a
lot of black. This widens that circle, per device, by an amount you
choose.

Supported:

    PVS-7     single tube
    PVS-31    dual tube
    GPNVG-18  quad tube panoramic

Not supported:

    PVS-14    its material ignores the parameter the other three use,
              and no working control was found. It is switched off in
              the config rather than left half working.


REQUIREMENTS

  UE4SS for Into the Radius 2.
  Developed and tested against UE4SS v3.0.1 Beta.

  Lua only. No game assets are replaced, so no pak tools and no other
  dependency.


INSTALL

  Copy the "ITR2NVGFieldOfView" folder into

      IntoTheRadius2\Content\Paks\LuaMods\

  To uninstall, delete that folder. Nothing is written to the game's
  files and the goggles return to stock on the next launch.


CONFIGURING

  Edit config.txt inside the mod folder. It is re-read once a second,
  so a change applies as soon as the goggles are on - no reload.

      [PVS7]    extend = 150
      [PVS31]   extend = 150
      [GPNVG]   extend = 240,  base = 0.126
      [PVS14]   enabled = 0


  READ THIS BEFORE TUNING

  "extend" is a percentage of the material's radius parameter, NOT a
  percentage of what you see. The visible area grows much more slowly
  than the number does. In testing, 150 read as roughly a 15 percent
  bigger view.

  So move in large steps. If a change looks like it did nothing, try
  200 before deciding the mod is broken.


  GPNVG is a special case. Unlike the other two it never sets a radius
  of its own, so there is no stock value to take a percentage of - the
  mod creates the override from scratch and "base" is what 100 refers
  to. 0.126 is borrowed from the dual tube. That makes GPNVG's
  percentage not directly comparable to the other two; judge it by eye
  rather than by matching numbers across devices.


NOTES

  Stock values are written to stock.txt on first sight and never
  re-read, so reloading the mod cannot compound the scaling. Delete
  that file if you want it to re-learn.

  Save games are not touched.

  Nothing about detection or gameplay changes - this only affects how
  much of the image the goggles let you see.
