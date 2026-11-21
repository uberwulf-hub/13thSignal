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
- **Explorer's catch scare.** By default, getting caught in Explorer is gentle: you fall and the Listener slowly
  leans over you, with no shriek. Older players can switch on the **full** version (its face suddenly in yours,
  with a shriek) from the main menu's **CATCH SCARE** button. It asks a times-table question (13-19 times 6-9),
  easy for an older kid and not something a little one does by accident. It lasts **only until the game is
  closed**, so the next person starts gentle again. In Parent Settings you can turn that switch off, or make the
  full scare permanent for Explorer.
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
| Turn a relay (Sector 3) / stop recording (Sector 5) | R | Right bumper |
| Use / throw the item in your hand | Left mouse button | Right trigger |
| Pick an inventory slot | 1-6 or the scroll wheel | D-pad left / right |
| Drop the item in your hand | G | D-pad down |
| Journal (clues) | Tab or J (hold); scroll with the wheel or arrow keys | Back/View |
| Pause | Esc | Start |
| Fullscreen / window | F11 or Alt+Enter (or Options → Display) | |

**The monsters**

- **THE LISTENER** is blind and hears everything. **Running is a bad idea:** when it hears you run (or walk
  on a grate, or bang a door) it stops dead, rears up and screeches, then comes for the sound much faster
  than it walks. If it catches you, you fall backwards and it bends down over you, face to face. In Survivor
  and Nightmare that's a full jump scare: its face is suddenly right in yours, with a shriek. (Explorer keeps it
  gentle: no shriek, it just leans slowly down over you. A parent can switch on the full version for Explorer
  in **Parent Settings**. Older players can also switch it on themselves from the main menu: **CATCH SCARE** asks
  a times-table question (like 17 x 6) that a little one won't answer by accident. It stays on only until the game
  is closed, and a parent can lock the switch in Parent Settings.)
  More about the Listener: Listen for its clicking: the faster it clicks, the closer it is to finding you.
  The **NOISE** bar shows how far your sound carries. Running is loud, the orange metal grates are LOUD, and
  crouching is quieter, but not silent. **Doors are heavy blast doors:** opening one is a bang it can hear from
  far away, and the clank as it shuts gives away where you just were.
  **It learns.** If you hide in lockers a lot, it starts checking them, so hold your breath when it stops at yours.
  If you run a lot, it strings tripwires across the halls you run through. Crouch to step over them. If you crouch
  everywhere, it learns to hear you crawl, and your crouching gets twice as loud.
  **It's hard to predict.** It stops at random to listen, gets hunches about where you are and comes to check,
  and when it hunts you it heads for where you're going and lunges. When it stops to listen, it can sense you
  close by even if you're silent, so don't stand still right next to it. **Don't stare at it, either:** look at it too long
  and it twitches, then glitches: the picture tears, it leaves black smears of itself behind, and it reappears a few metres away (in Nightmare it
  prefers to come closer). **Once it's onto you it doesn't let go
  easily:** it keeps hunting for several seconds after the last sound you made, and when it loses you it
  searches the spots around where it last heard you before it gives up. (Explorer is gentler: no
  crawl-learning, no lunges, it only senses you if you stand right next to it, it gives up sooner, and it
  only ever glitches away from you.)
- **THE REPLACEMENT** is a scientist mannequin that only moves when you can't see it. It wakes up when the power comes back on.
  Keep your light on it.
- **ECHO** copies MERIDIAN's voice and gives you bad advice. Check what it says against the notes you find.

**Every game is different.** The puzzles change each time you play:
- **Sector 1:** the breaker order and the note's clues to it, the elevator code, which colour is painted where, and where the keycard and the note are.
- **Sector 2:** which vault holds the drive, and where the fuse is.
- **Sector 3:** where the receivers are, so every relay lab needs a new answer. Each layout is checked by a solver before you get it, so it can always be solved with the lab's relays.
- **Sector 4:** where the jammers and the shutter button are, which square the checkpoint laser is on, where the camera hall's camera and pillars are, and where the elevator wing's laser grid and camera are (always far enough apart that you need both jammers).
- **Sector 5:** where the pressure plates are. Each one always stays far enough from its door that you need your copy.
- **Sector 6:** which switch on the power board runs which circuit (the labels are missing), and where the elevator key is.

