extends CanvasLayer
class_name ScreenFade
## Simple transition overlay inspired by the UI-System screen-fade helper.

@onready var _rect: ColorRect = $ColorRect

func _ready() -> void:
	layer = 100
	_rect.color.a = 0.0
	hide()

func fade_to(callback: Callable) -> void:
	show()
	var tween := create_tween()
	tween.tween_property(_rect, "color:a", 1.0, 0.2)
	tween.tween_callback(callback)

func fade_in() -> void:
	show()
	_rect.color.a = 1.0
	var tween := create_tween()
	tween.tween_property(_rect, "color:a", 0.0, 0.2)
	tween.tween_callback(hide)
