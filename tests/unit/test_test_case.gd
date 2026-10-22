extends TestCase
## The runner's error handling as seen by a normal test. (Crash detection is
## proven by the runner self-check in tests/run_tests.gd.)


func test_expected_error_is_consumed() -> void:
	expect_error("intentional")
	push_error("intentional error from test_expected_error_is_consumed")
	assert_eq(expected_errors.size(), 1)
