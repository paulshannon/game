extends RefCounted
## Runner self-check fixture: forgets `extends TestCase`. The runner must
## fail it, not report its test methods as passing.


func test_looks_like_a_test() -> void:
	pass
