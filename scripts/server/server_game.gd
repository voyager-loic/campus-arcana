extends Node
## Dedicated authoritative game server.
## Simulates movement, visibility, shooting, damage and abilities, and sends
## each player a snapshot containing ONLY what their squad can currently see.

const Cfg = preload("res://scripts/config.gd")
const MapData = preload("res://scripts/map_data.gd")

const FLAG_MOVING := 1
const FLAG_OUTRAGE := 2
const FLAG_RUSH := 4
const FLAG_ALIVE := 8
const FLAG_INVISIBLE := 16
const FLAG_STICK := 32
const FLAG_FLASH := 64
const FLAG_WAND_BOOST := 128


class Soldier:
	var team := 0
	var idx := 0
	var weapon := 0
	var pos := Vector2.ZERO
	var facing := 0.0
	var watch_angle := 0.0
	var facing_lock := false
	var voice_turn := false  # last order came by voice: turn at VOICE_TURN_SPEED
	var hp: float = Cfg.SOLDIER_HP
	var mp: float = Cfg.SOLDIER_MP
	var health_regen_wait := 0.0
	var alive := true
	var path := PackedVector2Array()
	var moving := false
	var last_moved := -100.0
	var fire_cd := 0.0
	var target := -1
	var acquire := 0.0
	var rush_t := 0.0
	var outrage_t := 0.0
	var invisible_t := 0.0
	var stick_mode := false
	var stick_burst_t := 0.0
	var wand_boost_t := 0.0
	var dash_t := 0.0
	var dash_duration := 0.0
	var dash_from := Vector2.ZERO
	var dash_to := Vector2.ZERO
	var dash_invulnerable := false


var map := MapData.new()
var peers := [0, 0]          # peer id per slot (0 = empty)
var names := ["", ""]
var squads := [[], []]       # Array[Soldier] per team
var selected := [0, 0]
var cooldowns := [[], []]
var fogs := []               # {pos, radius, t}
var scans := []              # {team, origin, t}
var events := [[], []]       # per team, flushed with every snapshot
var vis_table := [[false, false, false, false], [false, false, false, false]]  # vis_table[team][enemy idx]
var rematch_votes := [false, false]
var loadouts := [Cfg.DEFAULT_LOADOUTS.duplicate(), Cfg.DEFAULT_LOADOUTS.duplicate()]
var loadout_ready := [false, false]
var state := Cfg.State.WAITING
var deployment := 0.0
var countdown := 0.0
var winner := -1
var time := 0.0
var rng := RandomNumberGenerator.new()


func start(port: int, cert := "", key := "") -> void:
	Net.server = self
	var err := Net.host(port, cert, key)
	if err != OK:
		push_error("Server failed to listen on port %d (error %d)" % [port, err])
		get_tree().quit(1)
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	rng.randomize()
	_reset_squads()
	print("[server] Tactical Squad Duel server listening on port %d%s" % [port, " (TLS)" if cert != "" else ""])


# --------------------------------------------------------------------------
# Connections
# --------------------------------------------------------------------------

func _slot_of(peer_id: int) -> int:
	return peers.find(peer_id)


func _kick(id: int) -> void:
	if Net.peer:
		Net.peer.disconnect_peer(id)


func _on_peer_connected(id: int) -> void:
	var slot := peers.find(0)
	if slot == -1:
		print("[server] peer %d rejected: server full" % id)
		Net.s_reject.rpc_id(id, "Server is full (a match is already running).")
		get_tree().create_timer(0.5).timeout.connect(_kick.bind(id))
		return
	peers[slot] = id
	names[slot] = "Player %d" % (slot + 1)
	print("[server] peer %d joined as slot %d" % [id, slot])
	Net.s_welcome.rpc_id(id, slot)
	if state == Cfg.State.WAITING:
		_begin_loadout()


func _on_peer_disconnected(id: int) -> void:
	var slot := _slot_of(id)
	if slot == -1:
		return
	print("[server] slot %d (peer %d) left" % [slot, id])
	peers[slot] = 0
	names[slot] = ""
	state = Cfg.State.WAITING
	loadout_ready = [false, false]
	_reset_squads()
	var other := 1 - slot
	if peers[other] != 0:
		events[other].append(["msg", "Opponent left. Waiting for a new opponent..."])


func on_hello(id: int, player_name: String) -> void:
	var slot := _slot_of(id)
	if slot == -1:
		return
	player_name = player_name.strip_edges().left(16)
	if player_name == "":
		player_name = "Player %d" % (slot + 1)
	names[slot] = player_name


