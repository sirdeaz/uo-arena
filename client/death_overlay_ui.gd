extends Control
class_name DeathOverlayUI

## The full-screen death wash and its countdown, driven straight off the wire.
##
## Purely reactive, the same as `CastBarUI` — no timer of its own. `ArenaClient` calls
## `set_countdown` every physics tick with the local player's real `respawn_countdown`
## off the server's own snapshot, never a client-side guess (#136), and `clear` once it
## reads alive again.

var _seconds_remaining: float = 0.0


func set_countdown(seconds: float) -> void:
	visible = true
	_seconds_remaining = seconds
	queue_redraw()


## Idempotent — `ArenaClient._update_hud` calls this every tick the local player is
## alive, not only once on the tick revive actually happens.
func clear() -> void:
	if not visible:
		return
	visible = false
	queue_redraw()


func _draw() -> void:
	if not visible:
		return

	draw_rect(
		Rect2(Vector2.ZERO, size), Color(Palette.HEALTH_HURT, Palette.DEATH_OVERLAY_ALPHA)
	)

	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size() * 2
	var text := "you died — back in %.1fs" % maxf(_seconds_remaining, 0.0)
	draw_string(
		font, Vector2(0.0, size.y * 0.5), text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Palette.UI_TEXT
	)
