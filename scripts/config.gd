extends RefCounted
## Shared game constants (used by both the authoritative server and the client).
## Access via: const Cfg = preload("res://scripts/config.gd")

const DEFAULT_PORT := 9080
const MAX_PLAYERS := 2
const SQUAD_SIZE := 4
## Increment whenever the multiplayer RPC or snapshot format becomes
## incompatible. Mismatched builds are rejected with an actionable message.
const PROTOCOL_VERSION := 1
const CONNECTION_TIMEOUT := 8.0
const SNAPSHOT_TIMEOUT := 6.0
const SERVER_HELLO_TIMEOUT := 8.0
const SNAPSHOT_RATE := 20.0

const TILE := 32
const MAP_W := 80
const MAP_H := 71
const WORLD_SIZE := Vector2(MAP_W * TILE, MAP_H * TILE)

# --- Soldiers -------------------------------------------------------------
const SOLDIER_RADIUS := 11.0
const SOLDIER_HP := 100
const SOLDIER_MP := 100.0
const MP_RECOVERY_TIME := 16.0
const MP_RESTORE_PER_DAMAGE := 0.35
const HEALTH_REGEN_DELAY := 10.0
const HEALTH_REGEN_RATE := 5.0
const MOVE_SPEED := 120.0              # px / s
const TURN_SPEED := deg_to_rad(540.0)  # rad / s
const VOICE_TURN_SPEED := deg_to_rad(300.0)  # after a voice order, so spoken turns are visible
## If true, a soldier that was moving keeps walking to its destination after the
## player switches to another soldier. If false it stops immediately.
const CONTINUE_MOVE_WHEN_DESELECTED := true

# --- Vision ---------------------------------------------------------------
const VIEW_RANGE := 420.0
const VIEW_CONE := deg_to_rad(120.0)   # full angle
const AWARE_RADIUS := 64.0             # 360 degree "hearing" radius
const FOG_SEE_DEPTH := 22.0            # how far you can see into a fog cloud

# --- Weapons --------------------------------------------------------------
enum Weapon { RIFLE, SMG, SHOTGUN }
const WEAPONS := {
	Weapon.RIFLE: {"name": "Arc Bolt", "range": 400.0, "cone": 18.0, "interval": 0.60, "damage": 34, "pellets": 1, "accuracy": 0.92},
	Weapon.SMG: {"name": "Volley", "range": 290.0, "cone": 44.0, "interval": 0.13, "damage": 8, "pellets": 1, "accuracy": 0.72},
	Weapon.SHOTGUN: {"name": "Prism", "range": 175.0, "cone": 66.0, "interval": 0.90, "damage": 10, "pellets": 6, "accuracy": 0.62},
}
## Weapon of each squad slot (same for both teams).
const SQUAD_WEAPONS := [Weapon.RIFLE, Weapon.SMG, Weapon.SHOTGUN, Weapon.RIFLE]
const REACTION_TIME := 0.22  # delay before a soldier opens fire on a newly acquired target

