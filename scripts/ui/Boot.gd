extends Node
## Routes visual launches to the main menu and headless launches to the world.

const WORLD_SCENE := "res://scenes/World.tscn"
const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"

func _ready() -> void:
	call_deferred("_route")

func _route() -> void:
	var next_scene := WORLD_SCENE if RuntimeConfig.is_headless() or RuntimeConfig.is_snapshot() else MENU_SCENE
	get_tree().change_scene_to_file(next_scene)
