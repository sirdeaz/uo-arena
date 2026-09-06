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
const HEALTH_BAR_WIDTH: float = 52.0

## Top of the character's head, in body coordinates. Everything overhead hangs off
## this rather than off `RADIUS`: the sprite is taller than the collision circle, so a
## bar placed above the circle would be drawn across the mage's chest.
const HEAD_TOP: float = -FighterSprite.ANCHORS[FighterSprite.Facing.DOWN].y

## Gap between the head and the health bar, and between the bar and the mantra above it.
const OVERHEAD_GAP: float = 6.0
const MANTRA_GAP: float = 14.0

## Cursor distance below which holding the move button does nothing. Without it a
## cursor resting on your own feet flips direction every frame and you vibrate.
const MOUSE_DEAD_ZONE: float = 16.0

const MANTRA_COLOR := Palette.MANTRA
const MANTRA_FONT_SIZE: int = 16

## Thickness of the dark halo behind the mantra. The words are read against the arena
## floor at a glance, mid-fight, so they get an outline rather than relying on contrast.
const MANTRA_OUTLINE_SIZE: int = 3

## How long the release / fizzle / interrupt burst stays on screen.
const BURST_SECONDS: float = 0.4
const RUNE_COUNT: int = 3

## How hard to pull a predicted body back toward the server's version of it. A player
## keeps running `move_and_slide` on their own input so steering stays instant, and this
## is what quietly reconciles the guess.
##
## At 225 px/s a player legitimately travels 11 px between snapshots, and the round trip
## adds more, so correcting under this would mean nagging at honest lag.
const CORRECTION_THRESHOLD: float = 28.0

## Past this we are not correcting, we are teleporting — a respawn, or a desync worth
## admitting to. Snap, rather than sliding the body across the arena.
const TELEPORT_THRESHOLD: float = 120.0

const CORRECTION_RATE: float = 8.0
const REMOTE_RATE: float = 18.0

@export var body_color: Color = Palette.PLAYER
@export var player_controlled: bool = false

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

var _fx: Node2D

## Everything a player *reads* — status rings, health, the mantra — drawn on its own
## layer above the character. A child rather than part of `_draw` because the sprite
## has to go underneath all of it, and because this layer wants the engine's default
## filtering for text while the sprite wants none at all.
var _ui: Node2D

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
var _facing: FighterSprite.Facing = FighterSprite.Facing.DOWN

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
	combatant = Combatant.new()
	add_child(combatant)

	collision_layer = Constants.LAYER_PLAYERS
	collision_mask = Constants.LAYER_OBSTACLES

	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	collision.shape = circle
	add_child(collision)

	combatant.position = global_position

	# Nearest-neighbour, and only on this node: the character is pixel art, and the
	# engine's default smoothing turns a 64 px mage into a smear. The overhead text on
	# `_ui` is deliberately left on the default filter, where it belongs.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# Spell energy draws on its own additive layer so glow accumulates toward white
	# instead of flatly tinting the character. Kept at z 0, not below: a negative
	# z_index would sort it under the arena floor, which then paints over it.
	_fx = Node2D.new()
	# Lifted to the character's chest. The aura and the burst are things happening to a
	# body, so they follow the body up off the floor — unlike the sight line and the
	# bolts, which stay at the feet because that is where the raycast actually is, and
	# a drawn line that is not the line being tested is the failure `ArenaView` exists
	# to avoid.
	_fx.position = FighterSprite.CHEST
	_fx.z_index = 0
	_fx.material = SpellFX.additive_material()
	add_child(_fx)
	_fx.draw.connect(_draw_fx)

	# Added last so it draws last. Health, status and the mantra are the reads that
	# decide fights, and a cast aura is now big enough and high enough to sit right
	# behind them — so they go over the glow, not under it.
	_ui = Node2D.new()
	add_child(_ui)
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

	if server_driven:
		_apply_server_correction(delta)
	else:
		combatant.position = global_position

	if delta > 0.0:
		_travel_speed = was_at.distance_to(global_position) / delta
	_update_facing(global_position - was_at)

	queue_redraw()
	_ui.queue_redraw()
	_fx.queue_redraw()


## Pulls this body toward the server's version of where it is. Exponential rather than a
## raw lerp on delta, so the pull feels the same at any frame rate.
##
## Paralyze and death need nothing special here: both arrive through the snapshot into
## `can_move()`, so prediction stops on its own about a round trip late, and the
## overshoot that costs is roughly the size of the correction threshold — which is why
## the correction is a lerp rather than a snap.
func _apply_server_correction(delta: float) -> void:
	var error := global_position.distance_to(server_position)

	if error > TELEPORT_THRESHOLD:
		global_position = server_position
	elif not player_controlled:
		# Nobody is predicting this one, so track tightly. The smoothing is here only to
		# hide the step between snapshots.
		global_position = global_position.lerp(
			server_position, 1.0 - exp(-delta * REMOTE_RATE)
		)
	elif error > CORRECTION_THRESHOLD:
		global_position = global_position.lerp(
			server_position, 1.0 - exp(-delta * CORRECTION_RATE)
		)

	combatant.position = global_position


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

	var routed := movement_direction_toward(global_position, aim)
	# An aim inside the dead zone would stand you still. Walking straight is the worse
	# route but it is never the wrong answer, so it is what a failure degrades to.
	return straight if routed == Vector2.ZERO else routed