# --------------------------------------------------------------------------
# Match flow
# --------------------------------------------------------------------------

func _begin_loadout() -> void:
	_reset_squads()
	loadout_ready = [false, false]
	state = Cfg.State.LOADOUT
	for t in 2:
		if peers[t] != 0:
			events[t].append(["msg", "Choose three abilities for every squad member."])


func _ability_count(mask: int) -> int:
	var count := 0
	for ability in Cfg.ABILITY_COUNT:
		if mask & (1 << ability):
			count += 1
	return count


func on_loadout(id: int, ability_masks: Array) -> void:
	var slot := _slot_of(id)
	if slot == -1 or state != Cfg.State.LOADOUT or ability_masks.size() != Cfg.SQUAD_SIZE:
		return
	var validated := []
	for raw_mask in ability_masks:
		var mask := int(raw_mask)
		if mask < 0 or mask >= (1 << Cfg.ABILITY_COUNT) or _ability_count(mask) != 3:
			events[slot].append(["msg", "Every character needs exactly three abilities."])
			return
		validated.append(mask)
	loadouts[slot] = validated
	loadout_ready[slot] = true
	events[slot].append(["msg", "Loadout locked in."])
	if peers[0] != 0 and peers[1] != 0 and loadout_ready[0] and loadout_ready[1]:
		_start_match()

func _reset_squads() -> void:
	map.reset_breakables()
	for team in 2:
		squads[team] = []
		for i in Cfg.SQUAD_SIZE:
			var s := Soldier.new()
			s.team = team
			s.idx = i
			s.weapon = Cfg.SQUAD_WEAPONS[i]
			s.pos = map.spawn_position(team, i)
			s.facing = map.spawn_facing(team)
			s.watch_angle = s.facing
			squads[team].append(s)
		cooldowns[team].resize(Cfg.ABILITY_COUNT)
		cooldowns[team].fill(0.0)
		selected[team] = 0
	fogs.clear()
	scans.clear()
	vis_table = [[false, false, false, false], [false, false, false, false]]
	rematch_votes = [false, false]
	winner = -1


func _start_match() -> void:
	_reset_squads()
	map.set_doors_closed(false)
	for team in 2:
		for s: Soldier in squads[team]:
			var destination := map.spawn_position(team, s.idx)
			s.pos = map.entry_position(team, s.idx)
			s.path = map.find_path(s.pos, destination)
			s.facing = map.spawn_facing(team)
			s.watch_angle = s.facing
	state = Cfg.State.DEPLOYMENT
	deployment = Cfg.DEPLOYMENT_DURATION
	countdown = Cfg.COUNTDOWN
	for t in 2:
		events[t].append(["msg", "Squads entering the arena!"])


func on_rematch(id: int) -> void:
	var slot := _slot_of(id)
	if slot == -1 or state != Cfg.State.ENDED:
		return
	rematch_votes[slot] = true
	if rematch_votes[0] and rematch_votes[1]:
		_begin_loadout()
	else:
		events[1 - slot].append(["msg", "Opponent wants a rematch! Press Enter."])


# --------------------------------------------------------------------------
# Commands (validated)
# --------------------------------------------------------------------------

func _valid_vec(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y) and v.x > -100.0 and v.y > -100.0 \
		and v.x < Cfg.WORLD_SIZE.x + 100.0 and v.y < Cfg.WORLD_SIZE.y + 100.0


func _selected_soldier(slot: int) -> Soldier:
	var s: Soldier = squads[slot][selected[slot]]
	return s if s.alive else null


func on_select(id: int, idx: int) -> void:
	var slot := _slot_of(id)
	if slot == -1 or idx < 0 or idx >= Cfg.SQUAD_SIZE:
		return
	if not squads[slot][idx].alive:
		return
	if idx != selected[slot] and not Cfg.CONTINUE_MOVE_WHEN_DESELECTED:
		var prev: Soldier = squads[slot][selected[slot]]
		prev.path.clear()
	selected[slot] = idx


func _unit(slot: int, idx: int) -> Soldier:
	if slot == -1 or idx < 0 or idx >= Cfg.SQUAD_SIZE:
		return null
	var s: Soldier = squads[slot][idx]
	return s if s.alive else null


func _order_move(s: Soldier, target: Vector2, keep_facing: bool) -> void:
	if s == null or state != Cfg.State.PLAYING or not _valid_vec(target):
		return
	s.path = map.find_path(s.pos, target)
	if not keep_facing:
		s.facing_lock = false