# --- Abilities ------------------------------------------------------------
enum Ability { FOG, SCAN, RUSH, OUTRAGE, FLASH, BREAK_MAGIC, FIREBALL, INVISIBLE }
const ABILITY_COUNT := 8
const ABILITIES := {
	Ability.FOG: {"name": "Fog", "description": "Creates a vision-blocking fog cloud in front of each caster.", "mp_cost": 50.0, "cooldown": 10.0, "duration": 9.0, "radius": 74.0, "throw_distance": 96.0},
	Ability.SCAN: {"name": "Scan", "description": "Reveals recently moving enemies near each caster.", "mp_cost": 35.0, "cooldown": 7.0, "duration": 2.5, "radius": 460.0},
	Ability.RUSH: {"name": "Rush", "description": "Increases movement speed by 65% for 4 seconds.", "mp_cost": 45.0, "cooldown": 9.0, "duration": 4.0, "speed_mult": 1.65},
	Ability.OUTRAGE: {"name": "Outrage", "description": "Doubles attack speed and reduces damage taken by 20% for 2 seconds.", "mp_cost": 60.0, "cooldown": 12.0, "duration": 2.0, "rate_mult": 2.0, "damage_taken_mult": 0.8},
	Ability.FLASH: {"name": "Flash", "description": "Blinks forward in 0.1 seconds and grants invulnerability during the blink.", "mp_cost": 45.0, "cooldown": 8.0, "duration": 0.1, "distance": 150.0},
	Ability.BREAK_MAGIC: {"name": "F*** Magic", "description": "First cast: dash into stick stance (+25% speed, -80% range, +200% damage for 3s). Recast: fire a huge 5x-damage projectile, jump backward, and return to the wand.", "mp_cost": 55.0, "cooldown": 8.0, "dash_duration": 0.12, "dash_distance": 105.0, "return_duration": 0.2, "return_distance": 120.0, "stick_speed_mult": 1.25, "stick_range_mult": 0.2, "stick_damage_mult": 3.0, "burst_duration": 3.0, "wand_rate_mult": 1.5, "wand_range_mult": 1.35, "return_projectile_damage_mult": 5.0, "return_projectile_radius": 18.0},
	Ability.FIREBALL: {"name": "Fireball", "description": "Blasts the selected area for damage and knockback. Walls block it; friendly fire is enabled.", "mp_cost": 70.0, "cooldown": 13.0, "cast_range": 320.0, "radius": 78.0, "damage": 42, "knockback": 76.0},
	Ability.INVISIBLE: {"name": "Invisible", "description": "Become invisible and move 50% faster for 5 seconds. Dealing damage ends the effect.", "mp_cost": 65.0, "cooldown": 16.0, "duration": 5.0, "speed_mult": 1.5},
}
## Three equipped abilities per squad member. Bit N corresponds to Ability N.
const DEFAULT_LOADOUTS := [67, 28, 97, 134]
const ABILITY_SLOT_KEYS := ["W", "E", "R"]
## Spoken phrases that trigger each ability (lower-case, matched as whole words /
## word sequences). Includes a few common speech-recognition mishearings.
const VOICE_PHRASES := {
	Ability.FOG: ["fog", "fog magic", "cast fog", "summon fog", "mist", "cast mist", "smoke", "frog", "fogg"],
	Ability.SCAN: ["scan", "scans", "scanning", "scanner", "radar", "ping", "sonar", "pulse", "scam"],
	Ability.RUSH: ["rush", "rushing", "russia", "brush", "sprint", "dash", "boost", "go go"],
	Ability.OUTRAGE: ["outrage", "rage", "enrage", "fury", "berserk"],
	Ability.FLASH: ["flash", "blink", "flash forward", "flesh", "teleport"],
	# Chrome's profanity filter delivers "f***", which normalizes to "f".
	Ability.BREAK_MAGIC: ["break magic", "f magic", "fuck magic", "fucking magic", "freaking magic", "frick magic",
		"stick mode", "wand mode", "switch weapon"],
	Ability.FIREBALL: ["fireball", "fire ball", "fireballs", "fire bowl", "cast fireball"],
	Ability.INVISIBLE: ["invisible", "invisibility", "vanish", "cloak", "stealth"],
}
## How far ahead of each caster a voice-cast Fireball is aimed (clamped to cast_range).
const VOICE_CAST_DISTANCE := 180.0
## Equipped spell slots in W / E / R order: noun + number / key ("spell two",
## "cast E") or ordinal before or after the noun ("second spell", "spell third").
const VOICE_SPELL_NOUNS := ["spell", "ability", "skill", "slot", "cast", "use"]
const VOICE_SPELL_SLOTS := [
	{"ordinal": ["first"], "number": ["one", "1", "won", "w", "double u", "double you"]},
	{"ordinal": ["second"], "number": ["two", "2", "to", "too", "e"]},
	{"ordinal": ["third"], "number": ["three", "3", "tree", "r"]},
]

# --- Voice command vocabulary ------------------------------------------------
# Grammar: [who] [action] [where]. Every list is matched on whole words and the
# longest phrase wins, so "kitchen door" beats "kitchen" and "play again" beats "play".

