extends Node

## Where a client decides what kind of session it is in: a browser build practises
## offline, `--connect <host>` goes straight to a server, and anything else gets the
## join menu.
##
## The menu itself is authored in `client/client_main.tscn` now — its layout, its
## `menu_theme.tres` and the fact that it exists are the scene's business. This script
## only wires behaviour: which button does what, and what the status line says.

const DEFAULT_ADDRESS := "127.0.0.1"

## Where "Offline practice" goes. A scene reference wired in the Inspector rather than a
## `change_scene_to_file("res://…")` string in two places.
@export var practice_scene: PackedScene

@onready var _menu: CanvasLayer = $Menu
@onready var _address: LineEdit = $Menu/Panel/Address
@onready var _status: Label = $Menu/Panel/Status
@onready var _connect_button: Button = $Menu/Panel/ConnectButton
@onready var _hint: Label = $Menu/Panel/Hint


func _ready() -> void:
	# ENet does not exist in an HTML5 export, so the browser build has no multiplayer to
	# offer and never constructs a peer. It boots into the practice harness exactly as
	# it always has — which is what keeps the published page working unchanged.
	if OS.has_feature("web"):
		_go_to_practice.call_deferred()
		return

	# Secondary and error text get their own chrome entries so nothing on the menu
	# borrows a cast-feedback colour (#19). The theme carries the rest.
	_hint.add_theme_color_override("font_color", Palette.UI_TEXT_DIM)
	_status.add_theme_color_override("font_color", Palette.UI_TEXT_ALERT)

	_address.text = DEFAULT_ADDRESS
	_address.text_submitted.connect(func(text: String) -> void: _connect_to(text))
	_connect_button.pressed.connect(func() -> void: _connect_to(_address.text))
	($Menu/Panel/PracticeButton as Button).pressed.connect(_go_to_practice)

	if NetworkManager.last_failure != "":
		_status.text = NetworkManager.last_failure
		NetworkManager.last_failure = ""
		return

	var address := NetworkManager.requested_address()
	if address != "":
		_address.text = address
		_connect_to(address)


func _go_to_practice() -> void:
	if practice_scene != null:
		get_tree().change_scene_to_packed(practice_scene)
	else:
		# A missing Inspector wiring should not strand the player on a dead button.
		get_tree().change_scene_to_file("res://client/scenes/local_test.tscn")


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
