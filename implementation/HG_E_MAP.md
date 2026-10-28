# ETH HG floor E arena

The host chooses the arena using the map menu in the private lobby. Changing
the map clears both ready states. The original Ruined Dining Hall stays the
default and can be selected again. Both clients build the same geometry from
the map ID in the authoritative snapshot. Multiplayer protocol: 3.

## Drawing references

- ETH-authored HG E drawing, HG_E_20171010, publicly shared as
  [ETH_FloorPlan_E.pdf](https://uploads.strikinglycdn.com/files/ecd85dc6-1b5c-491b-b1be-986fc3d7c6f5/ETH_FloorPlan_E.pdf).
  The title block identifies Hauptgebaeude HG, floor E, plan 780, revisions
  through October 2017. The full page was rendered and visually inspected.
- ETH's [MaP Graduate Symposium 2024 booklet](https://ethz.ch/content/dam/ethz/special-interest/study-programme-websites/map-doctoral-school-dam/GrSy/MaP%20Graduate%20Symposium%202024%20-%20Booklet.pdf),
  printed page 5, corroborates the main hall, Polyterrasse, Raemistrasse and
  stairs surrounding the central entrance hall.
- The current [ETH navigation download](https://transfer.ethz.ch/de/ueber-uns/lageplan.html)
  links to a protected PDF. No authenticated plans were used.

## Adaptation

This is a game adaptation, not a survey-accurate model or a navigation aid.
North on the drawing is the Raemistrasse side of the game overview. The major
building relationships are traced: entrance rotunda and fountain; long main
hall; E 3/E 5; fan-shaped E 1.1/E 1.2 and E 7; side foyers; computer/seminar
rooms; projecting lecture wings; office strips; Polyterrasse entrance.

The map is 172 by 124 cells (5504 by 3968 world pixels), versus 80 by 71 for
the dining map. Cells are approximately a metre at the source drawing scale.
Corridors and doorways are simplified/widened for unit clearance. Office
strips are sealed and visibly roofed. Public rooms and circulation are
connected. Stairs are ordinary walkable tiles with tread decoration and no
height transition. Damaged movable furniture provides breakable cover.

## Rendering and checks

Static geometry remains cached. The large map texture is capped to 4096 pixels
on its longest axis; existing graphics quality and neon toggles still apply.
Only small breakable/door/effect layers animate during play.

`tests/test_hg_map.tscn` checks deployment clearance, routes through each wing,
all-cell floor connectivity, closing doors, map selection authorization and
returning to the old arena. `tests/bot_client.gd --map=hg_e` exercises the
networked map-selection and match flow.

Native overview capture:

`godot --path . -- --overview=hg_e --screenshot=/tmp/hg_e.png --shot_delay=2`
