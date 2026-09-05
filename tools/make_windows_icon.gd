extends SceneTree

## Rasterises `icon.svg` to the PNG that `tools/make_windows_icon.py` turns into
## `icon.ico`. Godot does the rasterising because it already bundles an SVG renderer and
## because it keeps `icon.svg` the single source of the artwork — redrawing the crosshair
## a second time in another tool is exactly the drift this project avoids elsewhere.
##
##   godot --headless --script tools/make_windows_icon.gd
##
## Build tooling: excluded from every export.

const SOURCE := "res://icon.svg"
const OUTPUT := "res://.godot/icon-256.png"
const SIZE: float = 256.0


func _init() -> void:
	var file := FileAccess.open(SOURCE, FileAccess.READ)
	if file == null:
		push_error("Cannot read %s" % SOURCE)
		quit(1)
		return

	var image := Image.new()
	# icon.svg is authored at 128px; scale up to the largest size a Windows .ico holds.
	var error := image.load_svg_from_string(file.get_as_text(), SIZE / 128.0)
	if error != OK:
		push_error("Could not rasterise %s (error %d)" % [SOURCE, error])
		quit(1)
		return

	var path := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if image.save_png(path) != OK:
		push_error("Could not write %s" % path)
		quit(1)
		return

	print("%s (%dx%d)" % [path, image.get_width(), image.get_height()])
	quit(0)
