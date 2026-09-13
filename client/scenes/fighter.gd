extends CharacterBody2D
class_name Fighter

## Client-side body for a combatant: physics, input, and the character on screen.
##
## It owns a `Combatant` in all three of its configurations, and what changes between
## them is only who advances that combatant's clock and who owns its position:
##
##   offline practice   `server_driven` false — it runs the real rules itself, as it
##                      always has, and its own position is the truth.
##   networked, yours   both flags — steers on your input for feel, and is corrected
##                      toward whatever the server says.
##   networked, theirs  `server_driven` only — no input to read, so it simply coasts
##                      to wherever the last snapshot put it.

const RADIUS: float = Constants.PLAYER_RADIUS

## Cursor distance below which holding the move button does nothing. Without it a
## cursor resting on your own feet flips direction every frame and you vibrate.
##
## It belongs to the cursor and to nothing else. A routed waypoint is not a cursor — see
## `WAYPOINT_EPSILON` and `steering_direction_toward` for why applying this to one parked
## the character on every corner in the arena.
const MOUSE_DEAD_ZONE: float = 16.0

## How close an aim has to be before there is no direction left in it. Sub-pixel, because
## unlike the cursor a waypoint is somewhere you are going: fifteen pixels short of a
## corner is mid-walk, not a request to stand still.
const WAYPOINT_EPSILON: float = 0.01

## The colour the mantra is set in. Every colour still goes through `client/palette.gd`;
## the point size it is set at lives on `FighterChrome`.
const MANTRA_COLOR := Palette.MANTRA

## How long the release / fizzle / interrupt burst stays on screen. Feel, not chrome, so
## it stays a `const` — like the prediction thresholds below and unlike the overhead
## measurements, which moved to `client/art/fighter_chrome.tres`.
const BURST_SECONDS: float = 0.4
const RUNE_COUNT: int = 3

## How hard to pull a predicted body back toward the server's version of it. A player
## keeps running `move_and_slide` on their own input so steering stays instant, and this
## is what quietly reconciles the guess.
##
## At 225 px/s a player legitimately travels 11 px between snapshots, and the round trip
## adds more, so correcting under this would mean nagging at honest lag.
const CORRECTION_THRESHOLD: float = 28.0

## Worst-case honest drift the server itself already tolerates: `submit_input` is
## unreliable, so the packet that says "I let go" can go missing, and
## `server/arena_server.gd`'s `_step_movement` only gives up and zeroes the input after
## `Constants.INPUT_TIMEOUT_SECONDS` — up to that long spent still moving on a stale
## direction. `TELEPORT_THRESHOLD` has to clear this with real margin, or the server's
## own documented, expected packet loss trips a hard snap on a normal connection (#89).
const MAX_HONEST_DRIFT: float = Constants.PLAYER_MOVE_SPEED * Constants.INPUT_TIMEOUT_SECONDS

## Past this we are not correcting, we are teleporting — a respawn, or a desync worth
## admitting to. Snap, rather than sliding the body across the arena.
##
## Twice `MAX_HONEST_DRIFT`: a respawn moves a player clear across the arena, hundreds
## of pixels, so there is plenty of room above the input timeout's own worst case
## before this stops meaning "give up" and starts meaning "you were only ever lagging."
const TELEPORT_THRESHOLD: float = MAX_HONEST_DRIFT * 2.0

const CORRECTION_RATE: float = 8.0
const REMOTE_RATE: float = 18.0

@export var body_color: Color = Palette.PLAYER
@export var player_controlled: bool = false

## The overhead-chrome measurements — health bar, status-ring offsets, mantra sizing,
## footing rim, and the two sprite anchors the reads hang off. A resource so the art is
## tuned in the inspector, not as constants here. `fighter.tscn` names
## `client/art/fighter_chrome.tres`; `_ready` loads that default when a bare
## `Fighter.new()` leaves this null.
##
## The character's own animation set lives in `client/art/mage_frames.tres`, a
## `SpriteFrames` assigned to the `Character` `AnimatedSprite2D` in the scene —
## `_update_character_animation` only names an animation and calls `play()` on it.
@export var chrome: FighterChrome

