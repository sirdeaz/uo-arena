extends TestCase

## `common/body_base.tscn` is the shared trunk of both player bodies — the client's
## `fighter.tscn` and the server's `player_body.tscn` inherit from it, so the circle
## and the collision layers are authored once here. The editor cannot reference a
## GDScript constant, so this pins the authored numbers to `common/constants.gd`: a
## change to a constant the base did not follow fails here rather than as a physics bug
## nobody can see.

const BASE_SCENE := preload("res://common/body_base.tscn")

var body: CharacterBody2D


func before_each() -> void:
	body = BASE_SCENE.instantiate()
	add_child(body)


func after_each() -> void:
	body.queue_free()


func test_it_sits_on_the_players_layer_and_collides_only_with_obstacles() -> void:
	assert_eq(
		body.collision_layer,
		Constants.LAYER_PLAYERS,
		"both bodies must be on the players layer for the client to predict the server"
	)
	assert_eq(
		body.collision_mask,
		Constants.LAYER_OBSTACLES,
		"they collide with cover only — players pass through each other and never block a spell"
	)


func test_its_circle_is_exactly_the_shared_player_radius() -> void:
	var shape_node := body.get_node("CollisionShape2D") as CollisionShape2D
	assert_true(shape_node != null, "the base body needs a CollisionShape2D child")
	var circle := shape_node.shape as CircleShape2D
	assert_true(circle != null, "the shape should be a circle — the shared footprint")
	assert_almost_eq(
		circle.radius,
		Constants.PLAYER_RADIUS,
		"the authored radius has drifted from Constants.PLAYER_RADIUS"
	)
