extends Node
## Runs every test_* method in res://tests/unit/test_*.gd. Exit code 0 = pass.
## Run: tools/test.sh   (or: godot --headless --path . res://tests/run_tests.tscn)

const UNIT_DIR: String = "res://tests/unit"


func _ready() -> void:
	var total: int = 0
	var failed: int = 0
	var dir: DirAccess = DirAccess.open(UNIT_DIR)
	var files: PackedStringArray = dir.get_files() if dir != null else PackedStringArray()
	for file: String in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var script: GDScript = load(UNIT_DIR.path_join(file)) as GDScript
		if script == null:
			printerr("FAIL %s: could not load" % file)
			failed += 1
			continue
		for method: Dictionary in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			var instance: TestCase = script.new() as TestCase
			instance.call(name)
			if instance.failures.is_empty():
				print("  ok   %s::%s" % [file.get_basename(), name])
			else:
				failed += 1
				for f: String in instance.failures:
					printerr("  FAIL %s::%s — %s" % [file.get_basename(), name, f])
	print("TEST_RESULT ok=%s passed=%d failed=%d" % [str(failed == 0).to_lower(), total - failed, failed])
	get_tree().quit(0 if failed == 0 and total > 0 else 1)