## True when this body is a view of a combatant the server owns. It then advances no
## timers of its own — health, status and cast state are written from snapshots — and
## only the display timers move locally, so the cast bar doesn't step at snapshot rate.
@export var server_driven: bool = false

## Where the server last said this fighter is. Ignored while `server_driven` is false.
var server_position: Vector2 = Vector2.ZERO

## Off by default. Getting yourself around cover is the skill this game is about, so this
## is an assist you switch on, not the way the game plays.
var pathfinding_enabled: bool = false

## Set by `enable_pathfinding`. Null on every fighter nobody is steering — a remote body
## has no cursor to route toward — and null in every test that does not ask for it, which
## is what makes "off" provably the old code path rather than an equivalent one.
var _steering: PathSteering = null

var combatant: Combatant

## The character on screen: an `AnimatedSprite2D` whose `SpriteFrames` and per-set timing
## are authored in `client/art/mage_frames.tres`. `_update_character_animation` picks an
## animation name and plays it; nothing here sets a frame up. Null only for a bare
## `Fighter.new()` with no scene, which still runs its logic and draws its footing.
@onready var _character: AnimatedSprite2D = get_node_or_null(^"Character")

## Spell energy, on its own additive layer so glow accumulates toward white instead of
## flatly tinting the character. Authored lifted to the chest — the aura and the burst
## are things happening to a body, so they follow it up off the floor — and kept at z 0,
## not below: a negative z_index would sort it under the arena floor, which then paints
## over it.
@onready var _fx: Node2D = get_node_or_null(^"FX")

## Everything a player *reads* — status rings, health, the mantra — on its own layer
## above the character. Separate from `_draw` because the sprite goes underneath all of
## it, and because this layer keeps linear filtering for the downscaled Uncial mantra
## while the sprite wants nearest.
@onready var _ui: Node2D = get_node_or_null(^"UI")

var _anim_time: float = 0.0

## How fast this body actually moved last frame, which is not the same as `velocity`:
## a fighter the server owns is carried by `_apply_server_correction` and never has a
## velocity of its own, so reading `velocity` would leave every opponent sliding around
## the arena in an idle pose.
var _travel_speed: float = 0.0

## Which way this fighter is pointing. Derived from where it actually moved rather than
## from `velocity`, for the same reason `_travel_speed` is: a fighter the server owns
## has no velocity of its own. It is held rather than reset when a fighter stops, so
## standing still leaves you facing the way you were last going.
var _facing: Facing = Facing.DOWN

## Who this fighter is casting at, when anyone knows. A caster turns to face their
## target — standing still and throwing a flamestrike over your shoulder reads as a
## bug — and only the local client knows its own target, so this is set rather than
## inferred. Null leaves the heading to movement, which is what every remote fighter
## falls back to.
var _aim_at: Variant = null
var _burst_remaining: float = 0.0
var _burst_color: Color = Color.WHITE
var _burst_expands: bool = true


func _ready() -> void:
	# A bare `Fighter.new()` — the sceneless-fallback test still makes one — comes in with
	# no chrome. The scene wires the real resource; this is the fallback.
	if chrome == null:
		chrome = load("res://client/art/fighter_chrome.tres")

	combatant = Combatant.new()
	add_child(combatant)
	combatant.position = global_position

	# The collision shape, the character's SpriteFrames, the two draw layers and their
	# properties are all authored in `client/scenes/fighter.tscn` now; a sceneless
	# `Fighter.new()` simply has none, and the guards below let it run without them.
	if _fx != null:
		_fx.draw.connect(_draw_fx)
	if _ui != null:
		_ui.draw.connect(_draw_ui)

	var state := combatant.entity_state
	state.cast_completed.connect(
		func(spell: SpellData) -> void: _burst(SpellVisuals.color_for(spell), true)
	)
	state.cast_fizzled.connect(
		func(_spell: SpellData, _reason: String) -> void: _burst(Palette.CAST_FIZZLED, false)
	)
	state.cast_interrupted.connect(
		func(_spell: SpellData) -> void: _burst(Palette.CAST_INTERRUPTED, false)
	)


func _burst(color: Color, expands: bool) -> void:
	_burst_color = color
	_burst_expands = expands
	_burst_remaining = BURST_SECONDS


