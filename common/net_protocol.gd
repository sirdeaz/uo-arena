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
	INPUT_ACK,
	RESPAWN_COUNTDOWN,
}

const RECORD_SIZE: int = 10

## Status the client draws as a ring. Being alive is deliberately not in here — health
## is already in the record, and two fields that can disagree about the same fact is one
## field too many.
enum Flag {
	PARALYZED = 1,
	POISONED = 2,
}


## Packs one combatant into a record for the wire.
##
## `input_ack` is only ever read back for the peer's own fighter — see
## `Fighter.receive_server_snapshot` — but it rides along on every record rather than a
## second per-peer RPC, the same way `POSITION` rides along for fighters that only ever
## read it for rendering, not reconciliation.
## `respawn_countdown` lives on `ArenaServer.Player`, not `Combatant` — it is scheduling
## bookkeeping, not a rule the combatant enforces — but it rides along on every record the
## same way `input_ack` does, rather than a second per-peer RPC. It is broadcast for every
## player, not only the dead one, because the record is one flat array sent to everyone;
## only the dying player's own client draws it.
static func encode_combatant(
	peer_id: int, combatant: Combatant, input_ack: int = 0, respawn_countdown: float = 0.0
) -> Array:
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
		input_ack,
		respawn_countdown,
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
	combatant.respawn_countdown = record[Slot.RESPAWN_COUNTDOWN]

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


## The last input sequence the server had actually folded into this record's position —
## see `Fighter.receive_server_snapshot`, the only reader of this that matters.
static func input_ack_of(record: Array) -> int:
	return record[Slot.INPUT_ACK]


## Clamps a steering vector arriving from a client.
##
## This one line is the entire defence against the obvious speed hack: the server does
## `velocity = direction * PLAYER_MOVE_SPEED`, so a client that sends a length-50 vector
## moves fifty times as fast as everyone else until someone notices.
static func sanitize_direction(direction: Vector2) -> Vector2:
	if not is_finite(direction.x) or not is_finite(direction.y):
		return Vector2.ZERO
	return direction.limit_length(1.0)


## Cleans a nickname arriving from a client, returning `""` when nothing usable survives
## — `ArenaServer.default_nickname` is what fills that in, because only the server knows
## which slot the name belongs to.
##
## The same kind of defence `sanitize_direction` is: a nickname is the one piece of
## player-chosen text this game draws on *other* people's screens, so it arrives assumed
## hostile. Control characters and newlines would break out of the single line the tag is
## drawn on, a run of spaces would let someone render an invisible name, and an
## arbitrarily long one would stretch a tag across the arena over everyone else's fight.
##
## Note this is a *display* name and nothing else. Identity is still `get_remote_sender_id()`
## and only that — see the header above `join_arena`. Two players may pick the same
## nickname and the server neither knows nor cares.
static func sanitize_nickname(raw: String) -> String:
	var cleaned := ""
	for character in raw:
		# Anything below space — newlines and tabs included — becomes a space rather than
		# being dropped, so "a\nb" reads as two words instead of silently becoming "ab".
		if character.unicode_at(0) < 32 or character.unicode_at(0) == 127:
			cleaned += " "
		else:
			cleaned += character

	# Collapse the runs those substitutions can leave behind, so a name cannot be padded
	# out to the length cap with whitespace and render as a blank tag.
	while cleaned.contains("  "):
		cleaned = cleaned.replace("  ", " ")

	cleaned = cleaned.strip_edges()
	if cleaned.length() > Constants.NICKNAME_MAX_LENGTH:
		cleaned = cleaned.substr(0, Constants.NICKNAME_MAX_LENGTH).strip_edges()
	return cleaned
