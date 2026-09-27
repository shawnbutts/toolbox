# Toolbox

A small toolbox of quality-of-life features. The first one is **Session XP**.

## Commands

`/toolbox` and `/tbx` do the same thing.

- `/toolbox help`: list commands
- `/toolbox xp`: show or hide the Session XP window
- `/toolbox reset`: start a new XP session
- `/toolbox font <9-32>`: set the window text size (default 12)

## Session XP

The window shows, for adventurer and producer XP:

- how long the session has run
- XP gained this session
- XP per hour over the whole session and over the last 10 minutes
- your level, how far through it you are, and an estimate of the time to the next level at your session rate

A session starts when you log in (or turn the add-on on) and when you press **Reset**.
It survives `/lua reload`. The window can be resized by dragging its corner. Settings, text size
and the window's open state are saved per character.
