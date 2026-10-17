extends SceneTree
## Headless test runner. Finds every tests/**/test_*.gd, runs its test_* methods and exits
## with code 1 if anything failed. Test methods (and before_each/after_each) may await,
## e.g. `await tree.physics_frame` to let physics run. A test also fails if the engine logs
## a script or engine error while it runs.
##   godot --headless --path . -s res://tests/run_tests.gd [-- filter]

const TEST_ROOT := "res://tests"


## Collects errors the engine logs, so a test that crashes can't pass.
class ErrorCollector:
	extends Logger

	var errors: PackedStringArray = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function])
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var result := errors
		errors = []
		_mutex.unlock()
		return result


var _started := false
var _collector := ErrorCollector.new()


func _process(_delta: float) -> bool:
	# Run on the first frame so autoloads are already in the tree.
	if not _started:
		_started = true
		_run_and_quit()
	return false


func _run_and_quit() -> void:
	OS.add_logger(_collector)
	var code: int = await _run_all(_filter_arg())
	OS.remove_logger(_collector)
	quit(code)


func _filter_arg() -> String:
	var args := OS.get_cmdline_user_args()
	return args[0] if args.size() > 0 else ""


func _run_all(filter: String) -> int:
	var passed := 0
	var failed := 0
	for path in _find_test_files(TEST_ROOT):
		_collector.take()
		var script: GDScript = load(path)
		if not script.can_instantiate():
			failed += 1
			print("  FAIL  ", path.get_file(), " does not compile")
			for error in _collector.take():
				print("          ", error)
			continue
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			var full_name := "%s::%s" % [path.get_file().get_basename(), method_name]
			if filter != "" and not full_name.contains(filter):
				continue
			_collector.take()
			var test: TestCase = script.new()
			test.tree = self
			await test.before_each()
			await test.call(method_name)
			await test.after_each()
			for error in _collector.take():
				test.fail("engine error: " + error)
			if test.failures.is_empty():
				passed += 1
				print("  PASS  ", full_name)
			else:
				failed += 1
				print("  FAIL  ", full_name)
				for failure in test.failures:
					print("          ", failure)
	print("\n%d passed, %d failed" % [passed, failed])
	return 1 if failed > 0 else 0


func _find_test_files(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for sub in dir.get_directories():
		found.append_array(_find_test_files(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	found.sort()
	return found
