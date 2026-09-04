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


func is_inside_bounds(point: Vector2) -> bool:
	return absf(point.x) < HALF_WIDTH and absf(point.y) < HALF_HEIGHT
