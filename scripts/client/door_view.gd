extends Node2D
## Lightweight animated entrance overlay. Keeping the moving door leaves out of
## MapView lets the large, detailed arena remain cached during deployment.

const Cfg = preload("res://scripts/config.gd")

var map
var game


func door_open_amount() -> float:
	if game == null or game.state != Cfg.State.DEPLOYMENT:
		return 0.0
	var elapsed: float = Cfg.DEPLOYMENT_DURATION - game.deployment
	return minf(
		smoothstep(0.0, Cfg.DEPLOYMENT_DOOR_OPEN_TIME, elapsed),
		smoothstep(0.0, Cfg.DEPLOYMENT_DOOR_CLOSE_TIME, game.deployment)
	)


func _draw() -> void:
	if map == null:
		return
	var t := float(Cfg.TILE)
	var panel := 3.0 * t
	var open := door_open_amount()
	var slide := panel * open
	var blue_y: float = map.MAIN_BOTTOM * t
	_draw_threshold(Rect2(2 * t, blue_y - 5, 6 * t, 18), Cfg.TEAM_COLORS[0], true, open)
	_draw_door_panel(Rect2(2 * t - slide, blue_y, panel, 8), Cfg.TEAM_COLORS[0], true)
	_draw_door_panel(Rect2(5 * t + slide, blue_y, panel, 8), Cfg.TEAM_COLORS[0], true)
	var red_x := (Cfg.MAP_W - 1) * t
	_draw_threshold(Rect2(red_x - 5, 2 * t, 18, 6 * t), Cfg.TEAM_COLORS[1], false, open)
	_draw_door_panel(Rect2(red_x, 2 * t - slide, 8, panel), Cfg.TEAM_COLORS[1], false)
	_draw_door_panel(Rect2(red_x, 5 * t + slide, 8, panel), Cfg.TEAM_COLORS[1], false)


func _draw_threshold(r: Rect2, team_color: Color, horizontal: bool, open: float) -> void:
	var pulse: float = 0.55 + 0.45 * sin(float(game.time) * 8.0)
	draw_rect(r, Color(0.03, 0.05, 0.08, 0.72))
	draw_rect(r.grow(-3), Color(team_color, (0.06 + 0.10 * pulse) * open))
	if horizontal:
		draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), Color(team_color, 0.45), 2.0)
		for i in 5:
			var light := Vector2(r.position.x + (i + 1) * r.size.x / 6.0, r.position.y + 2.0)
			draw_circle(light, 2.2, Color(team_color, 0.35 + 0.45 * pulse))
	else:
		draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y), Color(team_color, 0.45), 2.0)
		for i in 5:
			var light := Vector2(r.position.x + 2.0, r.position.y + (i + 1) * r.size.y / 6.0)
			draw_circle(light, 2.2, Color(team_color, 0.35 + 0.45 * pulse))


func _draw_door_panel(r: Rect2, team_color: Color, horizontal: bool) -> void:
	draw_rect(r.grow(3), Color(0, 0, 0, 0.32))
	draw_rect(r, Color("202936"))
	draw_rect(r.grow(-2), Color("394758"))
	draw_rect(r.grow(-2), Color(team_color, 0.65), false, 1.5)
	if horizontal:
		draw_line(r.position + Vector2(5, r.size.y * 0.5), r.end - Vector2(5, r.size.y * 0.5), Color(0.78, 0.84, 0.9, 0.5), 1.0)
	else:
		draw_line(r.position + Vector2(r.size.x * 0.5, 5), r.end - Vector2(r.size.x * 0.5, 5), Color(0.78, 0.84, 0.9, 0.5), 1.0)
