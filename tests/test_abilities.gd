extends Node
## Focused server-side checks for the expanded ability set.

const Cfg = preload("res://scripts/config.gd")
const ServerGame = preload("res://scripts/server/server_game.gd")

var failed := 0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  [PASS] ", label)
	else:
		failed += 1
		print("  [FAIL] ", label)


func _ready() -> void:
	var game = ServerGame.new()
	game.peers = [101, 202]
	game._reset_squads()
	game.state = Cfg.State.PLAYING
	var every_ability := (1 << Cfg.ABILITY_COUNT) - 1
	game.loadouts = [[every_ability, every_ability, every_ability, every_ability], [every_ability, every_ability, every_ability, every_ability]]
	var target := Cfg.WORLD_SIZE * 0.5

	game.on_ability(101, Cfg.Ability.OUTRAGE, target, false)
	_check(game.squads[0][0].outrage_t == 2.0, "Outrage lasts two seconds")
	_check(game._damage_after_defense(game.squads[0][0], 50) == 40, "Outrage reduces received damage by 20 percent")

	for soldier in game.squads[0]:
		soldier.mp = Cfg.SOLDIER_MP
	game.on_ability(101, Cfg.Ability.FLASH, target, false)
	_check(game.squads[0][0].dash_invulnerable and game.squads[0][0].dash_duration == 0.1, "Flash is a 0.1 second invulnerable dash")
	_check(game._damage_after_defense(game.squads[0][0], 50) == 0, "Flash blocks incoming damage")

	for soldier in game.squads[0]:
		soldier.mp = Cfg.SOLDIER_MP
	game.on_ability(101, Cfg.Ability.BREAK_MAGIC, target, false)
	_check(game.squads[0][0].stick_mode and game.squads[0][0].stick_burst_t == 3.0, "F*** Magic enters stick mode with a three second damage burst")
	game.cooldowns[0][Cfg.Ability.BREAK_MAGIC] = 0.0
	for soldier in game.squads[0]:
		soldier.mp = Cfg.SOLDIER_MP
	var return_caster = game.squads[0][0]
	var return_target = game.squads[1][0]
	return_caster.pos = game.map.spawn_position(0, 0)
	return_caster.facing = game.map.spawn_facing(0)
	return_target.alive = true
	return_target.hp = Cfg.SOLDIER_HP
	return_target.pos = return_caster.pos + Vector2.from_angle(return_caster.facing) * 50.0
	for enemy_idx in range(1, Cfg.SQUAD_SIZE):
		game.squads[1][enemy_idx].alive = false
	var facing_before_return: float = return_caster.facing
	game.on_ability(101, Cfg.Ability.BREAK_MAGIC, target, false)
	_check(not game.squads[0][0].stick_mode and game.squads[0][0].wand_boost_t == 3.0, "F*** Magic recast returns to an empowered wand")
	_check(is_equal_approx(game.squads[0][0].facing, facing_before_return), "F*** Magic backward jump preserves facing")
	_check(return_target.hp == 0.0, "F*** Magic return projectile deals five times full-shot damage")
	_check(game.events[0].any(func(ev): return ev[0] == "mega_shot" and ev[5] == 170), "F*** Magic broadcasts the giant projectile")

	for soldier in game.squads[0]:
		soldier.mp = Cfg.SOLDIER_MP
	game.cooldowns[0][Cfg.Ability.FIREBALL] = 0.0
	var caster = game.squads[0][0]
	var ally = game.squads[0][1]
	var enemy = game.squads[1][0]
	enemy.alive = true
	enemy.hp = Cfg.SOLDIER_HP
	for soldier in game.squads[0]:
		soldier.dash_t = 0.0
		soldier.dash_invulnerable = false
	caster.pos = game.map.spawn_position(0, 0)
	ally.pos = caster.pos
	enemy.pos = caster.pos
	var ally_hp: float = ally.hp
	var enemy_hp: float = enemy.hp
	game.on_ability(101, Cfg.Ability.FIREBALL, enemy.pos, false)
	_check(ally.hp < ally_hp and enemy.hp < enemy_hp, "Fireball damages allies and enemies inside its visible blast")
	_check(game.events[0].any(func(ev): return ev[0] == "fireball"), "Fireball broadcasts its blast effect")

	for soldier in game.squads[0]:
		soldier.mp = Cfg.SOLDIER_MP
		soldier.alive = true
		soldier.hp = Cfg.SOLDIER_HP
	game.cooldowns[0][Cfg.Ability.INVISIBLE] = 0.0
	game.on_ability(101, Cfg.Ability.INVISIBLE, target, false)
	_check(game.squads[0][0].invisible_t == 5.0, "Invisible lasts five seconds")
	game.squads[1][1].alive = true
	game.squads[1][1].hp = Cfg.SOLDIER_HP
	game._apply_damage(game.squads[0][0], game.squads[1][1], 1)
	_check(game.squads[0][0].invisible_t == 0.0, "Dealing damage cancels invisibility")

	# Voice cast: every ready member with the spell casts, each aiming from itself.
	game._reset_squads()
	game.state = Cfg.State.PLAYING
	var fireball_bit := 1 << Cfg.Ability.FIREBALL
	game.loadouts[0] = [fireball_bit, 1 << Cfg.Ability.SCAN, fireball_bit, fireball_bit]
	game.squads[0][3].mp = 10.0
	for team in 2:
		game.events[team].clear()
	game.on_ability_dir(101, Cfg.Ability.FIREBALL, Vector2.ZERO)
	var blasts: Array = game.events[0].filter(func(ev): return ev[0] == "fireball")
	var squad = game.squads[0]
	var ahead_of := func(s) -> bool:
		var requested: Vector2 = s.pos + Vector2.from_angle(s.facing) * Cfg.VOICE_CAST_DISTANCE
		var expected: Vector2 = game._ability_target(s, requested, float(Cfg.ABILITIES[Cfg.Ability.FIREBALL]["cast_range"]))
		return blasts.any(func(ev): return ev[1].distance_to(expected) < 1.0)
	_check(blasts.size() == 2 and ahead_of.call(squad[0]) and ahead_of.call(squad[2]),
		"Voice Fireball: each equipped caster blasts straight ahead of itself")
	_check(squad[0].mp < Cfg.SOLDIER_MP and squad[2].mp < Cfg.SOLDIER_MP and squad[1].mp == Cfg.SOLDIER_MP \
		and squad[3].mp == 10.0, "Voice Fireball: only equipped members with enough MP pay")

	# Voice turns are slower than mouse turns so spoken turns stay visible.
	var turner = game.squads[0][1]
	turner.facing = 0.0
	game.on_unit_face(101, 1, turner.pos + Vector2.from_angle(deg_to_rad(120.0)) * 100.0)
	game._update_facing_only(0.1)
	var voice_step := rad_to_deg(turner.facing)
	turner.facing = 0.0
	game.selected[0] = 1
	game.on_face(101, turner.pos + Vector2.from_angle(deg_to_rad(120.0)) * 100.0)
	game._update_facing_only(0.1)
	_check(is_equal_approx(voice_step, 30.0) and is_equal_approx(rad_to_deg(turner.facing), 54.0),
		"Voice turns rotate at 300 deg/s, mouse turns at 540 deg/s")

	print("\nAbility test results: %d failed." % failed)
	game.free()
	get_tree().quit(1 if failed > 0 else 0)
