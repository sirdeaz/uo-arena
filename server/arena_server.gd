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

## Ten bodies that stay apart at a glance. Telling players apart matters more than the
## palette being pretty, so these are spread around the wheel. The first two are the
## colours the practice harness already uses, so a duel looks like it always has.
const BODY_COLORS: Array[Color] = [
	Color("#6ec6ff"), Color("#e2574c"), Color("#7ee081"), Color("#ffd166"),
	Color("#c58cff"), Color("#ff9f6e"), Color("#5ad1c8"), Color("#f279c0"),
	Color("#b0bec5"), Color("#d4e157"),
]


## One player as the server sees them. The two target fields are separate on purpose;
## `_on_cast_started` explains why.
class Player extends RefCounted:
	var peer_id: int
	var combatant: Combatant
	var body: PlayerBody
	var color: Color

	var input: Vector2 = Vector2.ZERO
	var seconds_since_input: float = 0.0

	## Who the last accepted cast request named.
	var requested_target: int = 0
	## Who the spell currently in the air was aimed at when it began.
	var committed_target: int = 0

	var respawn_countdown: float = 0.0

	var cast_requests: int = 0
	var request_window: float = 0.0


var map: ArenaMap
var resolver: CombatResolver

var _players: Dictionary = {}
var _spawns: Array[Vector2] = []
var _snapshot_accumulator: float = 0.0


func _ready() -> void:
	map = load("res://server/arena_map.tscn").instantiate()
	add_child(map)
	_spawns = map.get_spawn_positions()

	# The resolver raycasts through `get_viewport().get_world_2d()`, so it has to hang
	# off the running tree rather than float loose.
	resolver = CombatResolver.new()
	add_child(resolver)


# ── Roster ────────────────────────────────────────────────────────────────────────


func add_player(peer_id: int) -> bool:
	if _players.has(peer_id) or _players.size() >= Constants.MAX_PLAYERS:
		return false

	var player := Player.new()
	player.peer_id = peer_id
	player.color = BODY_COLORS[_free_color_index()]

	player.combatant = Combatant.new()
	add_child(player.combatant)

	player.body = PlayerBody.new()
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


func colors() -> PackedColorArray:
	var out := PackedColorArray()
	for peer_id in _players:
		out.append(_players[peer_id].color)
	return out


# ── Requests from players ─────────────────────────────────────────────────────────


## Steering. The direction is clamped before it gets here; an unclamped one is a
## fifty-times-move-speed hack.
func set_input(peer_id: int, direction: Vector2) -> void:
	if not _players.has(peer_id):
		return
	var player: Player = _players[peer_id]
	player.input = direction
	player.seconds_since_input = 0.0


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
	if target_peer == peer_id or not _players.has(target_peer):
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
		records.append(NetProtocol.encode_combatant(peer_id, _players[peer_id].combatant))
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


func _step_movement(player: Player, delta: float) -> void:
	player.seconds_since_input += delta
	if player.seconds_since_input > Constants.INPUT_TIMEOUT_SECONDS:
		# Input arrives unreliably, so the packet that says "I let go" is the one that
		# can go missing. Without this, losing it leaves someone jogging into a wall
		# until they happen to press the button again.
		player.input = Vector2.ZERO

	var direction := player.input if player.combatant.can_move() else Vector2.ZERO
	player.body.velocity = direction * Constants.PLAYER_MOVE_SPEED
	player.body.move_and_slide()
	player.combatant.position = player.body.global_position


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


func _free_color_index() -> int:
	var taken := {}
	for peer_id in _players:
		taken[_players[peer_id].color] = true
	for index in BODY_COLORS.size():
		if not taken.has(BODY_COLORS[index]):
			return index
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
