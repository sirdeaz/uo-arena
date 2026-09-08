extends TestCase

## The arena is one authored scene now (`res://arena/arena.tscn`) — hand-painted in the
## editor, and read back by `ArenaMap`. Nothing describes the layout in code; these
## check the paint is internally consistent, because a slip in it is silent:
##
##  - a solid tile with no collision polygon blocks nothing but the pathfinder still
##    routes around it — invisible cover, the worst bug this game has, inverted;
##  - a lone solid cell the rectangle merge cannot fold in would route players around
##    empty ground;
##  - a half-mirrored paint hands one spawn the better cover.
##
## `ArenaMap.obstacle_rects()` derives the routing rectangles from the same solid cells,
## so it is checked here to fold them all back losslessly.

const HALF_W := ArenaMap.HALF_WIDTH
const HALF_H := ArenaMap.HALF_HEIGHT

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
	for layer in [walls, cover]:
		for cell in layer.get_used_cells():
			if _is_solid(layer, cell):
				cells[cell] = true
	return cells


# ── the floor is decoration under the whole play area ─────────────────────────

func test_the_play_area_has_a_floor_tile_everywhere() -> void:
	var play := Rect2(Vector2(-HALF_W, -HALF_H), Vector2(HALF_W * 2.0, HALF_H * 2.0))
	for cell in _cells_in(floor_layer, play):
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


# ── the tiles are the collision, and the collision is not art ─────────────────

func test_every_solid_tile_carries_a_collision_polygon() -> void:
	# The tile *is* the collision now. A solid-tagged tile with no physics polygon is
	# cover you walk through and are shot past.
	for layer in [walls, cover]:
		var tile_set: TileSet = layer.tile_set
		var source := tile_set.get_source(0) as TileSetAtlasSource
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			var data := source.get_tile_data(coords, 0)
			if data.get_custom_data("solid"):
				assert_true(
					data.get_collision_polygons_count(0) > 0,
					"solid tile %s has no collision polygon" % coords
				)


func test_obstacle_rects_fold_the_solid_cells_back_losslessly() -> void:
	# `obstacle_rects()` is the pathfinder's whole view of the arena. If the merge drops
	# a cell the routing graph has a hole in it; if it invents one, a phantom wall.
	var solid := _solid_cells()
	var covered := {}
	for rect in map.obstacle_rects():
		assert_true(rect.size.x > 0.0 and rect.size.y > 0.0, "obstacle rect %s has no area" % rect)
		for cell in _cells_in(walls, rect):
			assert_false(covered.has(cell), "cell %s is in two obstacle rects" % cell)
			covered[cell] = true
	assert_eq(covered.size(), solid.size(), "the merged rects cover a different cell count")
	for cell in solid:
		assert_true(covered.has(cell), "solid cell %s is in no obstacle rect" % cell)


func test_cover_is_tents_and_rocks_and_the_boundary_is_neither() -> void:
	var kinds := {}
	for rect in map.cover_rects():
		var kind := map.cover_kind_at(rect.get_center())
		assert_true(
			kind != ArenaMap.CoverKind.UNKNOWN,
			"cover at %s has no tent/rock kind, so the client draws it as a block" % rect.get_center()
		)
		kinds[kind] = true
	assert_true(kinds.has(ArenaMap.CoverKind.TENT), "the arena has tents to hide behind")
	assert_true(kinds.has(ArenaMap.CoverKind.ROCK), "the arena has rocks in the corners")


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

