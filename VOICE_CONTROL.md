# 🎙️ Voice Control & Tactical Command Guide

> **Campus Arcana** can be played completely hands-free: select soldiers, steer them across the map, aim firing cones, and trigger tactical spells, all by speaking.
>
> Mouse and keyboard keep working at all times.

---

## 📑 Table of Contents
1. [Browser Setup & Microphone](#-browser-setup--microphone)
2. [Command Grammar](#-command-grammar)
3. [Command Cheat Sheet](#-command-cheat-sheet)
4. [Directions, Steering & Distance](#-directions-steering--distance)
5. [Feedback: What You See](#-feedback-what-you-see)
6. [Multi-Tab Testing & Troubleshooting](#-multi-tab-testing--troubleshooting)
7. [Tips for Reliable Recognition](#-tips-for-reliable-recognition)
8. [Developer Guide](#-developer-guide)

---

## 🌐 Browser Setup & Microphone

Voice uses the browser **Web Speech API** through Godot's `JavaScriptBridge`.

- **Supported Browsers**: Google Chrome and Microsoft Edge (recommended), Safari.
  - *Note*: Firefox does not support the Web Speech API natively; use keyboard/mouse controls on Firefox.
- **Secure Context Required**: The browser microphone only activates on `http://localhost`, `http://127.0.0.1`, or `https://`.
- **Internet Connection**: Chrome's speech recognizer performs cloud-assisted processing and requires an active internet connection.

### Turning the Microphone On / Off
1. **Auto-Start**: The microphone automatically activates when you click **Deploy** (or press `Enter` / say *"deploy"*). Allow microphone permissions when prompted by your browser.
2. **Toggle Button / Key**: Press **V** or click the **Mic ON/OFF** button in the bottom-right corner to toggle listening at any time.

### Multi-Tab Mutex & Visibility Awareness
When testing a 1v1 match locally (e.g. via `./run_local.sh`), having two browser tabs open simultaneously could cause microphone contention and abort loops. The game resolves this automatically:
- **Tab Mutex**: A shared `localStorage` lock ensures only one browser tab actively consumes the microphone at a time.
- **Automatic Pause on Blur**: Switching to another tab or minimizing the window automatically pauses voice recognition in the hidden tab (`document.hidden`) and frees the microphone.
- **Automatic Resume on Focus**: Focusing the tab automatically reclaims the microphone lock.
- **Manual Claiming**: If a tab reports `mic in other tab (click Mic to claim)`, simply click the **Mic** button in that tab to forcefully claim the microphone.

---

## 🗣️ Command Grammar

Every voice utterance follows an intuitive tactical grammar:

```
[who]        [action]      [direction / angle / slot]
 Bravo        go            left
 Charlie      watch         right
 Alpha        left          30
 Bravo        forward       5
 Alpha        ability two   right
 Squad        hold
```

### 1. Who (Target Soldier)
Specifies which squad member executes the command. If omitted, the command defaults to the **currently selected soldier**.

| Say | Soldier | Slot / Role |
|---|---|---|
| `Alpha`, `Alfa`, `Rifle`, `Sniper` | **Alpha** | 1 · Rifle |
| `Bravo`, `SMG`, `Gunner` | **Bravo** | 2 · SMG |
| `Charlie`, `Shotgun`, `Breacher` | **Charlie** | 3 · Shotgun |
| `Delta`, `Marksman` | **Delta** | 4 · Marksman |
| `One` / `Two` / `Three` / `Four` | **1**, **2**, **3**, **4** | Only recognized at the **start** of a phrase (e.g., `"two go left"`, `"select three"`), preventing `"to"` from misidentifying as soldier 2. |
| `Squad`, `Team`, `Everyone`, `All`, `All units` | **Entire Squad** | Directs all living squad members simultaneously. |
| *(nobody specified)* | **Selected Soldier** | Reuses the active selection or the soldier specified earlier in the phrase. |

> **Selection Note**: Naming an individual soldier automatically **selects** them (if alive) so follow-up commands target them. If that soldier is down, the game warns you and cancels the order. Squad commands do not change the active selection.
>
> **Spells are squad-wide**: Every living soldier that has the requested ability equipped and enough MP casts it at the same time. Spoken spell slots (e.g. `"Charlie spell two"`) resolve the spell from that soldier's equipped loadout.

---

### 2. Chaining Orders & Sequential Queueing
Combine multiple tactical commands into a single breath using `and`, `then`, or `also`:
- **Chained Commands**:
  - `"Bravo go left and watch right"`
  - `"Alpha move up then Charlie move south"`
  - `"Squad rush and forward"`
- **Subject Inheritance**: Later clauses without an explicit subject automatically inherit the previously named soldier.
- **Movement Queueing**: If multiple movement orders are issued to the **same** soldier in a single utterance, the second move is automatically **queued** to execute after the first completes:
  - `"Alpha move south then go up a bit"` (walks south first, then steps upward).
  - Moves issued to *different* soldiers execute concurrently without delay.
- **Compound Directions**: Natural phrases like `"up and right"` or `"down and left"` are parsed as single diagonal movement vectors rather than chained command splits.

---

## 📋 Command Cheat Sheet

| Category | Example Spoken Phrases | Action & Behavior |
|---|---|---|
| **Select Soldier** | `"Alpha"`, `"Bravo"`, `"Select four"`, `"Switch to Charlie"`, `"Two"` | Selects the corresponding squad member. |
| **Cycle Soldier** | `"Next"`, `"Cycle"`, `"Switch"` | Cycles forward to the next living squad member. |
| **Drive Forward / Back** | `"Alpha forward"`, `"Advance"`, `"Keep going"`, `"Alpha backward"`, `"Fall back"`, `"Bravo forward 5"`, `"Back 3"` | Walks along the soldier's heading until a wall or `"stop"` (or N tiles). Backing up keeps facing forward. |
| **Turn** | `"Alpha left 30"`, `"Bravo right forty five"`, `"Turn left"`, `"A bit right"`, `"Turn around"` | Turns relative to the soldier (default 90°, `"a bit"` = 30°). Bends a walk in progress; a standing soldier turns on the spot. |
| **Turn and Walk** | `"Go left"`, `"Go right 20"`, `"Alpha left 30 and forward"` | Turns, then walks forward along the new heading. |
| **Move on Screen** | `"Alpha move up"`, `"North"`, `"Go east"`, `"Bravo go up and right"` | Moves in that compass screen direction (default ~9 tiles / 288px). |
| **Distance Modifiers** | `"... a bit"`, `"step back"`, `"... slightly"` · `"... all the way"`, `"... far"` | Short step (~3 tiles / 96px) · Maximum step until wall contact (~2000px). |
| **Halt / Stop** | `"Stop"`, `"Halt"`, `"Hold"`, `"Alpha hold position"`, `"Squad freeze"` | Immediately cancels paths and stops all movement. |
| **Aim / Watch Angle** | `"Watch left"`, `"Bravo face up"`, `"Cover right"`, `"Squad look down"` | Locks firing cone towards that direction. Retains facing while moving. |
| **Cast Fireball** | `"Fireball"`, `"Fireball right"`, `"Cast fireball up"` | Every ready Fireball caster blasts 180px from itself, in the spoken screen direction or straight ahead (clamped to 320px). Walls block; friendly fire enabled. |
| **Cast Abilities by Name** | `"Fog"`, `"Scan"`, `"Rush"`, `"Outrage"`, `"Flash"`, `"Break magic"`, `"Invisible"` | Every living soldier with the ability equipped and enough MP casts it at once (one shared cooldown). |
| **Cast Abilities by Slot** | `"Spell one"`, `"Ability two"`, `"Slot three"`, `"Cast E"`, `"Cast W"`, `"Third spell"` | Looks up the spell in slot **W / E / R** of the named or selected soldier, then casts it squad-wide like the name. |
| **Targeted Spell Slots** | `"Spell two right"`, `"Bravo second spell left"`, `"Cast E up"` | Targets and casts the slotted spell towards that direction. |
| **Match Flow** | `"Deploy"`, `"Join game"`, `"Rematch"`, `"Play again"`, `"One more"` | Deploys into the lobby or votes for a rematch post-game. |

---

## 🧭 Directions, Steering & Distance

### Steering (relative to the soldier)
For driving soldiers across the map, `forward` / `back` / `left` / `right` are relative to where **the soldier** is currently facing, like steering a character in vehicle mode:

| Spoken | Effect |
|---|---|
| `forward`, `ahead`, `advance`, `push`, `straight`, `keep going`, `continue` | Walk along heading until a wall or `"stop"`. Add a number for tiles: `"forward 5"`. |
| `back`, `backward`, `back up`, `reverse`, `retreat`, `fall back` | Walk backwards while still facing forward (covering the retreat). |
| `left 30`, `right forty five`, `turn left` | Turn by that many degrees (default 90°, `"a bit left"` = 30°). While walking, bends the path; while standing, turns on the spot. |
| `go left`, `go right 20` | Turn, then walk forward. |
| `turn around`, `about face`, `one eighty` | Turn 180°. |

Soldiers face the enemy when the match starts, so the first `"forward"` heads toward the opponent.

### Compass Directions (screen-relative)
Compass words are **screen-relative** and identical for both players:

| Spoken Direction | Screen Heading | Tactical Meaning |
|---|---|---|
| `up`, `north`, `top`, `upper`, `upward` | ↑ | North / Top of screen |
| `down`, `south`, `bottom`, `lower`, `downward` | ↓ | South / Bottom of screen |
| `east` | → | East / Towards enemy side |
| `west` | ← | West / Towards your home side |
| `northeast`, `northwest`, `southeast`, `southwest` | ↗, ↖, ↘, ↙ | Diagonals |
| `up and right`, `down and left`, etc. | ↗, ↙ | Combined directional phrasing |

`left` / `right` only mean screen sides when combined with another compass word (`"up and right"`) or when watching (`"watch left"`); on their own they steer the soldier.

### Stepping Distances
- **Default Step**: ~9 tiles ($288\text{ px}$). The soldier walks in the chosen direction and halts at obstacles.
- **Short Step** (`"a bit"`, `"a little"`, `"slightly"`, `"step"`, `"inch"`): ~3 tiles ($96\text{ px}$).
- **Full / Max Distance** (`"all the way"`, `"far"`, `"full"`, `"until the wall"`, `"max"`): Moves up to $2000\text{ px}$, stopping only when colliding with walls.

---

## 🎧 Feedback: What You See

### 1. In-Game Voice HUD Panel (Bottom-Right)
Active whenever the microphone is enabled:
- **Header State**: Displays real-time recognizer health:
  - `LISTENING`: Active and waiting for speech.
  - `HEARING YOU`: Audio detected; displays live animated volume bars.
  - `PAUSED (BACKGROUND TAB)`: Microphone relinquished because tab lost focus.
  - `MIC IN OTHER TAB`: Another local tab has claimed the audio device.
  - `MIC BLOCKED` / `NO MICROPHONE`: Permission or hardware issue.
- **Live Interim Line** (Yellow): Displays words being recognized incrementally in real time.
- **Utterance History**: Shows the last 4 utterances, their recognized action tags (e.g. `> BRAVO MOVE LEFT + BRAVO WATCH UP`), and elapsed age. Fades out after 9 seconds. Unrecognized phrases show `not a command`.

### 2. Tactical Map Overlay
- **Pings**: A tactical green circle appears at order destinations and spell targets.
- **Movement Trails**: Dashed visual trajectories render for all moving soldiers, indicating active navigation paths.
- **Sound Feedback**: A crisp tactical radio chirp plays whenever a voice order is recognized and issued.

---

## 🧪 Multi-Tab Testing & Troubleshooting

When developing locally with two tabs (Blue vs Red):

| Symptom | Cause | Solution |
|---|---|---|
| Panel displays `mic in other tab` | Another tab holds the localStorage mutex. | Click the **Mic ON/OFF** button in the current tab to claim mic focus immediately. |
| Panel displays `paused (background tab)` | The browser tab is hidden or minimized. | Click into the tab or bring it to the foreground; recognition will resume within 250ms. |
| Panel displays `mic blocked` | Browser denied microphone permission. | Click the lock/tune icon in the browser address bar, set Microphone to **Allow**, and reload. |
| Commands not recognized on Firefox | Firefox lacks Web Speech API support. | Use Google Chrome, Microsoft Edge, or Safari. Use keyboard fallbacks (`W`, `E`, `R`, `1`-`4`) on Firefox. |
| Console error `aborted` | Rapid browser microphone recreation. | The voice system automatically applies exponential backoff and locks to stabilize Chrome. |

### Inspecting Recognition in DevTools
Press `F12` or `Cmd+Option+I` to view the browser console. The built-in `[TSD Voice]` logger outputs:
```text
[TSD Voice] recognition active in tab 4k7a9x, session 1
[TSD Voice] audio/speech detected!
[TSD Voice] heard: bravo go left (final=false)
[TSD Voice] heard: bravo go left and watch right (final=true)
```

---

## 💡 Tips for Reliable Recognition

1. **Keep Commands Concise**: Short phrases recognize faster and with higher accuracy: `"Bravo advance"` or `"Alpha forward 5"`.
2. **Headset Recommendations**: Built-in laptop microphones often capture game sound effects or echo. A headset mic provides the best speech recognition.
3. **Interim Execution**: Single-stage directional movements execute as soon as the speech stream stabilizes for $0.4\text{ seconds}$—you do not have to wait for the browser to finalize the sentence. Untargeted spell orders like `"fireball"` wait briefly for a direction before defaulting forward, and a bare turn like `"alpha left"` waits for the end of the sentence in case a number follows (`"alpha left 30"` fires immediately).

---

## 💻 Developer Guide

### Architecture & Source Files
- [`scripts/config.gd`](file:///Users/cyrill/hackathon-game/scripts/config.gd): Vocabulary dictionaries:
  - `VOICE_SUBJECTS` & `VOICE_SUBJECT_NUMBERS`: Soldier mappings (`Alpha` through `Delta`, `Squad`, numbers `1`-`4`).
  - `VOICE_DIRECTIONS` & `VOICE_DIRECTION_VECTORS`: Screen-space directional mappings.
  - `VOICE_STEER`, `VOICE_TURN_DEFAULT`, `VOICE_TURN_SHORT`, `VOICE_NUMBER_WORDS`: Soldier-relative steering (`forward`, `back`, `left 30`, `turn around`).
  - `VOICE_PHRASES`: Ability names and phonetic mishearings.
  - `VOICE_SPELL_NOUNS` & `VOICE_SPELL_SLOTS`: Slotted spell triggers (`W`, `E`, `R`).
  - `VOICE_ACTIONS`: Command verbs (`watch`, `halt`, `deploy`, `rematch`, etc.).
- [`scripts/client/voice.gd`](file:///Users/cyrill/hackathon-game/scripts/client/voice.gd):
  - JavaScript Web Speech bridge (`JS_SETUP`) with localStorage tab mutex and visibility awareness.
  - Dynamic result queueing, interim stability timer (`INTERIM_STABLE_S = 0.4`), and grammar parser (`parse_utterance`, `parse_voice`).
- [`scripts/client/client_game.gd`](file:///Users/cyrill/hackathon-game/scripts/client/client_game.gd):
  - `_on_voice_command`: Maps parsed voice payloads into game server RPCs (`c_unit_move`, `c_unit_face`, `c_unit_stop`, `c_ability_dir`). Voice spells use `c_ability_dir`, so each caster aims from its own position.
  - Handles squad formation spreading and queued path generation.

### Running Headless Parser Tests
Verify all grammar rules, phonetic aliases, spell slot bindings, and directional steering without opening a Godot window:

```bash
# Locate Godot via the project helper:
GODOT=$(bash -c 'source tools/godot_path.sh; find_godot')

# Run the test suite:
$GODOT --headless --path . --script res://tests/test_voice_parser.gd
```
*(If `godot` is already in your system PATH, simply run `godot --headless --path . --script res://tests/test_voice_parser.gd`)*.

### Simulating Speech in Browser DevTools
Simulate speech inputs directly inside the browser console without a microphone:
```javascript
window.tsdVoice.queue.push({
  key: 'test:1',
  alts: ['charlie go left and watch right'],
  final: true
});
```

### In-Engine Debug Injection
In Godot GDScript or during automated bot matches:
```gdscript
# Directly inject spoken text:
Voice.inject("bravo go left")

# Or run client with the --say flag:
godot --path . -- --auto --name=Blue "--say=bravo go left;squad watch right;fireball"
```
