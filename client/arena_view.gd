extends Node2D
class_name ArenaView

## Draws the arena straight from its collision shapes, so what you see is exactly what
## the raycast hits. No art assets, no second source of truth to drift out of sync.
##
## Two rules hold the whole file together:
##
## 1. Every collision shape gets drawn. A shape this view cannot handle is reported and
##    painted in a loud placeholder colour rather than skipped. Invisible cover is the
##    worst failure this game has — a spell blocked by something you cannot see is
##    indistinguishable from a bug in the resolver.
## 2. A silhouette never hides part of its own collision box. Tents and rocks are drawn
##    over a dimmed footprint of the rect the raycast uses, so the shape you read and
##    the shape that blocks are the same shape.

const FLOOR_COLOR := Palette.FLOOR
const COVER_COLOR := Palette.COVER_FILL
const COVER_EDGE := Palette.COVER_EDGE
const WALL_COLOR := Palette.WALL

## The footprint under a tent or rock: the collision rect, dimmed, so the silhouette can
## sit inside it without any part of the real blocker going unpainted.
const FOOTPRINT_DARKEN := 0.55

const TENT_DOOR_COLOR := Palette.TENT_DOOR

## Half-width of the tent's doorway, as a fraction of the tent's width.
const TENT_DOOR_HALF_WIDTH: float = 0.1

## Loud on purpose. Anything in this colour is cover the view does not understand.
const UNSUPPORTED_COLOR := Palette.UNDRAWABLE

## Ground grid. One cell is one second of movement at `PLAYER_MOVE_SPEED`, which turns
## "can I reach that tent before the flamestrike lands" into a distance you can count
## instead of estimate, and makes small movement visible against a fixed reference.
## Kept far below the sight line and the bolts in contrast — this is a readability aid,
## not decoration.
const GRID_COLOR := Color(Palette.GRID, Palette.GRID_ALPHA)
const AXIS_COLOR := Color(Palette.GRID, Palette.GRID_AXIS_ALPHA)
const GRID_WIDTH: float = 1.0

const CIRCLE_SEGMENTS: int = 24
const ROCK_FACETS: int = 11

var map: ArenaMap

## Node paths already reported as undrawable, so the warning fires once rather than on
## every redraw.
var _warned := {}


func setup(arena_map: ArenaMap) -> void:
	map = arena_map
	queue_redraw()


## Side of one grid cell: one second of movement. Exposed so a test can pin the meaning
## rather than the number.
static func grid_pitch() -> float:
	return Constants.PLAYER_MOVE_SPEED


func _draw() -> void:
	if map == null:
		return

	_draw_floor()

	for wall in map.get_node("Bounds").get_children():
		_draw_body(wall, WALL_COLOR, WALL_COLOR)
	for piece in map.get_cover_pieces():
		_draw_cover(piece)


func _draw_floor() -> void:
	draw_rect(
		Rect2(
			-ArenaMap.HALF_WIDTH,
			-ArenaMap.HALF_HEIGHT,
			ArenaMap.HALF_WIDTH * 2.0,
			ArenaMap.HALF_HEIGHT * 2.0
		),
		FLOOR_COLOR
	)

	var pitch := grid_pitch()

	var columns := int(ArenaMap.HALF_WIDTH / pitch)
	for i in range(-columns, columns + 1):
		var x := float(i) * pitch
		draw_line(
			Vector2(x, -ArenaMap.HALF_HEIGHT),
			Vector2(x, ArenaMap.HALF_HEIGHT),
			AXIS_COLOR if i == 0 else GRID_COLOR,
			GRID_WIDTH
		)

	var rows := int(ArenaMap.HALF_HEIGHT / pitch)
	for i in range(-rows, rows + 1):
		var y := float(i) * pitch
		# y == 0 is the duel lane between the spawns; the brighter pair of axes also
		# shows the arena's 180° symmetry at a glance.
		draw_line(
			Vector2(-ArenaMap.HALF_WIDTH, y),
			Vector2(ArenaMap.HALF_WIDTH, y),
			AXIS_COLOR if i == 0 else GRID_COLOR,
			GRID_WIDTH
		)


