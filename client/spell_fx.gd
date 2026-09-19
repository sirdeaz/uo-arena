extends RefCounted
class_name SpellFX

## Shape generators for the crackling rings and jagged bolts, plus the meshes that turn
## them into glow.
##
## Shapes are seeded rather than randomised per frame: regenerating each frame strobes,
## while stepping the seed at a fixed rate reads as crackle. Drawing hands each shape to
## `res://client/shaders/spell_glow.gdshader` as one mesh, which does the halo→body→core
## falloff in the fragment shader instead of stacking flat-alpha passes on the CPU.

## How many times a second a shape re-rolls. Slow enough to read, fast enough to crackle.
const CRACKLE_HZ: float = 18.0


## A jagged polyline from `from` to `to`. Endpoints are exact — a bolt that stops short
## of its target reads as a miss.
static func bolt_path(
	from: Vector2, to: Vector2, segments: int, amplitude: float, rng_seed: int
) -> PackedVector2Array:
	var path := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var along := to - from
	var across := Vector2(-along.y, along.x)
	if across.length() > 0.0:
		across = across.normalized()

	for i in segments + 1:
		var t := float(i) / float(segments)
		var point := from.lerp(to, t)
		if i > 0 and i < segments:
			# Taper the wander toward both ends so the bolt looks anchored.
			var taper := sin(t * PI)
			point += across * rng.randf_range(-amplitude, amplitude) * taper
		path.append(point)
	return path


## A closed ring of points with jittered radius, centred on the origin.
static func ring_path(
	radius: float, points: int, jitter: float, rng_seed: int
) -> PackedVector2Array:
	var path := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in points:
		var angle := TAU * float(i) / float(points)
		var r := radius + rng.randf_range(-jitter, jitter)
		path.append(Vector2(r, 0.0).rotated(angle))
	return path


## Seed that advances at `CRACKLE_HZ`, so shapes hold still long enough to be seen.
static func crackle_seed(time: float, salt: int = 0) -> int:
	return int(time * CRACKLE_HZ) * 977 + salt


# ── Glow meshes ──────────────────────────────────────────────────────────────────
#
# `res://client/shaders/spell_glow.gdshader` turns a distance into a halo→body→core
# falloff in one fragment pass — real glow, replacing the old three stacked
# flat-alpha `draw_polyline`/`draw_circle` calls (#151). It reads that distance as
# `length(UV)`, so every mesh built below carries a UV that is a signed offset from
# the shape's own centre, one unit per axis: a stroke's offset across its width, or a
# disc's offset within its bounding quad. Building the vertex/UV/index arrays is the
# decision (CLAUDE.md: pull the decision into a static function), so it is pure and
# tested without a canvas; only `_submit` below touches the canvas.

## Half the visible width of a stroke at `width = 1.0` — the old halo pass's width
## (9.0) was the widest thing on screen, so it sets the new falloff's outer edge too.
const STROKE_HALF_WIDTH: float = 4.5


## Vertices, UVs and a triangle-list index array for a stroke strip along `points`,
## `width` wide. Closed strips wrap their end normals into their start ones so a ring
## has no seam at the join.
static func stroke_strip(points: PackedVector2Array, width: float, closed: bool) -> Dictionary:
	var count := points.size()
	var half := STROKE_HALF_WIDTH * width
	var loop_count := count + 1 if closed else count

	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in loop_count:
		var index := i % count
		var normal := _normal_at(points, index, closed)
		vertices.append(points[index] + normal * half)
		vertices.append(points[index] - normal * half)
		uvs.append(Vector2(0.0, 1.0))
		uvs.append(Vector2(0.0, -1.0))

	var indices := PackedInt32Array()
	for i in loop_count - 1:
		var a := i * 2
		indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])

	return {"vertices": vertices, "uvs": uvs, "indices": indices}


## The perpendicular a stroke's two rail vertices sit on at `points[i]` — the average
## of its neighbouring segment directions, so a bend gets a mitred rather than a
## kinked rail. Open strokes have no neighbour past either end; closed ones wrap.
static func _normal_at(points: PackedVector2Array, i: int, closed: bool) -> Vector2:
	var count := points.size()
	var has_prev := closed or i > 0
	var has_next := closed or i < count - 1
	var dir := Vector2.ZERO
	if has_prev:
		dir += (points[i] - points[(i - 1 + count) % count]).normalized()
	if has_next:
		dir += (points[(i + 1) % count] - points[i]).normalized()
	if dir.length() == 0.0:
		return Vector2.ZERO
	return Vector2(-dir.y, dir.x).normalized()


## Vertices, UVs and indices for a disc's bounding quad, centred on `centre`.
static func disc_quad(centre: Vector2, radius: float) -> Dictionary:
	var vertices := PackedVector2Array([
		centre + Vector2(-radius, -radius),
		centre + Vector2(radius, -radius),
		centre + Vector2(radius, radius),
		centre + Vector2(-radius, radius),
	])
	var uvs := PackedVector2Array([
		Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1),
	])
	return {"vertices": vertices, "uvs": uvs, "indices": PackedInt32Array([0, 1, 2, 0, 2, 3])}


## Submits a built mesh as one triangle array, flat-shaded `color` — the falloff
## shader on `canvas.material` does the rest per pixel.
static func _submit(canvas: CanvasItem, mesh: Dictionary, color: Color) -> void:
	var colors := PackedColorArray()
	colors.resize(mesh["vertices"].size())
	colors.fill(color)
	RenderingServer.canvas_item_add_triangle_array(
		canvas.get_canvas_item(), mesh["indices"], mesh["vertices"], colors, mesh["uvs"]
	)


## A glowing stroke along `points` — a jagged bolt, a fork, a crackling ring.
static func draw_glow_line(
	canvas: CanvasItem,
	points: PackedVector2Array,
	color: Color,
	intensity: float,
	width: float = 1.0,
	closed: bool = false
) -> void:
	if points.size() < 2 or intensity <= 0.0:
		return
	_submit(canvas, stroke_strip(points, width, closed), Color(color, intensity))


## A soft radial haze at `centre` — the aura behind a cast, the flash of an impact.
static func draw_glow_disc(
	canvas: CanvasItem, centre: Vector2, radius: float, color: Color, intensity: float
) -> void:
	if intensity <= 0.0 or radius <= 0.0:
		return
	_submit(canvas, disc_quad(centre, radius), Color(color, intensity))
