extends RefCounted
class_name PathSteering

## Turns "where the cursor is" into "where to aim right now", routed around cover.
##
## Answers with the cursor itself whenever the straight line is walkable, so when nothing
## is in the way the caller produces exactly the vector it always has and the toggle
## changes nothing at all. Everything else here exists because the goal moves every frame
## — it is the live cursor, not a destination picked once — which makes this a steering
## problem rather than a navigation one.

## How far the cursor may drift before the route is solved again.
const GOAL_DRIFT: float = 24.0

## Solve again at least this often regardless, so a slowly creeping cursor still
## refreshes. Six ticks is 10Hz at the physics rate the client and server both pin.
const REPLAN_INTERVAL_TICKS: int = 6

## How much better a fresh route has to be before it is worth abandoning the one already
## committed to. With the cursor directly behind a tent, rounding it either way costs
## exactly the same, and without this the choice of side would flip every time the route
## was solved — the character would wobble on the spot instead of setting off.
const HYSTERESIS: float = 0.85

## Counts solves, so a test can show the throttle actually throttles.
var plans_run: int = 0

var _finder: PathFinder
var _path := PackedVector2Array()
var _index: int = 0
var _goal := Vector2.ZERO
var _ticks_since_plan: int = 0

# Last answer given, so being asked twice in one tick answers the same twice. In
# multiplayer `Fighter._physics_process` and `ArenaClient._send_input` both ask, and an
# aim that differed between them would mean predicting one route while sending another.
var _memo_from := Vector2.INF
var _memo_cursor := Vector2.INF
var _memo_aim := Vector2.INF


func _init(finder: PathFinder) -> void:
	_finder = finder


## Where to steer for a cursor at `cursor`. Returns `cursor` unchanged whenever routing
## has nothing to add.
func waypoint_toward(from: Vector2, cursor: Vector2) -> Vector2:
	if from.is_equal_approx(_memo_from) and cursor.is_equal_approx(_memo_cursor):
		return _memo_aim

	var aim := _aim_for(from, cursor)
	_memo_from = from
	_memo_cursor = cursor
	_memo_aim = aim
	return aim


## The route still to walk, for the debug drawing. Empty when steering straight.
func path() -> PackedVector2Array:
	if _path.is_empty():
		return _path
	return _path.slice(_index)


func _aim_for(from: Vector2, cursor: Vector2) -> Vector2:
	if not is_finite(cursor.x) or not is_finite(cursor.y):
		return cursor

	_ticks_since_plan += 1

	# Checked every tick no matter what the replan throttle says, so the moment the cursor
	# comes into the clear you are steering straight at it again on that same frame.
	if _finder.segment_is_walkable(from, cursor):
		_forget()
		return cursor

	if _should_replan(from, cursor):
		_adopt(_finder.find_path(from, cursor), from, cursor)

	if _path.is_empty():
		# No route at all: a cursor buried in cover with no way round, a sealed pocket, or
		# a start we could not free. Hand the cursor back and let the caller walk straight
		# into whatever is there — being unable to move is worse than walking into a tent.
		return cursor

	var aim := _skip_ahead(from)
	if (aim - from).is_zero_approx():
		return cursor
	return aim


func _should_replan(from: Vector2, cursor: Vector2) -> bool:
	if _path.is_empty():
		return true
	if _goal.distance_to(cursor) > GOAL_DRIFT:
		return true
	if _ticks_since_plan >= REPLAN_INTERVAL_TICKS:
		return true
	# Pushed off the plan. Sliding along a face is the only way this happens, since the
	# geometry itself never moves.
	return not _finder.segment_is_walkable(from, _path[_index])


## Aims at the farthest waypoint still in view rather than the next one.
##
## You never have to touch a corner: the moment the one past it comes into sight you cut
## straight for that instead. That is what a person does, and it is what removes the
## pivoting you would otherwise get every time you arrived at a corner dead on. The index
## only moves forward, so a route can never send you back to a corner already rounded.
func _skip_ahead(from: Vector2) -> Vector2:
	for i in range(_path.size() - 1, _index, -1):
		if _finder.segment_is_walkable(from, _path[i]):
			_index = i
			return _path[i]

	# Nothing beyond the current corner is in sight, so the corner is still the way out.
	# Being close to it is not a reason to look past it — a corner you have not rounded
	# yet is exactly the one that is still in the way.
	return _path[_index]


func _adopt(candidate: PackedVector2Array, from: Vector2, cursor: Vector2) -> void:
	plans_run += 1
	_ticks_since_plan = 0
	_goal = cursor

	if candidate.is_empty():
		_forget()
		return

	# Stay on the route already committed to unless the new one is meaningfully better.
	if not _path.is_empty():
		var kept := _repointed(_path, cursor)
		if (
			_chain_is_walkable(from, kept, _index)
			and _chain_cost(from, kept, _index) * HYSTERESIS < _chain_cost(from, candidate, 0)
		):
			_path = kept
			return

	_path = candidate
	_index = 0


func _forget() -> void:
	_path = PackedVector2Array()
	_index = 0


## The same route, ending at a new destination. The corners it rounds are unchanged; only
## where it finishes moves, which is what the cursor did.
static func _repointed(
	path: PackedVector2Array, destination: Vector2
) -> PackedVector2Array:
	var out := path.duplicate()
	out[out.size() - 1] = destination
	return out


func _chain_is_walkable(from: Vector2, path: PackedVector2Array, index: int) -> bool:
	var previous := from
	for i in range(index, path.size()):
		if not _finder.segment_is_walkable(previous, path[i]):
			return false
		previous = path[i]
	return true


static func _chain_cost(from: Vector2, path: PackedVector2Array, index: int) -> float:
	var cost := 0.0
	var previous := from
	for i in range(index, path.size()):
		cost += previous.distance_to(path[i])
		previous = path[i]
	return cost
