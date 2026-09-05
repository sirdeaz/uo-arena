extends Node

## Role routing at boot, and the only file in the project that knows what an RPC is.
##
## Every RPC lives here rather than on a game node because Godot resolves RPC targets by
## node path, and the server tree and the client tree are both built imperatively with
## no shape in common. `/root/NetworkManager` is the one path that is identical on both
## ends and survives every scene change.
##
## It holds no rules in return. `ArenaServer` decides everything, `ArenaClient` draws it,
## and neither of them can tell whether a network is involved — which is what lets the
## whole game be tested headless without opening a socket. That matters concretely: CI
## runs the suite before it publishes the browser build.

## Why the last connection attempt ended, for the join screen to display. Cleared once
## it has been read.
var last_failure: String = ""

var arena_server: ArenaServer
var arena_client: ArenaClient

## Seconds spent waiting for a connection, or negative when not connecting. ENet can sit
## on a dead address for a long time before it admits defeat, and a join screen that
## spins forever is the first thing anyone hits.
const CONNECT_TIMEOUT_SECONDS: float = 5.0

var _connecting_for: float = -1.0


func _ready() -> void:
	if _is_test_run():
		# The test runner supplies its own scene, so don't route away from it — and
		# above all don't open a socket.
		return

	var scene := "res://client/client_main.tscn"
	if _is_server_role():
		scene = "res://server/server_main.tscn"
	# Deferred: the tree is still building autoloads during _ready.
	get_tree().change_scene_to_file.call_deferred(scene)


func _process(delta: float) -> void:
	if _connecting_for < 0.0:
		return
	_connecting_for += delta
	if _connecting_for >= CONNECT_TIMEOUT_SECONDS:
		_return_to_menu("no answer from the server")


# ── Command line ──────────────────────────────────────────────────────────────────


func _is_test_run() -> bool:
	return _has_flag("--test")


func _is_server_role() -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	# Accepts both `godot --server` and `godot -- --server`.
	return _has_flag("--server")


## The address a `--connect <host>` asked for, or "" for none.
func requested_address() -> String:
	return _flag_value("--connect")


func requested_port() -> int:
	var value := _flag_value("--port")
	return int(value) if value.is_valid_int() else Constants.DEFAULT_PORT


func _has_flag(flag: String) -> bool:
	return flag in OS.get_cmdline_args() or flag in OS.get_cmdline_user_args()


func _flag_value(flag: String) -> String:
	# Both lists, because `--server` reaches us as an engine argument and `-- --connect`
	# as a user one, and a launcher may use either form.
	for source in [OS.get_cmdline_args(), OS.get_cmdline_user_args()]:
		var args: PackedStringArray = source
		var index := args.find(flag)
		if index >= 0 and index + 1 < args.size():
			return args[index + 1]
	return ""


# ── Transport ─────────────────────────────────────────────────────────────────────
#
# The three functions below are the only places in the project that name a concrete
# transport. Moving to WebSocketMultiplayerPeer — which is what a browser build would
# need, since ENet simply does not exist in an HTML5 export — is a change to these
# bodies and to nothing else: no caller knows which one it got.


func _create_server_peer(port: int) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, Constants.MAX_PLAYERS) != OK:
		return null
	return peer


func _create_client_peer(address: String, port: int) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, port) != OK:
		return null
	return peer


func _disconnect_peer(peer_id: int) -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer != null:
		peer.disconnect_peer(peer_id)


# ── Hosting ───────────────────────────────────────────────────────────────────────


func host(arena: ArenaServer, port: int) -> Error:
	var peer := _create_server_peer(port)
	if peer == null:
		return ERR_CANT_CREATE

	arena_server = arena
	arena_server.snapshot_ready.connect(_on_snapshot_ready)
	arena_server.cast_event.connect(_on_cast_event)
	arena_server.spell_resolved.connect(_on_spell_resolved)
	arena_server.roster_changed.connect(_broadcast_roster)

	multiplayer.multiplayer_peer = peer
	_harden()
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK


func _on_peer_disconnected(peer_id: int) -> void:
	if arena_server != null:
		arena_server.remove_player(peer_id)


func _broadcast_roster() -> void:
	if arena_server != null:
		receive_roster.rpc(arena_server.peer_ids(), arena_server.colors())


func _on_snapshot_ready(records: Array) -> void:
	receive_snapshot.rpc(records)


func _on_cast_event(peer_id: int, event: EntityState.Event, spell_id: int) -> void:
	receive_cast_event.rpc(peer_id, event, spell_id)


func _on_spell_resolved(
	caster_peer: int, target_peer: int, spell_id: int, connected: bool
) -> void:
	if connected:
		receive_spell_resolved.rpc(caster_peer, target_peer, spell_id, true)
		return
	# A spell stopped by cover is news for the caster and nobody else. Broadcasting it
	# would tell your opponents that you had just taken a shot at them from behind a
	# tent — which is exactly the information cover is supposed to deny them.
	receive_spell_resolved.rpc_id(caster_peer, caster_peer, target_peer, spell_id, false)


# ── Joining ───────────────────────────────────────────────────────────────────────


