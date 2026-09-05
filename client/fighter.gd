extends CharacterBody2D
class_name Fighter

## Client-side body for a combatant: physics, input, and a placeholder drawn shape.
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

## Cursor distance below which holding the move button does nothing. Without it a
## cursor resting on your own feet flips direction every frame and you vibrate.
const MOUSE_DEAD_ZONE: float = 16.0

const MANTRA_COLOR := Color("#dcd0ff")

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

@export var body_color: Color = Color("#6ec6ff")
@export var player_controlled: bool = false

## True when this body is a view of a combatant the server owns. It then advances no
## timers of its own — health, status and cast state are written from snapshots — and
## only the display timers move locally, so the cast bar doesn't step at snapshot rate.
@export var server_driven: bool = false

## Where the server last said this fighter is. Ignored while `server_driven` is false.
var server_position: Vector2 = Vector2.ZERO

var combatant: Combatant

var _fx: Node2D
var _anim_time: float = 0.0
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

	# Spell energy draws on its own additive layer so glow accumulates toward white
	# instead of flatly tinting the character. Kept at z 0, not below: a negative
	# z_index would sort it under the arena floor, which then paints over it.
	_fx = Node2D.new()
	_fx.z_index = 0
	_fx.material = SpellFX.additive_material()
	add_child(_fx)
	_fx.draw.connect(_draw_fx)

	var state := combatant.entity_state
	state.cast_completed.connect(
		func(spell: SpellData) -> void: _burst(SpellVisuals.color_for(spell), true)
	)
	state.cast_fizzled.connect(
		func(_spell: SpellData, _reason: String) -> void: _burst(Color("#8a8f9c"), false)
	)
	state.cast_interrupted.connect(
		func(_spell: SpellData) -> void: _burst(Color("#ffa447"), false)
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
	move_and_slide()

	if server_driven:
		_apply_server_correction(delta)
	else:
		combatant.position = global_position

	queue_redraw()
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
		return movement_direction_toward(global_position, get_global_mouse_position())

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
	draw_circle(Vector2.ZERO, RADIUS, body_color)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, body_color.darkened(0.4), 2.0, true)

	if combatant.is_paralyzed():
		draw_arc(Vector2.ZERO, RADIUS + 7.0, 0.0, TAU, 32, Color("#ffd166"), 3.0, true)
	if combatant.poison_seconds_remaining > 0.0:
		draw_arc(Vector2.ZERO, RADIUS + 13.0, 0.0, TAU, 32, Color("#7ee081"), 2.0, true)

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
		SpellFX.draw_glow_line(_fx, embers, Color("#8a8f9c"), 0.35 * left, 0.6, true)
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

	var font := ThemeDB.fallback_font
	var font_size := 16
	var text: String = state.current_spell.mantra
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := Vector2(-width * 0.5, -RADIUS - 30.0)

	# Dark outline first so the words stay readable over the arena floor.
	for offset in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_string(
			font, origin + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			Color("#0d1017")
		)
	draw_string(
		font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, MANTRA_COLOR
	)


func _draw_health_bar() -> void:
	var fraction := clampf(combatant.health / Constants.PLAYER_MAX_HEALTH, 0.0, 1.0)
	var origin := Vector2(-HEALTH_BAR_WIDTH * 0.5, -RADIUS - 18.0)
	draw_rect(Rect2(origin, Vector2(HEALTH_BAR_WIDTH, 6.0)), Color("#2b2f3a"))
	draw_rect(
		Rect2(origin, Vector2(HEALTH_BAR_WIDTH * fraction, 6.0)),
		Color("#e2574c") if fraction < 0.35 else Color("#7ee081")
	)
	draw_rect(
		Rect2(origin, Vector2(HEALTH_BAR_WIDTH, 6.0)), Color("#0d1017"), false, 1.0
	)
