extends TestCase

## The arena floor, boundary and cover are painted tiles now
## (`client/scenes/arena_ground.tscn`), and collision stayed exactly where it was in
## `server/arena_map.tscn`. That split is only safe while the two agree, and nothing in
## the engine notices when they drift:
##
##  - a collider with no solid tile over it blocks spells and draws nothing — invisible
##    cover, the worst bug this game has;
##  - a solid-reading tile with no collider under it reads as shelter you can walk into
##    and be shot through.
##
## Both are silent. This walks every collider from `PathFinder.obstacle_polygons`' own
## source and asserts a solid tile sits over all of it — and that no solid tile sits in
## open play more than a tile from anything that collides, the outward-rounding margin
## the painter is allowed.

const HALF_W := ArenaMap.HALF_WIDTH
const HALF_H := ArenaMap.HALF_HEIGHT

var map: ArenaMap
var ground: Node2D
var walls: TileMapLayer
var cover: TileMapLayer
var floor_layer: TileMapLayer


func before_each() -> void:
	map = load("res://server/arena_map.tscn").instantiate()
	add_child(map)
	ground = load("res://client/scenes/arena_ground.tscn").instantiate()
	add_child(ground)
	walls = ground.get_node("Walls")
	cover = ground.get_node("Cover")
	floor_layer = ground.get_node("Floor")


func after_each() -> void:
	map.queue_free()
	ground.queue_free()


func _colliders() -> Array[StaticBody2D]:
	var bodies: Array[StaticBody2D] = []
	for body in map.get_node("Bounds").get_children():
		bodies.append(body)
	for body in map.get_cover_pieces():
		bodies.append(body)
	return bodies


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


# ── every collider is under a solid tile ──────────────────────────────────────

func test_every_collision_rect_is_fully_tiled() -> void:
	var solid := _solid_cells()
	for body in _colliders():
		var rect := ArenaTiles.collider_world_rect(body)
		assert_false(rect == Rect2(), "%s is not a rectangle collider" % body.name)
		for cell in ArenaTiles.rect_cells(rect):
			assert_true(
				solid.has(cell),
				"%s: no solid tile over cell %s — that collider is invisible cover" % [
					body.name, cell
				]
			)


# ── no solid tile floats free in the play area ────────────────────────────────

func test_no_solid_tile_sits_where_nothing_collides() -> void:
	# Every in-bounds solid cell has to belong to some collider grown by one tile — the
	# margin the painter rounds outward by. A solid cell further in than that is cover a
	# player would walk into expecting shelter that is not there.
	var allowed := {}
	for body in _colliders():
		var grown := ArenaTiles.collider_world_rect(body).grow(ArenaTiles.TILE)
		for cell in ArenaTiles.rect_cells(grown):
			allowed[cell] = true

	for cell in _solid_cells():
		var centre := ArenaTiles.cell_centre(cell)
		var in_play := absf(centre.x) < HALF_W and absf(centre.y) < HALF_H
		if not in_play:
			continue  # the wall band is allowed to run out past the play edge
		assert_true(
			allowed.has(cell),
			"solid tile at cell %s (world %s) is not over or beside any collider" % [
				cell, centre
			]
		)


# ── the floor is under the whole play area ────────────────────────────────────

func test_the_play_area_has_a_floor_tile_everywhere() -> void:
	var play := Rect2(
		Vector2(-HALF_W, -HALF_H), Vector2(HALF_W * 2.0, HALF_H * 2.0)
	)
	for cell in ArenaTiles.rect_cells(play):
		assert_true(
			floor_layer.get_cell_tile_data(cell) != null,
			"cell %s in the play area has no floor tile" % cell
		)


func test_the_floor_layer_carries_no_cover() -> void:
	# The floor is decoration only. A solid tile on it would be a blocker the coverage
	# checks above never look at.
	for cell in floor_layer.get_used_cells():
		assert_false(
			_is_solid(floor_layer, cell), "the floor layer has a solid tile at %s" % cell
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
