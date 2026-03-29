extends CanvasLayer

const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"
const OPTIONS_SCENE := preload("res://scenes/ui/OptionsMenu.tscn")

@onready var _menu_host: MenuHost = $MenuHost
@onready var _fade: ScreenFade = $ScreenFade

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true

func _exit_pause() -> void:
	get_tree().paused = false
	queue_free()

func _on_resume_button_pressed() -> void:
	_exit_pause()

func _on_save_button_pressed() -> void:
	var world := get_tree().current_scene
	if world and world.has_method("_save_world"):
		world._save_world()

func _on_load_button_pressed() -> void:
	var world := get_tree().current_scene
	if world and world.has_method("_load_world"):
		world._load_world()

func _on_options_button_pressed() -> void:
	var options: Control = _menu_host.show_menu(OPTIONS_SCENE)
	if options != null:
		options.closed.connect(func() -> void:
			_menu_host.close_menu()
		)

func _on_main_menu_button_pressed() -> void:
	get_tree().paused = false
	_fade.fade_to(func() -> void:
		get_tree().change_scene_to_file(MENU_SCENE)
	)
