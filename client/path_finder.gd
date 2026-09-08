extends RefCounted
class_name PathFinder

## Routes a player around cover, so holding the move button toward a point behind a tent
## walks around the tent instead of sliding along its face.
##
## This is a visibility graph. Every obstacle is inflated by the player's radius, the
## corners of those inflated outlines become nodes, every pair of corners that can see
## each other is joined, and A* searches the result. Inflating first is the part that
## makes a route walkable rather than merely short: it turns a body eighteen pixels wide
## into a point, so a line the search calls clear is one the player actually fits through.
##
## It is plain geometry on purpose — no navigation server, no baked mesh, nothing that
## needs a frame to settle — so a test can ask exactly the question the game asks without
## rendering anything. That is the same reason the arena is read from its tiles, and
## this reuses that converter rather than growing a second one: what the search routes
## around cannot then drift from what you see.
##
## The arena suits the approach — four convex cover pieces and four walls, about twenty
## corners, fixed at load. Joining corners is O(n²) in their count, so a map with many
## pieces, or with concave shapes, would want a navigation mesh instead.

## Clearance beyond the player's own radius. Deliberately small: every pixel here narrows
## every gap, and the tightest real gap in the arena — a corner rock and the south wall —
## is only 95px to begin with.
const CLEARANCE_MARGIN: float = 4.0

## Lengths below this are treated as nothing, when deciding whether a segment truly passed
## through an obstacle or merely grazed a corner of it.
const EPSILON: float = 0.01

## Obstacles grown by the player's radius, in world space. A point outside all of these is
## a position the real body fits in.
var _blockers: Array[PackedVector2Array] = []

## Every corner of every blocker, minus any that another blocker swallowed.
var _corners: PackedVector2Array = PackedVector2Array()

## `_visible[i]` lists the corner indices corner `i` can walk straight to.
var _visible: Array[PackedInt32Array] = []


## Builds the graph from a map. Called once — the arena's geometry is fixed at load and
## nothing ever moves it.
func build(map: ArenaMap) -> void:
	_blockers = []
	for polygon in obstacle_polygons(map):
		var grown := inflate(polygon, Constants.PLAYER_RADIUS + CLEARANCE_MARGIN)
		if grown.size() >= 3:
			_blockers.append(grown)

	# A corner buried inside another blocker is not somewhere anyone can stand, and
	# leaving it in only gives the search dead ends to rule out.
	_corners = PackedVector2Array()
	for polygon in _blockers:
		for point in polygon:
			if not _inside_any(point, _blockers):
				_corners.append(point)

	_visible = []
	for i in _corners.size():
		var row := PackedInt32Array()
		for j in _corners.size():
			if i != j and segment_is_clear(_corners[i], _corners[j], _blockers):
				row.append(j)
		_visible.append(row)


## True when the player can walk straight from `from` to `to` without clipping cover.
##
## This is the question the caller asks before bothering to route at all, so it has to
## agree with the graph exactly — which is why it goes through the same inflated blockers
## rather than the physics raycast. A ray is a zero-width line and would call a gap clear
## that an eighteen-pixel body cannot fit through.
func segment_is_walkable(from: Vector2, to: Vector2) -> bool:
	return segment_is_clear(
		_nudged_outside(from), _nudged_outside(to), _blockers
	)


## The waypoints to walk: the first corner to head for, then the rest, ending at the
## destination. Empty when there is no route at all.
##
## Both ends are nudged clear of any blocker they are inside first. Standing against a
## tent puts you inside its clearance zone — the zone is wider than the tent — and a route
## that refused to start there would mean pathfinding silently switching itself off in the
## exact situation it exists for.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var origin := _nudged_outside(from)
	var destination := _nudged_outside(to)

	if segment_is_clear(origin, destination, _blockers):
		return PackedVector2Array([destination])

	var count := _corners.size()
	if count == 0:
		return PackedVector2Array()

	var points := PackedVector2Array(_corners)
	points.append(origin)
	points.append(destination)
	var start := count
	var goal := count + 1

	var from_visible := PackedInt32Array()
	var to_visible := PackedInt32Array()
	for i in count:
		if segment_is_clear(origin, _corners[i], _blockers):
			from_visible.append(i)
		if segment_is_clear(destination, _corners[i], _blockers):
			to_visible.append(i)

	return _search(points, start, goal, from_visible, to_visible)


