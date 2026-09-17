extends Node
class_name ArenaServer

## The authoritative match, with no idea that a network exists.
##
## Everything here is plain methods and plain signals. `autoload/network_manager.gd` is
## the only file in the project that knows what an RPC is, and it holds no rules in
## return. That split is the reason all of this can be tested in the ordinary headless
## harness without opening a socket — which matters more than it sounds, because CI
## gates the browser deploy on those tests passing.
##
## Nothing here trusts a peer id it was handed. Every request is checked against the
## roster, and the *caster* is never taken from a payload at all — see `request_cast`.

signal snapshot_ready(records: Array)
signal cast_event(peer_id: int, event: EntityState.Event, spell_id: int)
signal spell_resolved(caster_peer: int, target_peer: int, spell_id: int, connected: bool)
signal roster_changed()

## One player as the server sees them. The two target fields are separate on purpose;
## `_on_cast_started` explains why.
class Player extends RefCounted:
	var peer_id: int
	var combatant: Combatant
	var body: PlayerBody

	## Which of the arena's slots this player holds. The server hands out a number and
	## stops there — what a slot *looks* like is the client's business, and `server/`
	## has to stay free of rendering for the Dedicated Server export to stay clean.
	var slot: int

	## The direction actually governing this player's current physics step. Only ever
	## written by `_step_movement` consuming an entry off `_input_queue` — never by
	## `set_input` directly — so it always corresponds to exactly the input
	## `_step_movement` last stepped with, not merely the most recent packet to arrive
	## (#132, #139).
	var input: Vector2 = Vector2.ZERO
	var seconds_since_input: float = 0.0

	## The sequence number of whichever buffered entry `_step_movement` last actually
	## consumed — not merely the most recent one `set_input` received. Echoed back in
	## every snapshot record as `INPUT_ACK` so the client knows exactly which of its own
	## buffered inputs are already folded into the position it is being told — see
	## `Fighter.receive_server_snapshot` (#113).
	var last_input_sequence: int = -1

	## `{"sequence": int, "direction": Vector2}` dictionaries, oldest first — buffered by
	## `set_input` as `submit_input` RPCs arrive, drained by `_step_movement` at exactly
	## one entry per physics tick, in order (#132). Bounded tight — see
	## `MAX_QUEUED_INPUTS`'s own doc comment for why this is a handful of entries, not the
	## full `INPUT_TIMEOUT_SECONDS` window #134 originally tried and had to be reverted
	## for (#137): letting the backlog grow that large meant draining it could itself take
	## long enough to read as a sustained, chronic lag rather than the odd small
	## correction.
	var _input_queue: Array[Dictionary] = []

	## Who the last accepted cast request named.
	var requested_target: int = 0
	## Who the spell currently in the air was aimed at when it began.
	var committed_target: int = 0

	var respawn_countdown: float = 0.0

	## `_within_request_budget`'s own bookkeeping — a 1-second rolling window on how many
	## cast requests this player has made. `request_window` is ticked in
	## `_step_cast_budget`; without that tick it never reaches 1.0, `cast_requests` never
	## resets, and a player who has ever made `MAX_CAST_REQUESTS_PER_SECOND` requests in
	## their whole session is refused every cast after, silently (#127).
	var cast_requests: int = 0
	var request_window: float = 0.0


## Authored so the collision circle and its layers are visible in the editor rather
## than assembled in `PlayerBody._ready()`. Collision only — no texture, nothing from
## `client/` — so the dedicated-server export stays clean.
const PLAYER_BODY_SCENE := preload("res://server/player_body.tscn")

## The `Arena` child instances `res://arena/arena_map.tscn` — the same hand-painted scene
## the client scenes instance, never `load()`ed here. Authored in `server/arena_server.tscn`.
@onready var map: ArenaMap = $Arena

## Authored as the `Resolver` child. It raycasts through `get_viewport().get_world_2d()`,
## so it has to hang off the running tree rather than float loose — which the scene
## guarantees.
@onready var resolver: CombatResolver = $Resolver

var _players: Dictionary = {}
var _spawns: Array[Vector2] = []
var _snapshot_accumulator: float = 0.0


func _ready() -> void:
	_spawns = map.get_spawn_positions()


# ── Roster ────────────────────────────────────────────────────────────────────────