func _order_face(s: Soldier, target: Vector2) -> void:
	if s == null or not _valid_vec(target) or target.distance_to(s.pos) < 2.0:
		return
	if state != Cfg.State.PLAYING and state != Cfg.State.COUNTDOWN:
		return
	s.watch_angle = (target - s.pos).angle()
	s.facing_lock = true


func on_move(id: int, target: Vector2, keep_facing: bool) -> void:
	var slot := _slot_of(id)
	if slot != -1:
		_order_move(_set_voice_turn(_selected_soldier(slot), false), target, keep_facing)


func on_face(id: int, target: Vector2) -> void:
	var slot := _slot_of(id)
	if slot != -1:
		_order_face(_set_voice_turn(_selected_soldier(slot), false), target)


func on_unit_move(id: int, idx: int, target: Vector2, queue: bool) -> void:
	var s := _set_voice_turn(_unit(_slot_of(id), idx), true)
	if queue and s != null and not s.path.is_empty() and state == Cfg.State.PLAYING and _valid_vec(target):
		s.path.append_array(map.find_path(s.path[s.path.size() - 1], target))
		return
	_order_move(s, target, false)


func on_unit_face(id: int, idx: int, target: Vector2) -> void:
	_order_face(_set_voice_turn(_unit(_slot_of(id), idx), true), target)


## Unit-addressed orders come from voice; mouse orders go to the selected soldier.
func _set_voice_turn(s: Soldier, voice: bool) -> Soldier:
	if s != null:
		s.voice_turn = voice
	return s


func _turn_speed(s: Soldier) -> float:
	return Cfg.VOICE_TURN_SPEED if s.voice_turn else Cfg.TURN_SPEED


func on_unit_stop(id: int, idx: int) -> void:
	var s := _unit(_slot_of(id), idx)
	if s != null:
		s.path.clear()


func on_ability(id: int, ability: int, target: Vector2, via_voice: bool) -> void:
	if _valid_vec(target):
		_cast_ability(_slot_of(id), ability, func(_s: Soldier) -> Vector2: return target, via_voice)


## Voice casts: every caster aims from its own position, along the world
## direction `dir` or, if it is zero, the way that caster is facing.
func on_ability_dir(id: int, ability: int, dir: Vector2) -> void:
	if not is_finite(dir.x) or not is_finite(dir.y):
		return
	_cast_ability(_slot_of(id), ability, func(s: Soldier) -> Vector2:
		var d := dir.normalized() if dir.length() > 0.01 else Vector2.from_angle(s.facing)
		return s.pos + d * Cfg.VOICE_CAST_DISTANCE, true)


## Every living squad member with the ability equipped and enough MP casts it.
## target_of(soldier) gives each caster's aim point (only Fireball aims).
func _cast_ability(slot: int, ability: int, target_of: Callable, via_voice: bool) -> void:
	if slot == -1 or not Cfg.ABILITIES.has(ability):
		return
	var def: Dictionary = Cfg.ABILITIES[ability]
	if state != Cfg.State.PLAYING:
		events[slot].append(["deny", ability, "not now"])
		return
	if cooldowns[slot][ability] > 0.0:
		events[slot].append(["deny", ability, "cooling down %.1fs" % cooldowns[slot][ability]])
		return
	var casters: Array[Soldier] = []
	var equipped_alive := 0
	var mp_cost: float = def["mp_cost"]
	for s: Soldier in squads[slot]:
		if not s.alive or (int(loadouts[slot][s.idx]) & (1 << ability)) == 0:
			continue
		equipped_alive += 1
		if s.mp >= mp_cost:
			casters.append(s)
	if casters.is_empty():
		var reason := "no living character has this ability" if equipped_alive == 0 else "MP is recharging"
		events[slot].append(["deny", ability, reason])
		return
	match ability:
		Cfg.Ability.FOG:
			for s: Soldier in casters:
				var cast_target := _fog_landing(s, float(def["throw_distance"]))
				fogs.append({"pos": cast_target, "radius": def["radius"], "t": def["duration"]})
		Cfg.Ability.SCAN:
			for s: Soldier in casters:
				scans.append({"team": slot, "origin": s.pos, "t": def["duration"]})
				var count := 0
				for e in squads[1 - slot]:
					if _scan_reveals(e, s.pos):
						count += 1
				events[slot].append(["scan", s.pos, def["radius"], count])
		Cfg.Ability.RUSH:
			for s: Soldier in casters:
				s.rush_t = def["duration"]
		Cfg.Ability.OUTRAGE:
			for s: Soldier in casters:
				s.outrage_t = def["duration"]
		Cfg.Ability.FLASH:
			for s: Soldier in casters:
				_start_dash(s, Vector2.from_angle(s.facing), float(def["distance"]), float(def["duration"]), true)
		Cfg.Ability.BREAK_MAGIC:
			for s: Soldier in casters:
				if s.stick_mode:
					_cast_return_projectile(s)
					s.stick_mode = false
					s.stick_burst_t = 0.0
					s.wand_boost_t = float(def["burst_duration"])
					_start_dash(s, Vector2.from_angle(s.facing + PI), float(def["return_distance"]), float(def["return_duration"]), true, false)
				else:
					s.stick_mode = true
					s.stick_burst_t = float(def["burst_duration"])
					s.wand_boost_t = 0.0
					_start_dash(s, Vector2.from_angle(s.facing), float(def["dash_distance"]), float(def["dash_duration"]), false)
		Cfg.Ability.FIREBALL:
			for s: Soldier in casters:
				var center := _ability_target(s, target_of.call(s), float(def["cast_range"]))
				_cast_fireball(s, center, def)
		Cfg.Ability.INVISIBLE:
			for s: Soldier in casters:
				s.invisible_t = def["duration"]
	for s: Soldier in casters:
		s.mp = maxf(0.0, s.mp - mp_cost)
	cooldowns[slot][ability] = float(def["cooldown"])
	events[slot].append(["ability", ability, casters[0].idx, via_voice, casters.size()])
	print("[server] slot %d used %s with %d caster(s)%s" % [slot, def["name"], casters.size(), " (voice)" if via_voice else ""])


