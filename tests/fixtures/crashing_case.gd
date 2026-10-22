extends TestCase
## Runner self-check fixtures (deliberately outside tests/unit, so the suite
## never runs them directly). tests/run_tests.gd runs each method and checks
## the runner reports the outcome named in its SELF_CHECKS table.


## Script error before any assert: must surface as a logged error.
func test_crashes_before_assert() -> void:
	var missing: Object = null
	missing.call("nope")
	assert_true(true, "unreachable")


## Script error after an await: the runner must wait for the coroutine.
func test_crashes_after_await() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	var missing: Object = null
	missing.call("nope")


## Error from deferred work the test queued: must still count for this test.
func test_deferred_error() -> void:
	_raise.call_deferred()


## Declared error that never happens: must fail as an unmet expectation.
func test_unmet_expected_error() -> void:
	expect_error("never logged")


func _raise() -> void:
	push_error("deferred boom")
