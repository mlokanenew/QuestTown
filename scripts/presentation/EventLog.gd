extends Node
## Listens to GameState signals and appends human-readable text to a RichTextLabel.
## Attach to the UI EventLog node in visual mode.

@export var max_lines: int = 20
@onready var label: RichTextLabel = $EventLog

func _ready() -> void:
	if RuntimeConfig.is_headless():
		return
	GameState.event_logged.connect(_on_event)

func _on_event(event: Dictionary) -> void:
	var msg := _format(event)
	if msg == "":
		return
	label.append_text(msg + "\n")
	# Trim old lines
	var lines := label.get_parsed_text().split("\n")
	if lines.size() > max_lines:
		label.clear()
		for line in lines.slice(lines.size() - max_lines):
			label.append_text(line + "\n")

func _format(event: Dictionary) -> String:
	match event.get("type", ""):
		"hero_arrived":
			return "[%d] %s (%s) arrived in town." % [
				event.get("tick", 0),
				event.get("hero_name", "?"),
				event.get("career", "?")
			]
		"hero_arrived_at_tavern":
			var id: int = event.get("hero_id", 0)
			if GameState.heroes.has(id):
				return "[%d] %s enters the tavern." % [event.get("tick", 0), GameState.heroes[id]["name"]]
		_:
			return ""
	return ""
