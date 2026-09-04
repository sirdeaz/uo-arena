extends CharacterBody2D
class_name Fighter

## Client-side body for a combatant: physics, input, and a placeholder drawn shape.
## Owns a `Combatant` (the authoritative rules object) and keeps its position in sync.
## When networking lands this becomes the client's predicted view of a server entity.

const RADIUS: float = 18.0
const HEALTH_BAR_WIDTH: float = 52.0

## Cursor distance below which holding the move button does nothing. Without it a
## cursor resting on your own feet flips direction every frame and you vibrate.
const MOUSE_DEAD_ZONE: float = 16.0

const MANTRA_COLOR := Color("#dcd0ff")

## How long the release / fizzle / interrupt burst stays on screen.
const BURST_SECONDS: float = 0.4
const RUNE_COUNT: int = 3

@export var body_color: Color = Color("#6ec6ff")
@export var player_controlled: bool = false

var combatant: Combatant

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
	combatant.tick_status(delta)
	_anim_time += delta
	_burst_remaining = maxf(0.0, _burst_remaining - delta)

	var direction := Vector2.ZERO
	if player_controlled and combatant.can_move():
		direction = _input_direction()
	velocity = direction * Constants.PLAYER_MOVE_SPEED
	move_and_slide()

	combatant.position = global_position
	queue_redraw()


## Direction to steer in when the cursor is at `target`, or zero inside the dead zone.
static func movement_direction_toward(from: Vector2, target: Vector2) -> Vector2:
	var offset := target - from
	if offset.length() <= MOUSE_DEAD_ZONE:
		return Vector2.ZERO
	return offset.normalized()


func _input_direction() -> Vector2:
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
	_draw_cast_animation()
	_draw_burst()

	draw_circle(Vector2.ZERO, RADIUS, body_color)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, body_color.darkened(0.4), 2.0, true)

	if combatant.is_paralyzed():
		draw_arc(Vector2.ZERO, RADIUS + 7.0, 0.0, TAU, 32, Color("#ffd166"), 3.0, true)
	if combatant.poison_seconds_remaining > 0.0:
		draw_arc(Vector2.ZERO, RADIUS + 13.0, 0.0, TAU, 32, Color("#7ee081"), 2.0, true)

	_draw_health_bar()
	_draw_mantra()


## Charging animation: a glow that brightens, a ring that fills with cast progress, and
## runes that orbit faster and draw inward as the spell nears release. All of it is
## keyed to real cast progress, so it doubles as a read on how far along they are.
func _draw_cast_animation() -> void:
	var state := combatant.entity_state

	if state.current_state == EntityState.State.RECOVERING:
		var recovery := state.recovery_time_elapsed / Constants.GLOBAL_CAST_RECOVERY_SECONDS
		draw_arc(
			Vector2.ZERO, RADIUS + 8.0, 0.0, TAU, 32,
			Color("#8a8f9c", 0.35 * (1.0 - recovery)), 2.0, true
		)
		return

	if state.current_state != EntityState.State.CASTING:
		return

	var progress := clampf(
		state.cast_time_elapsed / state.current_spell.cast_time_seconds, 0.0, 1.0
	)
	var color := SpellVisuals.color_for(state.current_spell)

	# Gathering glow beneath the caster.
	var pulse := 1.0 + sin(_anim_time * 9.0) * 0.06
	draw_circle(
		Vector2.ZERO, (RADIUS + 10.0) * pulse, Color(color, 0.10 + progress * 0.22)
	)

	# Progress ring, filling clockwise from the top.
	draw_arc(
		Vector2.ZERO, RADIUS + 9.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 48,
		Color(color, 0.9), 3.0, true
	)

	# Runes orbiting faster and tighter as the spell comes together.
	var orbit := (RADIUS + 22.0) - progress * 10.0
	var spin := _anim_time * (2.0 + progress * 6.0)
	for i in RUNE_COUNT:
		var angle := spin + TAU * float(i) / float(RUNE_COUNT)
		draw_circle(
			Vector2(orbit, 0).rotated(angle), 2.5 + progress * 1.5, Color(color, 0.95)
		)


## Release, fizzle or interrupt. A completed cast throws a ring outward; a failed one
## collapses inward, so the two read differently at a glance.
func _draw_burst() -> void:
	if _burst_remaining <= 0.0:
		return
	var fade := _burst_remaining / BURST_SECONDS
	var radius := (RADIUS + 6.0) + (1.0 - fade) * 26.0 if _burst_expands \
		else (RADIUS + 26.0) * fade
	draw_arc(
		Vector2.ZERO, maxf(radius, 1.0), 0.0, TAU, 32, Color(_burst_color, fade), 3.0, true
	)


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