func _fog_landing(s: Soldier, throw_distance: float) -> Vector2:
	var direction := Vector2.from_angle(s.facing)
	var open_distance := map.raycast(s.pos, direction, throw_distance)
	# Keep the landing point out of the wall. When cover is directly in front,
	# this collapses to zero and the fog is dropped at the caster's feet.
	var wall_clearance := Cfg.SOLDIER_RADIUS + 2.0
	var landing_distance := throw_distance
	if open_distance < throw_distance - 0.01:
		landing_distance = maxf(0.0, open_distance - wall_clearance)
	return s.pos + direction * landing_distance


func _start_dash(s: Soldier, direction: Vector2, distance: float, duration: float, invulnerable: bool, turn_to_dash := true) -> void:
	var d := direction.normalized()
	var side := d.orthogonal() * (Cfg.SOLDIER_RADIUS + 1.0)
	var open_distance := distance
	for offset in [Vector2.ZERO, side, -side]:
		open_distance = minf(open_distance, map.raycast(s.pos + offset, d, distance))
	if open_distance < distance - 0.01:
		open_distance = maxf(0.0, open_distance - Cfg.SOLDIER_RADIUS - 2.0)
	s.path.clear()
	s.dash_from = s.pos
	s.dash_to = s.pos + d * open_distance
	s.dash_duration = maxf(duration, 0.01)
	s.dash_t = s.dash_duration
	s.dash_invulnerable = invulnerable
	if turn_to_dash:
		s.facing = d.angle()
		s.watch_angle = s.facing


func _ability_target(s: Soldier, requested: Vector2, max_range: float) -> Vector2:
	var diff := requested - s.pos
	if diff.length() < 0.01:
		diff = Vector2.from_angle(s.facing)
	var distance := minf(diff.length(), max_range)
	var direction := diff.normalized()
	var open_distance := map.raycast(s.pos, direction, distance)
	if open_distance < distance - 0.01:
		distance = maxf(0.0, open_distance - 4.0)
	return s.pos + direction * distance