const VOICE_SUBJECTS := {
	0: ["alpha", "alfa", "alpher", "rifle", "sniper"],
	1: ["bravo", "brava", "bravos", "smg", "s m g", "gunner"],
	2: ["charlie", "charley", "charly", "shotgun", "shot gun", "breacher"],
	3: ["delta", "delter", "marksman"],
	-1: ["squad", "everyone", "everybody", "team", "all units", "all"],
}
## Number words only count as a soldier when they open the command ("two, go left")
## because recognisers constantly write "to" as "two" / "2".
const VOICE_SUBJECT_NUMBERS := {
	0: ["one", "1", "first"],
	1: ["two", "2", "second"],
	2: ["three", "3", "third"],
	3: ["four", "4", "fourth"],
}

## Screen-relative directions (x = right / towards the enemy, y = down).
## Both players see their base on the left, so these mean the same for both teams.
## On their own, "left" / "right" steer the soldier (VOICE_STEER); they only mean
## the screen sides next to another compass word ("up and right") or for watching.
const VOICE_DIRECTIONS := {
	"n": ["north", "up", "upward", "upwards", "top", "upper"],
	"s": ["south", "down", "downward", "downwards", "bottom", "lower"],
	"e": ["east", "right"],
	"w": ["west", "left"],
	"ne": ["northeast"],
	"nw": ["northwest"],
	"se": ["southeast"],
	"sw": ["southwest"],
}
const VOICE_DIRECTION_VECTORS := {
	"n": Vector2(0, -1), "s": Vector2(0, 1), "e": Vector2(1, 0), "w": Vector2(-1, 0),
	"ne": Vector2(1, -1), "nw": Vector2(-1, -1), "se": Vector2(1, 1), "sw": Vector2(-1, 1),
}
## How far a direction order walks (px). Soldiers stop early at walls.
const VOICE_STEP := 288.0
const VOICE_STEP_SHORT := 96.0
const VOICE_STEP_FAR := 2000.0

## Steering relative to where the soldier is facing, for driving soldiers across
## a big map: "alpha forward", "alpha left 30", "bravo back 5", "turn around".
## Forward / backward walk until a wall (or N tiles), a turn without a number is
## 90 degrees, and a turn while walking bends the walk.
const VOICE_STEER := {
	"forward": ["forward", "forwards", "ahead", "advance", "push", "front", "onward", "straight", "go straight",
		"keep going", "go on", "continue", "carry on"],
	"backward": ["backward", "backwards", "back", "back up", "reverse", "retreat", "fall back", "rear", "behind"],
	"left": ["left"],
	"right": ["right"],
	"around": ["turn around", "about face", "u turn", "one eighty", "180"],
	"go": ["go", "move", "walk", "run", "head"],
}
const VOICE_TURN_DEFAULT := 90.0
const VOICE_TURN_SHORT := 30.0
const VOICE_NUMBER_WORDS := {
	"zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
	"nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
	"sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30,
	"forty": 40, "fourty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
	"hundred": 100,
}

const VOICE_ACTIONS := {
	"watch": ["watch", "look", "face", "aim", "cover", "check", "guard", "eyes on", "point"],
	"halt": ["stop", "halt", "hold", "hold position", "freeze", "stay", "wait", "stand still", "cancel"],
	"next": ["next", "cycle", "switch"],
	"select": ["select", "switch to", "unit", "soldier", "number"],
	"short": ["a bit", "a little", "little", "bit", "slightly", "step", "inch"],
	"far": ["far", "all the way", "full", "until the wall", "max"],
	"deploy": ["deploy", "join game", "start game", "lets go", "let s go"],
	"rematch": ["rematch", "play again", "new match", "new game", "one more"],
}
## Recently moved enemies are what "Scan" reveals.
const SCAN_MOVE_MEMORY := 1.5

# --- Match ----------------------------------------------------------------
const COUNTDOWN := 3.0
const DEPLOYMENT_DURATION := 5.0
const DEPLOYMENT_DOOR_OPEN_TIME := 0.65
const DEPLOYMENT_UNIT_STAGGER := 0.12
const DEPLOYMENT_DOOR_CLOSE_TIME := 0.55

enum State { WAITING, LOADOUT, DEPLOYMENT, COUNTDOWN, PLAYING, ENDED }

const TEAM_COLORS := [Color(0.30, 0.65, 1.0), Color(1.0, 0.38, 0.32)]
const TEAM_NAMES := ["Blue", "Red"]


static func weapon_cone(weapon: int) -> float:
	return deg_to_rad(WEAPONS[weapon]["cone"])
