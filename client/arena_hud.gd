extends CanvasLayer
class_name ArenaHud

## The chrome both clients share: the cast bar, and the readout above it.
##
## Only the chrome. What the readout *says* stays with each client — a networked fight
## reports targets and a player count, the practice harness reports the dummy and the
## reset key — and folding those together would mean one string builder serving two
## different games. What must not differ is where these sit and what they look like, and
## that is exactly what was drifting while this lived in both clients at once.
##
## The stakes are higher than "two copies of four numbers": `tools/capture_promo_shot.gd`
## poses the practice scene, deliberately, so the link preview can never show something
## the game does not look like. The moment the two HUDs diverge, that guarantee is
## quietly false and the preview is of the client nobody plays.
##
## Kept flat in `client/` rather than given a `client/ui/` of its own on purpose:
## `tests/test_palette.gd` walks `res://client` with `get_files()`, which does not
## recurse, so a script in a subdirectory would silently stop being checked for raw hex
## literals. Drawing code belongs where that check can see it.

## Distance in from the left edge. Shared, so the two rows line up down one margin.
const MARGIN: float = 24.0

const CAST_BAR_SIZE := Vector2(260.0, 16.0)

## How far the cast bar floats above the bottom edge. Anchored rather than positioned:
## this used to be a y of 640, which is only the right answer while the viewport is
## exactly 720 tall, and said nothing about the gap being the point.
const CAST_BAR_BOTTOM_GAP: float = 64.0

## The readout hangs off the top-left corner, which is where a Control's origin already
## is, so it needs no anchoring — a position is the honest way to say it.
const READOUT_TOP: float = 20.0

var cast_bar: CastBarUI
var readout: Label

var _bound_state: EntityState


func _ready() -> void:
	cast_bar = CastBarUI.new()
	cast_bar.anchor_left = 0.0
	cast_bar.anchor_right = 0.0
	cast_bar.anchor_top = 1.0
	cast_bar.anchor_bottom = 1.0
	cast_bar.offset_left = MARGIN
	cast_bar.offset_right = MARGIN + CAST_BAR_SIZE.x
	cast_bar.offset_top = -(CAST_BAR_BOTTOM_GAP + CAST_BAR_SIZE.y)
	cast_bar.offset_bottom = -CAST_BAR_BOTTOM_GAP
	add_child(cast_bar)

	readout = Label.new()
	readout.position = Vector2(MARGIN, READOUT_TOP)
	readout.add_theme_color_override("font_color", Palette.UI_TEXT)
	add_child(readout)

	# A binding asked for before the HUD entered the tree still has to land.
	if _bound_state != null:
		cast_bar.bind(_bound_state)


## Point the cast bar at a caster's state.
##
## Deliberately not part of building the HUD. The practice harness has its player before
## the UI exists and can bind immediately; `ArenaClient` cannot, because the local
## fighter only arrives with the server's first roster. Anything that bound during
## `_ready()` would work offline and show a dead cast bar in every networked fight.
##
## Re-binding is allowed — a peer that leaves and rejoins gets a fresh `EntityState` —
## but binding the same one twice is refused, because `CastBarUI.bind` connects four
## signals and Godot errors on a duplicate connection.
func bind_cast_bar(state: EntityState) -> void:
	if state == null or state == _bound_state:
		return
	_bound_state = state
	if cast_bar != null:
		cast_bar.bind(state)


## The line of text under the controls. Callers compose their own; this only shows it.
func set_readout(text: String) -> void:
	if readout != null:
		readout.text = text