func _cast_return_projectile(caster: Soldier) -> void:
	var ability: Dictionary = Cfg.ABILITIES[Cfg.Ability.BREAK_MAGIC]
	var weapon: Dictionary = Cfg.WEAPONS[caster.weapon]
	var direction := Vector2.from_angle(caster.facing)
	var max_range: float = float(weapon["range"]) * float(ability["wand_range_mult"])
	var wall_distance := map.raycast(caster.pos, direction, max_range)
	var projectile_radius: float = float(ability["return_projectile_radius"])
	var victim: Soldier = null
	var hit_distance := wall_distance
	for enemy: Soldier in squads[1 - caster.team]:
		if not enemy.alive:
			continue
		var offset := enemy.pos - caster.pos
		var along := offset.dot(direction)
		if along <= 0.0 or along > hit_distance:
			continue
		if absf(direction.cross(offset)) > projectile_radius + Cfg.SOLDIER_RADIUS:
			continue
		if not map.has_los(caster.pos, enemy.pos, []):
			continue
		victim = enemy
		hit_distance = along
	var start := caster.pos + direction * (Cfg.SOLDIER_RADIUS + 4.0)
	var endpoint := caster.pos + direction * wall_distance
	# The return projectile stops at cover, but collapses designated cracked
	# tables so the next shot and subsequent movement can pass through.
	var broken := map.damage_breakable_at(endpoint + direction * 1.5, 999)
	_broadcast_breakable_destruction(broken)
	var damage := 0
	if victim != null:
		endpoint = victim.pos
		var full_shot_damage := int(weapon["damage"]) * int(weapon["pellets"])
		damage = _damage_after_defense(victim, roundi(full_shot_damage * float(ability["return_projectile_damage_mult"])))
	var projectile_event := ["mega_shot", caster.team, caster.idx, start, endpoint, damage]
	events[caster.team].append(projectile_event)
	if victim != null:
		if vis_table[victim.team][caster.idx]:
			events[victim.team].append(projectile_event)
		else:
			var incoming_angle := (caster.pos - victim.pos).angle() + rng.randf_range(-0.12, 0.12)
			events[victim.team].append(["incoming", victim.idx, incoming_angle, damage])
		if damage > 0:
			_apply_damage(caster, victim, damage)


func _cast_fireball(caster: Soldier, center: Vector2, def: Dictionary) -> void:
	for team in 2:
		events[team].append(["fireball", center, float(def["radius"]), caster.team])
	_broadcast_breakable_destruction(map.damage_breakables(center, float(def["radius"]), int(def["damage"])))
	for team in 2:
		for victim: Soldier in squads[team]:
			if not victim.alive or victim.pos.distance_to(center) > float(def["radius"]):
				continue
			if not map.has_los(center, victim.pos, []):
				continue
			var push_dir := (victim.pos - center).normalized()
			if push_dir == Vector2.ZERO:
				push_dir = Vector2.from_angle(caster.facing)
			var push_distance := minf(float(def["knockback"]), map.raycast(victim.pos, push_dir, float(def["knockback"])))
			if push_distance < float(def["knockback"]) - 0.01:
				push_distance = maxf(0.0, push_distance - Cfg.SOLDIER_RADIUS - 2.0)
			victim.pos = map.resolve_circle(victim.pos + push_dir * push_distance, Cfg.SOLDIER_RADIUS)
			var damage := _damage_after_defense(victim, int(def["damage"]))
			if damage > 0:
				_apply_damage(caster, victim, damage)


func _broadcast_breakable_destruction(destroyed: Array) -> void:
	for record in destroyed:
		for team in 2:
			events[team].append(["breakable", record[0], record[1], record[2]])


func _damage_after_defense(victim: Soldier, raw_damage: int) -> int:
	if victim.dash_t > 0.0 and victim.dash_invulnerable:
		return 0
	var damage := float(raw_damage)
	if victim.outrage_t > 0.0:
		damage *= float(Cfg.ABILITIES[Cfg.Ability.OUTRAGE]["damage_taken_mult"])
	return maxi(0, roundi(damage))


func _apply_damage(attacker: Soldier, victim: Soldier, damage: int) -> void:
	if damage <= 0 or not victim.alive:
		return
	events[victim.team].append(["card_hit", victim.idx, damage])
	var actual_damage := minf(float(damage), victim.hp)
	if attacker.team != victim.team:
		attacker.mp = minf(Cfg.SOLDIER_MP, attacker.mp + actual_damage * Cfg.MP_RESTORE_PER_DAMAGE)
	attacker.invisible_t = 0.0
	victim.hp -= damage
	victim.health_regen_wait = Cfg.HEALTH_REGEN_DELAY
	if victim.hp <= 0:
		victim.hp = 0
		victim.alive = false
		victim.path.clear()
		for t in 2:
			events[t].append(["kill", victim.team, victim.idx, victim.pos, attacker.team, attacker.idx])
		if selected[victim.team] == victim.idx:
			_auto_select(victim.team)


func _scan_reveals(e: Soldier, origin: Vector2) -> bool:
	return e.alive and e.invisible_t <= 0.0 and e.pos.distance_to(origin) <= Cfg.ABILITIES[Cfg.Ability.SCAN]["radius"] \
		and time - e.last_moved <= Cfg.SCAN_MOVE_MEMORY


