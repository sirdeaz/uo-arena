extends Node2D
class_name ArenaMap

## The arena, in one place — painted for looks and collided for physics by the same
## `TileMapLayer`s, in `res://arena/arena_map.tscn`. The server loads this scene too; it
## runs the tile physics headless and the Dedicated Server export drops the texture
## (checked in CI), so `server/` still ships collision only.
##
## Nothing here describes the layout. An obstacle is any painted cell whose tile carries
## a collision polygon in the TileSet — there is no parallel "solid" flag and no
## tent/rock enum. The play field is the extent of the `Floor` layer; the spawn points
## are wherever the `SpawnPoints` markers sit. This script only reads that back, so
## repainting the arena in the editor needs no edit here.


func get_spawn_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for marker in $SpawnPoints.get_children():
		positions.append(marker.position)
	return positions


## The rectangle a fighter is allowed to move within, in world space — the extent of the
## painted `Floor` layer, read straight back from it. Repaint the floor larger and
## `is_inside_bounds` follows; nothing here to keep in step by hand.
func bounds() -> Rect2:
	var layer: TileMapLayer = $Floor
	var used := layer.get_used_rect()
	var cell := Vector2(layer.tile_set.tile_size)
	var top_left := layer.to_global(layer.map_to_local(used.position) - cell * 0.5)
	return Rect2(top_left, Vector2(used.size) * cell)


func is_inside_bounds(point: Vector2) -> bool:
	var box := bounds()
	return (
		point.x > box.position.x and point.x < box.end.x
		and point.y > box.position.y and point.y < box.end.y
	)


## Every obstacle in the arena as a convex polygon, in world space — the tiles' own
## collision polygons, lifted straight off the `TileData` the physics engine uses,
## unioned so adjacent cells stop being a grid, then split back into convex parts.
## Built from `get_used_cells()` + tile data alone, with no live `World2D`, so the
## socket-free suite is unaffected.
##
## Convex on purpose: the visibility-graph pathfinder clips segments against each piece
## as a convex region, so an L-shaped merge has to arrive as two rectangles, not one
## outline with a notch. Cover and boundary alike — whatever is painted on `Walls` or
## `Cover` with a polygon is in here.
func obstacle_polygons() -> Array[PackedVector2Array]:
	var cells: Array[PackedVector2Array] = []
	for node in [$Walls, $Cover]:
		var layer: TileMapLayer = node
		for cell in layer.get_used_cells():
			var data := layer.get_cell_tile_data(cell)
			if data == null:
				continue
			var origin := layer.to_global(layer.map_to_local(cell))
			for i in data.get_collision_polygons_count(0):
				var local := data.get_collision_polygon_points(0, i)
				if local.size() < 3:
					continue
				var world := PackedVector2Array()
				for point in local:
					world.append(origin + point)
				cells.append(world)

	var convex: Array[PackedVector2Array] = []
	for outline in _union(cells):
		convex.append_array(Geometry2D.decompose_polygon_in_convex(outline))
	return convex


## Merges every polygon that touches or overlaps another into one outline, leaving
## disjoint pieces alone. Tile squares that share an edge come back as a single
## outline; two separate cover blocks stay two entries.
static func _union(pieces: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var groups: Array[PackedVector2Array] = []
	for piece in pieces:
		var merged := piece
		var absorbed := true
		while absorbed:
			absorbed = false
			for i in groups.size():
				var result := Geometry2D.merge_polygons(groups[i], merged)
				# One outline back means they joined; two means they never touched.
				if result.size() == 1:
					merged = result[0]
					groups.remove_at(i)
					absorbed = true
					break
		groups.append(merged)
	return groups
