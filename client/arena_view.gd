extends Node2D
class_name ArenaView

## Draws the arena straight from its collision shapes, so what you see is exactly what
## the raycast hits. No art assets, no second source of truth to drift out of sync.

const FLOOR_COLOR := Palette.FLOOR
const COVER_COLOR := Palette.COVER_FILL
const COVER_EDGE := Palette.COVER_EDGE
const WALL_COLOR := Palette.WALL

var map: ArenaMap


func setup(arena_map: ArenaMap) -> void:
	map = arena_map
	queue_redraw()


func _draw() -> void:
	if map == null:
		return

	draw_rect(
		Rect2(
			-ArenaMap.HALF_WIDTH,
			-ArenaMap.HALF_HEIGHT,
			ArenaMap.HALF_WIDTH * 2.0,
			ArenaMap.HALF_HEIGHT * 2.0
		),
		FLOOR_COLOR
	)

	for wall in map.get_node("Bounds").get_children():
		_draw_body(wall, WALL_COLOR, WALL_COLOR)
	for piece in map.get_cover_pieces():
		_draw_body(piece, COVER_COLOR, COVER_EDGE)


func _draw_body(body: StaticBody2D, fill: Color, edge: Color) -> void:
	for child in body.get_children():
		if child is not CollisionShape2D:
			continue
		var shape := (child as CollisionShape2D).shape
		if shape is not RectangleShape2D:
			continue
		var size: Vector2 = (shape as RectangleShape2D).size
		var rect := Rect2(body.position + child.position - size * 0.5, size)
		draw_rect(rect, fill)
		draw_rect(rect, edge, false, 2.0)
