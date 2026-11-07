# THE 13TH SIGNAL

*You were never supposed to hear it.*

A first-person horror escape game made with **Godot 4.3**. It plays like DOORS meets an escape room, with Doom Eternal intensity.
You win with your ears and your brain, not a gun. Scares come from **sound, darkness, timing and surprise**.
There is no blood, no gore and no graphic deaths. When a monster gets you, the screen fills with TV static and
you go back to the last checkpoint.

This first playable version is **Sector 1: Intake**. You wake up alone in an underground research facility.
The facility AI, MERIDIAN, talks to you over the intercom. Sometimes it tells the truth. Sometimes it's not
MERIDIAN at all.

## Parent guide (the safeguard)

| Mode | What it's like |
|---|---|
| **Explorer** | **No jump scares.** Slower, gentler monsters. The Listener never learns to check lockers, and the mannequin creeps closer but never catches you. When a voice lies, the game hints that it's lying. Quiet ambient sounds. |
| **Survivor** | Jump scares (a short sting sound and a quick glimpse of the mannequin), suspense and hiding. The monsters learn your habits. |
| **Nightmare** | More frequent, unpredictable scares, darker halls, faster learning. Mistakes like a wrong elevator code set off an alarm the monster can hear. |

- **The game starts in Explorer every time it's opened.** It never remembers a scary mode.
- **Survivor and Nightmare need the Parent PIN**, once each time the game is opened.
- **Set the PIN first:** Main menu → **PARENT SETTINGS** → choose 4 digits, then type them again.
  Until a PIN exists, the scary modes stay locked.
- In Parent Settings you can also **LOCK SCARY MODES NOW**, change the PIN, or remove it (which keeps the scary modes locked).
- Only a salted hash of the PIN is saved, never the digits themselves.
- **Forgot the PIN?** Delete the settings file and make a new one:
  `%APPDATA%\Godot\app_userdata\The 13th Signal\the_13th_signal.cfg` on Windows.

## How to play

**Goal:** get out of Sector 1 through the service elevator.

| Control | Keyboard / mouse | Controller |
|---|---|---|
| Move / look | WASD / mouse | Left stick / right stick |
| Run (loud!) | Shift | Left trigger or click the left stick |
| Crouch (quiet) | Ctrl or C (hold) | B (hold) |
| Use / open / hide | E | A |
| Flashlight | F | Y |
| Hold your breath (in a locker) | Space (hold) | X (hold) |
| Journal (clues) | Tab or J (hold) | Back/View |
| Pause | Esc | Start |

**The monsters**

- **THE LISTENER** is blind and hears everything. Listen for its clicking: the faster it clicks, the closer it is to finding you.
  The **NOISE** bar shows how far your sound carries. Walking is quiet, running is loud, the orange metal
  grates are LOUD, and crouching is almost silent. Doors make noise when you open them.
  **It learns.** If you hide in lockers a lot, it starts checking them, so hold your breath when it stops at yours.
  If you run a lot, it strings tripwires across the halls you run through. Crouch to step over them.
- **THE REPLACEMENT** is a scientist mannequin that only moves when you can't see it. It wakes up when the power comes back on.
  Keep your light on it.
- **ECHO** copies MERIDIAN's voice and gives you bad advice. Check what it says against the notes you find.

**Puzzles** (the colour code is different every game):
1. Find the maintenance note. It tells you the breaker order.
2. Find the security keycard and open SECURITY, the orange door off the main hall.
3. Flip the three breakers in the right order. In the wrong order they trip with a loud alarm.
4. The elevator door shows a colour order. Find the four painted numbers (red, blue, green, yellow) around the sector.
   Look at them with your light and they go in your journal.
5. Type the code at the elevator and step in.

### Sector 2: Archives

Clear Sector 1 to unlock it on the main menu, or press **CONTINUE** on Sector 1's end screen.

- **ECHO** joins the Listener. A figure made of TV static steps out where you arrived and walks **exactly where
  you walked**, a little slower than you walk. Stop for too long and it catches up. Go back the way you came and
  you walk straight into it. **Hiding in a locker breaks your trail** and it fades away for a while. It also copies
  MERIDIAN's voice, and it wants you to turn around. (In Explorer it never catches you. It just glitches away.)
- **Puzzle:** find a fuse in Cold Storage (all loud metal grates) and power the vault row. Three record
  terminals each say where the archive drive is. **Only one of them is really MERIDIAN telling the truth.**
  Work out which vault it must be; the statements change every game. The wrong vault sets off an alarm.
  Then take the drive to the archive server to unlock the elevator.
- 3 more signal fragments, one behind a low vent.

**Secrets:** 3 signal fragments are hidden in each sector. One is behind a low vent you have to crouch through.

## Run it from the source code

1. Install **Godot 4.3** (standard version) from <https://godotengine.org/download>.
2. Open Godot, click **Import**, choose this folder's `project.godot`, then press **F5** to play.

Everything is built in code (`scripts/`). Each sector's map is a text drawing: Sector 1's is at the top of
`scripts/sector.gd` and Sector 2's at the top of `scripts/sector_2.gd`. Redesign a sector by editing the
characters; the legend is right above each map.

`scripts/sector.gd` is also the shared base for every sector: monsters, lockers, noise, checkpoints, scares
and the end screen. A new sector is a script that `extends` it and overrides the hooks marked
`SECTOR HOOK` (map, rooms, puzzles, story), plus a line in `Game.SECTORS` in `scripts/game.gd`.
All sounds are synthesized in `scripts/sound.gd`, so there are no audio files to license.

**Automated test:** this plays through the sector and checks the Parent Lock, the puzzles, getting caught,
the checkpoints, the monster's learning, and Sector 2's vaults and ECHO:
```
godot --headless --path . res://tests/smoke_test.tscn
```

## Publishing to SauceStore

`saucestore.json` is the store listing, and
`.github/workflows/release.yml` builds `The13thSignal-windows.zip` and publishes a GitHub release
when you push a version tag (`git tag v0.1.0 && git push origin v0.1.0`).
Before tagging, write what changed in `release-notes/<version>.md`, one change per line. SauceStore shows these
lines as the game's Version history (a line starting with "Added" is tagged New, "Fixed" is tagged Fixed).
The store reads `saucestore.json` from the release's tag, so listing edits go live with the next release.


## Where it goes next

- **Sectors 3 to 12**, each with its own puzzle style and a new trick for the monsters.
- **SUBJECT 13**, the final boss. You only see the whole thing at the end, and you beat it with puzzle mechanics, not firepower.
- **13 signal fragments** across the game that unlock the true ending.
- Voice acting for MERIDIAN and ECHO, real recorded sound effects, more rooms and props.