func add_player(peer_id: int) -> bool:
	if _players.has(peer_id) or _players.size() >= Constants.MAX_PLAYERS:
		return false

	var player := Player.new()
	player.peer_id = peer_id
	player.slot = _free_slot()

	player.combatant = Combatant.new()
	add_child(player.combatant)

	player.body = PLAYER_BODY_SCENE.instantiate()
	player.body.position = first_free_spawn(_spawns, _occupied_positions())
	add_child(player.body)
	player.combatant.position = player.body.position

	var state := player.combatant.entity_state
	state.cast_started.connect(_on_cast_started.bind(peer_id))
	state.cast_completed.connect(_on_cast_completed.bind(peer_id))
	state.cast_fizzled.connect(_on_cast_fizzled.bind(peer_id))
	state.cast_interrupted.connect(_on_cast_interrupted.bind(peer_id))
	player.combatant.died.connect(_on_died.bind(peer_id))

	_players[peer_id] = player
	roster_changed.emit()
	return true


func remove_player(peer_id: int) -> void:
	if not _players.has(peer_id):
		return
	var player: Player = _players[peer_id]
	player.combatant.queue_free()
	player.body.queue_free()
	_players.erase(peer_id)
	roster_changed.emit()


func has_player(peer_id: int) -> bool:
	return _players.has(peer_id)


func player_count() -> int:
	return _players.size()


func combatant_of(peer_id: int) -> Combatant:
	if not _players.has(peer_id):
		return null
	return _players[peer_id].combatant


func body_of(peer_id: int) -> PlayerBody:
	if not _players.has(peer_id):
		return null
	return _players[peer_id].body


func peer_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	for peer_id in _players:
		ids.append(peer_id)
	return ids


func slots() -> PackedInt32Array:
	var out := PackedInt32Array()
	for peer_id in _players:
		out.append(_players[peer_id].slot)
	return out


# ── Requests from players ─────────────────────────────────────────────────────────


## How many buffered input entries `_step_movement` will hold at once — past this,
## `set_input` drops the oldest rather than let the backlog keep growing. Small and
## deliberately so: real UDP delivery clusters packets even over a perfectly healthy
## connection (ordinary router/OS-level batching, not a sign of anything wrong), so two
## or three packets landing between one physics tick and the next is routine, not an
## emergency — draining them one tick apiece, in order, is exactly what fixes the
## misattribution a live burst like that used to cause (#132). But bounding this at only
## a handful of entries also caps the *worst case*: even if a burst is larger than that,
## draining what's kept can never take more than `MAX_QUEUED_INPUTS` ticks, so the server
## can never fall meaningfully behind real time no matter how bad a burst gets.
##
## #134 bounded this to `INPUT_TIMEOUT_SECONDS` worth of ticks instead (30, half a
## second) and was reverted (#137) after a live test showed the backlog actually growing
## to that size routinely, not just under rare jitter — patiently draining half a second
## of stale queued input reads as a sustained, chronic lag, which is worse than the
## occasional small misattribution the queue existed to fix in the first place. This
## number has to stay small enough that draining a full queue can never itself become
## something a player would notice (#139).
const MAX_QUEUED_INPUTS: int = 3


## Steering. The direction is clamped before it gets here; an unclamped one is a
## fifty-times-move-speed hack.
##
## `sequence` is the client's own input-history tag. Buffered rather than applied
## immediately — `_step_movement` is what actually consumes it, one entry per physics
## tick, so an ordinary small cluster of packets landing between two ticks no longer
## makes the server silently skip simulating some of them (#132). Nothing here trusts
## `sequence` for anything but the round trip back to the client that sent it, so an
## out-of-order or replayed value only ever costs the sender their own reconciliation.
func set_input(peer_id: int, direction: Vector2, sequence: int) -> void:
	if not _players.has(peer_id):
		return
	var player: Player = _players[peer_id]
	player.seconds_since_input = 0.0
	player._input_queue.append({"sequence": sequence, "direction": direction})
	player._input_queue = trim_input_queue(player._input_queue, MAX_QUEUED_INPUTS)


## Keeps only the newest `max_entries` of a buffered input queue — the server-side
## counterpart of `Fighter.trim_input_history`, at a much tighter bound. See
## `MAX_QUEUED_INPUTS`'s own doc comment for why: an oldest entry dropped here was never
## going to be simulated far from real time anyway, and keeping it around would only
## grow how far behind draining the rest can fall.
static func trim_input_queue(
	queue: Array[Dictionary], max_entries: int
) -> Array[Dictionary]:
	if queue.size() <= max_entries:
		return queue
	return queue.slice(queue.size() - max_entries, queue.size())


