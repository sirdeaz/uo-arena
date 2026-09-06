extends Node

## The dedicated server's entry point. Builds the arena, opens the socket, and steps the
## simulation. Every rule lives in `ArenaServer` and every packet in `NetworkManager`;
## there is deliberately nothing else here.

var arena: ArenaServer


func _ready() -> void:
	# A headless process has no vsync to pace it and will otherwise spin as fast as the
	# CPU allows, burning a whole core to produce the same sixty physics steps.
	Engine.max_fps = Engine.physics_ticks_per_second

	arena = ArenaServer.new()
	add_child(arena)
	arena.roster_changed.connect(_on_roster_changed)

	var port := NetworkManager.requested_port()
	if NetworkManager.host(arena, port) != OK:
		push_error("[server] could not open port %d — is a server already running?" % port)
		get_tree().quit(1)
		return

	print("[server] UO Arena listening on port %d for up to %d players." % [
		port, Constants.MAX_PLAYERS
	])


func _physics_process(delta: float) -> void:
	# The one caller of `step`. Movement inside it uses `move_and_slide`, which reads the
	# engine's own physics delta, so it has to be driven from here and nowhere else.
	arena.step(delta)


## The only running commentary a dedicated server gives. Worth having: with no window
## to look at, the roster is the one signal that people are actually getting in.
func _on_roster_changed() -> void:
	print("[server] %d in the arena: %s" % [arena.player_count(), arena.peer_ids()])