func _physics_process(delta: float) -> void:
	if server_driven:
		# Only the visible timers. Running the real step here would tick poison locally,
		# inventing damage the server never dealt and interrupt bursts nobody caused.
		combatant.entity_state.advance_display_only(delta)
	else:
		combatant.tick(delta)

	_anim_time += delta
	_burst_remaining = maxf(0.0, _burst_remaining - delta)

	# Prediction: a server-driven local player still steers itself, because waiting a
	# round trip to start moving would be felt on every dodge. Remote fighters have no
	# input to read, so they simply coast to wherever the last snapshot put them.
	var direction := Vector2.ZERO
	if player_controlled and combatant.can_move():
		direction = input_direction()
	velocity = direction * Constants.PLAYER_MOVE_SPEED

	var was_at := global_position
	move_and_slide()
	var predicted_at := global_position

	if server_driven:
		_apply_server_correction(delta)
	else:
		combatant.position = global_position

	_travel_speed = travel_speed_for(
		player_controlled, was_at, predicted_at, global_position, delta
	)
	_update_facing(global_position - was_at)
	_update_character_animation()

	queue_redraw()
	if _ui != null:
		_ui.queue_redraw()
	if _fx != null:
		_fx.queue_redraw()


## Pulls this body toward the server's version of where it is. Exponential rather than a
## raw lerp on delta, so the pull feels the same at any frame rate.
##
## Paralyze and death need nothing special here: both arrive through the snapshot into
## `can_move()`, so prediction stops on its own about a round trip late, and the
## overshoot that costs is roughly the size of the correction threshold — which is why
## the correction is a lerp rather than a snap.
func _apply_server_correction(delta: float) -> void:
	global_position = corrected_position(
		global_position, server_position, delta, player_controlled
	)
	combatant.position = global_position


## The reconciliation decision itself, pulled out static so the curve — where the dead
## zone ends, where a lerp turns into a snap — can be checked without a scene tree.
##
## `player_controlled` gets the dead zone below `CORRECTION_THRESHOLD` so honest, bounded
## lag isn't fought frame to frame; a remote fighter has nothing of its own predicting it,
## so it tracks every drift, however small. Both lerp at their own rate up to
## `TELEPORT_THRESHOLD`, past which this stops being a correction — see that constant's
## own doc comment for why the line sits where it does.
static func corrected_position(
	current: Vector2, target: Vector2, delta: float, player_controlled: bool
) -> Vector2:
	var error := current.distance_to(target)

	if error > TELEPORT_THRESHOLD:
		return target
	if not player_controlled:
		return current.lerp(target, 1.0 - exp(-delta * REMOTE_RATE))
	if error > CORRECTION_THRESHOLD:
		return current.lerp(target, 1.0 - exp(-delta * CORRECTION_RATE))
	return current


## Gives this fighter a route-finder to steer with. Injected rather than looked up, the
## same way `CombatResolver` takes its space state as an argument: a fighter has no
## business knowing how to go and find the arena.
func enable_pathfinding(finder: PathFinder) -> void:
	_steering = PathSteering.new(finder)


## Flips the assist and reports the new state, mirroring `SpellAudio.toggle_muted`.
func toggle_pathfinding() -> bool:
	pathfinding_enabled = not pathfinding_enabled
	return pathfinding_enabled


## The route still to walk, for the debug drawing. Empty whenever steering is straight.
func steering_path() -> PackedVector2Array:
	if not pathfinding_enabled or _steering == null:
		return PackedVector2Array()
	return _steering.path()


## Which way to steer for a cursor at `cursor`, going around cover when the assist is on
## and the straight line is blocked.
##
## The dead zone is applied to the cursor first and the straight line is tried before
## anything else, so with the assist off — or with nothing in the way — this returns the
## very same vector the game has always produced, from the very same call.
##
## Split out of `input_direction` so it can be exercised without a mouse to simulate.
func steering_direction_toward(cursor: Vector2) -> Vector2:
	var straight := movement_direction_toward(global_position, cursor)
	if straight == Vector2.ZERO:
		return straight
	if not pathfinding_enabled or _steering == null:
		return straight

	var aim := _steering.waypoint_toward(global_position, cursor)
	if aim == cursor:
		return straight

	var routed := waypoint_direction_toward(global_position, aim)
	# Only a genuinely degenerate aim gets here now — a waypoint under your own feet.
	# Walking straight is the worse route but it is never the wrong answer, so it is what
	# a failure degrades to.
	return straight if routed == Vector2.ZERO else routed


