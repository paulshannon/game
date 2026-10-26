class_name GameMenu
extends CanvasLayer
## Base for a game's start menu. A game opts in by returning one from
## GameBase.make_menu(); main.gd then shows it instead of the plain join
## button, at startup and again after the connection is lost. Bots never see
## it (smoke tests join straight away).
##
## Subclasses build their UI in _ready() and call request_play() from their
## Play button.

signal play_requested()


func _init() -> void:
	layer = 10  # above the game, the HUD and the touch controls


## Shows the menu. `status` explains why it's back (empty at startup);
## `play_text` is the Play button's label ("Play", "Rejoin", "Try again").
func show_menu(status: String = "", play_text: String = "Play") -> void:
	_apply(status, play_text)
	visible = true


func hide_menu() -> void:
	visible = false


func request_play() -> void:
	hide_menu()
	play_requested.emit()


## What the player picked to join with (GameBase.join_choice), e.g. a ship.
func choice() -> Dictionary:
	return {}


## Subclass hook: update the status line and Play label.
func _apply(_status: String, _play_text: String) -> void:
	pass