# --------------------------------------------------------------------------
# Simulation
# --------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if Net.server != self:
		return
	time += dt
	match state:
		Cfg.State.DEPLOYMENT:
			deployment -= dt
			# Give both entrance doors time to finish opening before the squads
			# cross the threshold and spread into their starting formation.
			if Cfg.DEPLOYMENT_DURATION - deployment >= 0.55:
				for team in 2:
					for s: Soldier in squads[team]:
						_move_soldier(s, dt)
			if deployment <= 0.0:
				deployment = 0.0
				for team in 2:
					for s: Soldier in squads[team]:
						s.pos = map.spawn_position(team, s.idx)
						s.path.clear()
						s.facing = map.spawn_facing(team)
						s.watch_angle = s.facing
				map.set_doors_closed(true)
				state = Cfg.State.COUNTDOWN
				countdown = Cfg.COUNTDOWN
				for t in 2:
					events[t].append(["msg", "Get ready!"])
		Cfg.State.COUNTDOWN:
			countdown -= dt
			_update_facing_only(dt)
			if countdown <= 0.0:
				state = Cfg.State.PLAYING
				for t in 2:
					events[t].append(["msg", "FIGHT!"])
		Cfg.State.PLAYING:
			_simulate(dt)
	_compute_visibility()
	_broadcast()


func _fog_list() -> Array:
	var out := []
	for fog in fogs:
		out.append([fog["pos"], fog["radius"]])
	return out


func _update_facing_only(dt: float) -> void:
	for team in 2:
		for s in squads[team]:
			if s.facing_lock:
				s.facing = rotate_toward(s.facing, s.watch_angle, _turn_speed(s) * dt)


func _simulate(dt: float) -> void:
	for t in 2:
		for a in Cfg.ABILITY_COUNT:
			cooldowns[t][a] = maxf(0.0, cooldowns[t][a] - dt)
	for i in range(fogs.size() - 1, -1, -1):
		fogs[i]["t"] -= dt
		if fogs[i]["t"] <= 0.0:
			fogs.remove_at(i)
	for i in range(scans.size() - 1, -1, -1):
		scans[i]["t"] -= dt
		if scans[i]["t"] <= 0.0:
			scans.remove_at(i)

	var all: Array = squads[0] + squads[1]
	for s: Soldier in all:
		if not s.alive:
			continue
		_advance_regeneration(s, dt)
		s.mp = minf(Cfg.SOLDIER_MP, s.mp + Cfg.SOLDIER_MP / Cfg.MP_RECOVERY_TIME * dt)
		s.rush_t = maxf(0.0, s.rush_t - dt)
		s.outrage_t = maxf(0.0, s.outrage_t - dt)
		s.invisible_t = maxf(0.0, s.invisible_t - dt)
		s.stick_burst_t = maxf(0.0, s.stick_burst_t - dt)
		s.wand_boost_t = maxf(0.0, s.wand_boost_t - dt)
		_move_soldier(s, dt)

	# Soldier separation
	for i in all.size():
		var a: Soldier = all[i]
		if not a.alive:
			continue
		for j in range(i + 1, all.size()):
			var b: Soldier = all[j]
			if not b.alive:
				continue
			var diff := b.pos - a.pos
			var d := diff.length()
			var min_d := Cfg.SOLDIER_RADIUS * 2.0
			if d < min_d:
				var n := diff / d if d > 0.001 else Vector2.RIGHT
				var push := (min_d - d) * 0.5
				a.pos -= n * push
				b.pos += n * push
	for s: Soldier in all:
		if s.alive:
			s.pos = map.resolve_circle(s.pos, Cfg.SOLDIER_RADIUS)

	_compute_visibility()
	var fog_list := _fog_list()
	for s: Soldier in all:
		if s.alive:
			_shoot(s, dt, fog_list)
	_check_victory()


func _advance_regeneration(s: Soldier, dt: float) -> void:
	var regen_delta := maxf(0.0, dt - s.health_regen_wait)
	s.health_regen_wait = maxf(0.0, s.health_regen_wait - dt)
	if regen_delta > 0.0 and s.hp < Cfg.SOLDIER_HP:
		s.hp = minf(Cfg.SOLDIER_HP, s.hp + Cfg.HEALTH_REGEN_RATE * regen_delta)