## Direction to steer in when the cursor is at `target`, or zero inside the dead zone.
static func movement_direction_toward(from: Vector2, target: Vector2) -> Vector2:
	var offset := target - from
	if offset.length() <= MOUSE_DEAD_ZONE:
		return Vector2.ZERO
	return offset.normalized()


## Direction to steer in toward a routed waypoint at `target`. The same normalise, with
## the cursor's dead zone replaced by a sub-pixel one.
##
## The distinction is the whole of issue #28. Cover is inflated by `PLAYER_RADIUS +
## CLEARANCE_MARGIN`, so a mitred right-angled corner puts the waypoint 22·√2 = 31.1px
## out from the real corner — and an 18px body cannot stand closer than 18px to it. That
## leaves a 2.9px band the body can reach where a 16px dead zone had already given up,
## and giving up means steering straight at the cursor, which is the line through the
## tent. The tent pushes you back out, the aim flips, and you stand there vibrating.
## Every cover piece and wall in the arena is an axis-aligned rectangle, so that was all
## 24 corners in the visibility graph.
static func waypoint_direction_toward(from: Vector2, target: Vector2) -> Vector2:
	var offset := target - from
	if offset.length() <= WAYPOINT_EPSILON:
		return Vector2.ZERO
	return offset.normalized()


# ── Animation: which way this fighter is pointing, and what posture it's in ───────
#
# Pulled in from `client/fighter_sprite.gd` (#81) — a `class_name` on a RefCounted that
# nothing ever instantiated. The decision belongs here for the same reason
# `movement_direction_toward` above does: it needs no scene tree or clock to test, and
# `_update_character_animation` below is the only caller. Grouped under this one header
# rather than scattered by kind, so a reader can still hold "everything about picking an
# animation" in one place.
#
# The frames themselves — regions, loop flags, playback speed — live in
# `client/art/mage_frames.tres`, a `SpriteFrames` resource authored in the editor and
# assigned to the `Character` `AnimatedSprite2D` in `client/scenes/fighter.tscn`. Nothing
# here sets a frame up; `_update_character_animation` only names one and calls `play()`
# on it.
#
# What this may say: posture and heading, and nothing else. Health, status, cast
# progress, which spell, whose body this is: every one of those stays a `_draw()` call in
# a palette colour, because ten fighters wear this same robe and one hooded robe cannot
# be told from another at a glance. See `docs/art-direction.md`.

## Which way a fighter is pointing. UO plays on a diagonal grid, so movement resolves to
## the nearest of four headings — but the pack (#93) only draws three of them plus a
## non-directional idle; `animation_name`/`should_flip_h` are what make LEFT a mirror of
## RIGHT rather than its own set.
enum Facing { DOWN, UP, RIGHT, LEFT }

## Posture. `CAST` has carried no art of its own since #93 replaced the pack — see
## `animation_name` and `_update_character_animation`, which fall back to `IDLE`/`WALK`
## rather than erroring while that's true, and pick it back up automatically the moment
## a `cast_*` animation exists again. Kept as a real state rather than deleted: casting
## still wins the *decision* in `animation_for`, it just has nothing to show for it yet.
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


## The speed `animation_for` should judge WALK/IDLE against, given where this body
## actually was, where its own prediction (or lack of one) put it, and where it ended
## up after any server correction.
##
## A player-controlled fighter's own predicted move is what "walking" means for them —
## measuring speed after a server correction instead would fold in however fast an
## active correction is currently pulling them on top of that, which can read as a
## dead sprint while genuinely standing still. `CORRECTION_THRESHOLD`'s dead zone means
## this is not a rare edge case: any correction that fires at all starts well above
## `WALK_SPEED_THRESHOLD`. Before #93 this stayed invisible — casting always showed a
## dedicated cast pose regardless of speed — but a cast with no art of its own now
## falls back to whatever WALK/IDLE would show, which is exactly where it surfaced: a
## stationary, casting, player-controlled fighter reading as walking.
##
## A remote fighter has no prediction of its own to measure — the corrected position is
## the only signal it has of moving at all, so it keeps using that.
static func travel_speed_for(
	player_controlled: bool,
	was_at: Vector2,
	predicted_at: Vector2,
	corrected_at: Vector2,
	delta: float
) -> float:
	if delta <= 0.0:
		return 0.0
	var moved_to := predicted_at if player_controlled else corrected_at
	return was_at.distance_to(moved_to) / delta


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


