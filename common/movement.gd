extends RefCounted
class_name Movement

## The one place the actual movement math happens.
##
## `server/arena_server.gd`'s own authoritative step and `client/scenes/fighter.gd`'s
## local prediction and reconciliation replay all call this and only this, so the two can
## never structurally disagree given the same input history — the independent
## `move_and_slide()` calls this replaced are what let a client and server slide
## differently around the same corner on the same nominal input (#113).
##
## Gating on `can_move` happens in here, not at each call site, so a rule like paralysis
## or death can never gate one side of the sim and not the other — see #113's own "watch
## out for" on this exact trap.
static func step(body: CharacterBody2D, input: Vector2, can_move: bool) -> void:
	body.velocity = (input if can_move else Vector2.ZERO) * Constants.PLAYER_MOVE_SPEED
	body.move_and_slide()
