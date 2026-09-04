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

@export var body_color: Color = Color("#6ec6ff")
@export var player_controlled: bool = false

var combatant: Combatant


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


func _physics_process(delta: float) -> void:
	combatant.tick_status(delta)

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
	draw_circle(Vector2.ZERO, RADIUS, body_color)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, body_color.darkened(0.4), 2.0, true)

	if combatant.is_paralyzed():
		draw_arc(Vector2.ZERO, RADIUS + 7.0, 0.0, TAU, 32, Color("#ffd166"), 3.0, true)
	if combatant.poison_seconds_remaining > 0.0:
		draw_arc(Vector2.ZERO, RADIUS + 13.0, 0.0, TAU, 32, Color("#7ee081"), 2.0, true)

	_draw_health_bar()
	_draw_mantra()


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