## Asks to begin a cast. Returns whether it was accepted, which is not the same as the
## spell being in the air — a recast fizzles what was running and chains instead.
##
## `peer_id` is the caster, and every caller passes it from the transport's own idea of
## who sent the packet. No request carries a "who I am" field, so there is nothing here
## for a modified client to lie in.
func request_cast(peer_id: int, spell_id: int, target_peer: int) -> bool:
	if not _players.has(peer_id):
		return false

	var player: Player = _players[peer_id]
	if not player.combatant.is_alive():
		return false
	if not _within_request_budget(player):
		return false

	var spell := SpellBook.spell_for(spell_id)
	if spell == null:
		return false

	# A self-cast spell (Cure) resolves on the caster. It ignores whatever target the
	# client named — in a free-for-all there is nobody else worth aiming it at — and is
	# exempt from the "someone who isn't you" rule every other spell obeys.
	if spell.is_self_cast():
		target_peer = peer_id
	elif target_peer == peer_id or not _players.has(target_peer):
		return false

	var target: Player = _players[target_peer]
	if not target.combatant.is_alive():
		return false

	# Set before asking, because a cast that starts immediately emits `cast_started`
	# synchronously and `_on_cast_started` reads this. Put back if the shot is refused:
	# a refusal costs nothing, and that has to include the aim.
	var previous := player.requested_target
	player.requested_target = target_peer
	if not resolver.try_begin_cast(player.combatant, target.combatant, spell):
		player.requested_target = previous
		return false
	return true


# ── The step ──────────────────────────────────────────────────────────────────────


## Advances the whole match by one physics step.
##
## Movement is the exception to `delta` meaning anything here: `move_and_slide` reads
## the engine's own physics delta, so this must be driven from `_physics_process` and
## nowhere else. Cast timing, status and respawns all honour the `delta` passed.
func step(delta: float) -> void:
	for peer_id in _players:
		_step_movement(_players[peer_id], delta)
		_step_cast_budget(_players[peer_id], delta)

	# Rules second, and in their own pass: resolving a cast can kill someone, and
	# everyone should have finished moving before anyone's spell lands.
	for peer_id in _players:
		_players[peer_id].combatant.tick(delta)

	for peer_id in _players:
		_step_respawn(_players[peer_id], delta)

	_snapshot_accumulator += delta
	var interval := 1.0 / float(Constants.SNAPSHOT_HZ)
	if _snapshot_accumulator >= interval:
		_snapshot_accumulator = fmod(_snapshot_accumulator, interval)
		snapshot_ready.emit(build_snapshot())


func build_snapshot() -> Array:
	var records := []
	for peer_id in _players:
		var player: Player = _players[peer_id]
		records.append(
			NetProtocol.encode_combatant(peer_id, player.combatant, player.last_input_sequence)
		)
	return records


## Where a player who is *joining* appears: the first free spawn in map order.
##
## Deliberately not the furthest-away rule below. The first two spawns are the duel
## lane, and the map is drawn around that opening — a clear shot straight down the
## middle with cover a step away on either side. Placing joiners by distance instead
## would put the first two arrivals diagonally opposite with a tent between them, which
## is a worse first ten seconds than the map was designed to give.
static func first_free_spawn(spawns: Array[Vector2], occupied: Array[Vector2]) -> Vector2:
	for spawn in spawns:
		var taken := false
		for point in occupied:
			if point.distance_to(spawn) < Constants.PLAYER_RADIUS * 2.0:
				taken = true
				break
		if not taken:
			return spawn
	# Every marker is stood on. Fall back to whichever is least crowded.
	return pick_spawn(spawns, occupied)


## Where a player who is *respawning* appears: as far from everyone still standing as
## the map allows. Coming back to life next to whoever just killed you is the one
## outcome worth designing against.
static func pick_spawn(spawns: Array[Vector2], occupied: Array[Vector2]) -> Vector2:
	if spawns.is_empty():
		return Vector2.ZERO
	if occupied.is_empty():
		return spawns[0]

	var best := spawns[0]
	var best_clearance := -1.0
	for spawn in spawns:
		var nearest := INF
		for point in occupied:
			nearest = minf(nearest, spawn.distance_squared_to(point))
		if nearest > best_clearance:
			best_clearance = nearest
			best = spawn
	return best


# ── Internals ─────────────────────────────────────────────────────────────────────


