extends TestCase

## The arena is drawn from tiles now, and `tests/test_arena_tiles.gd` is what guarantees
## a solid tile sits over every collider. `ArenaView` kept the shape-to-outline
## conversion — `PathFinder` routes around the same polygons, and the developer overlay
## draws them — so these tests still pin that every shape the map can hold has an
## outline, and that an unknown shape reports itself rather than vanishing.
##
## Cover that blocks line of sight but is not drawn is still the worst bug this game has;
## `tests/test_arena_map.gd` deliberately cannot catch it — an invisible rock satisfies
## every reachability and fairness assertion it makes.

var map: ArenaMap


func before_each() -> void:
	map = load("res://arena/arena.tscn").instantiate()
	add_child(map)


func after_each() -> void:
	map.queue_free()


func _collision_shapes(body: Node) -> Array[CollisionShape2D]:
	var shapes: Array[CollisionShape2D] = []
	for child in body.get_children():
		if child is CollisionShape2D:
			shapes.append(child)
	return shapes


# ── nothing in the map is invisible ───────────────────────────────────────────

func test_every_obstacle_is_a_real_rectangle_the_overlay_can_outline() -> void:
	# Collision is the tiles now, and every obstacle the pathfinder and the overlay read
	# is one of these rectangles. A zero-area or inverted one would be cover that blocks
	# nothing, or a routing graph that trusts a degenerate polygon.
	var rects := map.obstacle_rects()
	assert_true(rects.size() >= 5, "walls plus cover should be at least five rectangles")
	for rect in rects:
		assert_true(
			rect.size.x > 0.0 and rect.size.y > 0.0,
			"obstacle rect %s has no area" % rect
		)


func test_every_solid_tile_carries_a_collision_polygon() -> void:
	# The tile *is* the collision. A solid-tagged tile with no physics polygon draws
	# cover you can walk through and be shot past.
	var tile_set: TileSet = map.get_node("Cover").tile_set
	var source := tile_set.get_source(0) as TileSetAtlasSource
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		var data := source.get_tile_data(coords, 0)
		if data.get_custom_data("solid"):
			assert_true(
				data.get_collision_polygons_count(0) > 0,
				"solid tile %s has no collision polygon" % coords
			)


# ── the shapes someone might reasonably drag in ───────────────────────────────

func test_a_rectangle_outlines_its_four_corners() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(200.0, 110.0)
	var points := ArenaView.shape_polygon(shape)
	assert_eq(points.size(), 4, "a rect has four corners")
	assert_true(points.has(Vector2(-100.0, -55.0)), "corners are centred on the shape")
	assert_true(points.has(Vector2(100.0, 55.0)), "corners are centred on the shape")


func test_a_circle_is_drawable_and_stays_within_its_radius() -> void:
	var shape := CircleShape2D.new()
	shape.radius = 65.0
	assert_true(ArenaView.can_draw(shape), "a round rock must not be invisible")
	for point in ArenaView.shape_polygon(shape):
		assert_almost_eq(point.length(), 65.0, "circle outline sits on the radius", 0.001)


func test_a_capsule_is_drawable_and_fits_its_own_bounds() -> void:
	var shape := CapsuleShape2D.new()
	shape.radius = 30.0
	shape.height = 140.0
	assert_true(ArenaView.can_draw(shape), "a capsule must not be invisible")
	for point in ArenaView.shape_polygon(shape):
		assert_true(absf(point.x) <= 30.001, "capsule stays inside its radius")
		assert_true(absf(point.y) <= 70.001, "capsule stays inside its height")


func test_a_convex_polygon_is_drawn_from_its_own_points() -> void:
	var shape := ConvexPolygonShape2D.new()
	shape.points = PackedVector2Array([
		Vector2(-40.0, -20.0), Vector2(40.0, -30.0), Vector2(30.0, 35.0), Vector2(-35.0, 25.0)
	])
	assert_true(ArenaView.can_draw(shape), "a convex rock must not be invisible")
	assert_eq(ArenaView.shape_polygon(shape).size(), 4, "drawn from the shape's own points")


func test_an_unhandled_shape_reports_itself_rather_than_claiming_it_can_be_drawn() -> void:
	# The failure mode that matters: `can_draw` must say no, so the view falls through
	# to the loud placeholder instead of skipping the shape.
	assert_false(ArenaView.can_draw(null), "a missing shape is not drawable")
	assert_false(
		ArenaView.can_draw(WorldBoundaryShape2D.new()),
		"an infinite plane has no outline — it must be reported, not silently skipped"
	)


# ── tents read as tents ───────────────────────────────────────────────────────

func test_every_cover_piece_declares_what_it_is() -> void:
	# The game tells the player to get behind a *tent*. A piece whose `kind` custom-data
	# is missing draws as an anonymous block, so the instruction stops being true.
	for rect in map.cover_rects():
		assert_true(
			ArenaMap.cover_kind_at(rect.get_center()) != ArenaMap.CoverKind.UNKNOWN,
			"cover at %s has no tent/rock kind, so it draws as a generic block" % rect.get_center()
		)


func test_tents_and_rocks_are_told_apart() -> void:
	var kinds := {}
	for rect in map.cover_rects():
		kinds[ArenaMap.cover_kind_at(rect.get_center())] = true
	assert_true(kinds.has(ArenaMap.CoverKind.TENT), "the arena has tents to hide behind")
	assert_true(kinds.has(ArenaMap.CoverKind.ROCK), "the arena has rocks in the corners")


func test_the_arena_scene_carries_no_rendering_into_the_server_build() -> void:
	# `server/` loads this scene too. It may hold `TileMapLayer`s — that is the
	# collision — but nothing that draws a texture: the Dedicated Server export drops
	# the tileset image (checked in CI, see .github/workflows/deploy.yml) and the
	# headless server runs the layers for physics alone.
	var stack: Array[Node] = [map]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		assert_false(
			node is Sprite2D or node is AnimatedSprite2D,
			"%s is a sprite — the arena scene must not draw art the server would pack" % node.name
		)
		stack.append_array(node.get_children())
