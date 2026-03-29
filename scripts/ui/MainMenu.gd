extends Control

const WORLD_SCENE := "res://scenes/World.tscn"
const OPTIONS_SCENE := preload("res://scenes/ui/OptionsMenu.tscn")

@onready var _menu_host: MenuHost = $MenuHost
@onready var _fade: ScreenFade = $ScreenFade
@onready var _load_button: Button = $Center/VBox/Panel/Margin/Inner/LoadButton
@onready var _status_label: Label = $Center/VBox/StatusLabel

func _ready() -> void:
	_refresh_status()
	_fade.fade_in()

func _on_new_button_pressed() -> void:
	RuntimeConfig.request_load_world = false
	_fade.fade_to(func() -> void:
		get_tree().change_scene_to_file(WORLD_SCENE)
	)

func _on_load_button_pressed() -> void:
	RuntimeConfig.request_load_world = true
	_fade.fade_to(func() -> void:
		get_tree().change_scene_to_file(WORLD_SCENE)
	)

func _on_options_button_pressed() -> void:
	var options: Control = _menu_host.show_menu(OPTIONS_SCENE)
	if options != null:
		options.closed.connect(func() -> void:
			_menu_host.close_menu()
			_refresh_status()
		)

func _on_quit_button_pressed() -> void:
	get_tree().quit()

func _refresh_status() -> void:
	var has_save := FileAccess.file_exists("user://questtown_save.json")
	_load_button.disabled = not has_save
	_status_label.text = "Load available." if has_save else "No save file detected yet."
