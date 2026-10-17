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
	return minf(smoothstep(0.0, 0.55, elapsed), smoothstep(0.0, 0.75, game.deployment))


func _draw() -> void:
	if map == null:
		return
	var t := float(Cfg.TILE)
	var panel := 3.0 * t
	var slide := panel * door_open_amount()
	var blue_y: float = map.MAIN_BOTTOM * t
	_draw_door_panel(Rect2(2 * t - slide, blue_y, panel, 8), Cfg.TEAM_COLORS[0], true)
	_draw_door_panel(Rect2(5 * t + slide, blue_y, panel, 8), Cfg.TEAM_COLORS[0], true)
	var red_x := (Cfg.MAP_W - 1) * t
	_draw_door_panel(Rect2(red_x, 2 * t - slide, 8, panel), Cfg.TEAM_COLORS[1], false)
	_draw_door_panel(Rect2(red_x, 5 * t + slide, 8, panel), Cfg.TEAM_COLORS[1], false)


func _draw_door_panel(r: Rect2, team_color: Color, horizontal: bool) -> void:
	draw_rect(r, Color("202936"))
	draw_rect(r.grow(-2), Color("394758"))
	draw_rect(r.grow(-2), Color(team_color, 0.65), false, 1.5)
	if horizontal:
		draw_line(r.position + Vector2(5, r.size.y * 0.5), r.end - Vector2(5, r.size.y * 0.5), Color(0.78, 0.84, 0.9, 0.5), 1.0)
	else:
		draw_line(r.position + Vector2(r.size.x * 0.5, 5), r.end - Vector2(r.size.x * 0.5, 5), Color(0.78, 0.84, 0.9, 0.5), 1.0)
