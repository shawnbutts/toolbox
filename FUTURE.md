# Future

Ideas we might build later. Nothing here is agreed or scheduled; ask the owner before starting one.

## Farmer's helper (owner, 2026-10-09)

A watering schedule and other help for small and large farms. Not for 1.7.0; maybe 1.8.0, maybe never.

### The rules (from https://www.sotalore.com/farming; confirm in game, the yields may be out of date)

- Seeds grow in 24 h (quick, 6-10 gold), 48 h (medium, 16 gold) or 72 h (slow, 30 gold). A greenhouse halves the
  time; planting inside multiplies it by 10.
- Full yield needs four waterings: at planting, then one in each third of the growing time (quick: 0-8 h, 8-16 h,
  16-24 h; harvest after 24 h). The second can be done right after planting, so waterings 3 and 4 and the harvest
  are the ones to time.
- The site lists each seed's typical yield with full watering (Carrot 8, Garlic 16, Mandrake 32, ...).

### What the API gives (checked 2026-10-09, API 29)

- Nothing about seeds, plants, growth or watering, and no chat event.
- Around it: `ShroudOnInventoryChanged` / `ShroudGetInventoryItems` (seeds leaving the bags),
  `ShroudOnItemsGained` (harvests count; perhaps `ShroudOnGatherResults` if plants are nodes), the scene
  (`ShroudGetSceneInfo().isPot`, `ShroudGetCurrentSceneNameRaw`) and position, the local clock (`os.time`,
  feature-detected), and the hovered thing (`ShroudGetKindUnderMouse`, `ShroudGetNameUnderMouse`,
  `ShroudGetDescriptionUnderMouse`): a planted crop's tooltip might show its growth or water state (unchecked).

### Ideas, in the suggested order

1. **Probe first:** `/toolbox farm probe` prints what the game reports for the crop under the mouse. If its tooltip
   shows growth or water state, the tracker can fill itself in on hover instead of by clicks.
2. **Watering tracker:** record a planting (seed, count, greenhouse / inside / outside; scene, spot and time taken
   automatically); show each batch's current window, when it opens and closes, and harvest time; one click marks a
   watering. Account scope: any character may tend the lot.
3. **Reminders:** a "Farming" notification source (window, HUD list, chat, sound): "Water due: 12 Carrot (Brittany
   lot), closes 22:59", a warning before a window closes, crop ready; at login, what came due while away.
4. **Harvest and yield per batch:** close a batch when its crop arrives; yield against the full-watering yield (a low
   one hints at a missed watering); profit per batch with seed cost and SotANET prices (`Toolbox.Prices`), gold per
   day of growing.
5. **Auto-detect planting:** seeds leaving the bags in a player town or on a lot asks "Planted 8 Garlic seeds? Track
   them" (asks, since selling or banking seeds removes them too).
6. **Large farms:** batches grouped by plot (scene + spot); a "Next action" line ("Owl's Head, 40 plants, water 3
   opens in 2h 10m"); a Beacon button to a plot (like the loot runs, `DD.MarkRun`); a planting-time planner (from
   your usual play hours, when to plant so waterings 3 and 4 and the harvest land while you're online); a seed
   shopping list for the next round.

### Limits

- No reminders while the game is closed (sotalore's calendar export covers that; Toolbox can't write a file).
- No free window: a Loot Tracker view (beside Runs) or a HUD strip. The package is at 16 Lua files: add the code to an
  existing one.
- sotalore's numbers are game facts, not add-on code, so the clean-room rule allows them.

## Run markers on the map (owner, 2026-10-10)

Built 2026-10-12 on API 30 (`DD.SyncMarkers`): a flag per run in its scene; the Beacon stays (markers never reach
the compass). Still to check in game: the scene match across visits. The notes below are the plan as it was.

Waiting on dev request 20 (add-on markers on the region map and minimap), expected in the next client with new API
docs. Build it only once the real API is in hand: its limits, scene scoping and hover note decide the design.

- Markers become the main way runs show up: one per filed run (the last `D.RUNS_KEEP`), placed when a run is filed
  (`D.FileRun`), at its spot (`D.MainSpot`), with a hover note (time, gold an hour, kills, items). They don't
  take the player's own beacon, as a Beacon click does today.
- Feature-detected: on a client without markers (API 25 is still the minimum), the Beacon button stays as it is.
- Keep the Beacon button as "take me there" if markers don't reach the compass (the beacon does); drop it if they do.
- Scene matching (`ShroudGetCurrentSceneNameRaw` across visits, instanced scenes) matters for scene-scoped markers
  too: check it in game with the Beacon meanwhile.
