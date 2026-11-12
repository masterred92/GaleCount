# Changelog

## 1.0.0
- First release for WoW: Forever (Interface 16001, client 1.60.1).
- Counts every Windfury proc as it happens: Windfury Weapon (all 4 ranks, +2 swings) and Windfury Totem (all 3 ranks, +1 swing, including a totem from another Shaman).
- After each fight: Windfury damage, Windfury's share of your damage and average damage per proc, read from Blizzard's own damage meter. Session totals and your best average per proc, with a Reset session button.
- In combat: live proc count, plus your damage and Windfury damage straight from Blizzard's meter.
- Storm-themed box: class colours first, then the accent and thunder sound of the talent tree you have the most points in. Themes live in one small table (`Themes.lua`).
- Thunder on Windfury streaks (2 procs within 4 seconds by default), on every proc, on a new best average, or off. Built-in game sounds only.
- Movable, resizable (drag the corner) and lockable box; position, size and scale are saved.
- `/galecount debug` setup check, `/galecount meter` to see the meter rows of your last fight, `/galecount report` for a copyable bug report.
