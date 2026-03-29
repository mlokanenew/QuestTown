extends Control
class_name MenuHost
## Lightweight menu stack host inspired by the UI-System-Godot popup/menu manager idea.

var _active_menu: Control = null

func show_menu(packed: PackedScene) -> Control:
	close_menu()
	if packed == null:
		return null
	_active_menu = packed.instantiate()
	add_child(_active_menu)
	return _active_menu

func close_menu() -> void:
	if _active_menu == null:
		return
	_active_menu.queue_free()
	_active_menu = null

func has_menu() -> bool:
	return _active_menu != null
