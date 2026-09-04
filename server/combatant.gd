extends Node
class_name Combatant

## The server's authoritative view of a fighter: position, health, status timers, and
## the cast state machine. Deliberately a plain `Node` with a `position` field rather
## than a `Node2D` — the server needs a point to raycast from, not a transform to
## render, and this keeps `server/` clean for the Dedicated Server export.

signal health_changed(new_health: float)
signal died

## Poison lands as discrete ticks, one per second, the way it reads in classic UO.
const POISON_TICK_SECONDS: float = 1.0

var position: Vector2 = Vector2.ZERO
var health: float = Constants.PLAYER_MAX_HEALTH
var poison_seconds_remaining: float = 0.0
var poison_damage_per_tick: float = 0.0
var paralyze_seconds_remaining: float = 0.0
var entity_state: EntityState

var _poison_tick_accumulator: float = 0.0


func _init() -> void:
	entity_state = EntityState.new()
	entity_state.name = "EntityState"


func _ready() -> void:
	add_child(entity_state)


func is_alive() -> bool:
	return health > 0.0


func is_paralyzed() -> bool:
	return paralyze_seconds_remaining > 0.0


func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health)
	# Any damage that lands breaks a spell — direct hits and poison ticks alike.
	entity_state.interrupt_cast()
	if health == 0.0:
		died.emit()


func apply_poison(duration_seconds: float, damage_per_tick: float = 0.0) -> void:
	# Re-poisoning refreshes rather than stacks.
	poison_seconds_remaining = maxf(poison_seconds_remaining, duration_seconds)
	poison_damage_per_tick = maxf(poison_damage_per_tick, damage_per_tick)


func apply_paralyze(duration_seconds: float) -> void:
	paralyze_seconds_remaining = maxf(paralyze_seconds_remaining, duration_seconds)


## Advances status timers by `delta`. Driven by the server so that tests (and, later,
## a fixed server step) can advance time explicitly rather than in real seconds.
func tick_status(delta: float) -> void:
	paralyze_seconds_remaining = maxf(0.0, paralyze_seconds_remaining - delta)

	if poison_seconds_remaining <= 0.0:
		return

	# Poison only burns for the time it has left, so a large delta can't over-tick it.
	var poisoned_for := minf(delta, poison_seconds_remaining)
	poison_seconds_remaining -= poisoned_for
	_poison_tick_accumulator += poisoned_for

	while _poison_tick_accumulator >= POISON_TICK_SECONDS:
		_poison_tick_accumulator -= POISON_TICK_SECONDS
		take_damage(poison_damage_per_tick)

	if poison_seconds_remaining <= 0.0:
		poison_damage_per_tick = 0.0
		_poison_tick_accumulator = 0.0