Items always stay in the same room, so the way through still works.

**The story across a run.** Every sector hides one record about the 13th sector, somewhere new each game. MERIDIAN changes as you go down: steady at first, then pausing and correcting itself, then borrowing ECHO's words (not in Explorer), and in Sector 6 it admits its map is incomplete. Three notes first heard in the relays keep coming back: ECHO hums them, the showroom plays them. At Sector 6's elevator, you choose what to power with the last spare line: the ROUTE MAP (it shows a 13th sector) or the CAB LIGHTS (a calm ride down). Each changes MERIDIAN's last line. As the doors close, the elevator shows your route ("INCOMPLETE [13]" if you found 4+ records, outside Explorer). Then the three notes play once more... with one missing.

Rooms are labelled on plates beside each doorway, and the room you're in shows at the top right.

**The facility notices you.** Run, or clang across a grate, and the nearest intercom answers with a clipped chime. Lights go out behind you one by one, and come back later. A room's name plate might read SECTOR 13 while you aren't looking. ECHO plays back your own footsteps from where you made them, plus one you didn't. In Survivor and Nightmare it gets worse:
- The Listener goes silent as it closes in on a noise, then breathes close by.
- You might hear footsteps where nobody is, then a pipe taps twice in the same spot. Learn the difference.
- MERIDIAN might say something only ECHO has said.

(Explorer keeps only the gentle, quiet ones.)

