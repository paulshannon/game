extends Node
## Runs every test_* method in res://tests/unit/test_*.gd. Exit code 0 = pass.
## Run: tools/test.sh   (or: godot --headless --path . res://tests/run_tests.tscn)
##
## A test fails if an assert fails, an expect_error() goes unmet, or any other
## engine/script error is logged while it runs, including after an `await` and
## in deferred work it queued (see ErrorCapture). Errors logged outside any
## test (loading a file, the runner itself) fail the run too: nothing captured
## is ever discarded unreported.
##
## Before the suite, a self-check runs tests/fixtures/ and confirms the runner
## still detects each kind of failure. It prints a few expected SCRIPT ERRORs.

const UNIT_DIR: String = "res://tests/unit"
const FIXTURES: String = "res://tests/fixtures"
## [fixture file, method, expected outcome, text the outcome must contain]
## "error"   = only logged errors, no assert failures
## "failure" = only assert/expectation failures, no logged errors
const SELF_CHECKS: Array[Array] = [
	["crashing_case.gd", "test_crashes_before_assert", "error", "null value"],
	["crashing_case.gd", "test_crashes_after_await", "error", "null value"],
	["crashing_case.gd", "test_deferred_error", "error", "deferred boom"],
	["crashing_case.gd", "test_unmet_expected_error", "failure", "never logged"],
	["not_a_test_case.gd", "test_looks_like_a_test", "failure", "does not extend TestCase"],
]


class Outcome:
	var failures: PackedStringArray = PackedStringArray()  # asserts, unmet expectations
	var errors: PackedStringArray = PackedStringArray()    # unexpected logged errors

	func problems() -> PackedStringArray:
		var out: PackedStringArray = failures
		for e: String in errors:
			out.append("error: " + e)
		return out


var _capture: ErrorCapture = ErrorCapture.new()
var _total: int = 0
var _failed: int = 0


func _ready() -> void:
	OS.add_logger(_capture)
	var self_check_ok: bool = await _self_check()
	var dir: DirAccess = DirAccess.open(UNIT_DIR)
	var files: PackedStringArray = dir.get_files() if dir != null else PackedStringArray()
	for file: String in files:
		if file.begins_with("test_") and file.ends_with(".gd"):
			await _run_file(file)
	_flush_stray("after the last test")
	OS.remove_logger(_capture)
	var ok: bool = self_check_ok and _failed == 0 and _total > 0
	print("TEST_RESULT ok=%s passed=%d failed=%d" % [str(ok).to_lower(), _total - _failed, _failed])
	get_tree().quit(0 if ok else 1)


func _run_file(file: String) -> void:
	var label: String = file.get_basename()
	_flush_stray("before " + label)
	var script: GDScript = load(UNIT_DIR.path_join(file)) as GDScript
	var load_errors: PackedStringArray = _capture.take()
	if script == null or not load_errors.is_empty():
		var problems: PackedStringArray = PackedStringArray(["could not load"]) if script == null else PackedStringArray()
		for e: String in load_errors:
			problems.append("error while loading: " + e)
		_record(label + "::(load)", problems)
		if script == null:
			return
	for method: Dictionary in script.get_script_method_list():
		var name: String = method["name"]
		if name.begins_with("test_"):
			_record("%s::%s" % [label, name], (await _run(script, name)).problems())


## Runs one test method. Waits for it if it awaits, then one more frame so
## deferred work it queued runs while its errors still count against it.
## Expects the capture to be empty on entry (callers flush stray errors first).
func _run(script: GDScript, name: String) -> Outcome:
	var outcome: Outcome = Outcome.new()
	var obj: Object = script.new()
	var instance: TestCase = obj as TestCase
	if instance == null:
		if obj != null and not obj is RefCounted:
			obj.free()
		outcome.failures.append("does not extend TestCase")
		return outcome
	var result: Variant = instance.call(name)
	if result is Object and (result as Object).has_signal("completed"):
		await Signal(result as Object, "completed")  # the test used await
	await get_tree().process_frame
	outcome.failures = instance.failures
	var errors: PackedStringArray = _capture.take()
	for fragment: String in instance.expected_errors:
		var hit: int = -1
		for i: int in errors.size():
			if errors[i].contains(fragment):
				hit = i
				break
		if hit == -1:
			outcome.failures.append("expected an error containing '%s'; none was logged" % fragment)
		else:
			errors.remove_at(hit)
	outcome.errors = errors
	return outcome


func _record(label: String, problems: PackedStringArray) -> void:
	_total += 1
	if problems.is_empty():
		print("  ok   " + label)
		return
	_failed += 1
	for p: String in problems:
		printerr("  FAIL %s — %s" % [label, p])


## Errors logged outside any test still fail the run.
func _flush_stray(where: String) -> void:
	var stray: PackedStringArray = _capture.take()
	if not stray.is_empty():
		var problems: PackedStringArray = PackedStringArray()
		for e: String in stray:
			problems.append("error: " + e)
		_record("(outside any test, %s)" % where, problems)


## Proves each failure mode is still detected. Not counted in passed/failed;
## a broken self-check fails the run on its own.
func _self_check() -> bool:
	print("  (runner self-check: the SCRIPT ERROR / ERROR lines below are expected)")
	var ok: bool = true
	for check: Array in SELF_CHECKS:
		var file: String = check[0]
		var method: String = check[1]
		var want: String = check[2]
		var text: String = check[3]
		_capture.take()
		var script: GDScript = load(FIXTURES.path_join(file)) as GDScript
		var why: String = "fixture did not load"
		if script != null:
			var outcome: Outcome = await _run(script, method)
			why = _self_check_mismatch(outcome, want, text)
		if not why.is_empty():
			ok = false
			printerr("  FAIL runner self-check %s::%s — %s" % [file.get_basename(), method, why])
	_capture.take()
	print("  self-check %s" % ("ok" if ok else "FAILED"))
	return ok


func _self_check_mismatch(outcome: Outcome, want: String, text: String) -> String:
	var hits: PackedStringArray = outcome.errors if want == "error" else outcome.failures
	var other: PackedStringArray = outcome.failures if want == "error" else outcome.errors
	if not other.is_empty():
		return "expected only %s entries, also got %s" % [want, str(other)]
	for h: String in hits:
		if h.contains(text):
			return ""
	return "expected an %s entry containing '%s', got %s" % [want, text, str(hits)]
