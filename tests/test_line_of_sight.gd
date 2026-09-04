extends TestCase

## LOS is checked against the `obstacles` physics layer at the moment a spell would
## connect. These tests build a real 2D physics world with real static bodies — no
## mocks — because the thing under test is precisely whether the raycast sees them.

var resolver: CombatResolver
var world: Node2D


func before_each() -> void:
	world = Node2D.new()
	add_child(world)
	resolver = CombatResolver.new()
	add_child(resolver)


func after_each() -> void:
	world.queue_free()
	resolver.queue_free()


## Places a rectangular obstacle on the obstacles layer, centred at `center`.
func _add_obstacle(center: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = Constants.LAYER_OBSTACLES
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	world.add_child(body)
	return body


func _space_state() -> PhysicsDirectSpaceState2D:
	return world.get_world_2d().direct_space_state


func test_clear_path_has_line_of_sight() -> void:
	await get_tree().physics_frame
	assert_true(
		resolver.has_line_of_sight(_space_state(), Vector2(0, 0), Vector2(200, 0)),
		"empty arena should not block a straight shot"
	)


func test_obstacle_between_blocks_line_of_sight() -> void:
	_add_obstacle(Vector2(100, 0), Vector2(40, 200))
	await get_tree().physics_frame
	assert_false(
		resolver.has_line_of_sight(_space_state(), Vector2(0, 0), Vector2(200, 0)),
		"a tent squarely between caster and target should block LOS"
	)


func test_obstacle_beside_the_path_does_not_block() -> void:
	# Same obstacle, moved well off the caster→target line.
	_add_obstacle(Vector2(100, 300), Vector2(40, 200))
	await get_tree().physics_frame
	assert_true(
		resolver.has_line_of_sight(_space_state(), Vector2(0, 0), Vector2(200, 0)),
		"cover that isn't on the line shouldn't block LOS"
	)


func test_player_bodies_do_not_block_line_of_sight() -> void:
	# A body on the players layer sitting directly on the line — teammates and the
	# target's own hitbox must not count as cover.
	var body := StaticBody2D.new()
	body.collision_layer = Constants.LAYER_PLAYERS
	body.collision_mask = 0
	body.position = Vector2(100, 0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 40)
	shape.shape = rect
	body.add_child(shape)
	world.add_child(body)

	await get_tree().physics_frame
	assert_true(
		resolver.has_line_of_sight(_space_state(), Vector2(0, 0), Vector2(200, 0)),
		"only the obstacles layer should break LOS"
	)
