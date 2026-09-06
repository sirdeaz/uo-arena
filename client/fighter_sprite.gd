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
## Nothing that a player reads under time pressure. The art carries posture — standing,
## walking, winding up a spell — and that is all. Health, status, cast progress, which
## spell, whose body this is: every one of those stays a `_draw()` call in a palette
## colour, because ten fighters wear this same art and a hooded robe cannot be told
## from another hooded robe at a glance. See `docs/art-direction.md`.
##
## ## Registration
##
## The atlas is built by `tools/pack_character_sprites.py`, which lands every frame on
## a fixed cell with the character's standing point at `ANCHOR`. That is what lets one
## offset serve every row: a fighter that stops walking mid-stride does not jump
## sideways, which is exactly what the raw pack does — its attack frames sit on a
## wider canvas, and each animation puts the character somewhere else on it.

const TEXTURE: Texture2D = preload("res://client/art/dark_mage.png")

## The three postures the pack covers. Ordered to match the atlas rows.
enum Anim { IDLE, WALK, CAST }

const CELL := Vector2(64.0, 64.0)

## Where, inside a cell, the character's feet are. The pivot everything hangs off, and
## the point a fighter's own position puts on the floor.
const ANCHOR := Vector2(26.0, 61.0)

## Roughly the character's middle, measured up from where they stand.
##
## Anything belonging to the *body* rather than to the ground hangs off this: a mage
## drawn standing upright has their chest here, and a cast aura gathering around their
## ankles reads as a puddle rather than as a spell. Ground marks — the footing, the
## status rings — stay at the feet, where the collision circle is.
const CHEST := Vector2(0.0, -26.0)

## Frames per row. The cast row is short: the pack's fourth attack frame is a
## right-facing burst of purple energy, which is a spell effect this game already draws
## itself, in the colour of the spell that was actually cast. See `docs/art-direction.md`.
const FRAME_COUNTS := [4, 4, 3]

const IDLE_FRAME_SECONDS: float = 0.22
const WALK_FRAME_SECONDS: float = 0.11

## Speed, in px/s, above which a fighter is walking rather than standing. Well under
## `PLAYER_MOVE_SPEED`, and well above the drift a server correction produces while a
## player stands still — otherwise a stationary remote fighter moonwalks on every
## snapshot.
const WALK_SPEED_THRESHOLD: float = 12.0


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


## Which frame of `anim` to show.
##
## Idle and walk loop on the clock. A cast does not: its frames are spread across the
## real cast progress, so the wind-up is a read on how close the spell is to landing
## rather than a loop that happens to be playing — the same choice `_draw_cast_animation`
## makes for the aura, and for the same reason. A one-second spell and a four-second one
## then look different, which is the point.
static func frame_for(anim: Anim, elapsed: float, cast_progress: float) -> int:
	var count: int = FRAME_COUNTS[anim]
	match anim:
		Anim.CAST:
			return clampi(int(clampf(cast_progress, 0.0, 1.0) * float(count)), 0, count - 1)
		Anim.WALK:
			return posmod(int(maxf(elapsed, 0.0) / WALK_FRAME_SECONDS), count)
		_:
			return posmod(int(maxf(elapsed, 0.0) / IDLE_FRAME_SECONDS), count)


## The patch of the atlas holding that frame.
static func region_for(anim: Anim, frame: int) -> Rect2:
	var column := posmod(frame, FRAME_COUNTS[anim])
	return Rect2(Vector2(float(column) * CELL.x, float(anim) * CELL.y), CELL)


## Where to put the atlas region so the character stands at `foot`, in the drawing
## node's own coordinates.
static func rect_for(foot: Vector2) -> Rect2:
	return Rect2(foot - ANCHOR, CELL)
