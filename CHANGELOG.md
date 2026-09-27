# Changelog

All notable changes to Toolbox are recorded here. Versions follow `N.N.N`; every
store submission needs a higher version than any submitted before (rejected ones included).

## [Unreleased]

### Added
- `/toolbox font <9-32>` sets the Session XP window's text size (saved per character).

### Changed
- More compact Session XP window: level and % share the track heading, gains and rates share
  one line, and elapsed time sits beside Reset. Smaller default text (12), a smaller default
  size, and a lower minimum size (160x100). Content scrolls when the window is made smaller.
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