## The name of the `SpriteFrames` animation for a posture and a heading. Passed straight
## to `AnimatedSprite2D.play` by `_update_character_animation`, and
## `tests/test_fighter_frames.gd` checks the pack actually carries every name this can
## return.
##
## `IDLE` is one non-directional animation — the pack draws no per-heading standing pose.
## `WALK` has no dedicated `LEFT` set: it returns the same name as `RIGHT`, and
## `should_flip_h` is what turns that into a mirrored walk rather than a fighter who
## faces left but visibly walks right. `CAST` still returns a distinct name per heading,
## unchanged since before #93, even though the current pack defines none of them — see
## `Anim.CAST`'s doc comment.
static func animation_name(anim: Anim, facing: Facing) -> StringName:
	if anim == Anim.IDLE:
		return &"idle"

	var heading := "down"
	match facing:
		Facing.UP:
			heading = "up"
		Facing.RIGHT:
			heading = "right"
		Facing.LEFT:
			# No walk_left in the pack (#93) — animation_name hands back walk_right's own
			# name, and should_flip_h is what mirrors it.
			heading = "left" if anim == Anim.CAST else "right"
	var posture := "walk" if anim == Anim.WALK else "cast"
	return StringName("%s_%s" % [posture, heading])


## Whether the `Character` sprite should be drawn mirrored for this heading. The pack has
## no dedicated left-facing walk (see `animation_name`) — this is what turns `walk_right`
## into a walk_left instead.
##
## Safe only because `Character.centered = true` in `fighter.tscn`, with no asymmetric
## offset: a centred sprite mirrors around its own local origin, so flipping it can never
## make a fighter hop sideways the way the old pack's uncorrected left set once did.
static func should_flip_h(facing: Facing) -> bool:
	return facing == Facing.LEFT


## The steering this player is asking for, before any rule is applied to it. Public
## because a networked client has to send the server the very same direction it is
## predicting with locally — if the two disagreed, every step would need correcting.
func input_direction() -> Vector2:
	# UO steering: hold the right mouse button and walk toward the cursor.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return steering_direction_toward(get_global_mouse_position())

	# WASD kept as a convenience for testing; UO itself has no keyboard movement.
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		direction.y += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		direction.y -= 1.0
	return direction.normalized()


func _draw() -> void:
	_draw_footing()


## Plays the animation for this frame's heading and posture on the `Character`
## `AnimatedSprite2D`. The frames, their speed and their loop flag live in
## `client/art/mage_frames.tres`; this only names one and calls `play()` when the
## posture or heading changes.
##
## A cast is the exception: rather than run on the animation's own clock, its frame is
## scrubbed to real cast progress, so a one-second spell and a four-second one show a
## different pose at the same moment — the read on how close the spell is to landing,
## the same choice `_draw_cast_animation` makes for the aura. Since #93 the current pack
## has no `cast_*` animation at all, so that only happens when `has_animation` says one
## exists — until then casting falls back to whatever `IDLE`/`WALK` would have shown, so
## it causes no visible change rather than an error.
func _update_character_animation() -> void:
	if _character == null or _character.sprite_frames == null:
		return

	var state := combatant.entity_state
	var posture := animation_for(state.current_state, _travel_speed)
	var wanted := animation_name(posture, _facing)

	if posture == Anim.CAST and not _character.sprite_frames.has_animation(wanted):
		posture = Anim.WALK if _travel_speed > WALK_SPEED_THRESHOLD else Anim.IDLE
		wanted = animation_name(posture, _facing)

	_character.flip_h = should_flip_h(_facing)

	var count := _character.sprite_frames.get_frame_count(wanted)
	if count <= 0:
		return

	if posture == Anim.CAST and state.current_spell != null \
			and state.current_spell.cast_time_seconds > 0.0:
		if _character.animation != wanted:
			_character.play(wanted)
		var progress := clampf(
			state.cast_time_elapsed / state.current_spell.cast_time_seconds, 0.0, 1.0
		)
		_character.pause()
		_character.frame = clampi(int(progress * float(count)), 0, count - 1)
		return

	if _character.animation != wanted or not _character.is_playing():
		_character.play(wanted)