## Direction to steer in when the cursor is at `target`, or zero inside the dead zone.
static func movement_direction_toward(from: Vector2, target: Vector2) -> Vector2:
	var offset := target - from
	if offset.length() <= MOUSE_DEAD_ZONE:
		return Vector2.ZERO
	return offset.normalized()


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
	draw_texture_rect_region(
		FighterSprite.TEXTURE,
		FighterSprite.rect_for(Vector2.ZERO, _facing),
		current_frame_region()
	)


## The mark on the floor the character stands on: the collision circle itself, filled
## as a shadow and rimmed in this fighter's own colour.
##
## The rim is not decoration, it is the identity read, and it is why the circle this
## replaced could go. Ten fighters wear one hooded robe, so the art cannot say which of
## them you are looking at; blue-is-you has to survive somewhere, and drawing it at the
## collision radius keeps `ArenaView`'s bargain besides — the shape you read is still
## exactly the shape that blocks.
func _draw_footing() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color(Palette.OUTLINE, Palette.BODY_SHADOW_ALPHA))
	draw_arc(
		Vector2.ZERO, RADIUS, 0.0, TAU, 32,
		Color(body_color, Palette.BODY_RING_ALPHA), 2.0, true
	)


## Which patch of the atlas this fighter is showing right now. Public so the practice
## harness and the tests can ask without waiting for a frame to be drawn.
func current_frame_region() -> Rect2:
	var state := combatant.entity_state
	var anim := FighterSprite.animation_for(state.current_state, _travel_speed)
	var progress := 0.0
	if anim == FighterSprite.Anim.CAST and state.current_spell != null:
		progress = state.cast_time_elapsed / state.current_spell.cast_time_seconds
	return FighterSprite.region_for(
		FighterSprite.frame_for(anim, _facing, _anim_time, progress)
	)


## Turns this fighter toward whatever it is casting at, or back to its heading of
## travel. Called by whoever knows the target; `null` gives movement the say again.
func aim_at(target: Variant) -> void:
	_aim_at = target


## Which way this fighter is pointing. Public so a test can read it without drawing.
func facing() -> FighterSprite.Facing:
	return _facing


## Hands the frame's facts to `FighterSprite.heading_for` and keeps the answer. The
## decision itself lives there, where a test can call it without a scene tree.
func _update_facing(travelled: Vector2) -> void:
	_facing = FighterSprite.heading_for(
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
			Vector2.ZERO, RADIUS + 7.0, 0.0, TAU, 32, Palette.STATUS_PARALYZED, 3.0, true
		)
	if combatant.poison_seconds_remaining > 0.0:
		_ui.draw_arc(
			Vector2.ZERO, RADIUS + 13.0, 0.0, TAU, 32, Palette.STATUS_POISONED, 2.0, true
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
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, MANTRA_FONT_SIZE).x
	var origin := Vector2(-width * 0.5, HEAD_TOP - OVERHEAD_GAP - MANTRA_GAP)

	# Dark outline so the words stay readable over the arena floor. One call rather than
	# the four offset passes this used to take.
	_ui.draw_string_outline(
		font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, MANTRA_FONT_SIZE,
		MANTRA_OUTLINE_SIZE, Palette.OUTLINE
	)
	_ui.draw_string(
		font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, MANTRA_FONT_SIZE, MANTRA_COLOR
	)


func _draw_health_bar() -> void:
	var fraction := clampf(combatant.health / Constants.PLAYER_MAX_HEALTH, 0.0, 1.0)
	var origin := Vector2(-HEALTH_BAR_WIDTH * 0.5, HEAD_TOP - OVERHEAD_GAP)
	_ui.draw_rect(Rect2(origin, Vector2(HEALTH_BAR_WIDTH, 6.0)), Palette.BAR_TRACK)
	_ui.draw_rect(
		Rect2(origin, Vector2(HEALTH_BAR_WIDTH * fraction, 6.0)),
		Palette.HEALTH_HURT if fraction < Palette.HEALTH_HURT_FRACTION \
			else Palette.HEALTH_HEALTHY
	)
	_ui.draw_rect(
		Rect2(origin, Vector2(HEALTH_BAR_WIDTH, 6.0)), Palette.OUTLINE, false, 1.0
	)
