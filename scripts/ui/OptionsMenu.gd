extends PanelContainer
class_name OptionsMenu

signal closed

@onready var _window_button: Button = $Margin/VBox/WindowButton
@onready var _ui_scale_button: Button = $Margin/VBox/UIScaleButton

func _ready() -> void:
	_refresh()

func _on_window_button_pressed() -> void:
	SettingsManager.toggle_window_mode()
	_refresh()

func _on_ui_scale_button_pressed() -> void:
	SettingsManager.cycle_ui_scale()
	_refresh()

func _on_back_button_pressed() -> void:
	closed.emit()

func _refresh() -> void:
	_window_button.text = "Window Mode: %s" % SettingsManager.get_window_mode_label()
	_ui_scale_button.text = "UI Scale: %s" % SettingsManager.get_ui_scale_label()
