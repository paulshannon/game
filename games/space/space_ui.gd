class_name SpaceUi
extends RefCounted
## The space game's UI theme, built from Kenney's UI Pack: Sci-fi
## (assets/kenney/ui-pack-sci-fi). Built in code so the 9-slice margins sit
## next to the sprite they describe; the pack itself is never edited.
##
## Sprites are the pack's "Default" (1x) size. 9-slice margins keep corners,
## screws and the header bar unscaled at any panel or button size.

const PACK: String = "res://assets/kenney/ui-pack-sci-fi/"
const FONT_PATH: String = PACK + "Font/Kenney Future.ttf"

## Header strip of the panel sprite, in pixels (rows 0-31 are the blue bar).
const HEADER_HEIGHT: float = 32.0

const INK := Color(0.29, 0.31, 0.38)          # dark grey text on light panels
const ACCENT := Color(0.11, 0.63, 0.86)       # the pack's blue
const STAR_WHITE := Color(0.93, 0.95, 1.0)


static func font() -> Font:
	return load(FONT_PATH) as Font


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 18

	# Buttons: the depth sprite at rest; the flat one when pressed, with the
	# label nudged down so the button looks like it sinks.
	var normal: StyleBoxTexture = _box("PNG/Extra/Default/button_rectangle_depth.png",
			Vector4(16, 14, 16, 18), Vector4(28, 10, 28, 14))
	var hover: StyleBoxTexture = normal.duplicate()
	hover.modulate_color = Color(0.86, 0.94, 1.0)
	var pressed: StyleBoxTexture = _box("PNG/Extra/Default/button_rectangle.png",
			Vector4(16, 14, 16, 14), Vector4(28, 14, 28, 10))
	var disabled: StyleBoxTexture = normal.duplicate()
	disabled.modulate_color = Color(1, 1, 1, 0.5)
	var focus := StyleBoxFlat.new()   # keyboard/gamepad focus ring
	focus.draw_center = false
	focus.set_border_width_all(3)
	focus.border_color = ACCENT
	focus.set_corner_radius_all(10)
	focus.set_expand_margin_all(4)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", focus)
	t.set_font_size("font_size", "Button", 24)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.5))

	# Panel with the blue header strip ("Ship Status" in Kenney's sample).
	# Content starts at the top edge so the first child (the header label)
	# can sit exactly on the strip.
	t.set_stylebox("panel", "PanelContainer", _box(
			"PNG/Blue/Default/button_square_header_large_rectangle.png",
			Vector4(16, HEADER_HEIGHT + 2, 16, 16), Vector4(28, 0, 28, 28)))

	t.set_color("font_color", "Label", INK)
	return t


## left/top/right/bottom: x/y/z/w.
static func _box(path: String, slice: Vector4, content: Vector4) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = load(PACK + path) as Texture2D
	s.texture_margin_left = slice.x
	s.texture_margin_top = slice.y
	s.texture_margin_right = slice.z
	s.texture_margin_bottom = slice.w
	s.content_margin_left = content.x
	s.content_margin_top = content.y
	s.content_margin_right = content.z
	s.content_margin_bottom = content.w
	return s
