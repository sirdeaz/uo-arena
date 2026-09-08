extends RefCounted
class_name ArenaTiles

## The cell arithmetic shared by the thing that paints the arena tiles and the test that
## checks them. Pulled out as plain static functions for the same reason
## the arena's own geometry lives in the paint: the reader and the check have to agree, or the
## check is worthless, and neither should need a scene tree to ask the question.
##
## A cell `c` covers the world-space square `[c * tile, c * tile + tile)` on each axis —
## the native `TileMapLayer` mapping when the layer sits at the origin, which is where
## `res://arena/arena.tscn` puts it.

const TILE: int = 32


## Every cell a world-space rect touches, rounded outward to whole cells. Outward, never
## inward: a collider with no solid tile over it is invisible cover, which is the worst
## failure this game has, so the tiles are allowed to overhang the shape but never to
## fall short of it.
static func rect_cells(rect: Rect2, tile: int = TILE) -> Array:
	var cells := []
	var x0 := int(floor(rect.position.x / tile))
	var x1 := int(ceil(rect.end.x / tile)) - 1
	var y0 := int(floor(rect.position.y / tile))
	var y1 := int(ceil(rect.end.y / tile)) - 1
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			cells.append(Vector2i(x, y))
	return cells


## The world-space centre of a cell.
static func cell_centre(cell: Vector2i, tile: int = TILE) -> Vector2:
	return Vector2(cell.x + 0.5, cell.y + 0.5) * tile


## The rect a StaticBody2D's rectangle collider occupies in world space. Returns an empty
## rect for anything that is not a plain axis-aligned RectangleShape2D — the arena's
## colliders all are, and a non-rect would want handling rather than a silent guess. The
## body must be inside the tree, so its global transform is real.
static func collider_world_rect(body: StaticBody2D) -> Rect2:
	for child in body.get_children():
		if child is not CollisionShape2D:
			continue
		var collision := child as CollisionShape2D
		if collision.shape is not RectangleShape2D:
			continue
		var size: Vector2 = (collision.shape as RectangleShape2D).size
		return Rect2(collision.global_position - size * 0.5, size)
	return Rect2()
