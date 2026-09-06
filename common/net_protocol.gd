extends RefCounted
class_name NetProtocol

## The shape of everything that crosses the wire, and the only place that knows it.
##
## A state snapshot is a flat positional array per player rather than a dictionary:
## ten players at `SNAPSHOT_HZ` is two hundred records a second, and dictionary keys
## would re-send their own names in every one of them.
##
## What a record carries is decided entirely by what the client actually draws. Poison
## and paralyze are booleans here, not remaining seconds, because the fighter draws a
## ring from "is it lit" and never from the number. What a record cannot carry is the
## three ways a cast can end — a fizzle and an interrupt leave the machine looking the
## same a frame later, and INTERRUPTED clears itself within one frame, so at snapshot
## rate it would simply never be sampled. Those go as announced events instead.


enum Slot {
	PEER,
	POSITION,
	HEALTH,
	FLAGS,
	CAST_STATE,
	SPELL,
	CAST_ELAPSED,
	RECOVERY_ELAPSED,
}

const RECORD_SIZE: int = 8

## Status the client draws as a ring. Being alive is deliberately not in here — health
## is already in the record, and two fields that can disagree about the same fact is one
## field too many.
enum Flag {
	PARALYZED = 1,
	POISONED = 2,
}


## Packs one combatant into a record for the wire.
static func encode_combatant(peer_id: int, combatant: Combatant) -> Array:
	var state := combatant.entity_state

	var flags := 0
	if combatant.is_paralyzed():
		flags |= Flag.PARALYZED
	if combatant.poison_seconds_remaining > 0.0:
		flags |= Flag.POISONED

	return [
		peer_id,
		combatant.position,
		combatant.health,
		flags,
		state.current_state,
		SpellBook.id_of(state.current_spell),
		state.cast_time_elapsed,
		state.recovery_time_elapsed,
	]


## Writes one record into a mirror combatant, returning false if the record is malformed
## so a client fed nonsense drops it rather than drawing from it.
##
## Fields are written directly rather than through `take_damage` and `apply_poison`.
## Those are rules, and running the rules on a mirror would invent damage the server
## never dealt and interrupt bursts that nothing caused.
static func apply_record(record: Array, combatant: Combatant) -> bool:
	if record.size() != RECORD_SIZE:
		return false

	var flags: int = record[Slot.FLAGS]

	combatant.position = record[Slot.POSITION]
	combatant.health = record[Slot.HEALTH]

	# A nominal duration is enough to light the ring, and the next snapshot in 50 ms
	# either relights it or does not. Nothing on a mirror ever counts these down.
	combatant.paralyze_seconds_remaining = 1.0 if flags & Flag.PARALYZED else 0.0
	combatant.poison_seconds_remaining = 1.0 if flags & Flag.POISONED else 0.0
	combatant.poison_damage_per_tick = 0.0

	combatant.entity_state.apply_remote_state(
		record[Slot.CAST_STATE],
		SpellBook.spell_for(record[Slot.SPELL]),
		record[Slot.CAST_ELAPSED],
		record[Slot.RECOVERY_ELAPSED]
	)
	return true


static func peer_of(record: Array) -> int:
	return record[Slot.PEER]


## Clamps a steering vector arriving from a client.
##
## This one line is the entire defence against the obvious speed hack: the server does
## `velocity = direction * PLAYER_MOVE_SPEED`, so a client that sends a length-50 vector
## moves fifty times as fast as everyone else until someone notices.
static func sanitize_direction(direction: Vector2) -> Vector2:
	if not is_finite(direction.x) or not is_finite(direction.y):
		return Vector2.ZERO
	return direction.limit_length(1.0)
