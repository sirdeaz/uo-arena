extends Node2D
class_name ArenaView

## A developer overlay of the arena's true collision shapes, off by default.
##
## The floor, the boundary and the cover are painted tiles now — `client/scenes/
## arena_ground.tscn`, editable in the editor — and `tests/test_arena_tiles.gd` is what
## guarantees a solid tile sits over every collider and nowhere else. That test replaced
## the job this node used to do by drawing everything itself.
##
## What stays here is the shape-to-outline conversion (`shape_polygon`), because
## `client/path_finder.gd` routes around the very same polygons, and a switchable overlay
## that draws those outlines so a mismatch between a collider and its tile can be seen
## directly. Set `debug_shapes` true — from the remote inspector, or a one-line patch —
## and every collision shape is outlined; anything this view cannot outline is still a
## loud magenta placeholder rather than a silent gap.

const WALL_EDGE := Palette.WALL
const COVER_EDGE := Palette.COVER_EDGE

## Loud on purpose. Anything in this colour is a shape the overlay cannot outline.
const UNSUPPORTED_COLOR := Palette.UNDRAWABLE

const CIRCLE_SEGMENTS: int = 24

## Off by default: the tiles are what a player sees. Flip it to check tile alignment
## against the shapes the resolver actually raycasts.
var debug_shapes: bool = false

var map: ArenaMap

## Node paths already reported as undrawable, so the warning fires once rather than on
## every redraw.
var _warned := {}


func setup(arena_map: ArenaMap) -> void:
	map = arena_map
	queue_redraw()


func _draw() -> void:
	if map == null or not debug_shapes:
		return

	for wall in map.get_node("Bounds").get_children():
		_draw_body(wall, WALL_EDGE)
	for piece in map.get_cover_pieces():
		_draw_body(piece, COVER_EDGE)


func _draw_body(body: StaticBody2D, edge: Color) -> void:
	for child in body.get_children():
		if child is not CollisionShape2D:
			continue
		var collision := child as CollisionShape2D
		_draw_shape(collision, body.transform * collision.transform, edge)


# ── shapes ────────────────────────────────────────────────────────────────────

## Outline of a collision shape in its own local space, or an empty array if this view
## has no way to draw it. Static so a test can ask exactly the question the drawing
## asks, without having to render anything — and so `PathFinder` can route around the
## same outline the overlay draws.
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


## True when `shape_polygon` can produce a real outline for this shape. A shape that
## fails this draws as a placeholder and warns.
static func can_draw(shape: Shape2D) -> bool:
	return shape != null and shape_polygon(shape).size() >= 3


func _draw_shape(collision: CollisionShape2D, xform: Transform2D, edge: Color) -> void:
	if not can_draw(collision.shape):
		_draw_unsupported(collision, xform)
		return
	var points := _transformed(shape_polygon(collision.shape), xform)
	_draw_outline(points, edge)


## Fail loudly. An unknown shape gets a magenta bounding box and a warning naming the
## node, so a collider the overlay cannot outline is still visibly there.
func _draw_unsupported(collision: CollisionShape2D, xform: Transform2D) -> void:
	var path := str(collision.get_path())
	if not _warned.has(path):
		_warned[path] = true
		var described := "no shape" if collision.shape == null else collision.shape.get_class()
		push_warning(
			("ArenaView cannot outline %s (%s), so it is a magenta placeholder. " % [path, described])
			+ "Teach ArenaView.shape_polygon how to outline this shape."
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
