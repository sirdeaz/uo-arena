extends TestCase

## `server/player_body.tscn` inherits `common/body_base.tscn` and adds only its script.
## The shared circle and layer bits are pinned in `tests/test_body_base.gd`; this checks
## the one thing that is genuinely per-scene — that the inheritance is wired, so the
## server body still comes up as a `PlayerBody` with the base's collision child intact
## (an inherited-scene override that does not survive re-import fails here).

const BODY_SCENE := preload("res://server/player_body.tscn")

var body: PlayerBody


func before_each() -> void:
	body = BODY_SCENE.instantiate()
	add_child(body)


func after_each() -> void:
	body.queue_free()


func test_it_inherits_the_shared_base_and_keeps_its_own_script() -> void:
	assert_true(body is PlayerBody, "the inherited scene must still resolve to PlayerBody")
	var shape_node := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	assert_true(
		shape_node != null and shape_node.shape is CircleShape2D,
		"the base's CollisionShape2D must come through the inheritance"
	)
	assert_eq(
		body.collision_mask,
		Constants.LAYER_OBSTACLES,
		"the base's collision mask must come through the inheritance"
	)
