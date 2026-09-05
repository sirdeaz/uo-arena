extends Node2D
class_name ArenaMap

## Collision-only arena. Holds no sprites or visual nodes — the client draws its own
## view of these bounds — so `server/` stays clean for the Dedicated Server export.
##
## Layout is a duel lane down the middle with tents flanking it, and a rock in each
## far corner. The opening shot is available straight down the lane; stepping off it
## puts a tent between you and the enemy immediately. Cover is placed with 180°
## rotational symmetry so neither spawn is favoured.

const HALF_WIDTH: float = 600.0
const HALF_HEIGHT: float = 400.0

## What a piece of cover is, so the client can draw a tent as a tent. Carried as a node
## group rather than a script or a sprite: a group is plain scene data, it survives a
## rename, it is one checkbox in the editor's Node > Groups panel, and `server/` gains
## no rendering code by having it.
enum CoverKind { UNKNOWN, TENT, ROCK }

const GROUP_TENT := "cover_tent"
const GROUP_ROCK := "cover_rock"


func get_spawn_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for marker in $SpawnPoints.get_children():
		positions.append(marker.position)
	return positions


## Cover the players fight around, excluding the boundary walls.
func get_cover_pieces() -> Array[StaticBody2D]:
	var pieces: Array[StaticBody2D] = []
	for child in $Cover.get_children():
		pieces.append(child)
	return pieces


## The kind hint on a cover piece. `UNKNOWN` is drawn as a plain block rather than
## guessed at, so a new piece added without a group still shows up.
static func cover_kind(piece: Node) -> CoverKind:
	if piece.is_in_group(GROUP_TENT):
		return CoverKind.TENT
	if piece.is_in_group(GROUP_ROCK):
		return CoverKind.ROCK
	return CoverKind.UNKNOWN


func is_inside_bounds(point: Vector2) -> bool:
	return absf(point.x) < HALF_WIDTH and absf(point.y) < HALF_HEIGHT
