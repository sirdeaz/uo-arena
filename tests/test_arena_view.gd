extends TestCase

## `ArenaView` is the only thing standing between a collision shape and a player who
## cannot see it. Cover that blocks line of sight but draws nothing is the worst bug
## this game has — the opponent's casts fail silently and it looks like the resolver
## is broken — so these tests treat "every shape in the map is drawable" as a property
## of the map, not something to check by eye.
##
## `tests/test_arena_map.gd` deliberately cannot catch this: an invisible rock satisfies
## every reachability and fairness assertion it makes.

var map: ArenaMap


func before_each() -> void:
	map = load("res://server/arena_map.tscn").instantiate()
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

func test_every_cover_shape_can_actually_be_drawn() -> void:
	for piece in map.get_cover_pieces():
		var shapes := _collision_shapes(piece)
		assert_true(shapes.size() > 0, "%s has no collision shape at all" % piece.name)
		for collision in shapes:
			assert_true(
				ArenaView.can_draw(collision.shape),
				"%s is a %s, which ArenaView would draw as a placeholder — cover that blocks but is not drawn reads as a resolver bug" % [
					piece.name,
					"null shape" if collision.shape == null else collision.shape.get_class()
				]
			)


func test_every_boundary_wall_can_actually_be_drawn() -> void:
	for wall in map.get_node("Bounds").get_children():
		for collision in _collision_shapes(wall):
			assert_true(
				ArenaView.can_draw(collision.shape),
				"%s would not be drawn" % wall.name
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
	# The game tells the player to get behind a *tent*. A piece with no kind still
	# draws, but it draws as an anonymous block, so the instruction stops being true.
	for piece in map.get_cover_pieces():
		assert_true(
			ArenaMap.cover_kind(piece) != ArenaMap.CoverKind.UNKNOWN,
			"%s has no cover_tent/cover_rock group, so it draws as a generic block" % piece.name
		)


func test_tents_and_rocks_are_told_apart() -> void:
	var kinds := {}
	for piece in map.get_cover_pieces():
		kinds[ArenaMap.cover_kind(piece)] = true
	assert_true(kinds.has(ArenaMap.CoverKind.TENT), "the arena has tents to hide behind")
	assert_true(kinds.has(ArenaMap.CoverKind.ROCK), "the arena has rocks in the corners")


func test_the_kind_hint_carries_no_rendering_into_the_server_scene() -> void:
	# `server/` must stay exportable as a Dedicated Server build: collision only.
	for piece in map.get_cover_pieces():
		for child in piece.get_children():
			assert_true(
				child is CollisionShape2D,
				"%s/%s is not a collision shape — server/ must hold no visuals" % [
					piece.name, child.name
				]
			)


# ── the floor says how far away things are ────────────────────────────────────

func test_a_floor_grid_cell_is_one_second_of_movement() -> void:
	# The grid is a distance readout, not decoration: counting cells to a tent is
	# counting seconds against a cast time.
	assert_almost_eq(
		ArenaView.grid_pitch(),
		Constants.PLAYER_MOVE_SPEED,
		"one grid cell should be one second of running"
	)


func test_the_grid_is_fine_enough_to_show_movement_across_the_arena() -> void:
	var cells_across := (ArenaMap.HALF_WIDTH * 2.0) / ArenaView.grid_pitch()
	assert_true(
		cells_across >= 4.0,
		"the arena should be several cells wide, is %.1f" % cells_across
	)