**The monsters start somewhere new each game, too.** The Listener (and Sector 1's mannequin) start in a random room, always far from where you start, never in your starting room, a safe room or a lab, and always somewhere they could walk to you from.

**Sector 1's puzzles:**
1. Find the maintenance note. It tells you the breaker order.
2. Find the security keycard and open SECURITY, the orange door off the main hall.
3. Flip the three breakers in the right order. In the wrong order they trip with a loud alarm.
4. The elevator door shows a colour order. Find the four painted numbers (red, blue, green, yellow) around the sector.
   Look at them with your light and they go in your journal.
5. Type the code at the elevator and step in. The doors close behind you... and the light starts to fail.

**Your items come with you.** Whatever is in your inventory when you ride the elevator down is still in your
pockets in the next sector (and if you get caught, you keep them). Starting a sector from the main menu
means empty pockets.

### Items and your inventory

Your flashlight is in your left hand; your right hand holds whatever you've picked from your **inventory**
(six slots, along the bottom of the screen). Everyday things lie around every sector, somewhere different each game.
Look at one and press **E** to pick it up.

| Item | What it does |
|---|---|
| Battery | Recharges your flashlight |
| Glow stick | Crack it and toss it: it lights the area for about a minute and a half, and mannequins can't move in its light |
| Soda can, glass bottle, wrench | **Throw it to distract the Listener**: it goes to check where it landed, not where you are. Bottles smash and carry the furthest |
| Coffee mug, stapler, clipboard | Mostly junk, but you can throw them as a (quieter) distraction. Mugs break |
| Old photograph, ID badge | Look at them for a scrap of the story |

**Everything bounces and makes a real sound.** Each hit makes two sounds: the thing itself (a can's tinny
clank, a wrench's long ring, a mug's clink) and whatever it hit (dry concrete, a rattling grate, a booming
metal door, a glass wall). The harder it hits, the louder it is, and the Listener hears every bounce.
Glass and china only break if they hit hard. **Mannequins are solid:** you can't walk through them and things
bounce off them with a hollow knock... and a moment later, something inside it moves.

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

### Sector 3: Relay Station

Signal-relay puzzles. Transmitters shoot a beam of signal in a straight line. Pick up relays (**E**), put them
down (**E**) and turn them (**R**): a beam that reaches a relay leaves the way its arrow points. Get each beam into
its receiver. Beams go through glass, but you can't. Each receiver needs its own colour, and a relay hit by two
colours jams.

- **Relay Lab 1** teaches it, **Lab 2** hides the receiver behind glass, and **Lab 3** has red and blue beams.
  Each lab opens the gate to the next; Lab 3 opens the elevator.
- **The labs are shielded.** ECHO can't follow you in; it waits at the door. In Explorer, no monster can enter a lab.
- **ECHO is scarier** from here on (and in Sector 2): black empty eyes and a mouth that opens as it gets close,
  a head that snaps round to stare at you, a whisper you hear before you see it, and sometimes your own voice.
  In Survivor and Nightmare it also stretches taller and reaches for you, lurches forward along your trail,
  and fills the screen with static up close.

### Sector 4: Security Wing

Portable **signal jammers**. Put one down (**E**) and it jams its own floor square and the 8 around it (the
glowing purple square): **laser grids** switch off, **security cameras** go dark, **your footsteps are silent**,
and **ECHO can't step in**. While you carry it, it does nothing, and you can walk right over it.

- A laser grid blocks the checkpoint. The jammer in the hall gets you into the Armory, which has a second jammer
  and a button that opens a shutter back to the hall.
- A camera sweeps the camera hall; you can see its cone of light. Hide behind the pillars between sweeps, or jam
  it. If a camera keeps you in view (longer in Explorer), an alarm brings the Listener. Cameras can't see straight
  down: the square under a camera is a blind spot.
- The elevator is behind a laser grid watched by a second camera. One jammer can't cover both, so you need both
  jammers there at once.

### Sector 5: Playback Lab

**Recorders.** Press **E** at a recorder booth to start recording, move around, and press **R** to stop.
A green hologram copy of you replays exactly what you did, then stays standing where you finished. Its weight
holds down **pressure plates**, and each plate holds a door open. Only one copy exists at a time.

- **Lab 1:** the plate is too far from its door, so your copy holds it while you walk through.
- **Lab 2:** two doors in a row. Your copy must stand on the ORANGE plate long enough for you to get through,
  then move to the YELLOW plate.
- **Control room:** your copy must cross loud grates to hold the GREEN plate, which holds the elevator open.
  Your copy makes *your* noise: walk normally while recording and the Listener hears it, finds your copy and
  erases it. Crouch while you record. (In Explorer the Listener leaves copies alone.)

### Sector 6: Showroom

Rooms full of identical store mannequins. Most are props; some are **the Replacement** (1 in Explorer, which
never catches you, 2 in Survivor, 3 in Nightmare), and you can't tell which until one has moved.
**Light freezes them:** in a lit room they can't move at all, even when you look away. In the dark they move
whenever you aren't looking.

The **power board** in the main hall has four circuits (WEST showroom, EAST showroom, STOCKROOM, ELEVATOR) and
carries **only two at once**. Each circuit lights its room and powers its shutter; a third overloads the board,
everything goes dark and an alarm goes off. EAST + STOCKROOM gets you the elevator key; WEST + ELEVATOR gets you
out. Every time you switch, the room you leave goes dark, and the main hall only has emergency lighting.

**Secrets:** 3 signal fragments are hidden in each sector. One is behind a low vent you have to crouch through.

## Phones and tablets (Android)

The game also builds as an Android app (`The13thSignal-android.apk`), and SauceStore offers it to phones.

- **Touch controls** appear on phones and touch screens: a joystick appears wherever your left thumb touches,
  dragging on the right side looks around, and there are buttons for USE, LIGHT, RUN and CROUCH (tap to
  switch on and off), HOLD BREATH (only in a locker), R (Sectors 3 and up), JOURNAL and pause.
  A Bluetooth game controller works too. **Options → On-screen controls** switches them Auto / On / Off.
- **Options → Graphics** is Low / Medium / High. Phones start on Low (no flashlight shadows or glow).

### Android signing key (handled for you)

Android only installs an update over an older copy if both were signed with the **same key**. The build keeps
that key in a **private draft release** called *Android signing key (private - do not publish or delete)*.
Drafts never expire, and only people who can push to this repository can see them. Every build downloads the key
from there, so the key never changes and updates always install over the old copy. **Leave that draft alone:**
don't publish it and don't delete it. (Deleting it would mean a new key, and phones would have to uninstall
the game before the next update.) You can download its two files from the Releases page as a backup.

Optional: to use a key of your own instead, add these repository secrets (**Settings → Secrets and variables →
Actions**). They take priority over the stored key. Changing keys means phones must reinstall once.

| Secret | What it is |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the `.keystore` file, base64-encoded |
| `ANDROID_KEYSTORE_ALIAS` | the key's alias |
| `ANDROID_KEYSTORE_PASSWORD` | its password |

To build just the Android app without releasing, run **Actions → Android → Run workflow**; the `.apk` is kept
as a download on the run's page.

## Art and models

Floors, walls, ceilings, grates, doors and lockers use real photographed textures from
[Poly Haven](https://polyhaven.com) (CC0; see `licenses/POLYHAVEN-TEXTURES.txt`). The menus use the **Special Elite** typewriter font by Astigmatic (Apache 2.0; see
`licenses/SPECIAL-ELITE-FONT-LICENSE.txt`). The flashlight, wrench, clipboard and stapler are
Poly Haven CC0 models (see `licenses/POLYHAVEN-MODELS.txt`). The signal fragments are dark crystals built in
code, and all sounds are synthesized in code. The Replacement and the
showroom mannequins are built from smooth shapes in code. To use a real mannequin model instead, put a CC0
`.glb` at `assets/models/mannequin.glb` (see `assets/models/README.md`).

## Run it from the source code

1. Install **Godot 4.3** (standard version) from <https://godotengine.org/download>.
2. Open Godot, click **Import**, choose this folder's `project.godot`, then press **F5** to play.

Everything is built in code (`scripts/`). Each sector's map is a text drawing at the top of its script
(`scripts/sector.gd`, `scripts/sector_2.gd`, `scripts/sector_3.gd`, `scripts/sector_4.gd`, `scripts/sector_5.gd`, `scripts/sector_6.gd`). Redesign a sector by editing the
characters; the legend is right above each map.

`scripts/sector.gd` is also the shared base for every sector: monsters, lockers, noise, checkpoints, scares
and the end screen. A new sector is a script that `extends` it and overrides the hooks marked
`SECTOR HOOK` (map, rooms, puzzles, story), plus a line in `Game.SECTORS` in `scripts/game.gd`.
All sounds are synthesized in `scripts/sound.gd`, so there are no audio files to license.

**Automated test:** this plays through the sector and checks the Parent Lock, the puzzles, getting caught,
the checkpoints, the monster's learning, Sector 2's vaults and ECHO, Sector 3's relay labs, Sector 4's jammers and cameras, and Sector 5's recordings and plates:
```
godot --headless --path . res://tests/smoke_test.tscn
```

## Publishing to SauceStore

`saucestore.json` is the store listing, and
`.github/workflows/release.yml` builds `The13thSignal-windows.zip` and `The13thSignal-android.apk` and publishes a GitHub release
when you push a version tag (`git tag v0.1.0 && git push origin v0.1.0`).
Before tagging, write what changed in `release-notes/<version>.md`, one change per line. SauceStore shows these
lines as the game's Version history (a line starting with "Added" is tagged New, "Fixed" is tagged Fixed).
The store reads `saucestore.json` from the release's tag, so listing edits go live with the next release.


## Where it goes next

- **Sectors 7 to 12**, each with its own puzzle style and a new trick for the monsters.
- **SUBJECT 13**, the final boss. You only see the whole thing at the end, and you beat it with puzzle mechanics, not firepower.
- **13 signal fragments** across the game that unlock the true ending.
- Voice acting for MERIDIAN and ECHO, real recorded sound effects, more rooms and props.
