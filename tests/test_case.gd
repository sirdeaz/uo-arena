extends Node
class_name TestCase

## Base class for UO Arena tests. Subclass it, add methods named `test_*`, and the
## runner will discover and execute them. Test methods may `await` (e.g. on
## `get_tree().physics_frame`) — the runner awaits each one.

var failures: Array[String] = []
var assertion_count: int = 0


## Runs before each test method. Override to build fixtures.
func before_each() -> void:
	pass


## Runs after each test method. Override to tear fixtures down.
func after_each() -> void:
	pass


func assert_true(condition: bool, message: String) -> void:
	assertion_count += 1
	if not condition:
		failures.append("%s — expected true, got false" % message)


func assert_false(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		failures.append("%s — expected false, got true" % message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	assertion_count += 1
	if actual != expected:
		failures.append("%s — expected %s, got %s" % [message, expected, actual])


func assert_almost_eq(actual: float, expected: float, message: String, tolerance: float = 0.001) -> void:
	assertion_count += 1
	if absf(actual - expected) > tolerance:
		failures.append("%s — expected %s (±%s), got %s" % [message, expected, tolerance, actual])
