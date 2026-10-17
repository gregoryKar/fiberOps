class_name TestCase
extends RefCounted
## Base class for tests. Methods starting with "test_" are run by tests/run_tests.gd.
## Assertions record failures instead of stopping, so one test reports every broken check.

var tree: SceneTree
var failures: PackedStringArray = []


## Called before each test method.
func before_each() -> void:
	pass


## Called after each test method.
func after_each() -> void:
	pass


func fail(message: String) -> void:
	failures.append(message)


func assert_true(value: bool, message := "expected true") -> void:
	if not value:
		fail(message)


func assert_false(value: bool, message := "expected false") -> void:
	if value:
		fail(message)


func assert_eq(actual: Variant, expected: Variant, message := "") -> void:
	if actual != expected:
		fail("%s expected <%s> got <%s>" % [message, expected, actual])


func assert_almost(actual: float, expected: float, tolerance := 1e-5, message := "") -> void:
	if absf(actual - expected) > tolerance:
		fail("%s expected %f ±%f got %f" % [message, expected, tolerance, actual])


func assert_not_null(value: Variant, message := "expected non-null") -> void:
	if value == null:
		fail(message)
