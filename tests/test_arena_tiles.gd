extends TestCase

## The arena is one authored scene now (`res://arena/arena.tscn`) — painted for looks
## and collided for physics by the same `TileMapLayer`s, generated from the obstacle
## rectangles in `arena/arena_map.gd` by `tools/build_arena.gd`. There is no second copy
## to drift from, but the paint can still disagree with the rectangles the pathfinder
## and the resolver read, and nothing in the engine notices:
##
##  - an obstacle rect with no solid tile over it blocks a raycast but the routing graph
##    and the overlay draw nothing there — invisible cover, the worst bug this game has;
##  - a solid tile with no rectangle under it reads as shelter a player walks into and
##    is shot through.
##
## Both are silent. These pin the paint to `ArenaMap.obstacle_rects()`, and pin the
## whole thing to its own 180° symmetry so a half-mirrored arena cannot pass.

const HALF_W := ArenaMap.HALF_WIDTH
const HALF_H := ArenaMap.HALF_HEIGHT
const TILE := ArenaMap.TILE

var map: ArenaMap
var walls: TileMapLayer
var cover: TileMapLayer
var floor_layer: TileMapLayer


func before_each() -> void:
	map = load("res://arena/arena.tscn").instantiate()
	add_child(map)
	walls = map.get_node("Walls")
	cover = map.get_node("Cover")
	floor_layer = map.get_node("Floor")


func after_each() -> void:
	map.queue_free()


func _is_solid(layer: TileMapLayer, cell: Vector2i) -> bool:
	var data := layer.get_cell_tile_data(cell)
	return data != null and data.get_custom_data("solid")


func _solid_cells() -> Dictionary:
	var cells := {}
	for layer in [walls, cover]:
		for cell in layer.get_used_cells():
			if _is_solid(layer, cell):
				cells[cell] = true
	return cells


# ── every obstacle rect is under solid tiles, and nothing solid floats free ────

func test_every_obstacle_rect_is_fully_tiled() -> void:
	var solid := _solid_cells()
	for rect in map.obstacle_rects():
		for cell in ArenaTiles.rect_cells(rect, TILE):
			assert_true(
				solid.has(cell),
				"no solid tile over cell %s of obstacle %s — invisible cover" % [cell, rect]
			)


func test_no_solid_tile_sits_where_no_obstacle_is() -> void:
	var allowed := {}
	for rect in map.obstacle_rects():
		for cell in ArenaTiles.rect_cells(rect, TILE):
			allowed[cell] = true

	for cell in _solid_cells():
		assert_true(
			allowed.has(cell),
			"solid tile at cell %s is over no obstacle rectangle" % cell
		)


# ── the floor is decoration under the whole play area ─────────────────────────

func test_the_play_area_has_a_floor_tile_everywhere() -> void:
	var play := Rect2(Vector2(-HALF_W, -HALF_H), Vector2(HALF_W * 2.0, HALF_H * 2.0))
	for cell in ArenaTiles.rect_cells(play, TILE):
		assert_true(
			floor_layer.get_cell_tile_data(cell) != null,
			"cell %s in the play area has no floor tile" % cell
		)


func test_the_floor_layer_carries_no_collision() -> void:
	for cell in floor_layer.get_used_cells():
		assert_false(
			_is_solid(floor_layer, cell), "the floor layer has a solid tile at %s" % cell
		)


# ── the arena is its own 180° reflection ──────────────────────────────────────

func test_the_solid_silhouette_is_rotationally_symmetric() -> void:
	# Cover is placed so neither spawn is favoured. A mirrored-then-half-edited paint
	# would pass every coverage check above and still hand one side the better ground.
	var solid := _solid_cells()
	for cell in solid:
		var mirror := Vector2i(-cell.x - 1, -cell.y - 1)
		assert_true(
			solid.has(mirror),
			"solid cell %s has no partner at %s — the arena is not 180° symmetric" % [cell, mirror]
		)


func test_the_spawns_are_their_own_negation() -> void:
	var spawns := {}
	for point in map.get_spawn_positions():
		spawns[point] = true
	for point in spawns:
		assert_true(
			spawns.has(-point), "spawn %s has no rotational partner at %s" % [point, -point]
		)


# ── the cell arithmetic itself ───────────────────────────────────────────────

func test_rect_cells_rounds_outward_never_short() -> void:
	# A rect whose edges fall mid-cell must still include the cells those edges are in.
	var rect := Rect2(Vector2(-20.0, 4.0), Vector2(40.0, 40.0))  # x -20..20, y 4..44
	var cells := ArenaTiles.rect_cells(rect, 16)
	assert_true(cells.has(Vector2i(-2, 0)), "the left edge at x=-20 is in column -2")
	assert_true(cells.has(Vector2i(1, 2)), "the bottom-right at (20, 44) is in cell (1, 2)")
	for cell in cells:
		var c := ArenaTiles.cell_centre(cell, 16)
		assert_true(
			c.x > rect.position.x - 16.0 and c.x < rect.end.x + 16.0,
			"cell %s is more than a tile outside the rect" % cell
		)
