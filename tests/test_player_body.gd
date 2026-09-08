extends TestCase

## `server/player_body.tscn` is authored, but the layer bits and the body radius it
## carries are the same numbers `common/constants.gd` names — and the editor cannot
## reference a GDScript constant. These pin the two together, so a change to a constant
## that the scene did not follow fails here rather than as a physics bug nobody can see.

const BODY_SCENE := preload("res://server/player_body.tscn")

var body: PlayerBody


func before_each() -> void:
	body = BODY_SCENE.instantiate()
	add_child(body)


func after_each() -> void:
	body.queue_free()


func test_it_sits_on_the_players_layer_and_collides_only_with_obstacles() -> void:
	assert_eq(
		body.collision_layer,
		Constants.LAYER_PLAYERS,
		"the server body has to be on the players layer for the client to predict it"
	)
	assert_eq(
		body.collision_mask,
		Constants.LAYER_OBSTACLES,
		"it must collide with cover only — players pass through each other and never block a spell"
	)


func test_its_circle_is_exactly_the_shared_player_radius() -> void:
	var shape_node := body.get_node("CollisionShape2D") as CollisionShape2D
	assert_true(shape_node != null, "the authored body needs a CollisionShape2D child")
	var circle := shape_node.shape as CircleShape2D
	assert_true(circle != null, "the shape should be a circle, like the client's footprint")
	assert_almost_eq(
		circle.radius,
		Constants.PLAYER_RADIUS,
		"the authored radius has drifted from Constants.PLAYER_RADIUS"
	)
