class_name TestCase
extends RefCounted
## Minimal assertion base for tests/unit/test_*.gd. Every method whose name
## starts with "test_" is run by tests/run_tests.gd.
##
## Deliberately tiny so the repo has no third-party test dependency. If tests
## outgrow it, drop in GUT or gdUnit4 under addons/ and port these files.

var failures: PackedStringArray = PackedStringArray()


func assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		failures.append("expected true. " + msg)


func assert_false(cond: bool, msg: String = "") -> void:
	if cond:
		failures.append("expected false. " + msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual != expected:
		failures.append("expected %s, got %s. %s" % [str(expected), str(actual), msg])


func assert_near(actual: float, expected: float, tolerance: float = 0.0001, msg: String = "") -> void:
	if absf(actual - expected) > tolerance:
		failures.append("expected %f ± %f, got %f. %s" % [expected, tolerance, actual, msg])
