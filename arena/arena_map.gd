extends Node2D
class_name ArenaMap

## The arena, in one place — painted for looks and collided for physics by the same
## `TileMapLayer`s, in the same `.tscn`. The server loads this scene too; it runs the
## tile physics headless and the Dedicated Server export drops the texture (checked in
## CI), so `server/` still ships collision only.
##
## Layout is a duel lane down the middle with tents flanking it and a rock in each far
## corner. The opening shot is available straight down the lane; stepping off it puts a
## tent between you and the enemy immediately. Cover is placed with 180° rotational
## symmetry so neither spawn is favoured.
##
## The obstacle rectangles and spawn points below are the source of record.
## `tools/build_arena.gd` paints `arena.tscn` from them, and `tests/test_arena_tiles.gd`
## fails if the paint and this list drift. Every coordinate is a multiple of 32 — the
## tile size — which moved the arena a little off its old 5-lattice values (HALF_WIDTH
## 600→608, HALF_HEIGHT 400→416, tents 200×110→192×96, rocks 130→128, the duel spawns
## ±500→±512): the cost of the tiles owning the collision.

const TILE: int = 32

const HALF_WIDTH: float = 608.0
const HALF_HEIGHT: float = 416.0

## What a piece of cover is, so the client can draw a tent as a tent. Carried on the
## tile's `kind` custom-data now that there are no cover nodes to put in a group.
enum CoverKind { UNKNOWN, TENT, ROCK }

## Obstacle rectangles in world space, each tagged with its kind. Walls included: the
## boundary is solid tiles like everything else. All coordinates are multiples of `TILE`.
const OBSTACLES: Array[Dictionary] = [
	{"rect": Rect2(-640.0, -448.0, 1280.0, 32.0), "kind": "wall"},   # north
	{"rect": Rect2(-640.0, 416.0, 1280.0, 32.0), "kind": "wall"},    # south
	{"rect": Rect2(-640.0, -448.0, 32.0, 896.0), "kind": "wall"},    # west
	{"rect": Rect2(608.0, -448.0, 32.0, 896.0), "kind": "wall"},     # east
	{"rect": Rect2(-96.0, -192.0, 192.0, 96.0), "kind": "tent"},     # tent north — centre (0, -144)
	{"rect": Rect2(-96.0, 96.0, 192.0, 96.0), "kind": "tent"},       # tent south — centre (0, 144)
	{"rect": Rect2(-352.0, 192.0, 128.0, 128.0), "kind": "rock"},    # rock south-west — centre (-288, 256)
	{"rect": Rect2(224.0, -320.0, 128.0, 128.0), "kind": "rock"},    # rock north-east — centre (288, -256)
]

## Spawn points, in order. The first two are the duel lane — the 1v1 pair on the centre
## line, which several tests still read as "the opening shot" — and the set as a whole is
## 180° rotationally symmetric: for every spawn `p` there is a spawn at `-p`.
const SPAWNS: Array[Vector2] = [
	Vector2(-512.0, 0.0), Vector2(512.0, 0.0),
	Vector2(-512.0, 288.0), Vector2(512.0, -288.0),
	Vector2(-512.0, -288.0), Vector2(512.0, 288.0),
	Vector2(-160.0, 352.0), Vector2(160.0, -352.0),
	Vector2(-160.0, -352.0), Vector2(160.0, 352.0),
]


func get_spawn_positions() -> Array[Vector2]:
	return SPAWNS.duplicate()


## Every solid rectangle in the arena — cover and boundary walls alike — in world space.
## Replaces the old `get_cover_pieces()`: pathfinding routes around these, and they are
## the same rectangles the tiles are painted over.
func obstacle_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for spec in OBSTACLES:
		rects.append(spec["rect"])
	return rects


## Just the cover — tents and rocks, not the boundary — for callers that only care about
## the pieces a player hides behind.
func cover_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for spec in OBSTACLES:
		if spec["kind"] != "wall":
			rects.append(spec["rect"])
	return rects


## What kind of cover, if any, sits at a world point. `UNKNOWN` for open ground or a
## boundary wall — the client draws only tents and rocks.
static func cover_kind_at(point: Vector2) -> CoverKind:
	for spec in OBSTACLES:
		if (spec["rect"] as Rect2).has_point(point):
			match spec["kind"]:
				"tent":
					return CoverKind.TENT
				"rock":
					return CoverKind.ROCK
	return CoverKind.UNKNOWN


func is_inside_bounds(point: Vector2) -> bool:
	return absf(point.x) < HALF_WIDTH and absf(point.y) < HALF_HEIGHT
