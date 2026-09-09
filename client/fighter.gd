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

## Top of the character's head, in body coordinates. Everything overhead hangs off
## this rather than off `RADIUS`: the sprite is taller than the collision circle, so a
## bar placed above the circle would be drawn across the mage's chest. Read off `sprite`
## in `_ready` rather than a `const`, now that the atlas geometry lives in a resource.
var _head_top: float = 0.0

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

## Past this we are not correcting, we are teleporting — a respawn, or a desync worth
## admitting to. Snap, rather than sliding the body across the arena.
const TELEPORT_THRESHOLD: float = 120.0

const CORRECTION_RATE: float = 8.0
const REMOTE_RATE: float = 18.0

@export var body_color: Color = Palette.PLAYER
@export var player_controlled: bool = false

## The character atlas and its frame table. A resource so the art is swapped in the
## editor rather than in code — `client/scenes/fighter.tscn` names `client/art/wizard.tres`
## here. Left assignable rather than hard-wired so a bare `Fighter.new()` in a test still
## gets the default, which `_ready` loads when this is null.
@export var sprite: FighterSprite

## The overhead-chrome measurements — health bar, status-ring offsets, mantra sizing,
## footing rim. A resource for the same reason `sprite` is: tuned in the inspector next
## to the sprite, not as constants here. `fighter.tscn` names
## `client/art/fighter_chrome.tres`; `_ready` loads that default when a bare
## `Fighter.new()` leaves this null.
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

## The character on screen. A `Sprite2D` child rather than a `draw_texture_rect_region`
## call, so it can be selected and previewed in the editor; `_sync_character` walks its
## `region_rect` across the atlas each frame. Null only for a bare `Fighter.new()` with
## no scene, which still runs its logic and draws its footing.
@onready var _character: Sprite2D = get_node_or_null(^"Character")

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
	# A bare `Fighter.new()` — the sceneless-fallback test still makes one — comes in with
	# no sprite and no chrome. The scene wires the real resources; these are the fallbacks.
	if sprite == null:
		sprite = load("res://client/art/wizard.tres")
	if chrome == null:
		chrome = load("res://client/art/fighter_chrome.tres")
	_head_top = sprite.head_top()

	combatant = Combatant.new()
	add_child(combatant)
	combatant.position = global_position

	# The scene authors the atlas texture on the `Character` node, but a swapped
	# `FighterSprite` can point at a different sheet — keep the node in step with it.
	if _character != null:
		_character.texture = sprite.texture

	# The collision shape, the two draw layers and their properties are all authored in
	# `client/scenes/fighter.tscn` now; a sceneless `Fighter.new()` simply has none, and
	# the guards below let it run without them.
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

	if server_driven:
		_apply_server_correction(delta)
	else:
		combatant.position = global_position

	if delta > 0.0:
		_travel_speed = was_at.distance_to(global_position) / delta
	_update_facing(global_position - was_at)

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
	_sync_character()
	_draw_footing()


## Points the `Character` node at this frame's atlas cell. The frame maths still lives in
## `FighterSprite` and `current_frame_region`; this only copies the answer onto a node the
## editor can show, in place of the `draw_texture_rect_region` call it replaced —
## `centered = false` plus this `offset` reproduces the old `rect_for` top-left exactly.
##
## Driven from `_draw` rather than `_physics_process` so the sprite tracks the posture on
## every redraw, including the ones a frozen pose asks for (the promo capture) where
## physics is not running.
func _sync_character() -> void:
	if _character == null:
		return
	_character.region_rect = current_frame_region()
	_character.offset = -sprite.anchor(_facing)


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
		Color(body_color, Palette.BODY_RING_ALPHA), chrome.footing_rim_width, true
	)


## Which patch of the atlas this fighter is showing right now. Public so the practice
## harness and the tests can ask without waiting for a frame to be drawn.
func current_frame_region() -> Rect2:
	var state := combatant.entity_state
	var anim := FighterSprite.animation_for(state.current_state, _travel_speed)
	var progress := 0.0
	if anim == FighterSprite.Anim.CAST and state.current_spell != null:
		progress = state.cast_time_elapsed / state.current_spell.cast_time_seconds
	return sprite.region_for(
		sprite.frame_for(anim, _facing, _anim_time, progress)
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
	var origin := Vector2(-width * 0.5, _head_top - chrome.overhead_gap - chrome.mantra_gap)

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
	var origin := Vector2(-bar_width * 0.5, _head_top - chrome.overhead_gap)
	_ui.draw_rect(Rect2(origin, Vector2(bar_width, bar_height)), Palette.BAR_TRACK)
	_ui.draw_rect(
		Rect2(origin, Vector2(bar_width * fraction, bar_height)),
		Palette.HEALTH_HURT if fraction < Palette.HEALTH_HURT_FRACTION \
			else Palette.HEALTH_HEALTHY
	)
	_ui.draw_rect(
		Rect2(origin, Vector2(bar_width, bar_height)), Palette.OUTLINE, false, 1.0
	)
