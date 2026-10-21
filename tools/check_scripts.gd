extends Node
## Compiles every .gd file in the project and exits non-zero on failure.
##
## Why a scene and not `godot --check-only --script`: --check-only does not
## register autoloads, so any script that uses `Net` reports a bogus
## "Identifier not found". Running this as a scene loads autoloads exactly
## like the real game does.
##
## Run: tools/check.sh   (or: godot --headless --path . res://tools/check_scripts.tscn)

const SKIP_DIRS: PackedStringArray = ["res://.godot", "res://addons", "res://build"]


func _ready() -> void:
	var files: PackedStringArray = PackedStringArray()
	_collect("res://", files)
	var failed: PackedStringArray = PackedStringArray()
	for path: String in files:
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate():
			failed.append(path)
	if failed.is_empty():
		print("CHECK_RESULT ok=true scripts=%d" % files.size())
		get_tree().quit(0)
	else:
		for path: String in failed:
			printerr("CHECK_FAILED %s" % path)
		print("CHECK_RESULT ok=false failed=%d scripts=%d" % [failed.size(), files.size()])
		get_tree().quit(1)


func _collect(dir_path: String, out: PackedStringArray) -> void:
	for skip: String in SKIP_DIRS:
		if dir_path.begins_with(skip):
			return
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		if file.get_extension() == "gd":
			out.append(dir_path.path_join(file))