## The identity ring at the collision circle, in this fighter's own colour.
##
## The rim is not decoration, it is the identity read. Ten fighters wear one hooded
## robe, so the art cannot say which of them you are looking at; blue-is-you has to
## survive somewhere, and drawing it at the collision radius keeps `ArenaView`'s
## bargain besides — the shape you read is still exactly the shape that blocks. See
## `docs/art-direction.md`.
##
## The ground shadow this used to draw alongside the rim is the `Shadow` `Sprite2D`
## authored in `client/scenes/fighter.tscn` now (#93) — it carried no meaning of its
## own (`palette.gd`'s own comment on `BODY_SHADOW_ALPHA` called it "the weaker of the
## two on purpose"), so unlike the rim it was free to become an asset.
##
## `Shadow` sits at `z_index = -1` so it still paints under this rim despite being a
## child node (a parent's own `_draw()` otherwise always precedes its children's).
## That puts it in the same z bucket as `arena/arena_map.tscn`'s `Walls`/`Cover`
## layers (also -1) — it still renders under cover today only because `Arena` is
## added to the tree before `Stage`/spawned fighters in both
## `client/scenes/arena_client.tscn` and `client/scenes/local_test.tscn`, so tree
## order breaks the tie. A future reorder of `Arena` vs `Stage` could regress that
## silently — nothing currently tests it.
func _draw_footing() -> void:
	draw_arc(
		Vector2.ZERO, RADIUS, 0.0, TAU, 32,
		Color(body_color, Palette.BODY_RING_ALPHA), chrome.footing_rim_width, true
	)


## Turns this fighter toward whatever it is casting at, or back to its heading of
## travel. Called by whoever knows the target; `null` gives movement the say again.
func aim_at(target: Variant) -> void:
	_aim_at = target


## Which way this fighter is pointing. Public so a test can read it without drawing.
func facing() -> Facing:
	return _facing


## Hands the frame's facts to `heading_for` above and keeps the answer. The decision
## itself is a static, callable without a scene tree — see the section above.
func _update_facing(travelled: Vector2) -> void:
	_facing = heading_for(
		combatant.entity_state.current_state == EntityState.State.CASTING,
		_aim_at,
		global_position,
		travelled,
		_facing
	)


## Status, health and speech, above the character rather than on it.
func _draw_ui() -> void:
	if combatant.is_paralyzed():
		_ui.draw_arc(
			Vector2.ZERO, RADIUS + chrome.paralyze_ring_offset, 0.0, TAU, 32,
			Palette.STATUS_PARALYZED, 3.0, true
		)
	if combatant.poison_seconds_remaining > 0.0:
		_ui.draw_arc(
			Vector2.ZERO, RADIUS + chrome.poison_ring_offset, 0.0, TAU, 32,
			Palette.STATUS_POISONED, 2.0, true
		)

	_draw_health_bar()
	_draw_mantra()


func _draw_fx() -> void:
	_draw_cast_animation()
	_draw_burst()