func _draw_body(body: StaticBody2D, fill: Color, edge: Color) -> void:
	for child in body.get_children():
		if child is not CollisionShape2D:
			continue
		var collision := child as CollisionShape2D
		_draw_shape(collision, body.transform * collision.transform, fill, edge)


## Cover gets a silhouette when the map tells us what it is and the shape is a plain
## rect. Anything else falls back to the generic shape drawing, which still draws.
func _draw_cover(piece: StaticBody2D) -> void:
	var kind := ArenaMap.cover_kind(piece)
	for child in piece.get_children():
		if child is not CollisionShape2D:
			continue
		var collision := child as CollisionShape2D
		var xform := piece.transform * collision.transform

		if kind != ArenaMap.CoverKind.UNKNOWN and collision.shape is RectangleShape2D:
			var size: Vector2 = (collision.shape as RectangleShape2D).size
			var rect := Rect2(-size * 0.5, size)
			if kind == ArenaMap.CoverKind.TENT:
				_draw_tent(rect, xform)
			else:
				_draw_rock(rect, xform)
			continue

		_draw_shape(collision, xform, COVER_COLOR, COVER_EDGE)


# ── shapes ────────────────────────────────────────────────────────────────────

## Outline of a collision shape in its own local space, or an empty array if this view
## has no way to draw it. Static so a test can ask exactly the question the drawing
## asks, without having to render anything.
static func shape_polygon(shape: Shape2D) -> PackedVector2Array:
	var points := PackedVector2Array()

	if shape is RectangleShape2D:
		var half: Vector2 = (shape as RectangleShape2D).size * 0.5
		points.append(Vector2(-half.x, -half.y))
		points.append(Vector2(half.x, -half.y))
		points.append(Vector2(half.x, half.y))
		points.append(Vector2(-half.x, half.y))
	elif shape is CircleShape2D:
		var radius: float = (shape as CircleShape2D).radius
		for i in CIRCLE_SEGMENTS:
			points.append(
				Vector2(radius, 0.0).rotated(TAU * float(i) / float(CIRCLE_SEGMENTS))
			)
	elif shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		# Godot's capsule stands upright and `height` includes both caps, so the
		# straight section is what is left after taking a radius off each end.
		var straight := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
		var per_cap := CIRCLE_SEGMENTS / 2
		for i in per_cap:
			var angle := PI * float(i) / float(per_cap)
			points.append(
				Vector2(cos(angle), sin(angle)) * capsule.radius + Vector2(0.0, straight)
			)
		for i in per_cap:
			var angle := PI + PI * float(i) / float(per_cap)
			points.append(
				Vector2(cos(angle), sin(angle)) * capsule.radius - Vector2(0.0, straight)
			)
	elif shape is ConvexPolygonShape2D:
		points = (shape as ConvexPolygonShape2D).points.duplicate()

	return points


## True when `shape_polygon` can produce a real outline for this shape. A cover piece
## that fails this draws as a placeholder and warns.
static func can_draw(shape: Shape2D) -> bool:
	return shape != null and shape_polygon(shape).size() >= 3


func _draw_shape(
	collision: CollisionShape2D, xform: Transform2D, fill: Color, edge: Color
) -> void:
	if not can_draw(collision.shape):
		_draw_unsupported(collision, xform)
		return
	var points := _transformed(shape_polygon(collision.shape), xform)
	draw_colored_polygon(points, fill)
	_draw_outline(points, edge)