## Every solid rectangle in the arena, in world space — cover and boundary walls alike,
## as `ArenaMap.obstacle_rects()` reports them. The arena is tiled now, so these are the
## same rectangles the tiles are painted over, tile-aligned; the routing graph is built
## from exactly what the resolver raycasts against.
static func obstacle_polygons(map: ArenaMap) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	for rect in map.obstacle_rects():
		polygons.append(PackedVector2Array([
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		]))
	return polygons


## Grows a polygon outward by `amount`, or returns empty when the shape is too degenerate
## to offset.
##
## Whether an offset grows or shrinks depends on the ring's winding, which is not
## something we can assume — `shape_polygon` builds its outlines in a fixed order but a
## convex polygon shape carries whatever order its author gave it. So the result is
## checked: if it did not come back bigger, the winding was against us, and the reversed
## polygon is offset instead. Getting this backwards would quietly shrink every obstacle
## and route players straight through tents.
static func inflate(polygon: PackedVector2Array, amount: float) -> PackedVector2Array:
	if polygon.size() < 3:
		return PackedVector2Array()

	var area := absf(polygon_area(polygon))
	var grown := _largest_ring(Geometry2D.offset_polygon(polygon, amount, Geometry2D.JOIN_MITER))
	if absf(polygon_area(grown)) > area:
		return grown

	var reversed := polygon.duplicate()
	reversed.reverse()
	grown = _largest_ring(Geometry2D.offset_polygon(reversed, amount, Geometry2D.JOIN_MITER))
	if absf(polygon_area(grown)) > area:
		return grown

	return PackedVector2Array()


static func _largest_ring(rings: Array[PackedVector2Array]) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := 0.0
	for ring in rings:
		var area := absf(polygon_area(ring))
		if area > best_area:
			best_area = area
			best = ring
	return best


## True when nothing in `polygons` blocks a straight walk from `from` to `to`.
static func segment_is_clear(
	from: Vector2, to: Vector2, polygons: Array[PackedVector2Array]
) -> bool:
	for polygon in polygons:
		if _segment_enters(from, to, polygon):
			return false
	return true


## Twice the signed area of a polygon, halved — the plain shoelace sum. Sign follows
## winding, so callers that only want size take the absolute value.
static func polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	var count := polygon.size()
	for i in count:
		var a := polygon[i]
		var b := polygon[(i + 1) % count]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


# ── Geometry ──────────────────────────────────────────────────────────────────────


## True when the segment passes through the inside of a convex polygon, rather than merely
## touching a corner or running along an edge.
##
## Grazing has to be allowed. The graph's own nodes sit on these outlines, so a route that
## hugs one would otherwise be rejected as a collision with the very thing it is going
## around, and no path would ever be found.
##
## Clips the segment against each edge's half-plane and asks whether anything of real
## length survives inside — exact for convex shapes, and every shape `shape_polygon`
## produces is convex.
static func _segment_enters(
	from: Vector2, to: Vector2, polygon: PackedVector2Array
) -> bool:
	var direction := to - from
	var length := direction.length()
	if length <= EPSILON:
		return false

	var centroid := _centroid(polygon)
	var entering := 0.0
	var leaving := 1.0
	var count := polygon.size()

	for i in count:
		var a := polygon[i]
		var normal := _outward_normal(a, polygon[(i + 1) % count], centroid)
		var denominator := normal.dot(direction)
		var distance := normal.dot(from - a)

		if absf(denominator) <= EPSILON:
			# Parallel to this edge: either wholly outside it, or it constrains nothing.
			if distance >= 0.0:
				return false
			continue

		var t := -distance / denominator
		if denominator < 0.0:
			entering = maxf(entering, t)
		else:
			leaving = minf(leaving, t)

		if leaving <= entering:
			return false

	return (leaving - entering) * length > EPSILON