## Consumes at most one buffered input entry per call, so a step's own `input` and
## `last_input_sequence` always correspond to the one entry actually stepped with —
## never to whichever packet happened to be the latest arrival by the time this ran.
## Ticks with nothing new queued simply keep holding the last entry consumed, the same as
## before #132; a burst still gets each of its (bounded — see `MAX_QUEUED_INPUTS`) queued
## entries its own tick, draining in order over the next several ticks rather than
## collapsing into this one the way a live-overwritten `input` used to.
func _step_movement(player: Player, delta: float) -> void:
	player.seconds_since_input += delta
	if player.seconds_since_input > Constants.INPUT_TIMEOUT_SECONDS:
		# Input arrives unreliably, so the packet that says "I let go" is the one that
		# can go missing. Without this, losing it leaves someone jogging into a wall
		# until they happen to press the button again. A backlog queued before the
		# silence started is just as stale as the held direction it would otherwise keep
		# re-simulating, so it is given up on too.
		player.input = Vector2.ZERO
		player._input_queue.clear()
	elif not player._input_queue.is_empty():
		var entry: Dictionary = player._input_queue.pop_front()
		player.input = entry["direction"]
		player.last_input_sequence = entry["sequence"]

	Movement.step(player.body, player.input, player.combatant.can_move())
	player.combatant.position = player.body.global_position


## Ticks `_within_request_budget`'s rolling window. Its own doc comment explains why the
## budget exists; this is the tick that makes it a *rolling* one second rather than a
## ceiling for the whole session (#127).
func _step_cast_budget(player: Player, delta: float) -> void:
	player.request_window += delta


func _step_respawn(player: Player, delta: float) -> void:
	if player.respawn_countdown <= 0.0:
		return
	player.respawn_countdown -= delta
	if player.respawn_countdown > 0.0:
		return

	player.respawn_countdown = 0.0
	var where := pick_spawn(_spawns, _occupied_positions(player.peer_id))
	player.body.global_position = where
	player.combatant.revive(where)
	player.input = Vector2.ZERO


func _within_request_budget(player: Player) -> bool:
	# The state machine already denies casts during recovery, but nothing stops a
	# modified client asking at wire speed, and every request costs a raycast.
	if player.request_window >= 1.0:
		player.request_window = 0.0
		player.cast_requests = 0
	if player.cast_requests >= Constants.MAX_CAST_REQUESTS_PER_SECOND:
		return false
	player.cast_requests += 1
	return true


## The lowest slot nobody holds, so a player who leaves frees their number for the next
## arrival rather than leaving a gap.
func _free_slot() -> int:
	var taken := {}
	for peer_id in _players:
		taken[_players[peer_id].slot] = true
	for slot in Constants.MAX_PLAYERS:
		if not taken.has(slot):
			return slot
	return 0


func _occupied_positions(excluding: int = 0) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for peer_id in _players:
		if peer_id == excluding:
			continue
		var player: Player = _players[peer_id]
		if player.combatant.is_alive():
			points.append(player.combatant.position)
	return points


## The moment a spell truly begins — which is often not the moment it was asked for.
## A recast fizzles whatever was running and the spell you chained into starts later,
## after the recovery. Committing the aim here is what sends that chained spell at
## whoever you were pointing at when it left your hands, rather than at whoever you had
## selected two presses ago.
func _on_cast_started(_spell: SpellData, peer_id: int) -> void:
	var player: Player = _players[peer_id]
	player.committed_target = player.requested_target


func _on_cast_completed(spell: SpellData, peer_id: int) -> void:
	cast_event.emit(peer_id, EntityState.Event.COMPLETED, SpellBook.id_of(spell))

	var player: Player = _players[peer_id]
	# The target can quit, or die to someone else, while the spell is in the air. A
	# spell aimed at nobody simply goes nowhere — it is not an error.
	if not _players.has(player.committed_target):
		return
	var target: Player = _players[player.committed_target]
	if not target.combatant.is_alive():
		return

	var connected := resolver.resolve_cast(player.combatant, target.combatant, spell)
	spell_resolved.emit(peer_id, target.peer_id, SpellBook.id_of(spell), connected)


func _on_cast_fizzled(spell: SpellData, _reason: String, peer_id: int) -> void:
	cast_event.emit(peer_id, EntityState.Event.FIZZLED, SpellBook.id_of(spell))


func _on_cast_interrupted(spell: SpellData, peer_id: int) -> void:
	cast_event.emit(peer_id, EntityState.Event.INTERRUPTED, SpellBook.id_of(spell))


func _on_died(peer_id: int) -> void:
	var player: Player = _players[peer_id]
	player.respawn_countdown = Constants.RESPAWN_SECONDS
	player.input = Vector2.ZERO