## Fail loudly. Silent omission is the one behaviour that must not survive here, so an
## unknown shape gets a magenta bounding box and a warning naming the node.
func _draw_unsupported(collision: CollisionShape2D, xform: Transform2D) -> void:
	var path := str(collision.get_path())
	if not _warned.has(path):
		_warned[path] = true
		var described := "no shape" if collision.shape == null else collision.shape.get_class()
		push_warning(
			("ArenaView cannot draw %s (%s), so it is a magenta placeholder. " % [path, described])
			+ "Cover a player cannot see is worse than no cover — teach "
			+ "ArenaView.shape_polygon how to outline this shape."
		)

	if collision.shape == null:
		return

	var bounds := collision.shape.get_rect()
	var corners := _transformed(
		PackedVector2Array([
			bounds.position,
			Vector2(bounds.end.x, bounds.position.y),
			bounds.end,
			Vector2(bounds.position.x, bounds.end.y),
		]),
		xform
	)
	draw_colored_polygon(corners, Color(UNSUPPORTED_COLOR, 0.25))
	_draw_outline(corners, UNSUPPORTED_COLOR, 3.0)
	draw_line(corners[0], corners[2], UNSUPPORTED_COLOR, 3.0)
	draw_line(corners[1], corners[3], UNSUPPORTED_COLOR, 3.0)


# ── cover silhouettes ─────────────────────────────────────────────────────────

## A tent: a peaked roof with a ridge pole and a dark doorway, inscribed in the
## collision rect that is drawn underneath it. The peak is what separates it from the
## rock at a glance — a straight ridge reads as built, an irregular lump reads as stone.
func _draw_tent(rect: Rect2, xform: Transform2D) -> void:
	_draw_footprint(rect, xform)

	var centre_x := rect.get_center().x
	var apex := Vector2(centre_x, rect.position.y)
	var base_centre := Vector2(centre_x, rect.end.y)

	var canvas := _transformed(
		PackedVector2Array([
			apex, Vector2(rect.end.x, rect.end.y), Vector2(rect.position.x, rect.end.y)
		]),
		xform
	)
	draw_colored_polygon(canvas, COVER_COLOR)
	_draw_outline(canvas, COVER_EDGE)

	# Ridge pole, so the peak reads as a peak rather than a flat triangle.
	draw_line(xform * apex, xform * base_centre, COVER_EDGE.darkened(0.25), 2.0)

	var door_half := rect.size.x * TENT_DOOR_HALF_WIDTH
	var door := _transformed(
		PackedVector2Array([
			base_centre - Vector2(door_half, 0.0),
			Vector2(centre_x, rect.position.y + rect.size.y * 0.42),
			base_centre + Vector2(door_half, 0.0),
		]),
		xform
	)
	draw_colored_polygon(door, TENT_DOOR_COLOR)


## A rock: an irregular chunky lump. The jitter is seeded from the piece's own position
## so a given rock has the same silhouette on every frame and between runs.
func _draw_rock(rect: Rect2, xform: Transform2D) -> void:
	_draw_footprint(rect, xform)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(xform.origin)

	var centre := rect.get_center()
	var radii := rect.size * 0.5
	var points := PackedVector2Array()
	for i in ROCK_FACETS:
		var angle := TAU * float(i) / float(ROCK_FACETS)
		var chunk := rng.randf_range(0.86, 1.0)
		points.append(
			centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y) * chunk
		)
	var world := _transformed(points, xform)

	draw_colored_polygon(world, COVER_COLOR.darkened(0.12))
	_draw_outline(world, COVER_EDGE)

	# A couple of facet creases catching the light, from an off-centre high point.
	var crest := xform * (centre + Vector2(-radii.x * 0.22, -radii.y * 0.28))
	for i in [0, 3, 6]:
		draw_line(crest, world[i % world.size()], COVER_EDGE.darkened(0.35), 1.5)


func _draw_footprint(rect: Rect2, xform: Transform2D) -> void:
	var corners := _transformed(
		PackedVector2Array([
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		]),
		xform
	)
	draw_colored_polygon(corners, COVER_COLOR.darkened(FOOTPRINT_DARKEN))
	_draw_outline(corners, COVER_EDGE.darkened(0.45), 1.0)


# ── helpers ───────────────────────────────────────────────────────────────────

func _transformed(points: PackedVector2Array, xform: Transform2D) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(xform * point)
	return out


func _draw_outline(points: PackedVector2Array, color: Color, width: float = 2.0) -> void:
	if points.size() < 2:
		return
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, width)
