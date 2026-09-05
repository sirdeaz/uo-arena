extends Node

## Manual multiplayer smoke test — deliberately not part of the suite.
##
## `tests/test_main.gd` lists `res://tests` non-recursively, so nothing under
## `tests/manual/` is ever discovered by the runner, and the existing
## `exclude_filter="tests/*"` keeps it out of every export. CI therefore never opens a
## socket, which matters because the browser deploy is gated on the suite passing.
##
## What it is for: a headless client that joins, picks an opponent and casts at them on
## a loop, so the whole round trip — request, line-of-sight check, resolution, announced
## events, damage coming back down in snapshots — can be exercised with nobody at a
## mouse. Run a server and two of these:
##
##   powershell -File run_game.ps1 -Server
##   godot --headless res://tests/manual/loopback.tscn -- --test --connect 127.0.0.1
##
## The `--test` is what stops NetworkManager routing away from this scene; everything
## else about the session is a perfectly ordinary client.


func _ready() -> void:
	# Connecting swaps out the current scene, which would take this node with it, so the
	# part that has to keep working lives under the root instead.
	get_tree().root.add_child.call_deferred(Driver.new())


class Driver extends Node:
	const CAST_INTERVAL := 1.5
	const MAGIC_ARROW := 0

	var _timer: float = 0.0
	var _announced: bool = false

	func _ready() -> void:
		var address := NetworkManager.requested_address()
		if address == "":
			address = "127.0.0.1"
		print("[loopback] connecting to %s" % address)
		if NetworkManager.join(address, NetworkManager.requested_port()) != OK:
			print("[loopback] could not open a connection")
			get_tree().quit(1)

	func _process(delta: float) -> void:
		var client := NetworkManager.arena_client
		if client == null:
			return

		if not _announced:
			_announced = true
			print("[loopback] joined as peer %d" % client.local_peer_id)

		_timer += delta
		if _timer < CAST_INTERVAL:
			return
		_timer = 0.0

		var target := _opponent(client)
		if target == 0:
			print("[loopback] alone in the arena, waiting")
			return

		client.cast_requested.emit(MAGIC_ARROW, target)

		# Health, not `last_event()`. A cast refused for want of line of sight is refused
		# silently — that is the whole point of a refusal costing nothing — so the HUD
		# line would just sit there still reporting the last shot that did land, which
		# reads as a hit that never happened. The numbers cannot lie like that.
		var mine := client.fighter_of(client.local_peer_id)
		var theirs := client.fighter_of(target)
		print("[loopback] cast at %d | me %d @ %v | them %d @ %v" % [
			target,
			roundi(mine.combatant.health),
			mine.server_position,
			roundi(theirs.combatant.health),
			theirs.server_position,
		])

	func _opponent(client: ArenaClient) -> int:
		for peer_id in client.peer_ids():
			if peer_id != client.local_peer_id:
				return peer_id
		return 0
