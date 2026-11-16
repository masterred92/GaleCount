# Changelog

## 1.0.2
- Fixed: Windfury procs were not counted in a real fight (issue #1). In combat this client hides buff and proc details from addons unless the game marks a spell as always visible, and Gale Count was relying on details it couldn't see.
- Gale Count now checks what the client allows and picks how to count: from the Windfury buff when the game keeps it visible (a re-proc while the buff is up counts too), otherwise from your own Windfury cast events if the game sends them. Two procs close together both count.
- If neither is available, the window says plainly that procs can't be counted on this client and shows Windfury damage from the game's damage meter after each fight. If the meter has no separate Windfury line, it says so instead of guessing.
- This detection follows the game's documented rules for this client and should work here; confirmation in game will come from players. `/gale debug` shows which method is active and what the client allows, which helps with bug reports.
- UI polish: bigger text, gold labels, padlock button, clearer idle state.

## 1.0.1
- `/gc` clashed with the game's guild chat command; use `/gale` (or `/galecount` as a backup). Help text, first-run tip and README updated.

## 1.0.0
- First release for WoW: Forever (Interface 16001, client 1.60.1).
- Counts every Windfury proc as it happens: Windfury Weapon (all 4 ranks, +2 swings) and Windfury Totem (all 3 ranks, +1 swing, including a totem from another Shaman).
- After each fight: Windfury damage, Windfury's share of your damage and average damage per proc, read from Blizzard's own damage meter. Session totals and your best average per proc, with a Reset session button.
- In combat: live proc count, plus your damage and Windfury damage straight from Blizzard's meter.
- Storm-themed box: class colours first, then the accent and thunder sound of the talent tree you have the most points in. Themes live in one small table (`Themes.lua`).
- Thunder on Windfury streaks (2 procs within 4 seconds by default), on every proc, on a new best average, or off. Built-in game sounds only.
- Movable, resizable (drag the corner) and lockable box; position, size and scale are saved.
- `/galecount debug` setup check, `/galecount meter` to see the meter rows of your last fight, `/galecount report` for a copyable bug report.
