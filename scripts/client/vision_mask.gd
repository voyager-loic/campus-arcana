extends Node2D
## Draws the combined vision area of the local squad in white on black.
## Rendered inside a (half resolution) SubViewport; the fog shader darkens
## everything that is black in this mask.
## NOTE: this is purely cosmetic. Which enemies you can see is decided by the
## server - hidden enemies are never sent to the client.

const Cfg = preload("res://scripts/config.gd")

var game  # ClientGame
var reveal_all := false


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Cfg.WORLD_SIZE), Color.BLACK)
	if game == null:
		return
	if reveal_all:
		draw_rect(Rect2(Vector2.ZERO, Cfg.WORLD_SIZE), Color.WHITE)
		return
	var fogs: Array = game.fog_list()
	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	var cone_step := deg_to_rad(maxf(1.5, game.cone_step_deg * 0.25))
	var circle_segments := maxi(16, roundi(36.0 * sqrt(game.effect_density)))
	for o in game.own:
		if not o["alive"]:
			continue
		var origin: Vector2 = o["disp"]
		var facing: float = o["disp_facing"]
		# Cone
		var half := Cfg.VIEW_CONE * 0.5
		var steps := int(ceil(Cfg.VIEW_CONE / cone_step))
		_add_fan(points, indices, origin, facing - half, Cfg.VIEW_CONE, steps, Cfg.VIEW_RANGE, fogs)
		# Close-range awareness circle
		_add_fan(points, indices, origin, 0.0, TAU, circle_segments, Cfg.AWARE_RADIUS, fogs)
	if points.is_empty():
		return
	var colors := PackedColorArray()
	colors.resize(points.size())
	colors.fill(Color.WHITE)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors)


func _add_fan(points: PackedVector2Array, indices: PackedInt32Array, origin: Vector2, start: float,
		span: float, steps: int, radius: float, fogs: Array) -> void:
	var base := points.size()
	points.append(origin)
	for i in steps + 1:
		var a := start + span * float(i) / steps
		var d := Vector2.from_angle(a)
		var dist: float = game.map.sight_distance(origin, d, radius, fogs)
		points.append(origin + d * dist)
	for i in steps:
		indices.append(base)
		indices.append(base + 1 + i)
		indices.append(base + 2 + i)
