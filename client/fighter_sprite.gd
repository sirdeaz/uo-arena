extends RefCounted
class_name FighterSprite

## The character atlas, and the rules for picking a frame out of it.
##
## Split out of `Fighter` for the reason the rest of this codebase splits things out:
## which frame a fighter should be showing is a decision, and a decision belongs in a
## static function that a test can call without a scene tree, a texture or a clock.
## `Fighter` is left with the drawing, which is one call.
##
## ## What the sprite is allowed to say
##
## Posture and heading, and nothing else. Health, status, cast progress, which spell,
## whose body this is: every one of those stays a `_draw()` call in a palette colour,
## because ten fighters wear this same robe and one hooded robe cannot be told from
## another at a glance. See `docs/art-direction.md`.
##
## ## The atlas
##
## One row of 46 frames, 79×65 each, exactly as the pack supplies it — no repacking
## step, so what ships is the artwork that was handed over. The strip is not uniform:
## walking is six frames per heading, casting is four, and the two are interleaved
## rather than grouped, which is why the ranges below are a table rather than a stride.
##
## ## Registration
##
## The pack is registered to within a pixel across every set but one: the left-facing
## walk sits about 3.6 px left inside its cells, and drawn from a single anchor a
## fighter would hop sideways every time it turned. So the anchor is per heading,
## measured from the walk frames — the clean ones, with no staff or flame dipping below
## the hem to confuse where the feet are — and the cast frames of a heading borrow it.
##
## A cast set genuinely does lean into the spell, by a pixel or two. That is the artist
## drawing a mage putting their weight behind a flamestrike, and it is left alone;
## `tests/test_fighter_sprite.gd` re-measures the committed atlas and pins the anchors
## rather than trusting this comment.

const TEXTURE: Texture2D = preload("res://client/art/wizard.png")

## Which way a fighter is pointing. UO plays on a diagonal grid and this pack has four
## headings, so movement resolves to the nearest of them.
enum Facing { DOWN, UP, RIGHT, LEFT }

## Posture. Idle and walk share one set of frames — the pack draws no separate standing
## pose — and are told apart by how fast that set is played.
enum Anim { IDLE, WALK, CAST }

const CELL := Vector2(79.0, 65.0)

## Roughly the character's middle, measured up from where they stand.
##
## Anything belonging to the *body* rather than to the ground hangs off this: a cast
## aura gathering around a mage's ankles reads as a puddle rather than as a spell.
## Ground marks — the footing, the status rings — stay at the feet, where the collision
## circle is.
const CHEST := Vector2(0.0, -26.0)

## Where in a cell the feet are, per heading. Everything else in the atlas registers to
## within a pixel; `LEFT` does not, and this is the correction.
const ANCHORS := {
	Facing.DOWN: Vector2(31.0, 49.0),
	Facing.UP: Vector2(30.0, 49.0),
	Facing.RIGHT: Vector2(30.0, 49.0),
	Facing.LEFT: Vector2(27.0, 49.0),
}

## Where each set starts in the strip, and how long it runs.
##
## Walking and casting alternate by heading rather than sitting in blocks, so this is
## read from the sheet rather than derived.
const WALK_RANGES := {
	Facing.DOWN: Vector2i(0, 6),
	Facing.UP: Vector2i(6, 6),
	Facing.RIGHT: Vector2i(12, 6),
	Facing.LEFT: Vector2i(22, 6),
}

const CAST_RANGES := {
	Facing.RIGHT: Vector2i(18, 4),
	Facing.LEFT: Vector2i(28, 4),
	Facing.DOWN: Vector2i(32, 4),
	Facing.UP: Vector2i(36, 4),
}

## Frames 40-45 are a staff-raised channel with its own sparkle burst, and are
## deliberately unused. The game already announces a cast with the mantra overhead and
## an aura in the colour of the spell being cast; a second, fixed, yellow-and-blue
## flourish would say the same thing again and in the wrong colour. Recorded here so
## the next person can see it was a decision rather than an oversight.
const CHANNEL_RANGE := Vector2i(40, 6)

const FRAME_COUNT: int = 46

const IDLE_FRAME_SECONDS: float = 0.22
const WALK_FRAME_SECONDS: float = 0.11

## Speed, in px/s, above which a fighter is walking rather than standing. Well under
## `PLAYER_MOVE_SPEED`, and well above the drift a server correction produces while a
## player stands still — otherwise a stationary remote fighter moonwalks on every
## snapshot.
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


## The stretch of the strip holding `anim` for `facing`, as (first frame, length).
static func range_for(anim: Anim, facing: Facing) -> Vector2i:
	if anim == Anim.CAST:
		return CAST_RANGES[facing]
	return WALK_RANGES[facing]


## Which frame of the strip to show.
##
## Idle and walk loop on the clock, off the same set — the pack has no standing pose,
## so a fighter at rest plays its walk gently rather than freezing, which reads as
## breathing instead of as a paused game.
##
## A cast does not loop: its frames are spread across real cast progress, so the
## wind-up is a read on how close the spell is to landing rather than an animation that
## happens to be playing. That is the same choice `_draw_cast_animation` makes for the
## aura, and for the same reason — a one-second spell and a four-second one then look
## different at the same moment, which is the point.
static func frame_for(
	anim: Anim, facing: Facing, elapsed: float, cast_progress: float
) -> int:
	var span := range_for(anim, facing)
	var start := span.x
	var count := span.y

	if anim == Anim.CAST:
		var step := int(clampf(cast_progress, 0.0, 1.0) * float(count))
		return start + clampi(step, 0, count - 1)

	var seconds := WALK_FRAME_SECONDS if anim == Anim.WALK else IDLE_FRAME_SECONDS
	return start + posmod(int(maxf(elapsed, 0.0) / seconds), count)


## The patch of the atlas holding that frame.
static func region_for(frame: int) -> Rect2:
	return Rect2(Vector2(float(posmod(frame, FRAME_COUNT)) * CELL.x, 0.0), CELL)


## Where to put the atlas region so the character stands at `foot`, in the drawing
## node's own coordinates.
static func rect_for(foot: Vector2, facing: Facing) -> Rect2:
	return Rect2(foot - ANCHORS[facing], CELL)


## How far above the feet this heading's head reaches, for hanging the mantra and the
## health bar off. The cell is the same height whichever way the mage faces, so this is
## one number rather than a table.
static func head_top() -> float:
	return -ANCHORS[Facing.DOWN].y