func _move_soldier(s: Soldier, dt: float) -> void:
	if s.dash_t > 0.0:
		s.dash_t = maxf(0.0, s.dash_t - dt)
		var progress := 1.0 - s.dash_t / s.dash_duration
		s.pos = s.dash_from.lerp(s.dash_to, clampf(progress, 0.0, 1.0))
		s.moving = true
		s.last_moved = time
		if s.dash_t <= 0.0:
			s.pos = map.resolve_circle(s.dash_to, Cfg.SOLDIER_RADIUS)
			s.dash_invulnerable = false
		return
	var desired := s.watch_angle if s.facing_lock else s.facing
	s.moving = false
	if not s.path.is_empty():
		while s.path.size() >= 2 and map.clear_walk(s.pos, s.path[1], Cfg.SOLDIER_RADIUS):
			s.path.remove_at(0)
		var tgt: Vector2 = s.path[0]
		var diff := tgt - s.pos
		var dist := diff.length()
		var speed := Cfg.MOVE_SPEED
		if s.rush_t > 0.0:
			speed *= Cfg.ABILITIES[Cfg.Ability.RUSH]["speed_mult"]
		if s.stick_mode:
			speed *= Cfg.ABILITIES[Cfg.Ability.BREAK_MAGIC]["stick_speed_mult"]
		if s.invisible_t > 0.0:
			speed *= Cfg.ABILITIES[Cfg.Ability.INVISIBLE]["speed_mult"]
		var step := speed * dt
		if dist > 0.01:
			var dir_angle := diff.angle()
			if not s.facing_lock:
				desired = dir_angle
				s.watch_angle = dir_angle
		if dist <= step:
			s.pos = tgt
			s.path.remove_at(0)
		else:
			s.pos += diff / dist * step
		s.moving = true
		s.last_moved = time
	s.facing = rotate_toward(s.facing, desired, _turn_speed(s) * dt)


func _compute_visibility() -> void:
	var fog_list := _fog_list()
	for team in 2:
		var enemies: Array = squads[1 - team]
		for e: Soldier in enemies:
			var seen := false
			if e.alive and e.invisible_t <= 0.0:
				for s: Soldier in squads[team]:
					if s.alive and map.can_see(s.pos, s.facing, e.pos, fog_list):
						seen = true
						break
			vis_table[team][e.idx] = seen


func _shoot(s: Soldier, dt: float, fog_list: Array) -> void:
	s.fire_cd = maxf(0.0, s.fire_cd - dt)
	var w: Dictionary = Cfg.WEAPONS[s.weapon]
	var cone := Cfg.weapon_cone(s.weapon)
	var rng_max: float = w["range"]
	if s.stick_mode:
		rng_max *= float(Cfg.ABILITIES[Cfg.Ability.BREAK_MAGIC]["stick_range_mult"])
	elif s.wand_boost_t > 0.0:
		rng_max *= float(Cfg.ABILITIES[Cfg.Ability.BREAK_MAGIC]["wand_range_mult"])
	var best: Soldier = null
	var best_d := INF
	for e: Soldier in squads[1 - s.team]:
		if not e.alive or e.invisible_t > 0.0:
			continue
		var diff := e.pos - s.pos
		var d := diff.length()
		if d > rng_max + Cfg.SOLDIER_RADIUS:
			continue
		if d > Cfg.SOLDIER_RADIUS * 2.0 and absf(angle_difference(s.facing, diff.angle())) > cone * 0.5:
			continue
		if not map.has_los(s.pos, e.pos, fog_list):
			continue
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		s.target = -1
		s.acquire = 0.0
		return
	if best.idx != s.target:
		s.target = best.idx
		s.acquire = Cfg.REACTION_TIME
	if s.acquire > 0.0:
		s.acquire -= dt
		return
	if s.fire_cd > 0.0:
		return

	var interval: float = w["interval"]
	var acc: float = w["accuracy"]
	if s.outrage_t > 0.0:
		interval /= float(Cfg.ABILITIES[Cfg.Ability.OUTRAGE]["rate_mult"])
	if s.wand_boost_t > 0.0:
		interval /= float(Cfg.ABILITIES[Cfg.Ability.BREAK_MAGIC]["wand_rate_mult"])
	if s.moving:
		acc *= 0.8
	acc *= 1.0 - 0.35 * clampf(best_d / rng_max, 0.0, 1.0)
	s.fire_cd = interval

	var dmg := 0
	var ends := []
	var dir := (best.pos - s.pos).normalized()
	var perp := Vector2(-dir.y, dir.x)
	for _p in int(w["pellets"]):
		if rng.randf() < acc:
			dmg += int(w["damage"])
			ends.append(best.pos + perp * rng.randf_range(-5.0, 5.0))
		else:
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			ends.append(best.pos + perp * side * rng.randf_range(14.0, 30.0) + dir * rng.randf_range(0.0, 60.0))
	if s.stick_mode and s.stick_burst_t > 0.0:
		dmg = roundi(float(dmg) * float(Cfg.ABILITIES[Cfg.Ability.BREAK_MAGIC]["stick_damage_mult"]))
	dmg = _damage_after_defense(best, dmg)
	var muzzle := s.pos + Vector2.from_angle(s.facing) * (Cfg.SOLDIER_RADIUS + 4.0)
	var shot_ev := ["shot", s.team, s.idx, muzzle, ends, dmg]
	events[s.team].append(shot_ev)
	if vis_table[best.team][s.idx]:
		events[best.team].append(shot_ev)
	else:
		# Hidden shooter: only reveal the rough direction of incoming fire.
		var ang := (s.pos - best.pos).angle() + rng.randf_range(-0.25, 0.25)
		events[best.team].append(["incoming", best.idx, ang, dmg])

	if dmg > 0:
		_apply_damage(s, best, dmg)


