extends TestCase

## The one place movement math happens, shared by `server/arena_server.gd`'s own step and
## `client/scenes/fighter.gd`'s prediction and reconciliation replay — see #113. Checked
## here against a real `CharacterBody2D` in the tree, the same way `test_player_body.gd`
## pins the body it runs on.

const BODY_SCENE := preload("res://server/player_body.tscn")

var body: PlayerBody


func before_each() -> void:
	body = BODY_SCENE.instantiate()
	add_child(body)


func after_each() -> void:
	body.queue_free()


func test_a_step_with_input_moves_the_body() -> void:
	var was_at := body.global_position
	Movement.step(body, Vector2.RIGHT, true)
	await get_tree().physics_frame
	assert_true(
		body.global_position.x > was_at.x, "an allowed step with input must actually move"
	)


func test_a_step_that_cannot_move_ignores_the_input() -> void:
	var was_at := body.global_position
	Movement.step(body, Vector2.RIGHT, false)
	await get_tree().physics_frame
	assert_eq(
		body.global_position,
		was_at,
		"can_move gates the input here, not at the call site — see #113's own watch-out"
	)


func test_a_step_with_no_input_leaves_velocity_at_zero() -> void:
	Movement.step(body, Vector2.ZERO, true)
	assert_eq(body.velocity, Vector2.ZERO, "no direction must mean no velocity")
