extends RefCounted
class_name FighterSprite

## Which animation the fighter's sprite should be playing: its heading and its posture.
##
## The frames themselves — regions, per-heading registration, loop flags, playback speed —
## live in `client/art/wizard_frames.tres`, a `SpriteFrames` resource authored in the
## editor and assigned to the `AnimatedSprite2D` in `client/scenes/fighter.tscn`. Nothing
## in code sets a frame up; `Fighter` only names an animation and calls `play()` on it as
## a fighter moves or casts. Swapping the pack, or retiming a set, is editing that `.tres`
## in the inspector.
##
## What is left here is the decision — heading and posture — and the decision belongs
## somewhere a test can reach without a scene tree or a clock, the same reason the rest of
## the codebase splits its decisions out (`Fighter.movement_direction_toward`). Every
## function below is `static`.
##
## ## What the sprite is allowed to say
##
## Posture and heading, and nothing else. Health, status, cast progress, which spell,
## whose body this is: every one of those stays a `_draw()` call in a palette colour,
## because ten fighters wear this same robe and one hooded robe cannot be told from
## another at a glance. See `docs/art-direction.md`.

## Which way a fighter is pointing. UO plays on a diagonal grid and this pack has four
## headings, so movement resolves to the nearest of them.
enum Facing { DOWN, UP, RIGHT, LEFT }

## Posture. Idle and walk share one set of frames — the pack draws no separate standing
## pose — and are told apart by how fast that set is played, which the `SpriteFrames`
## resource does with two animations over the same frames.
enum Anim { IDLE, WALK, CAST }


## Speed, in px/s, above which a fighter is walking rather than standing. Well under
## `PLAYER_MOVE_SPEED`, and well above the drift a server correction produces while a
## player stands still — otherwise a stationary remote fighter moonwalks on every
## snapshot. Gameplay feel rather than a property of the art, so it stays in code.
const WALK_SPEED_THRESHOLD: float = 12.0

## Movement shorter than this in one step says nothing about which way anyone is
## pointing, so the previous heading is kept. Without it a fighter pinned against a
## tent, sliding a fraction of a pixel a frame, spins on the spot.
const FACING_EPSILON: float = 0.5


## Which heading `direction` points at, or `previous` when it points nowhere.
##
## Ties go to the horizontal. A player walking exactly diagonally is drawn facing along
## the duel lane rather than up or down it, which is the read that matters: the lane is
## east-west and so is almost every shot fired down it.
static func facing_for(direction: Vector2, previous: Facing) -> Facing:
	if direction.length() < FACING_EPSILON:
		return previous
	if absf(direction.x) >= absf(direction.y):
		return Facing.RIGHT if direction.x > 0.0 else Facing.LEFT
	# Godot's y grows downward, so a positive y is toward the bottom of the screen.
	return Facing.DOWN if direction.y > 0.0 else Facing.UP


## Which heading to show, given everything the client knows about a fighter this frame.
##
## A caster faces what they are casting at; everyone else faces where they are going. Aim
## wins because it is the more deliberate act: a mage side-stepping behind a tent while
## throwing a spell down the lane is pointing at the spell, not at the tent.
##
## `aim` is `null` for every fighter nobody has named a target to — a snapshot carries
## positions and state, never intent, so every remote body falls back to travel and a
## remote mage casting on the spot faces wherever it last walked. That is the known cost
## of deriving heading client-side instead of paying for a ninth slot in the record; it
## is written down in `docs/sprite-pipeline-readiness.md` rather than hidden here.
static func heading_for(
	casting: bool, aim: Variant, from: Vector2, travelled: Vector2, previous: Facing
) -> Facing:
	if casting and aim != null:
		var at: Vector2 = aim
		return facing_for(at - from, previous)
	return facing_for(travelled, previous)


## Which posture a fighter in `state`, travelling at `speed` px/s, should be showing.
##
## Casting wins over walking: you can walk while casting in this game, and what the
## opponent needs off the silhouette is that a spell is coming, not that feet are
## moving. The mantra overhead says which spell; this only says that there is one.
static func animation_for(state: EntityState.State, speed: float) -> Anim:
	if state == EntityState.State.CASTING:
		return Anim.CAST
	if speed > WALK_SPEED_THRESHOLD:
		return Anim.WALK
	return Anim.IDLE


## The name of the `SpriteFrames` animation for a posture and a heading, e.g. `walk_left`.
## `Fighter` passes the result straight to `AnimatedSprite2D.play`, and
## `tests/test_fighter_frames.gd` checks the pack actually carries every name this can
## return.
static func animation_name(anim: Anim, facing: Facing) -> StringName:
	var posture := "idle"
	match anim:
		Anim.WALK:
			posture = "walk"
		Anim.CAST:
			posture = "cast"
	var heading := "down"
	match facing:
		Facing.UP:
			heading = "up"
		Facing.RIGHT:
			heading = "right"
		Facing.LEFT:
			heading = "left"
	return StringName("%s_%s" % [posture, heading])
