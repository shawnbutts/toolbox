# Changelog

All notable changes to Toolbox are recorded here. Versions follow `N.N.N`; every
store submission needs a higher version than any submitted before (rejected ones included).

## [Unreleased]

## [0.1.0] - 2026-09-27

### Added
- `/toolbox` and `/tbx` slash commands with `help`, `xp` and `reset`.
- Session XP tracking for adventurer and producer XP from the total XP values:
  elapsed time, XP gained, XP/hour for the session and the last 10 minutes,
  level, % through the level and estimated time to the next level.
- "Session XP" window (Shroud.UI) with a Reset button; remembers whether it is
  open and where it is.
- Sessions survive `/lua reload`; a new login starts a new session.
