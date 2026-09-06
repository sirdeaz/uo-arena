extends RefCounted
class_name SpellFX

## Shape generators for the crackling rings and jagged bolts.
##
## Everything is seeded rather than randomised per frame: regenerating each frame
## strobes, while stepping the seed at a fixed rate reads as crackle. Drawing stacks
## these shapes in additive passes — a wide dim halo, a mid body, then a thin near-white
## core — which is what makes light look like it is glowing rather than painted.

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


## An additive material. Additive is what sells energy: overlapping passes accumulate
## toward white, so a shape looks lit from within rather than painted on.
static func additive_material() -> CanvasItemMaterial:
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return material


## Draws a line three times — a wide dim halo, a body, then a thin near-white core.
## Stacked additively that reads as a glowing filament rather than a coloured stroke.
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

	var path := points
	if closed:
		path = points.duplicate()
		path.append(points[0])

	var core := color.lerp(Color(1, 1, 1), 0.72)
	canvas.draw_polyline(path, Color(color, 0.10 * intensity), 9.0 * width, true)
	canvas.draw_polyline(path, Color(color, 0.30 * intensity), 4.5 * width, true)
	canvas.draw_polyline(path, Color(core, 0.85 * intensity), 1.6 * width, true)


## A soft radial haze, built from a few stacked discs. Cheap stand-in for real bloom,
## which the Compatibility renderer will not give us for 2D.
static func draw_glow_disc(
	canvas: CanvasItem, centre: Vector2, radius: float, color: Color, intensity: float
) -> void:
	if intensity <= 0.0 or radius <= 0.0:
		return
	canvas.draw_circle(centre, radius, Color(color, 0.05 * intensity))
	canvas.draw_circle(centre, radius * 0.62, Color(color, 0.07 * intensity))
	canvas.draw_circle(centre, radius * 0.30, Color(color, 0.12 * intensity))