## Charging aura: a crackling ring that tightens and brightens with real cast progress,
## throwing arcs outward the way the concept art does. Keyed to progress rather than to
## a loop, so it doubles as a read on how close the spell is to landing.
func _draw_cast_animation() -> void:
	var state := combatant.entity_state

	if state.current_state == EntityState.State.RECOVERING:
		var left := 1.0 - state.recovery_time_elapsed / Constants.GLOBAL_CAST_RECOVERY_SECONDS
		var embers := SpellFX.ring_path(RADIUS + 12.0, 20, 5.0, SpellFX.crackle_seed(_anim_time))
		SpellFX.draw_glow_line(_fx, embers, Palette.CAST_RECOVERING, 0.35 * left, 0.6, true)
		return

	if state.current_state != EntityState.State.CASTING:
		return

	var progress := clampf(
		state.cast_time_elapsed / state.current_spell.cast_time_seconds, 0.0, 1.0
	)
	var color := SpellVisuals.color_for(state.current_spell)
	var flame := SpellVisuals.style_for(state.current_spell) == SpellVisuals.Style.FLAME
	var seed := SpellFX.crackle_seed(_anim_time)

	# Energy gathers inward as the spell comes together.
	var radius := (RADIUS + 26.0) - progress * 9.0
	var intensity := 0.35 + progress * 0.65

	SpellFX.draw_glow_disc(_fx, Vector2.ZERO, radius * 1.15, color, intensity * 0.9)

	# Flame wanders in soft rounded tendrils; arc snaps in sharp angular ones.
	var jitter := (2.0 if flame else 4.5) + progress * 2.5
	var ring_points := 34 if flame else 26
	var ring := SpellFX.ring_path(radius, ring_points, jitter, seed)
	SpellFX.draw_glow_line(_fx, ring, color, intensity, 0.75 + progress * 0.5, true)

	# Arcs thrown outward off the ring — the detail that makes it read as energy.
	var spikes := 5 + int(progress * 4.0)
	for i in spikes:
		var anchor: Vector2 = ring[(i * ring.size() / spikes) % ring.size()]
		var reach := (6.0 + progress * 12.0) * (1.4 if flame else 1.0)
		var tip := anchor + anchor.normalized() * reach
		var arc := SpellFX.bolt_path(
			anchor, tip, 3, (1.5 if flame else 4.0), seed + i * 31
		)
		SpellFX.draw_glow_line(_fx, arc, color, intensity * 0.8, 0.5)


## Release, fizzle or interrupt. A completed cast throws a ring outward; a failed one
## collapses inward, so the two read differently at a glance.
func _draw_burst() -> void:
	if _burst_remaining <= 0.0:
		return
	var fade := _burst_remaining / BURST_SECONDS
	var radius := (RADIUS + 6.0) + (1.0 - fade) * 34.0 if _burst_expands \
		else (RADIUS + 30.0) * fade
	if radius < 1.0:
		return
	var ring := SpellFX.ring_path(
		radius, 28, radius * 0.10, SpellFX.crackle_seed(_anim_time, 7)
	)
	SpellFX.draw_glow_line(_fx, ring, _burst_color, fade, 0.9, true)
	SpellFX.draw_glow_disc(_fx, Vector2.ZERO, radius, _burst_color, fade * 0.7)


## The spoken words, overhead, for as long as the cast runs. This is the opponent's
## read on what is coming — and what a fizzle-feint fakes.
func _draw_mantra() -> void:
	var state := combatant.entity_state
	if state.current_state != EntityState.State.CASTING:
		return

	var font := SpellVisuals.MANTRA_FONT
	var text: String = state.current_spell.mantra
	var font_size := chrome.mantra_font_size
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := Vector2(-width * 0.5, chrome.head_top - chrome.overhead_gap - chrome.mantra_gap)

	# Dark outline so the words stay readable over the arena floor. One call rather than
	# the four offset passes this used to take.
	_ui.draw_string_outline(
		font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		chrome.mantra_outline_size, Palette.OUTLINE
	)
	_ui.draw_string(
		font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, MANTRA_COLOR
	)


func _draw_health_bar() -> void:
	var fraction := clampf(combatant.health / Constants.PLAYER_MAX_HEALTH, 0.0, 1.0)
	var bar_width := chrome.health_bar_width
	var bar_height := chrome.health_bar_height
	var origin := Vector2(-bar_width * 0.5, chrome.head_top - chrome.overhead_gap)
	_ui.draw_rect(Rect2(origin, Vector2(bar_width, bar_height)), Palette.BAR_TRACK)
	_ui.draw_rect(
		Rect2(origin, Vector2(bar_width * fraction, bar_height)),
		Palette.HEALTH_HURT if fraction < Palette.HEALTH_HURT_FRACTION \
			else Palette.HEALTH_HEALTHY
	)
	_ui.draw_rect(
		Rect2(origin, Vector2(bar_width, bar_height)), Palette.OUTLINE, false, 1.0
	)
