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


## Casting never pins you — moving while casting is the whole premise. Paralyze is the
## only thing that stops your feet, and it leaves you free to keep casting.
func can_move() -> bool:
	return is_alive() and not is_paralyzed()


func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	# A corpse takes no further hits. Without this, poison carries on ticking a dead
	# body and re-emits `died` on every tick — which, now that something listens for
	# `died` in order to schedule a respawn, would queue a fresh respawn every second
	# until the poison ran out.
	if not is_alive():
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


## Stand back up. Full health, nothing lingering, and nothing queued — a respawn is not
## a fizzle and not an interrupt, so `entity_state.reset()` announces none of them.
func revive(at: Vector2) -> void:
	position = at
	health = Constants.PLAYER_MAX_HEALTH
	poison_seconds_remaining = 0.0
	poison_damage_per_tick = 0.0
	paralyze_seconds_remaining = 0.0
	_poison_tick_accumulator = 0.0
	entity_state.reset()
	health_changed.emit(health)


## The authoritative step: one call advances everything this combatant owns. Exactly one
## thing calls it — the server in a networked match, the fighter itself in the offline
## harness — and nothing else advances any part of it. Status runs before cast timing so
## that a poison tick landing this frame interrupts the spell before it can complete.
func tick(delta: float) -> void:
	# Time stops for the dead. Without this a corpse keeps running its cast machine, and
	# anyone who died with a spell queued behind a fizzle would finish casting it.
	if not is_alive():
		return
	tick_status(delta)
	entity_state.tick(delta)


## Advances status timers by `delta`. Driven explicitly rather than from `_process` so
## that the server can step it at a fixed rate and tests can step exact windows.
func tick_status(delta: float) -> void:
	# Nothing burns on the dead. Reviving clears the timers outright.
	if not is_alive():
		return

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