## True when the point is properly inside the polygon, not merely on its edge. A polygon's
## own corners must not count as inside it.
static func _is_inside(point: Vector2, polygon: PackedVector2Array) -> bool:
	var centroid := _centroid(polygon)
	var count := polygon.size()
	for i in count:
		var a := polygon[i]
		var normal := _outward_normal(a, polygon[(i + 1) % count], centroid).normalized()
		if normal.dot(point - a) > -EPSILON:
			return false
	return true


static func _inside_any(point: Vector2, polygons: Array[PackedVector2Array]) -> bool:
	for polygon in polygons:
		if _is_inside(point, polygon):
			return true
	return false


## The nearest position outside every blocker. A point already clear of them is returned
## untouched, so this costs nothing in the ordinary case.
func _nudged_outside(point: Vector2) -> Vector2:
	var moved := point
	# Twice, because leaving one blocker can land on the edge of its neighbour.
	for _pass in 2:
		for polygon in _blockers:
			if _is_inside(moved, polygon):
				moved = _closest_boundary_point(moved, polygon)
	return moved


static func _closest_boundary_point(
	point: Vector2, polygon: PackedVector2Array
) -> Vector2:
	var best := polygon[0]
	var best_distance := INF
	var count := polygon.size()
	for i in count:
		var candidate := Geometry2D.get_closest_point_to_segment(
			point, polygon[i], polygon[(i + 1) % count]
		)
		var distance := point.distance_to(candidate)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## The edge normal that points away from the shape. Derived from the centroid rather than
## assumed from winding, so neither Godot's y-down axis nor whichever order
## `offset_polygon` hands a ring back in can flip it.
static func _outward_normal(a: Vector2, b: Vector2, centroid: Vector2) -> Vector2:
	var normal := (b - a).orthogonal()
	if normal.dot(centroid - a) > 0.0:
		return -normal
	return normal


## Vertex average, which for a convex polygon is always inside it.
static func _centroid(polygon: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for point in polygon:
		sum += point
	return sum / float(polygon.size())



# ── Search ────────────────────────────────────────────────────────────────────────


## A* over the visibility graph. Small enough — about twenty nodes — that scanning the
## open set beats maintaining a heap.
func _search(
	points: PackedVector2Array,
	start: int,
	goal: int,
	from_visible: PackedInt32Array,
	to_visible: PackedInt32Array
) -> PackedVector2Array:
	var total := points.size()
	var destination := points[goal]

	var came_from := PackedInt32Array()
	came_from.resize(total)
	came_from.fill(-1)

	var best := PackedFloat32Array()
	best.resize(total)
	best.fill(INF)
	best[start] = 0.0

	var closed := PackedByteArray()
	closed.resize(total)

	while true:
		var current := -1
		var current_score := INF
		for i in total:
			if closed[i] == 1 or is_inf(best[i]):
				continue
			var score: float = best[i] + points[i].distance_to(destination)
			if score < current_score:
				current_score = score
				current = i

		if current == -1:
			return PackedVector2Array()
		if current == goal:
			break
		closed[current] = 1

		for neighbour in _neighbours(current, start, goal, from_visible, to_visible):
			if closed[neighbour] == 1:
				continue
			var step: float = best[current] + points[current].distance_to(points[neighbour])
			if step < best[neighbour]:
				best[neighbour] = step
				came_from[neighbour] = current

	return _reconstruct(points, came_from, start, goal)


func _neighbours(
	node: int,
	start: int,
	goal: int,
	from_visible: PackedInt32Array,
	to_visible: PackedInt32Array
) -> PackedInt32Array:
	# A start that could see the goal never reaches the search — `find_path` returns the
	# straight line before getting here — so the start only ever opens onto corners.
	if node == start:
		return from_visible
	if node == goal:
		return PackedInt32Array()

	var out := PackedInt32Array(_visible[node])
	if to_visible.has(node):
		out.append(goal)
	return out


static func _reconstruct(
	points: PackedVector2Array, came_from: PackedInt32Array, start: int, goal: int
) -> PackedVector2Array:
	var backwards := PackedVector2Array()
	var node := goal
	while node != start and node != -1:
		backwards.append(points[node])
		node = came_from[node]

	if node != start:
		return PackedVector2Array()

	var path := PackedVector2Array()
	for i in range(backwards.size() - 1, -1, -1):
		path.append(backwards[i])
	return path
