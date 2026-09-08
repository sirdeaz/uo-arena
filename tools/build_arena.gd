extends SceneTree

## Paints `res://arena/arena.tscn` from the obstacle rectangles and spawn points in
## `arena/arena_map.gd`. Run it after changing that data:
##
##   godot --headless --script res://tools/build_arena.gd
##
## The scene is authored output — commit it — but it is generated so the paint can
## never quietly disagree with the collision the pathfinder and the resolver read.
## `tests/test_arena_tiles.gd` is the check that it did not drift.

const MAP := preload("res://arena/arena_map.gd")
const TILESET := preload("res://arena/arena_tileset.tres")
const OUT := "res://arena/arena.tscn"

const FLOOR_TILE := Vector2i(0, 0)
const KIND_TILE := {"wall": Vector2i(1, 0), "tent": Vector2i(2, 0), "rock": Vector2i(3, 0)}


func _initialize() -> void:
	var root := _build()
	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		push_error("pack failed: %d" % pack_err)
		quit(1)
		return
	var save_err := ResourceSaver.save(packed, OUT)
	if save_err != OK:
		push_error("save failed: %d" % save_err)
		quit(1)
		return
	print("wrote ", OUT)
	quit()


func _build() -> Node2D:
	var tile: int = MAP.TILE
	var root := Node2D.new()
	root.name = "ArenaMap"
	root.set_script(MAP)

	var floor_layer := _layer("Floor", -2, root)
	var half_w := int(MAP.HALF_WIDTH) / tile
	var half_h := int(MAP.HALF_HEIGHT) / tile
	for cx in range(-half_w, half_w):
		for cy in range(-half_h, half_h):
			floor_layer.set_cell(Vector2i(cx, cy), 0, FLOOR_TILE)

	var walls := _layer("Walls", -1, root)
	var cover := _layer("Cover", -1, root)
	for spec in MAP.OBSTACLES:
		var rect: Rect2 = spec["rect"]
		var kind: String = spec["kind"]
		var layer := walls if kind == "wall" else cover
		var atlas: Vector2i = KIND_TILE[kind]
		var x0 := int(rect.position.x) / tile
		var y0 := int(rect.position.y) / tile
		var x1 := int(rect.position.x + rect.size.x) / tile
		var y1 := int(rect.position.y + rect.size.y) / tile
		for cx in range(x0, x1):
			for cy in range(y0, y1):
				layer.set_cell(Vector2i(cx, cy), 0, atlas)

	var spawns := Node2D.new()
	spawns.name = "SpawnPoints"
	root.add_child(spawns)
	spawns.owner = root
	var index := 1
	for point in MAP.SPAWNS:
		var marker := Marker2D.new()
		marker.name = "Spawn%d" % index
		marker.position = point
		spawns.add_child(marker)
		marker.owner = root
		index += 1

	return root


func _layer(layer_name: String, z: int, root: Node) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.z_index = z
	layer.tile_set = TILESET
	root.add_child(layer)
	layer.owner = root
	return layer
