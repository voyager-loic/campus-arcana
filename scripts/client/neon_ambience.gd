extends Node2D
## Lightweight, purely visual arena ambience. It deliberately uses batched
## CanvasItem drawing instead of Light2D nodes, so the effect remains usable on
## integrated GPUs and in the web build.

const Cfg = preload("res://scripts/config.gd")

var effects_enabled := true
var quality := 2
var reduced_flashes := false
var map
var _phase := 0.0
var _redraw_accumulator := 0.0

const CYAN := Color("43d9ff")
const VIOLET := Color("ad6cff")
const MAGENTA := Color("ff4fc8")

const STRIPS := [
	[Vector2(2.0, 42.45), Vector2(8.0, 42.45), CYAN],
	[Vector2(79.45, 2.0), Vector2(79.45, 8.0), MAGENTA],
	[Vector2(27.55, 47.0), Vector2(27.55, 58.0), VIOLET],
	[Vector2(78.45, 48.0), Vector2(78.45, 65.0), CYAN],
	[Vector2(33.0, 69.45), Vector2(48.0, 69.45), VIOLET],
	[Vector2(57.0, 69.45), Vector2(72.0, 69.45), MAGENTA],
]

const RUNES := [
	[Vector2(39.5, 17.0), CYAN],
	[Vector2(53.0, 27.5), VIOLET],
	[Vector2(67.0, 35.5), MAGENTA],
	[Vector2(35.0, 53.0), CYAN],
	[Vector2(68.0, 58.0), VIOLET],
]


func _ready() -> void:
	z_index = 2
	queue_redraw()


func configure(enabled: bool, graphics_quality: int, reduce_flashes: bool) -> void:
	effects_enabled = enabled
	quality = clampi(graphics_quality, 0, 2)
	reduced_flashes = reduce_flashes
	visible = effects_enabled
	set_process(effects_enabled)
	queue_redraw()


func _process(delta: float) -> void:
	if not effects_enabled:
		return
	_phase = fmod(_phase + delta, TAU * 8.0)
	_redraw_accumulator += delta
	var refresh_rate: float = [8.0, 14.0, 22.0][quality]
	if _redraw_accumulator >= 1.0 / refresh_rate:
		_redraw_accumulator = 0.0
		queue_redraw()


func _draw() -> void:
	if not effects_enabled:
		return
	var tile := float(Cfg.TILE)
	var pulse_strength := 0.10 if reduced_flashes else 0.20
	var pulse := 0.82 + sin(_phase * 1.7) * pulse_strength
	var strips := STRIPS
	var runes := RUNES
	if map != null and map.map_id == "hg_e":
		strips = [
			[Vector2(81, 114), Vector2(87, 114), CYAN],
			[Vector2(81, 23), Vector2(87, 23), MAGENTA],
			[Vector2(77.5, 56), Vector2(77.5, 66), VIOLET],
			[Vector2(93.5, 76), Vector2(93.5, 86), CYAN],
			[Vector2(34, 100), Vector2(48, 100), VIOLET],
			[Vector2(116, 44), Vector2(130, 44), MAGENTA],
		]
		runes = [[Vector2(84, 60), CYAN], [Vector2(84, 85), VIOLET], [Vector2(57, 66), MAGENTA], [Vector2(111, 94), CYAN], [Vector2(84, 35), VIOLET]]

	# Thin architectural strips give the entrances and service room a readable
	# identity without changing collision or obscuring the floor plan.
	for strip in strips:
		var a: Vector2 = strip[0] * tile
		var b: Vector2 = strip[1] * tile
		var color: Color = strip[2]
		draw_line(a, b, Color(color, 0.055 * pulse), 18.0, true)
		draw_line(a, b, Color(color, 0.15 * pulse), 7.0, true)
		draw_line(a, b, Color(color, 0.82 * pulse), 2.0, true)
		draw_circle(a, 4.0, Color(color, 0.75 * pulse))
		draw_circle(b, 4.0, Color(color, 0.75 * pulse))

	# Broken warding circles mark useful navigation landmarks. Their restrained
	# alpha keeps them legible under fog without competing with units.
	var rune_count: int = [2, 4, runes.size()][quality]
	for i in rune_count:
		var center: Vector2 = runes[i][0] * tile
		var color: Color = runes[i][1]
		_draw_rune(center, 15.0 + float(i % 2) * 4.0, color, pulse, i)

	# A handful of deterministic motes supplies motion without particle nodes.
	var mote_count: int = [5, 10, 17][quality]
	for i in mote_count:
		var base := Vector2(
			(7.0 + fmod(float(i * 19), 66.0)) * tile,
			(5.0 + fmod(float(i * 13), 60.0)) * tile
		)
		var orbit: Vector2 = Vector2(cos(_phase * (0.38 + i * 0.01) + i), sin(_phase * 0.31 + i * 1.7)) * (5.0 + i % 4)
		if map != null and map.map_id == "hg_e":
			base = Vector2(57.0 + (i * 7) % 54, 45.0 + (i * 11) % 55) * tile
			if map.is_wall_at(base + orbit):
				continue
		var color := CYAN if i % 3 == 0 else (VIOLET if i % 3 == 1 else MAGENTA)
		var mote_alpha := 0.24 if reduced_flashes else 0.36
		draw_circle(base + orbit, 4.5, Color(color, mote_alpha * pulse))
		draw_circle(base + orbit, 1.4, Color(color, 0.85))


func _draw_rune(center: Vector2, radius: float, color: Color, pulse: float, seed: int) -> void:
	draw_arc(center, radius + 7.0, -2.8 + seed * 0.2, 1.7 + seed * 0.2, 18, Color(color, 0.09 * pulse), 10.0, true)
	draw_arc(center, radius, -2.8 + seed * 0.2, 1.7 + seed * 0.2, 18, Color(color, 0.62 * pulse), 2.0, true)
	for spoke in 3:
		var angle := _phase * 0.16 + float(spoke) * TAU / 3.0 + seed
		var inner := center + Vector2.from_angle(angle) * (radius - 5.0)
		var outer := center + Vector2.from_angle(angle) * (radius + 3.0)
		draw_line(inner, outer, Color(color, 0.48 * pulse), 1.5, true)
