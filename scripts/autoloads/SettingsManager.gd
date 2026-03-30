extends Node
## Small persistent settings store inspired by the project-template setup.

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "display"
const UI_SCALE_VERSION := 3
const DEFAULT_WINDOW_SIZE := Vector2i(1920, 1080)

var window_mode: String = "windowed"
var ui_scale: float = 1.0

func _ready() -> void:
	load_settings()
	apply_settings()

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	window_mode = str(config.get_value(SECTION, "window_mode", window_mode))
	ui_scale = float(config.get_value(SECTION, "ui_scale", ui_scale))
	var stored_scale_version: int = int(config.get_value(SECTION, "ui_scale_version", 1))
	if stored_scale_version < UI_SCALE_VERSION:
		ui_scale = 1.0
		save_settings()

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "window_mode", window_mode)
	config.set_value(SECTION, "ui_scale", ui_scale)
	config.set_value(SECTION, "ui_scale_version", UI_SCALE_VERSION)
	config.save(CONFIG_PATH)

func apply_settings() -> void:
	if window_mode == "fullscreen":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var current_size := DisplayServer.window_get_size()
		if current_size.x < DEFAULT_WINDOW_SIZE.x or current_size.y < DEFAULT_WINDOW_SIZE.y:
			DisplayServer.window_set_size(DEFAULT_WINDOW_SIZE)
	get_tree().root.content_scale_factor = clamp(ui_scale, 0.8, 1.5)

func toggle_window_mode() -> void:
	window_mode = "windowed" if window_mode == "fullscreen" else "fullscreen"
	apply_settings()
	save_settings()

func cycle_ui_scale() -> void:
	var scales := [1.0, 1.25, 1.5]
	var current_index := scales.find(round(ui_scale * 100.0) / 100.0)
	if current_index < 0:
		current_index = 0
	ui_scale = scales[(current_index + 1) % scales.size()]
	apply_settings()
	save_settings()

func get_window_mode_label() -> String:
	return "Fullscreen" if window_mode == "fullscreen" else "Windowed"

func get_ui_scale_label() -> String:
	return "%d%%" % int(ui_scale * 100.0)