func join(address: String, port: int) -> Error:
	var peer := _create_client_peer(address, port)
	if peer == null:
		return ERR_CANT_CONNECT

	multiplayer.multiplayer_peer = peer
	_harden()
	multiplayer.connected_to_server.connect(_on_connected_to_server, CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	multiplayer.server_disconnected.connect(_on_server_disconnected, CONNECT_ONE_SHOT)
	_connecting_for = 0.0
	return OK


func _on_connected_to_server() -> void:
	_connecting_for = -1.0

	# Built and wired before it enters the tree, so `local_peer_id` is already correct
	# when `_ready` runs and the first roster cannot arrive at a half-configured client.
	var previous := get_tree().current_scene
	arena_client = load("res://client/scenes/arena_client.tscn").instantiate()
	arena_client.local_peer_id = multiplayer.get_unique_id()
	arena_client.input_changed.connect(_on_local_input_changed)
	arena_client.cast_requested.connect(_on_local_cast_requested)

	get_tree().root.add_child(arena_client)
	get_tree().current_scene = arena_client
	if previous != null:
		previous.queue_free()

	join_arena.rpc_id(1, Constants.PROTOCOL_VERSION)


func _on_connection_failed() -> void:
	_return_to_menu("could not reach that server")


func _on_server_disconnected() -> void:
	_return_to_menu("the server closed the connection")


## Tears the session down and puts the join screen back up with an explanation.
func _return_to_menu(reason: String) -> void:
	last_failure = reason
	_connecting_for = -1.0
	arena_client = null
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file.call_deferred("res://client/client_main.tscn")


func _on_local_input_changed(direction: Vector2) -> void:
	submit_input.rpc_id(1, direction)


func _on_local_cast_requested(spell_id: int, target_peer: int) -> void:
	request_cast.rpc_id(1, spell_id, target_peer)


func _harden() -> void:
	var scene_multiplayer := multiplayer as SceneMultiplayer
	if scene_multiplayer == null:
		return
	# Relaying is on by default, which lets one client `rpc_id` another directly.
	# Everything here goes through the server, so nothing needs peer-to-peer — and
	# turning it off closes the hole a second time on top of the `is_server()` guards.
	scene_multiplayer.server_relay = false


# ── Client to server ──────────────────────────────────────────────────────────────
#
# Not one of these takes a "who am I" argument. The caster is always
# `get_remote_sender_id()`, which the transport fills in, so there is no field here for
# a modified client to lie in. That is the whole of the identity story.
#
# Everything stays on channel 0: Godot already routes reliable, unreliable and
# unreliable-ordered traffic onto separate ENet system channels, and a custom
# `transfer_channel` would need a matching `channel_count` at both ends to work.


@rpc("any_peer", "call_remote", "reliable")
func join_arena(protocol_version: int) -> void:
	if not multiplayer.is_server() or arena_server == null:
		return
	# Valid only for the duration of this call, so read it before anything else.
	var sender := multiplayer.get_remote_sender_id()

	if protocol_version != Constants.PROTOCOL_VERSION:
		receive_rejected.rpc_id(sender, "this server is running a different version")
		_disconnect_peer(sender)
		return

	# Deliberately here rather than on `peer_connected`: that fires before the joining
	# client has a scene to receive anything, so a roster sent then lands nowhere.
	if not arena_server.add_player(sender):
		receive_rejected.rpc_id(sender, "the arena is full")
		_disconnect_peer(sender)
		return


@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_input(direction: Vector2) -> void:
	if not multiplayer.is_server() or arena_server == null:
		return
	arena_server.set_input(
		multiplayer.get_remote_sender_id(), NetProtocol.sanitize_direction(direction)
	)


@rpc("any_peer", "call_remote", "reliable")
func request_cast(spell_id: int, target_peer: int) -> void:
	if not multiplayer.is_server() or arena_server == null:
		return
	arena_server.request_cast(multiplayer.get_remote_sender_id(), spell_id, target_peer)


# ── Server to clients ─────────────────────────────────────────────────────────────
#
# `authority` means only peer 1 is accepted, which is what stops a client forging any
# of these at another client.


@rpc("authority", "call_remote", "unreliable_ordered")
func receive_snapshot(records: Array) -> void:
	if arena_client != null:
		arena_client.apply_snapshot(records)


@rpc("authority", "call_remote", "reliable")
func receive_cast_event(peer_id: int, event: int, spell_id: int) -> void:
	if arena_client != null:
		arena_client.apply_cast_event(peer_id, event, spell_id)


@rpc("authority", "call_remote", "reliable")
func receive_spell_resolved(
	caster_peer: int, target_peer: int, spell_id: int, connected: bool
) -> void:
	if arena_client != null:
		arena_client.apply_spell_resolved(caster_peer, target_peer, spell_id, connected)


@rpc("authority", "call_remote", "reliable")
func receive_roster(peer_ids: PackedInt32Array, roster_colors: PackedColorArray) -> void:
	if arena_client != null:
		arena_client.apply_roster(peer_ids, roster_colors)


@rpc("authority", "call_remote", "reliable")
func receive_rejected(reason: String) -> void:
	_return_to_menu(reason)
