extends CharacterBody2D
class_name PlayerBody

## The server's physical presence for one player: a circle that slides along cover, and
## nothing else. No sprite, no input, no drawing.
##
## This is the only `Node2D` descendant in `server/`, and the exception is deliberate.
## The rule exists to keep *rendering* out of the dedicated-server export, and a
## collision body is physics. What it buys is worth the exception: the server slides
## along a tent using exactly the same code the client predicts with, so hugging cover
## does not manufacture a correction on every frame.


func _ready() -> void:
	collision_layer = Constants.LAYER_PLAYERS
	# Obstacles only. Players pass through one another and never block a spell — the
	# same choice `Fighter` makes, and the one `test_line_of_sight.gd` pins.
	collision_mask = Constants.LAYER_OBSTACLES

	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = Constants.PLAYER_RADIUS
	collision.shape = circle
	add_child(collision)
