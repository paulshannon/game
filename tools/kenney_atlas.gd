extends SceneTree
## Converts a Kenney spritesheet XML (<TextureAtlas>/<SubTexture>) into one
## AtlasTexture .tres per sprite, so code and scenes can reference sprites by
## name instead of pixel rectangles.
##
## Usage (after the sheet PNG has been imported — run tools/check.sh first):
##   godot --headless --path . -s res://tools/kenney_atlas.gd -- \
##       res://assets/kenney/<pack>/Spritesheet/<sheet>.xml
## or simply: tools/kenney_atlas.sh <that xml path>
##
## Output: <sheet>_atlas/<sprite_name>.tres next to the XML. Re-running
## overwrites those files, which is safe: they are derived data, so the XML
## stays the source of truth and Kenney files are never edited.


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: -s res://tools/kenney_atlas.gd -- res://path/to/sheet.xml")
		quit(2)
		return
	var total_failed: int = 0
	for xml_path: String in args:
		total_failed += _convert(xml_path)
	quit(0 if total_failed == 0 else 1)


func _convert(xml_path: String) -> int:
	var parser := XMLParser.new()
	if parser.open(xml_path) != OK:
		printerr("ATLAS_FAILED cannot open %s" % xml_path)
		return 1

	var base_dir: String = xml_path.get_base_dir()
	var out_dir: String = base_dir.path_join(xml_path.get_file().get_basename() + "_atlas")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	var sheet: Texture2D = null
	var written: int = 0
	var failed: int = 0
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		match parser.get_node_name():
			"TextureAtlas":
				var image_path: String = base_dir.path_join(parser.get_named_attribute_value_safe("imagePath"))
				sheet = load(image_path) as Texture2D
				if sheet == null:
					printerr("ATLAS_FAILED %s not imported/loadable (run tools/check.sh first)" % image_path)
					return 1
			"SubTexture":
				if sheet == null:
					printerr("ATLAS_FAILED SubTexture before TextureAtlas in %s" % xml_path)
					return 1
				var atlas := AtlasTexture.new()
				atlas.atlas = sheet
				atlas.region = Rect2(
						parser.get_named_attribute_value_safe("x").to_float(),
						parser.get_named_attribute_value_safe("y").to_float(),
						parser.get_named_attribute_value_safe("width").to_float(),
						parser.get_named_attribute_value_safe("height").to_float())
				var sprite_name: String = parser.get_named_attribute_value_safe("name").get_basename()
				var out_path: String = out_dir.path_join(sprite_name.validate_filename() + ".tres")
				if ResourceSaver.save(atlas, out_path) == OK:
					written += 1
				else:
					printerr("ATLAS_FAILED could not write %s" % out_path)
					failed += 1
	print("ATLAS_RESULT xml=%s written=%d failed=%d out=%s" % [xml_path, written, failed, out_dir])
	return failed
