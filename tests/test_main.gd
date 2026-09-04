extends Node

## Headless test runner. Discovers `tests/test_*.gd` (excluding this file and
## test_case.gd), runs every `test_*` method, and exits non-zero on failure.
##
##   godot --headless res://tests/test_main.tscn -- --test

const TESTS_DIR := "res://tests"

var _total := 0
var _failed := 0


func _ready() -> void:
	await _run_all()


func _run_all() -> void:
	print("")
	for script_path in _discover_test_scripts():
		await _run_script(script_path)

	print("")
	if _failed == 0:
		print("PASS — %d test%s" % [_total, "" if _total == 1 else "s"])
		get_tree().quit(0)
	else:
		print("FAIL — %d of %d test%s failed" % [_failed, _total, "" if _total == 1 else "s"])
		get_tree().quit(1)


func _discover_test_scripts() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		push_error("Cannot open %s" % TESTS_DIR)
		return paths
	for file_name in dir.get_files():
		if file_name.begins_with("test_") and file_name.ends_with(".gd") \
				and file_name != "test_main.gd" and file_name != "test_case.gd":
			paths.append("%s/%s" % [TESTS_DIR, file_name])
	paths.sort()
	return paths


func _run_script(script_path: String) -> void:
	print("── %s" % script_path.get_file())
	var script: GDScript = load(script_path)
	if script == null or not script.can_instantiate():
		# A test file that won't even parse must fail the run, not vanish from it.
		_total += 1
		_failed += 1
		print("   FAIL <could not load script — see parse errors above>")
		return

	var method_names := _test_method_names(script)
	if method_names.is_empty():
		_total += 1
		_failed += 1
		print("   FAIL <no test_* methods found>")
		return

	for method_name in method_names:
		await _run_one(script, method_name)


func _test_method_names(script: GDScript) -> Array[String]:
	var names: Array[String] = []
	# Instantiate once purely to enumerate methods; the real instance is per-test
	# so no state leaks between them.
	var probe: TestCase = script.new()
	for method in probe.get_method_list():
		if method.name.begins_with("test_"):
			names.append(method.name)
	probe.free()
	names.sort()
	return names


func _run_one(script: GDScript, method_name: String) -> void:
	_total += 1
	var test_case: TestCase = script.new()
	add_child(test_case)

	await test_case.before_each()
	await test_case.call(method_name)
	await test_case.after_each()

	if test_case.failures.is_empty():
		print("   ok   %s (%d assertion%s)" % [
			method_name, test_case.assertion_count,
			"" if test_case.assertion_count == 1 else "s",
		])
	else:
		_failed += 1
		print("   FAIL %s" % method_name)
		for failure in test_case.failures:
			print("        %s" % failure)

	test_case.queue_free()
