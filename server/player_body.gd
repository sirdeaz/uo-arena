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
##
## Layout — the circle, its radius, and the collision layers — is authored in
## `server/player_body.tscn` now, not built here. The `.tscn` mirrors
## `Constants.PLAYER_RADIUS` / `LAYER_PLAYERS` / `LAYER_OBSTACLES` by hand;
## `tests/test_player_body.gd` fails if the two drift. Obstacles only in the mask:
## players pass through one another and never block a spell — the same choice `Fighter`
## makes, and the one `test_line_of_sight.gd` pins.
