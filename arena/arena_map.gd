extends Node2D
class_name ArenaMap

## The arena, in one place — painted for looks and collided for physics by the same
## `TileMapLayer`s, in `res://arena/arena.tscn`. The server loads this scene too; it
## runs the tile physics headless and the Dedicated Server export drops the texture
## (checked in CI), so `server/` still ships collision only.
##
## Nothing here describes the layout. The tent, the rocks and the boundary are wherever
## they are painted on the `Walls` and `Cover` layers; the spawn points are wherever the
## `SpawnPoints` markers sit. This script only reads that back — which cells are solid,
## which kind of cover a point is on — so the pathfinder and the overlay route around
## exactly what the resolver raycasts against.

const TILE: int = 32

## The play field the `Floor` layer is painted to. Not an obstacle — the outer extent a
## fighter is allowed to reach, read by `is_inside_bounds` and the reachability tests.
const HALF_WIDTH: float = 608.0
const HALF_HEIGHT: float = 416.0

## What a piece of cover is, so the client can draw a tent as a tent. Read from the
## tile's `kind` custom-data.
enum CoverKind { UNKNOWN, TENT, ROCK }


func get_spawn_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for marker in $SpawnPoints.get_children():
		positions.append(marker.position)
	return positions


## Every solid rectangle in the arena — cover and boundary walls alike — in world
## space, merged from the painted `Walls` + `Cover` cells into as few axis-aligned
## rectangles as cover them. Pathfinding routes around these.
func obstacle_rects() -> Array[Rect2]:
	return _merge_cells(_solid_cells([$Walls, $Cover]))


## Just the cover a player hides behind — tents and rocks, not the boundary.
func cover_rects() -> Array[Rect2]:
	return _merge_cells(_solid_cells([$Cover]))


## What kind of cover, if any, is painted at a world point. `UNKNOWN` for open ground or
## a boundary wall — the client draws only tents and rocks.
func cover_kind_at(point: Vector2) -> CoverKind:
	var cover: TileMapLayer = $Cover
	var data := cover.get_cell_tile_data(cover.local_to_map(cover.to_local(point)))
	if data == null:
		return CoverKind.UNKNOWN
	match data.get_custom_data("kind"):
		"tent":
			return CoverKind.TENT
		"rock":
			return CoverKind.ROCK
	return CoverKind.UNKNOWN


func is_inside_bounds(point: Vector2) -> bool:
	return absf(point.x) < HALF_WIDTH and absf(point.y) < HALF_HEIGHT


# ── reading the paint ────────────────────────────────────────────────────────────


## Cells that carry the `solid` custom-data, across the given layers, as a set.
func _solid_cells(layers: Array) -> Dictionary:
	var cells := {}
	for layer in layers:
		var tile_layer: TileMapLayer = layer
		for cell in tile_layer.get_used_cells():
			var data := tile_layer.get_cell_tile_data(cell)
			if data != null and data.get_custom_data("solid"):
				cells[cell] = true
	return cells


## Greedy maximal-rectangle cover of a cell set: for each cell not yet taken, grow right
## as far as the row stays solid, then grow down as far as every column of that width
## stays solid. Exact — the rectangles tile the set with no gap and no overlap — and
## small: a boundary loop comes back as four bands, a tent as one rectangle.
static func _merge_cells(cells: Dictionary) -> Array[Rect2]:
	var taken := {}
	var rects: Array[Rect2] = []
	var ordered := cells.keys()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)

	for cell in ordered:
		if taken.has(cell):
			continue
		var width := 1
		while cells.has(Vector2i(cell.x + width, cell.y)) \
				and not taken.has(Vector2i(cell.x + width, cell.y)):
			width += 1
		var height := 1
		while _row_free(cells, taken, cell.x, cell.y + height, width):
			height += 1
		for j in height:
			for i in width:
				taken[Vector2i(cell.x + i, cell.y + j)] = true
		rects.append(Rect2(
			cell.x * TILE, cell.y * TILE, width * TILE, height * TILE
		))
	return rects


static func _row_free(cells: Dictionary, taken: Dictionary, x: int, y: int, width: int) -> bool:
	for i in width:
		var at := Vector2i(x + i, y)
		if not cells.has(at) or taken.has(at):
			return false
	return true
