extends Node

## Where a client decides what kind of session it is in: a browser build practises
## offline, `--connect <host>` goes straight to a server, and anything else gets a menu.

const DEFAULT_ADDRESS := "127.0.0.1"

var _address: LineEdit
var _status: Label
var _connect_button: Button


func _ready() -> void:
	# ENet does not exist in an HTML5 export, so the browser build has no multiplayer to
	# offer and never constructs a peer. It boots into the practice harness exactly as
	# it always has — which is what keeps the published page working unchanged.
	if OS.has_feature("web"):
		get_tree().change_scene_to_file.call_deferred("res://client/scenes/local_test.tscn")
		return

	_build_ui()

	if NetworkManager.last_failure != "":
		_status.text = NetworkManager.last_failure
		NetworkManager.last_failure = ""
		return

	var address := NetworkManager.requested_address()
	if address != "":
		_address.text = address
		_connect_to(address)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := VBoxContainer.new()
	panel.position = Vector2(80.0, 200.0)
	panel.custom_minimum_size = Vector2(420.0, 0.0)
	panel.add_theme_constant_override("separation", 12)
	layer.add_child(panel)

	var title := Label.new()
	title.text = "UO Arena"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#dcd0ff"))
	panel.add_child(title)

	var hint := Label.new()
	hint.text = "Enter the address of a server, or practise on your own."
	hint.add_theme_color_override("font_color", Color("#8a8f9c"))
	panel.add_child(hint)

	_address = LineEdit.new()
	_address.text = DEFAULT_ADDRESS
	_address.custom_minimum_size = Vector2(300.0, 0.0)
	_address.text_submitted.connect(func(text: String) -> void: _connect_to(text))
	panel.add_child(_address)

	_connect_button = Button.new()
	_connect_button.text = "Connect"
	_connect_button.pressed.connect(func() -> void: _connect_to(_address.text))
	panel.add_child(_connect_button)

	var practice := Button.new()
	practice.text = "Offline practice"
	practice.pressed.connect(
		func() -> void:
			get_tree().change_scene_to_file("res://client/scenes/local_test.tscn")
	)
	panel.add_child(practice)

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("#ffa447"))
	panel.add_child(_status)


func _connect_to(address: String) -> void:
	var host := address.strip_edges()
	if host == "":
		_status.text = "enter an address first"
		return

	# Disabled rather than hidden: the button coming back is how you know the attempt
	# gave up, and NetworkManager gives up on its own after a few seconds.
	_connect_button.disabled = true
	_status.text = "connecting to %s…" % host

	if NetworkManager.join(host, NetworkManager.requested_port()) != OK:
		_connect_button.disabled = false
		_status.text = "could not open a connection to %s" % host