func _auto_select(team: int) -> void:
	for i in Cfg.SQUAD_SIZE:
		var j: int = (selected[team] + 1 + i) % Cfg.SQUAD_SIZE
		if squads[team][j].alive:
			selected[team] = j
			return


func _check_victory() -> void:
	var alive := [0, 0]
	for t in 2:
		for s: Soldier in squads[t]:
			if s.alive:
				alive[t] += 1
	if alive[0] > 0 and alive[1] > 0:
		return
	state = Cfg.State.ENDED
	if alive[0] == 0 and alive[1] == 0:
		winner = -1
	else:
		winner = 0 if alive[0] > 0 else 1
	print("[server] match ended, winner: %d" % winner)


# --------------------------------------------------------------------------
# Snapshots
# --------------------------------------------------------------------------

func _flags(s: Soldier) -> int:
	var f := 0
	if s.moving: f |= FLAG_MOVING
	if s.outrage_t > 0.0: f |= FLAG_OUTRAGE
	if s.rush_t > 0.0: f |= FLAG_RUSH
	if s.alive: f |= FLAG_ALIVE
	if s.invisible_t > 0.0: f |= FLAG_INVISIBLE
	if s.stick_mode: f |= FLAG_STICK
	if s.dash_t > 0.0: f |= FLAG_FLASH
	if s.wand_boost_t > 0.0: f |= FLAG_WAND_BOOST
	return f


func _broadcast() -> void:
	var fog_data := []
	for fog in fogs:
		fog_data.append([fog["pos"], fog["radius"], fog["t"]])
	for team in 2:
		var pid: int = peers[team]
		if pid == 0:
			events[team].clear()
			continue
		var own := []
		for s: Soldier in squads[team]:
			var tgt: Vector2 = s.path[s.path.size() - 1] if not s.path.is_empty() else s.pos
			own.append([s.idx, s.pos, s.facing, s.hp, _flags(s), tgt, s.watch_angle if s.facing_lock else INF, s.mp])
		var en := []
		var scanned := []
		var enemy_alive := []
		for e: Soldier in squads[1 - team]:
			enemy_alive.append(e.alive)
			# Show both formations during the cinematic border entry.
			if vis_table[team][e.idx] or state == Cfg.State.DEPLOYMENT or state == Cfg.State.COUNTDOWN or (state == Cfg.State.ENDED and e.alive):
				en.append([e.idx, e.pos, e.facing, e.hp, _flags(e)])
			elif e.alive:
				for sc in scans:
					if sc["team"] == team and _scan_reveals(e, sc["origin"]):
						scanned.append([e.idx, e.pos])
						break
		var snap := {
			"st": state,
			"dp": deployment,
			"ct": countdown,
			"win": winner,
			"sel": selected[team],
			"own": own,
			"en": en,
			"sc": scanned,
			"ea": enemy_alive,
			"fg": fog_data,
			"br": map.breakable_state(),
			"cd": cooldowns[team].duplicate(),
			"ev": events[team],
			"rm": rematch_votes.duplicate(),
			"names": names.duplicate(),
			"lo": loadouts[team].duplicate(),
			"rd": loadout_ready.duplicate(),
			"conn": [peers[0] != 0, peers[1] != 0],
		}
		events[team] = []
		Net.s_snapshot.rpc_id(pid, snap)
