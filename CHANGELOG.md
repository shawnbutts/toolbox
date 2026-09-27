# Changelog

All notable changes to Toolbox are recorded here. Versions follow `N.N.N`; every
store submission needs a higher version than any submitted before (rejected ones included).

## [Unreleased]

### Added
- Daily stats window (`/toolbox daily`, also in settings): gold picked up, kills by you or your
  pet, and adventurer / producer XP gained today. Resets at local midnight (midnight UTC if the
  local clock is unavailable); kept per character across reloads and relogs.
- Line spacing setting (`/toolbox spacing <0-12>` and a slider in settings). Text lines now have
  a fixed height that follows the text size, so smaller text makes the windows shorter.
- Hovering the compact XP window pops up the Session XP window after a short delay; it stays
  while the pointer is over either window. Can be turned off in settings.
- Compact XP window (`/toolbox compact`, also in settings): session time, current adventurer
  and producer pools, and XP earned on each in the last hour.
- `/toolbox config` opens a Toolbox Settings window: a text-size slider for the Session XP
  window and a checkbox to show or hide it.
- `/toolbox font <9-32>` sets the Session XP window's text size (saved per character).

### Changed
- Window names and commands: the compact window is now **XP** (`/toolbox xp`), and the old
  Session XP window is **XP Detailed** (`/toolbox xpdetailed`, alias `xpd`). `/toolbox compact`
  is gone. Window positions and settings carry over.
- The build allows `os.date` / `os.time` (for the daily reset); other `os` and all `io` use is
  still refused.
- Lower minimum window heights (Session XP 60, compact 50) now that lines can be tighter.
- "Next level" and "Last hour" lines use the normal text colour instead of the dimmed one.
- Sample history now covers the last hour (was 10 minutes); the session is stored in saved
  vars once per tick instead of on every XP event.
- More compact Session XP window: level and % share the track heading, gains and rates share
  one line, and elapsed time sits beside Reset. Smaller default text (12), a smaller default
  size, and a lower minimum size (160x100). Content scrolls when the window is made smaller.
- The "Next level" line always shows the XP still needed, and says why there is no time
  estimate ("no XP gained yet", "max level") instead of a bare `--`.
- 10px left/right gutter in the Session XP window so the progress bars no longer touch the edge.

## [0.1.0] - 2026-09-27

### Added
- `/toolbox` and `/tbx` slash commands with `help`, `xp` and `reset`.
- Session XP tracking for adventurer and producer XP from the total XP values:
  elapsed time, XP gained, XP/hour for the session and the last 10 minutes,
  level, % through the level and estimated time to the next level.
- "Session XP" window (Shroud.UI) with a Reset button; remembers whether it is
  open and where it is.
- Sessions survive `/lua reload`; a new login starts a new session.
