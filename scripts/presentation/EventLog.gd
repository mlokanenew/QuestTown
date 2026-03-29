extends Node
## Listens to GameState signals and appends human-readable text to a RichTextLabel.
## Attach to the UI EventLog node in visual mode.

@export var max_lines: int = 20
@onready var label: RichTextLabel = $VBox/EventLog

func _ready() -> void:
	if RuntimeConfig.is_headless():
		return
	set_compact_mode(true)
	GameState.event_logged.connect(_on_event)
	GameState.state_reloaded.connect(_rebuild_from_state)

func set_compact_mode(compact: bool) -> void:
	max_lines = 3 if compact else 20
	_rebuild_from_state()

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
		"hero_started_quest":
			return "[%d] %s takes quest: %s." % [
				event.get("tick", 0),
				event.get("hero_name", "?"),
				event.get("quest_name", "?")
			]
		"hero_departed_for_quest":
			return "[%d] %s leaves town for %s." % [
				event.get("tick", 0),
				event.get("hero_name", "?"),
				event.get("quest_name", "?")
			]
		"hero_completed_quest":
			var outcome := "completed" if event.get("success", false) else "barely survived"
			return "[%d] %s %s %s (+%dg, +%dxp)." % [
				event.get("tick", 0),
				event.get("hero_name", "?"),
				outcome,
				event.get("quest_name", "?"),
				event.get("gold_reward", 0),
				event.get("xp_reward", 0)
			]
		"hero_heading_home":
			return "[%d] %s heads back to town from %s." % [
				event.get("tick", 0),
				event.get("hero_name", "?"),
				event.get("quest_name", "?")
			]
		"hero_returned_from_quest":
			return "[%d] %s returns from %s." % [
				event.get("tick", 0),
				event.get("hero_name", "?"),
				event.get("quest_name", "?")
			]
		"hero_spent_at_tavern":
			return "[%d] %s spends %dg at the tavern for %s." % [
				event.get("tick", 0),
				event.get("hero_name", "?"),
				event.get("amount", 0),
				event.get("service", "service")
			]
		"hero_spent_at_weapons_shop":
			return "[%d] %s spends %dg at the general goods shop." % [
				event.get("tick", 0),
				event.get("hero_name", "?"),
				event.get("amount", 0)
			]
		"hero_spent_at_temple":
			return "[%d] %s spends %dg at the temple for %s." % [
				event.get("tick", 0),
				event.get("hero_name", "?"),
				event.get("amount", 0),
				event.get("service", "service")
			]
		"hero_recovering":
			return "[%d] %s is recovering from injuries." % [
				event.get("tick", 0),
				event.get("hero_name", "?")
			]
		"hero_ready_again":
			return "[%d] %s is ready for work again." % [
				event.get("tick", 0),
				event.get("hero_name", "?")
			]
		"hero_leveled_up":
			return "[%d] %s reached level %d." % [
				event.get("tick", 0),
				event.get("hero_name", "?"),
				event.get("level", 1)
			]
		_:
			return ""
	return ""

func _rebuild_from_state() -> void:
	label.clear()
	for event in GameState.get_recent_events(max_lines):
		var msg := _format(event)
		if msg != "":
			label.append_text(msg + "\n")
