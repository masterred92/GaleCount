# Changelog

## 1.1.0
- **Idle fade:** out of combat the box rests at 35% alpha. It comes back to full in combat (also after a `/reload` in combat), under the mouse (including the padlock, resize grip and Reset button), during a proc flash or proc window and during `/gale test`. `/gale fade` turns it off or on at once. On by default.
- **Live Windfury drain bar:** when procs can be counted (`aura` or `cast` detection) and a proc lands, the bar turns into a bright accent-coloured countdown over your streak window (`/gale streak`, default 4 seconds): `WINDFURY! 3.2s`, or `WINDFURY! x3 3.2s` once procs chain inside the window (each proc restarts it). When the window runs out the Windfury share bar and the theme colour come back. When procs can't be counted (`none`), the bar never runs; nothing is guessed.
- **Right-click quick menu** (out of combat; also `/gale menu`): sound mode, sound file, idle fade, compact mode, locked, click-through when locked, test preview, reset session and reset position. Uses Blizzard's own menu; it doesn't open in combat and entries clicked after combat starts do nothing.
- **Compact mode** (`/gale compact`, off by default): a slim 60-pixel strip with the headline, the proc count, the padlock and the bar. Switching back restores your saved size; `/gale size` while compact changes the saved full size.
- **Click-through when locked** (`/gale clickthrough`, off by default): while the box is locked, clicks pass through it (box, padlock and Reset button). `/gale unlock` or `/gale clickthrough` makes it clickable again; the help, the padlock tooltip and the lock message say so.
- `/gale test` is now a full preview of one proc window (flash, headline, drain bar, sound); it stops when combat starts or a real proc lands.
- Settings from 1.0.x (position, size, scale, lock, sounds, streak) carry over; the new switches start at their defaults.

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
