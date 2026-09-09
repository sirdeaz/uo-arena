extends TestCase

## The arena is one authored scene (`res://arena/arena_map.tscn`) — hand-painted in the
## editor, and read back by `ArenaMap`. Nothing describes the layout in code; these
## check the paint is internally consistent, because a slip in it is silent:
##
##  - a tile painted into an obstacle layer with no collision polygon blocks nothing,
##    yet still reads as floor — cover you walk through and are shot past;
##  - a half-mirrored paint hands one spawn the better cover.
##
## `ArenaMap.obstacle_polygons()` lifts the routing shapes off those same tiles, so it
## is checked here to cover exactly the painted cells and no more.

var map: ArenaMap
var walls: TileMapLayer
var cover: TileMapLayer
var floor_layer: TileMapLayer


func before_each() -> void:
	map = load("res://arena/arena_map.tscn").instantiate()
	add_child(map)
	walls = map.get_node("Walls")
	cover = map.get_node("Cover")
	floor_layer = map.get_node("Floor")


func after_each() -> void:
	map.queue_free()


## A cell is an obstacle when its tile carries a collision polygon — the same test
## `ArenaMap` and the physics engine apply. There is no separate "solid" flag any more.
func _has_collision(layer: TileMapLayer, cell: Vector2i) -> bool:
	var data := layer.get_cell_tile_data(cell)
	return data != null and data.get_collision_polygons_count(0) > 0


## Every cell a tile-aligned world rect covers, from the layer's own `local_to_map` —
## the arena is painted on whole cells, so the corners map exactly and there is no
## rounding to get wrong.
func _cells_in(layer: TileMapLayer, rect: Rect2) -> Array:
	var lo := layer.local_to_map(rect.position)
	var hi := layer.local_to_map(rect.end)
	var cells := []
	for y in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			cells.append(Vector2i(x, y))
	return cells


func _solid_cells() -> Dictionary:
	var cells := {}
	for layer: TileMapLayer in [walls, cover]:
		for cell in layer.get_used_cells():
			if _has_collision(layer, cell):
				cells[cell] = true
	return cells


# ── the floor is decoration under the whole play area ─────────────────────────

func test_the_play_area_has_a_floor_tile_everywhere() -> void:
	for cell in _cells_in(floor_layer, map.bounds()):
		assert_true(
			floor_layer.get_cell_tile_data(cell) != null,
			"cell %s in the play area has no floor tile" % cell
		)


func test_the_floor_layer_carries_no_collision() -> void:
	for cell in floor_layer.get_used_cells():
		assert_false(
			_has_collision(floor_layer, cell),
			"the floor layer has a colliding tile at %s" % cell
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


# ── the tiles are the collision, and the collision is not art ─────────────────

func test_no_tile_in_an_obstacle_layer_is_missing_its_collision() -> void:
	# The tile *is* the collision now. A tile painted onto `Walls` or `Cover` with no
	# physics polygon is cover you walk through and are shot past — and it reads exactly
	# like the floor, so nothing but this notices.
	for layer: TileMapLayer in [walls, cover]:
		for cell in layer.get_used_cells():
			assert_true(
				_has_collision(layer, cell),
				"%s tile at %s carries no collision polygon" % [layer.name, cell]
			)


func test_obstacle_polygons_cover_exactly_the_painted_cells() -> void:
	# `obstacle_polygons()` is the pathfinder's whole view of the arena. If it drops a
	# cell the routing graph has a hole in it; if it invents area, a phantom wall.
	var cell_area := float(walls.tile_set.tile_size.x * walls.tile_set.tile_size.y)
	var expected := float(_solid_cells().size()) * cell_area

	var total := 0.0
	for polygon in map.obstacle_polygons():
		assert_true(polygon.size() >= 3, "obstacle polygon %s has no area" % polygon)
		total += absf(_polygon_area(polygon))

	assert_almost_eq(
		total, expected,
		"the obstacle polygons cover a different area than the painted cells", 1.0
	)
	# And every painted cell's centre sits inside one of them.
	for layer: TileMapLayer in [walls, cover]:
		for cell in layer.get_used_cells():
			if not _has_collision(layer, cell):
				continue
			var centre := layer.to_global(layer.map_to_local(cell))
			var inside := false
			for polygon in map.obstacle_polygons():
				if Geometry2D.is_point_in_polygon(centre, polygon):
					inside = true
					break
			assert_true(inside, "painted cell at %s is in no obstacle polygon" % centre)


func _polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


func test_the_arena_scene_carries_no_rendering_into_the_server_build() -> void:
	# `server/` loads this scene too. `TileMapLayer`s are allowed — they are the
	# collision — but nothing that draws a texture: the Dedicated Server export drops the
	# tileset image (CI-checked, .github/workflows/deploy.yml) and the headless server
	# runs the layers for physics alone.
	var stack: Array[Node] = [map]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		assert_false(
			node is Sprite2D or node is AnimatedSprite2D,
			"%s is a sprite — the arena scene must not draw art the server would pack" % node.name
		)
		stack.append_array(node.get_children())
