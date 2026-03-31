extends Node3D
## Root scene script. Wires SimulationRoot, CommandServer, and ScenarioRunner together.

const OPTIONS_SCENE := preload("res://scenes/ui/OptionsMenu.tscn")
const FONT_HEADING_PATH := "res://assets/fonts/Cinzel.ttf"
const FONT_BODY_PATH := "res://assets/fonts/NotoSans.ttf"
const FRAME_ORNATE_PATH := "res://assets/ui/theme/frame_ornate.png"
const FRAME_SIMPLE_PATH := "res://assets/ui/theme/frame_simple.png"
const THEME_DIVIDER_PATH := "res://assets/ui/theme/divider.png"
const BUTTON_BLUE_PATH := "res://assets/ui/theme/button_blue.png"
const BUTTON_BLUE_OUTLINE_PATH := "res://assets/ui/theme/button_blue_outline.png"
const BUTTON_BLUE_FLAT_PATH := "res://assets/ui/theme/button_blue_flat.png"
const ICON_AWARD_PATH := "res://assets/ui/icons/award.png"
const ICON_BOOK_PATH := "res://assets/ui/icons/book_open.png"
const ICON_CHARACTER_PATH := "res://assets/ui/icons/character.png"
const ICON_CAMPFIRE_PATH := "res://assets/ui/icons/campfire.png"
const ICON_SHIELD_PATH := "res://assets/ui/icons/shield.png"
const ICON_SWORD_PATH := "res://assets/ui/icons/sword.png"
const ICON_SKULL_PATH := "res://assets/ui/icons/skull.png"
const UI_SOUND_CLICK_PATH := "res://assets/audio/ui/click.ogg"
const UI_SOUND_OPEN_PATH := "res://assets/audio/ui/open.ogg"
const UI_SOUND_CLOSE_PATH := "res://assets/audio/ui/close.ogg"
const UI_SOUND_CONFIRM_PATH := "res://assets/audio/ui/confirm.ogg"

const UI_BACKGROUND := Color(0.06, 0.08, 0.10, 0.0)
const UI_SURFACE_1 := Color(0.07, 0.10, 0.15, 0.88)
const UI_SURFACE_2 := Color(0.11, 0.15, 0.21, 0.95)
const UI_SURFACE_PAPER := Color(0.90, 0.86, 0.77, 0.96)
const UI_SURFACE_PAPER_SOFT := Color(0.83, 0.78, 0.68, 0.93)
const UI_BORDER_SUBTLE := Color(0.58, 0.48, 0.30, 0.44)
const UI_TEXT_PRIMARY := Color(0.96, 0.94, 0.89, 1.0)
const UI_TEXT_MUTED := Color(0.72, 0.76, 0.81, 1.0)
const UI_TEXT_DARK := Color(0.16, 0.18, 0.22, 1.0)
const UI_ACCENT := Color(0.77, 0.63, 0.28, 1.0)
const UI_ACCENT_SOFT := Color(0.77, 0.63, 0.28, 0.18)
const UI_WARNING := Color(0.86, 0.53, 0.28, 1.0)
const UI_SUCCESS := Color(0.49, 0.70, 0.58, 1.0)

const TYPE_SCREEN_TITLE := 28
const TYPE_PANEL_TITLE := 22
const TYPE_QUEST_TITLE := 28
const TYPE_SECTION_LABEL := 12
const TYPE_BODY := 15
const TYPE_META := 12

const SPACE_1 := 6
const SPACE_2 := 10
const SPACE_3 := 14
const SPACE_4 := 18
const RADIUS_PANEL := 18
const RADIUS_BUTTON := 12

@onready var sim: Node = $SimulationRoot
@onready var cmd_server: Node = $CommandServer
@onready var build_manager: Node = $BuildManager
@onready var camera_controller: Camera3D = $Camera3D
@onready var menu_host: Control = $UILayer/MenuHost

var _selected_hero_id: int = -1
var _selected_building_id: int = -1
var _quest_filter_boxes: Dictionary = {}
var _pause_menu: CanvasLayer = null
var _left_panel_collapsed: bool = false
var _right_panel_collapsed: bool = true
var _event_feed_expanded: bool = false
var _selected_entity_kind: String = ""
var _details_expanded: bool = false
var _selected_quest_id: String = ""
var _ui_sfx: Dictionary = {}
var _ui_textures: Dictionary = {}
var _ui_fonts: Dictionary = {}
var _ui_tweens: Dictionary = {}
var _roster_expanded: bool = false

const BUILDING_ICONS := {
	"tavern": "res://assets/ui/tavern_icon.svg",
	"weapons_shop": "res://assets/ui/weapons_shop_icon.svg",
	"temple": "res://assets/ui/temple_icon.svg",
}

const HERO_PORTRAITS := {
	"martial": "res://assets/characters/knight_texture.png",
	"rogue": "res://assets/characters/rogue_texture.png",
	"scholar": "res://assets/characters/mage_texture.png",
	"devout": "res://assets/characters/mage_texture.png",
	"commoner": "res://assets/characters/barbarian_texture.png",
}

const QUEST_TYPE_ICONS := {
	"combat": ICON_SWORD_PATH,
	"forage": ICON_AWARD_PATH,
	"spiritual": ICON_CAMPFIRE_PATH,
}

func _make_style(bg: Color, border: Color, radius: int = RADIUS_PANEL, border_width: int = 1, padding: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	style.content_margin_left = padding
	style.content_margin_top = padding
	style.content_margin_right = padding
	style.content_margin_bottom = padding
	return style

func _resource_path_to_absolute(path: String) -> String:
	if path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path

func _load_runtime_texture(path: String) -> Texture2D:
	if _ui_textures.has(path):
		return _ui_textures[path]
	var absolute := _resource_path_to_absolute(path)
	var image := Image.load_from_file(absolute)
	if image == null or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	_ui_textures[path] = texture
	return texture

func _load_runtime_font(path: String) -> FontFile:
	if _ui_fonts.has(path):
		return _ui_fonts[path]
	var font := FontFile.new()
	if font.load_dynamic_font(_resource_path_to_absolute(path)) != OK:
		return null
	_ui_fonts[path] = font
	return font

func _load_runtime_sound(path: String) -> AudioStreamOggVorbis:
	return AudioStreamOggVorbis.load_from_file(_resource_path_to_absolute(path))

func _make_texture_style(texture: Texture2D, texture_margin: int, padding: int, draw_center: bool = true, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = texture_margin
	style.texture_margin_top = texture_margin
	style.texture_margin_right = texture_margin
	style.texture_margin_bottom = texture_margin
	style.content_margin_left = padding
	style.content_margin_top = padding
	style.content_margin_right = padding
	style.content_margin_bottom = padding
	style.draw_center = draw_center
	style.modulate_color = tint
	return style

func _ensure_ornament_frame(control: Control, texture: Texture2D, patch_margin: int = 16, expand: int = 8, tint: Color = Color(1, 1, 1, 0.78)) -> void:
	if control == null or texture == null:
		return
	var frame := control.get_node_or_null("ThemeFrame") as NinePatchRect
	if frame == null:
		frame = NinePatchRect.new()
		frame.name = "ThemeFrame"
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.show_behind_parent = true
		frame.anchors_preset = Control.PRESET_FULL_RECT
		control.add_child(frame)
		control.move_child(frame, 0)
	frame.texture = texture
	frame.draw_center = false
	frame.patch_margin_left = patch_margin
	frame.patch_margin_top = patch_margin
	frame.patch_margin_right = patch_margin
	frame.patch_margin_bottom = patch_margin
	frame.offset_left = -expand
	frame.offset_top = -expand
	frame.offset_right = expand
	frame.offset_bottom = expand
	frame.modulate = tint

func _ensure_divider_texture(parent: Control, name: String = "ThemeDivider") -> void:
	if parent == null:
		return
	var divider := parent.get_node_or_null(name) as TextureRect
	if divider == null:
		divider = TextureRect.new()
		divider.name = name
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		divider.stretch_mode = TextureRect.STRETCH_TILE
		divider.custom_minimum_size = Vector2(0, 8)
		parent.add_child(divider)
		parent.move_child(divider, 0)
	divider.texture = _load_runtime_texture(THEME_DIVIDER_PATH)
	divider.modulate = Color(1, 1, 1, 0.72)

func _ensure_ui_sound_players() -> void:
	if not _ui_sfx.is_empty():
		return
	for key in ["hover", "click", "open", "close", "confirm"]:
		var player := AudioStreamPlayer.new()
		player.name = "UISfx_%s" % key
		match key:
			"hover":
				player.stream = _load_runtime_sound(UI_SOUND_CLICK_PATH)
				player.volume_db = -11.0
			"click":
				player.stream = _load_runtime_sound(UI_SOUND_CLICK_PATH)
				player.volume_db = -7.0
			"open":
				player.stream = _load_runtime_sound(UI_SOUND_OPEN_PATH)
				player.volume_db = -6.0
			"close":
				player.stream = _load_runtime_sound(UI_SOUND_CLOSE_PATH)
				player.volume_db = -6.0
			"confirm":
				player.stream = _load_runtime_sound(UI_SOUND_CONFIRM_PATH)
				player.volume_db = -5.0
		add_child(player)
		_ui_sfx[key] = player

func _play_ui_sound(kind: String) -> void:
	var player: Variant = _ui_sfx.get(kind)
	if player is AudioStreamPlayer:
		(player as AudioStreamPlayer).play()

func _wire_button_sfx(button: BaseButton, pressed_kind: String = "click") -> void:
	if button == null:
		return
	if not button.mouse_entered.is_connected(_on_any_ui_button_hover):
		button.mouse_entered.connect(_on_any_ui_button_hover)
	if pressed_kind == "confirm":
		if not button.pressed.is_connected(_on_any_ui_button_confirm):
			button.pressed.connect(_on_any_ui_button_confirm)
	elif pressed_kind == "open":
		if not button.pressed.is_connected(_on_any_ui_button_open):
			button.pressed.connect(_on_any_ui_button_open)
	elif pressed_kind == "close":
		if not button.pressed.is_connected(_on_any_ui_button_close):
			button.pressed.connect(_on_any_ui_button_close)
	elif not button.pressed.is_connected(_on_any_ui_button_click):
		button.pressed.connect(_on_any_ui_button_click)

func _on_any_ui_button_hover() -> void:
	_play_ui_sound("hover")

func _on_any_ui_button_click() -> void:
	_play_ui_sound("click")

func _on_any_ui_button_open() -> void:
	_play_ui_sound("open")

func _on_any_ui_button_close() -> void:
	_play_ui_sound("close")

func _on_any_ui_button_confirm() -> void:
	_play_ui_sound("confirm")

func _kill_ui_tween(key: String) -> void:
	if _ui_tweens.has(key):
		var tween: Variant = _ui_tweens[key]
		if tween is Tween:
			(tween as Tween).kill()
		_ui_tweens.erase(key)

func _animate_panel_slide(panel: Control, show: bool, from_offset: Vector2, key: String) -> void:
	if panel == null:
		return
	_kill_ui_tween(key)
	if show:
		panel.visible = true
		panel.modulate.a = 0.0
		panel.position += from_offset
		var tween := create_tween()
		_ui_tweens[key] = tween
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(panel, "modulate:a", 1.0, 0.18)
		tween.tween_property(panel, "position", panel.position - from_offset, 0.20)
		tween.finished.connect(func() -> void:
			_ui_tweens.erase(key)
		)
	else:
		var tween := create_tween()
		_ui_tweens[key] = tween
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_IN)
		tween.tween_property(panel, "modulate:a", 0.0, 0.14)
		tween.tween_property(panel, "position", panel.position + from_offset, 0.16)
		tween.finished.connect(func() -> void:
			panel.visible = false
			panel.modulate.a = 1.0
			panel.position -= from_offset
			_ui_tweens.erase(key)
		)

func _pulse_control(control: CanvasItem, key: String, scale_up: Vector2 = Vector2(1.02, 1.02)) -> void:
	if control == null:
		return
	_kill_ui_tween(key)
	if control is Control:
		var typed := control as Control
		typed.pivot_offset = typed.size * 0.5
	var tween := create_tween()
	_ui_tweens[key] = tween
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", scale_up, 0.10)
	tween.tween_property(control, "scale", Vector2.ONE, 0.14)
	tween.finished.connect(func() -> void:
		control.scale = Vector2.ONE
		_ui_tweens.erase(key)
	)

func _highlight_status_card() -> void:
	var card := get_node_or_null("UILayer/LeftPanel/VBox/StatusCard") as Control
	if card == null:
		return
	_pulse_control(card, "status_pulse", Vector2(1.01, 1.01))

func _animate_details_visibility(extra: Control, show: bool) -> void:
	if extra == null:
		return
	_kill_ui_tween("details_visibility")
	if show:
		extra.visible = true
		extra.modulate.a = 0.0
		extra.position.y += 8.0
		var tween := create_tween()
		_ui_tweens["details_visibility"] = tween
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(extra, "modulate:a", 1.0, 0.14)
		tween.tween_property(extra, "position:y", extra.position.y - 8.0, 0.16)
		tween.finished.connect(func() -> void:
			_ui_tweens.erase("details_visibility")
		)
	else:
		var tween := create_tween()
		_ui_tweens["details_visibility"] = tween
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_IN)
		tween.tween_property(extra, "modulate:a", 0.0, 0.10)
		tween.tween_property(extra, "position:y", extra.position.y + 6.0, 0.12)
		tween.finished.connect(func() -> void:
			extra.visible = false
			extra.modulate.a = 1.0
			extra.position.y -= 6.0
			_ui_tweens.erase("details_visibility")
		)

func _apply_button_theme(button: Button, variant: String, selected: bool = false) -> void:
	if button == null:
		return
	var font_size := TYPE_BODY
	var normal_bg := UI_SURFACE_2
	var hover_bg := UI_SURFACE_2.lightened(0.06)
	var pressed_bg := UI_SURFACE_2.darkened(0.08)
	var disabled_bg := Color(UI_SURFACE_2, 0.42)
	var normal_border := UI_BORDER_SUBTLE
	var hover_border := UI_ACCENT
	var pressed_border := UI_ACCENT
	var text_color := UI_TEXT_PRIMARY
	var disabled_text := Color(UI_TEXT_MUTED, 0.58)
	match variant:
		"accent":
			normal_bg = UI_ACCENT if not selected else UI_ACCENT.lightened(0.08)
			hover_bg = UI_ACCENT.lightened(0.08)
			pressed_bg = UI_ACCENT.darkened(0.10)
			disabled_bg = Color(UI_ACCENT.darkened(0.18), 0.42)
			normal_border = UI_ACCENT.lightened(0.18)
			hover_border = UI_TEXT_PRIMARY
			pressed_border = UI_TEXT_PRIMARY
			text_color = UI_TEXT_PRIMARY
		"paper":
			normal_bg = UI_SURFACE_PAPER
			hover_bg = UI_SURFACE_PAPER.lightened(0.03)
			pressed_bg = UI_SURFACE_PAPER_SOFT
			disabled_bg = Color(UI_SURFACE_PAPER_SOFT, 0.5)
			normal_border = UI_BORDER_SUBTLE
			hover_border = UI_ACCENT
			pressed_border = UI_ACCENT
			text_color = UI_TEXT_DARK
			disabled_text = Color(UI_TEXT_DARK, 0.5)
			font_size = 14
		"rail":
			normal_bg = UI_SURFACE_1
			hover_bg = UI_SURFACE_2
			pressed_bg = UI_ACCENT_SOFT
			disabled_bg = Color(UI_SURFACE_1, 0.36)
			normal_border = UI_ACCENT if selected else UI_BORDER_SUBTLE
			hover_border = UI_ACCENT
			pressed_border = UI_ACCENT
			text_color = UI_TEXT_PRIMARY
			font_size = 14
		"offer":
			normal_bg = UI_SURFACE_PAPER if selected else Color(UI_SURFACE_PAPER, 0.88)
			hover_bg = UI_SURFACE_PAPER
			pressed_bg = UI_SURFACE_PAPER_SOFT
			disabled_bg = Color(UI_SURFACE_PAPER_SOFT, 0.52)
			normal_border = UI_ACCENT if selected else UI_BORDER_SUBTLE
			hover_border = UI_ACCENT
			pressed_border = UI_ACCENT
			text_color = UI_TEXT_DARK
			disabled_text = Color(UI_TEXT_DARK, 0.5)
			font_size = 14
		"roster":
			normal_bg = UI_ACCENT_SOFT if selected else UI_SURFACE_1
			hover_bg = UI_SURFACE_2
			pressed_bg = UI_ACCENT_SOFT
			disabled_bg = Color(UI_SURFACE_1, 0.32)
			normal_border = UI_ACCENT if selected else UI_BORDER_SUBTLE
			hover_border = UI_ACCENT
			pressed_border = UI_ACCENT
			text_color = UI_TEXT_PRIMARY
			font_size = 13
		_:
			pass
	button.set("theme_override_styles/normal", _make_style(normal_bg, normal_border, RADIUS_BUTTON, 1, 12))
	button.set("theme_override_styles/hover", _make_style(hover_bg, hover_border, RADIUS_BUTTON, 1, 12))
	button.set("theme_override_styles/pressed", _make_style(pressed_bg, pressed_border, RADIUS_BUTTON, 1, 12))
	button.set("theme_override_styles/disabled", _make_style(disabled_bg, normal_border, RADIUS_BUTTON, 1, 12))
	button.set("theme_override_colors/font_color", text_color)
	button.set("theme_override_colors/font_hover_color", text_color)
	button.set("theme_override_colors/font_pressed_color", text_color)
	button.set("theme_override_colors/font_disabled_color", disabled_text)
	button.set("theme_override_font_sizes/font_size", font_size)
	button.set("theme_override_fonts/font", _load_runtime_font(FONT_BODY_PATH))
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var button_blue := _load_runtime_texture(BUTTON_BLUE_PATH)
	var button_blue_outline := _load_runtime_texture(BUTTON_BLUE_OUTLINE_PATH)
	var button_blue_flat := _load_runtime_texture(BUTTON_BLUE_FLAT_PATH)
	match variant:
		"accent":
			font_size = 15
			button.set("theme_override_styles/normal", _make_texture_style(button_blue, 18, 14, true, UI_ACCENT.lightened(0.10)))
			button.set("theme_override_styles/hover", _make_texture_style(button_blue, 18, 14, true, UI_ACCENT.lightened(0.22)))
			button.set("theme_override_styles/pressed", _make_texture_style(button_blue_outline, 18, 14, true, UI_ACCENT.darkened(0.08)))
			button.set("theme_override_styles/disabled", _make_texture_style(button_blue_flat, 18, 14, true, Color(UI_SURFACE_2.lightened(0.10), 0.58)))
			button.set("theme_override_colors/font_color", UI_TEXT_PRIMARY)
			button.set("theme_override_colors/font_hover_color", UI_TEXT_PRIMARY)
			button.set("theme_override_colors/font_pressed_color", UI_TEXT_PRIMARY)
			button.set("theme_override_colors/font_disabled_color", Color(UI_TEXT_MUTED, 0.62))
		"chrome":
			font_size = 13
			var chrome_normal := Color(0.31, 0.43, 0.54, 0.92)
			var chrome_hover := Color(0.39, 0.51, 0.62, 0.96)
			var chrome_pressed := Color(0.27, 0.37, 0.47, 0.96)
			if selected:
				chrome_normal = UI_ACCENT.lightened(0.14)
				chrome_hover = UI_ACCENT.lightened(0.24)
				chrome_pressed = UI_ACCENT.darkened(0.04)
			button.set("theme_override_styles/normal", _make_texture_style(button_blue_flat, 18, 12, true, chrome_normal))
			button.set("theme_override_styles/hover", _make_texture_style(button_blue, 18, 12, true, chrome_hover))
			button.set("theme_override_styles/pressed", _make_texture_style(button_blue_outline, 18, 12, true, chrome_pressed))
			button.set("theme_override_styles/disabled", _make_texture_style(button_blue_flat, 18, 12, true, Color(0.24, 0.29, 0.35, 0.48)))
			button.set("theme_override_colors/font_color", UI_TEXT_PRIMARY)
			button.set("theme_override_colors/font_hover_color", UI_TEXT_PRIMARY)
			button.set("theme_override_colors/font_pressed_color", UI_TEXT_PRIMARY)
			button.set("theme_override_colors/font_disabled_color", Color(UI_TEXT_MUTED, 0.54))
	button.set("theme_override_font_sizes/font_size", font_size)

func _apply_label_role(label: Label, role: String, dark: bool = false) -> void:
	if label == null:
		return
	label.set("theme_override_fonts/font", _load_runtime_font(FONT_BODY_PATH))
	match role:
		"screen_title":
			label.set("theme_override_fonts/font", _load_runtime_font(FONT_HEADING_PATH))
			label.set("theme_override_font_sizes/font_size", TYPE_SCREEN_TITLE)
			label.set("theme_override_colors/font_color", UI_TEXT_PRIMARY if not dark else UI_TEXT_DARK)
		"panel_title":
			label.set("theme_override_fonts/font", _load_runtime_font(FONT_HEADING_PATH))
			label.set("theme_override_font_sizes/font_size", TYPE_PANEL_TITLE)
			label.set("theme_override_colors/font_color", UI_TEXT_PRIMARY if not dark else UI_TEXT_DARK)
		"quest_title":
			label.set("theme_override_fonts/font", _load_runtime_font(FONT_HEADING_PATH))
			label.set("theme_override_font_sizes/font_size", TYPE_QUEST_TITLE)
			label.set("theme_override_colors/font_color", UI_TEXT_PRIMARY if not dark else UI_TEXT_DARK)
		"section":
			label.set("theme_override_font_sizes/font_size", TYPE_SECTION_LABEL)
			label.set("theme_override_colors/font_color", UI_TEXT_MUTED if not dark else Color(UI_TEXT_DARK, 0.7))
			label.uppercase = false
		"meta":
			label.set("theme_override_font_sizes/font_size", TYPE_META)
			label.set("theme_override_colors/font_color", UI_TEXT_MUTED if not dark else Color(UI_TEXT_DARK, 0.68))
		_:
			label.set("theme_override_font_sizes/font_size", TYPE_BODY)
			label.set("theme_override_colors/font_color", UI_TEXT_PRIMARY if not dark else UI_TEXT_DARK)

func _ensure_quest_scrim() -> void:
	var ui_layer := get_node_or_null("UILayer")
	var drawer := get_node_or_null("UILayer/QuestDrawer")
	if ui_layer == null or drawer == null:
		return
	var scrim := get_node_or_null("UILayer/QuestScrim")
	if scrim == null:
		scrim = ColorRect.new()
		scrim.name = "QuestScrim"
		scrim.color = Color(0.03, 0.05, 0.08, 0.52)
		scrim.anchors_preset = Control.PRESET_FULL_RECT
		scrim.mouse_filter = Control.MOUSE_FILTER_STOP
		scrim.visible = false
		ui_layer.add_child(scrim)
		ui_layer.move_child(scrim, drawer.get_index())

func _apply_visual_design_system() -> void:
	_ensure_quest_scrim()
	var frame_simple := _load_runtime_texture(FRAME_SIMPLE_PATH)
	var frame_ornate := _load_runtime_texture(FRAME_ORNATE_PATH)
	var icon_book := _load_runtime_texture(ICON_BOOK_PATH)
	var icon_campfire := _load_runtime_texture(ICON_CAMPFIRE_PATH)
	var icon_character := _load_runtime_texture(ICON_CHARACTER_PATH)
	var icon_sword := _load_runtime_texture(ICON_SWORD_PATH)
	var top_bar := get_node_or_null("UILayer/TopBar")
	if top_bar:
		top_bar.set("theme_override_styles/panel", _make_style(Color(UI_SURFACE_1, 0.92), Color(UI_ACCENT, 0.14), 22, 0, 10))
		top_bar.offset_top = 18.0
		top_bar.offset_bottom = 70.0
		_ensure_ornament_frame(top_bar, frame_simple, 16, 4, Color(1, 1, 1, 0.42))
	var left_panel := get_node_or_null("UILayer/LeftPanel")
	if left_panel:
		left_panel.set("theme_override_styles/panel", _make_style(Color(UI_SURFACE_1, 0.74), Color(UI_BORDER_SUBTLE, 0.32), 20, 0, 12))
	var right_panel := get_node_or_null("UILayer/RightPanel")
	if right_panel:
		right_panel.set("theme_override_styles/panel", _make_style(Color(UI_SURFACE_1, 0.72), Color(UI_BORDER_SUBTLE, 0.28), 20, 0, 12))
	var event_panel := get_node_or_null("UILayer/EventLogPanel")
	if event_panel:
		event_panel.set("theme_override_styles/panel", _make_style(Color(UI_SURFACE_1, 0.76), Color(UI_BORDER_SUBTLE, 0.20), 18, 0, 10))
	var roster_panel := get_node_or_null("UILayer/RosterPanel")
	if roster_panel:
		roster_panel.set("theme_override_styles/panel", _make_style(Color(UI_SURFACE_1, 0.86), Color(UI_ACCENT, 0.18), 18, 0, 10))
		_ensure_ornament_frame(roster_panel, frame_ornate, 16, 5, Color(1, 1, 1, 0.44))
	var quest_drawer := get_node_or_null("UILayer/QuestDrawer")
	if quest_drawer:
		quest_drawer.set("theme_override_styles/panel", _make_style(Color(0.09, 0.12, 0.16, 0.97), Color(UI_ACCENT, 0.22), 24, 0, 16))
		_ensure_ornament_frame(quest_drawer, frame_ornate, 16, 8, Color(1, 1, 1, 0.55))
	var summary_card := get_node_or_null("UILayer/RightPanel/VBox/SummaryCard")
	if summary_card:
		summary_card.set("theme_override_styles/panel", _make_style(Color(UI_SURFACE_PAPER, 0.97), Color(UI_BORDER_SUBTLE, 0.38), 18, 0, 14))
		_ensure_ornament_frame(summary_card, frame_ornate, 16, 3, Color(1, 1, 1, 0.26))
	var facts_card := get_node_or_null("UILayer/RightPanel/VBox/PrimaryFactsCard")
	if facts_card:
		facts_card.set("theme_override_styles/panel", _make_style(Color(UI_SURFACE_PAPER, 0.93), Color(UI_BORDER_SUBTLE, 0.22), 16, 0, 12))
	var action_card := get_node_or_null("UILayer/RightPanel/VBox/ActionCard")
	if action_card:
		action_card.set("theme_override_styles/panel", _make_style(Color(UI_SURFACE_2, 0.94), Color(UI_ACCENT, 0.24), 16, 0, 12))
	var quest_header := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestDetailHeader")
	if quest_header:
		quest_header.set("theme_override_styles/panel", _make_style(Color(UI_SURFACE_PAPER, 0.97), Color(UI_BORDER_SUBTLE, 0.40), 20, 0, 14))
		_ensure_ornament_frame(quest_header, frame_ornate, 16, 4, Color(1, 1, 1, 0.42))
	var quest_meta := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestMetaCard")
	if quest_meta:
		quest_meta.set("theme_override_styles/panel", _make_style(Color(UI_SURFACE_2, 0.94), Color(UI_ACCENT, 0.18), 18, 0, 14))
	var quest_suitability := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestSuitabilityCard")
	if quest_suitability:
		quest_suitability.set("theme_override_styles/panel", _make_style(Color(UI_SURFACE_PAPER, 0.92), Color(UI_BORDER_SUBTLE, 0.20), 18, 0, 14))
	var active_card := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestLowerRow/ActiveQuestCard")
	if active_card:
		active_card.set("theme_override_styles/panel", _make_style(Color(UI_SURFACE_2, 0.92), Color(UI_ACCENT, 0.18), 18, 0, 12))
	var completed_card := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestLowerRow/CompletedQuestCard")
	if completed_card:
		completed_card.set("theme_override_styles/panel", _make_style(Color(UI_SURFACE_PAPER, 0.92), Color(UI_BORDER_SUBTLE, 0.18), 18, 0, 12))
	var status_card := get_node_or_null("UILayer/LeftPanel/VBox/StatusCard")
	if status_card:
		status_card.set("theme_override_styles/panel", _make_style(Color(UI_SURFACE_2, 0.86), Color(UI_BORDER_SUBTLE, 0.18), 14, 0, 10))
	var quest_header_box := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestHeader") as Control
	if quest_header_box:
		_ensure_divider_texture(quest_header_box)

	for path in [
		"UILayer/TopBar/TopBarRow/Speed1Button",
		"UILayer/TopBar/TopBarRow/Speed2Button",
		"UILayer/TopBar/TopBarRow/Speed3Button",
		"UILayer/TopBar/TopBarRow/PauseButton",
		"UILayer/TopBar/TopBarRow/OptionsButton",
		"UILayer/LeftPanel/VBox/SaveLoadRow/SaveButton",
		"UILayer/LeftPanel/VBox/SaveLoadRow/LoadButton",
		"UILayer/LeftPanelTab",
		"UILayer/RightPanelTab",
		"UILayer/EventLogPanel/VBox/Header/ExpandButton",
		"UILayer/QuestDrawer/QuestVBox/QuestHeader/QuestCloseButton",
		"UILayer/RightPanel/VBox/MoreDetailsButton",
		"UILayer/RosterPanel/RosterVBox/RosterPrevButton",
		"UILayer/RosterPanel/RosterVBox/RosterNextButton",
		"UILayer/RosterPanel/RosterVBox/RosterExpandButton"
	]:
		_apply_button_theme(get_node_or_null(path), "chrome")
	_apply_button_theme(get_node_or_null("UILayer/TopBar/TopBarRow/QuestDrawerButton"), "accent")
	_apply_button_theme(get_node_or_null("UILayer/TopBar/TopBarRow/BuildPanelToggleButton"), "accent")
	_apply_button_theme(get_node_or_null("UILayer/TopBar/TopBarRow/DetailsPanelToggleButton"), "paper")
	for path in [
		"UILayer/LeftPanel/VBox/BuildRail/BuildButton",
		"UILayer/LeftPanel/VBox/BuildRail/BuildWeaponsShopButton",
		"UILayer/LeftPanel/VBox/BuildRail/BuildTempleButton"
	]:
		_apply_button_theme(get_node_or_null(path), "rail")
	_apply_button_theme(get_node_or_null("UILayer/LeftPanel/VBox/ContextUpgradeButton"), "accent")
	_apply_button_theme(get_node_or_null("UILayer/RightPanel/VBox/ActionCard/ActionVBox/ActionButtons/BuildingActionButton"), "accent")
	_apply_button_theme(get_node_or_null("UILayer/RightPanel/VBox/ActionCard/ActionVBox/ActionButtons/OutputActionButton"), "paper")
	_apply_button_theme(get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestActionButton"), "accent")
	var quest_button := get_node_or_null("UILayer/TopBar/TopBarRow/QuestDrawerButton")
	if quest_button:
		quest_button.icon = icon_book
	var build_toggle := get_node_or_null("UILayer/TopBar/TopBarRow/BuildPanelToggleButton")
	if build_toggle:
		build_toggle.icon = icon_campfire
	var details_toggle := get_node_or_null("UILayer/TopBar/TopBarRow/DetailsPanelToggleButton")
	if details_toggle:
		details_toggle.icon = icon_character
	var quest_action_button := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestActionButton")
	if quest_action_button:
		quest_action_button.icon = icon_sword

	_apply_label_role(get_node_or_null("UILayer/TopBar/TopBarRow/GoldLabel"), "panel_title")
	_apply_label_role(get_node_or_null("UILayer/TopBar/TopBarRow/TownTitleStack/TownTitleLabel"), "screen_title")
	_apply_label_role(get_node_or_null("UILayer/TopBar/TopBarRow/TownTitleStack/TownSubtitleLabel"), "meta")
	_apply_label_role(get_node_or_null("UILayer/TopBar/TopBarRow/HeroSummaryLabel"), "body")
	_apply_label_role(get_node_or_null("UILayer/LeftPanel/VBox/Header/TitleLabel"), "panel_title")
	_apply_label_role(get_node_or_null("UILayer/LeftPanel/VBox/BuildSectionLabel"), "section")
	_apply_label_role(get_node_or_null("UILayer/LeftPanel/VBox/BuildSectionHint"), "meta")
	_apply_label_role(get_node_or_null("UILayer/LeftPanel/VBox/UtilitySectionLabel"), "section")
	_apply_label_role(get_node_or_null("UILayer/RightPanel/VBox/Header/EntityTitle"), "panel_title")
	_apply_label_role(get_node_or_null("UILayer/RightPanel/VBox/InspectorLeadLabel"), "meta")
	_apply_label_role(get_node_or_null("UILayer/RightPanel/VBox/ActionSectionLabel"), "section")
	_apply_label_role(get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestHeader/QuestTitle"), "screen_title")
	_apply_label_role(get_node_or_null("UILayer/RosterPanel/RosterVBox/RosterTitle"), "section")
	_apply_label_role(get_node_or_null("UILayer/EventLogPanel/VBox/Header/TitleLabel"), "section")
	_apply_label_role(get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestListColumn/QuestOffersTitle"), "section")
	_apply_label_role(get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestListColumn/QuestFilterSummaryLabel"), "meta")
	_apply_label_role(get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestDetailHeader/QuestDetailHeaderVBox/QuestDetailKicker"), "section", true)
	_apply_label_role(get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestDetailHeader/QuestDetailHeaderVBox/QuestDetailTitleLabel"), "quest_title", true)
	_apply_label_role(get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestDetailHeader/QuestDetailHeaderVBox/QuestDetailSummaryLabel"), "body", true)

	var help := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestHelp")
	if help:
		help.set("theme_override_colors/font_color", UI_TEXT_MUTED)
		help.set("theme_override_font_sizes/font_size", TYPE_BODY)
		help.set("theme_override_fonts/font", _load_runtime_font(FONT_BODY_PATH))
	var gold_label := get_node_or_null("UILayer/TopBar/TopBarRow/GoldLabel")
	if gold_label:
		gold_label.set("theme_override_colors/font_color", Color(1.0, 0.92, 0.70, 1.0))
	var summary_label := get_node_or_null("UILayer/TopBar/TopBarRow/HeroSummaryLabel")
	if summary_label:
		summary_label.set("theme_override_colors/font_color", Color(UI_TEXT_MUTED, 0.92))

	for path in [
		"UILayer/RightPanel/VBox/HealthSectionLabel",
		"UILayer/RightPanel/VBox/XpSectionLabel",
		"UILayer/QuestDrawer/QuestVBox/QuestLowerRow/ActiveQuestCard/ActiveQuestVBox/ActiveQuestTitle",
		"UILayer/QuestDrawer/QuestVBox/QuestLowerRow/CompletedQuestCard/CompletedQuestVBox/CompletedQuestTitle"
	]:
		_apply_label_role(get_node_or_null(path), "section")

	var health_bar := get_node_or_null("UILayer/RightPanel/VBox/HealthBar")
	if health_bar:
		health_bar.set("theme_override_styles/background", _make_style(Color(UI_SURFACE_2, 0.8), Color(UI_BORDER_SUBTLE, 0.5), 999, 1, 4))
		health_bar.set("theme_override_styles/fill", _make_style(Color(0.72, 0.31, 0.27, 1.0), Color(0.85, 0.53, 0.47, 1.0), 999, 0, 4))
	var xp_bar := get_node_or_null("UILayer/RightPanel/VBox/XpBar")
	if xp_bar:
		xp_bar.set("theme_override_styles/background", _make_style(Color(UI_SURFACE_2, 0.8), Color(UI_BORDER_SUBTLE, 0.5), 999, 1, 4))
		xp_bar.set("theme_override_styles/fill", _make_style(UI_ACCENT, UI_ACCENT.lightened(0.16), 999, 0, 4))
	var portrait_panel := get_node_or_null("UILayer/RightPanel/VBox/SummaryCard/SummaryRow/PortraitPanel")
	if portrait_panel:
		portrait_panel.set("theme_override_styles/panel", _make_style(Color(UI_SURFACE_2, 0.88), Color(UI_ACCENT, 0.28), 16, 1, 8))
		_ensure_ornament_frame(portrait_panel, frame_simple, 16, 3, Color(1, 1, 1, 0.28))

func _ready() -> void:
	if RuntimeConfig.is_headless():
		cmd_server.set_sim(sim)
		cmd_server.start(RuntimeConfig.port)

	if RuntimeConfig.is_test() and RuntimeConfig.scenario_path != "":
		var runner: Node = load("res://scripts/control/ScenarioRunner.gd").new()
		add_child(runner)
		runner.run_scenario.call_deferred(sim, RuntimeConfig.scenario_path)
		return

	if not RuntimeConfig.is_headless():
		_ensure_ui_sound_players()
		var btn := get_node_or_null("UILayer/LeftPanel/VBox/BuildRail/BuildButton")
		if btn:
			btn.pressed.connect(_on_build_tavern_pressed)
			_wire_button_sfx(btn)
		var btn2 := get_node_or_null("UILayer/LeftPanel/VBox/BuildRail/BuildWeaponsShopButton")
		if btn2:
			btn2.pressed.connect(_on_build_weapons_shop_pressed)
			_wire_button_sfx(btn2)
		var btn3 := get_node_or_null("UILayer/LeftPanel/VBox/BuildRail/BuildTempleButton")
		if btn3:
			btn3.pressed.connect(_on_build_temple_pressed)
			_wire_button_sfx(btn3)
		var upgrade_btn := get_node_or_null("UILayer/LeftPanel/VBox/ContextUpgradeButton")
		if upgrade_btn:
			upgrade_btn.pressed.connect(_start_selected_building_upgrade)
			_wire_button_sfx(upgrade_btn, "confirm")
		var save_btn := get_node_or_null("UILayer/LeftPanel/VBox/SaveLoadRow/SaveButton")
		if save_btn:
			save_btn.pressed.connect(_save_world)
			_wire_button_sfx(save_btn)
		var load_btn := get_node_or_null("UILayer/LeftPanel/VBox/SaveLoadRow/LoadButton")
		if load_btn:
			load_btn.pressed.connect(_load_world)
			_wire_button_sfx(load_btn)
		var enable_all_btn := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestListColumn/QuestFilterControls/EnableAllQuestsButton")
		if enable_all_btn:
			enable_all_btn.pressed.connect(func() -> void: _set_all_quest_filters(true))
			_wire_button_sfx(enable_all_btn)
		var disable_all_btn := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestListColumn/QuestFilterControls/DisableAllQuestsButton")
		if disable_all_btn:
			disable_all_btn.pressed.connect(func() -> void: _set_all_quest_filters(false))
			_wire_button_sfx(disable_all_btn)
		var quest_btn := get_node_or_null("UILayer/TopBar/TopBarRow/QuestDrawerButton")
		if quest_btn:
			quest_btn.pressed.connect(_toggle_quest_drawer)
			_wire_button_sfx(quest_btn, "open")
		var quest_close := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestHeader/QuestCloseButton")
		if quest_close:
			quest_close.pressed.connect(_toggle_quest_drawer)
			_wire_button_sfx(quest_close, "close")
		var build_toggle := get_node_or_null("UILayer/TopBar/TopBarRow/BuildPanelToggleButton")
		if build_toggle:
			build_toggle.pressed.connect(_toggle_left_panel)
			_wire_button_sfx(build_toggle)
		var details_toggle := get_node_or_null("UILayer/TopBar/TopBarRow/DetailsPanelToggleButton")
		if details_toggle:
			details_toggle.pressed.connect(_toggle_right_panel)
			_wire_button_sfx(details_toggle)
		var left_collapse := get_node_or_null("UILayer/LeftPanel/VBox/Header/CollapseButton")
		if left_collapse:
			left_collapse.pressed.connect(_toggle_left_panel)
			_wire_button_sfx(left_collapse)
		var right_collapse := get_node_or_null("UILayer/RightPanel/VBox/Header/CollapseButton")
		if right_collapse:
			right_collapse.pressed.connect(_toggle_right_panel)
			_wire_button_sfx(right_collapse)
		var left_tab := get_node_or_null("UILayer/LeftPanelTab")
		if left_tab:
			left_tab.pressed.connect(_toggle_left_panel)
			_wire_button_sfx(left_tab)
		var right_tab := get_node_or_null("UILayer/RightPanelTab")
		if right_tab:
			right_tab.pressed.connect(_toggle_right_panel)
			_wire_button_sfx(right_tab)
		var expand_log := get_node_or_null("UILayer/EventLogPanel/VBox/Header/ExpandButton")
		if expand_log:
			expand_log.pressed.connect(_toggle_event_feed)
			_wire_button_sfx(expand_log)
		var speed1 := get_node_or_null("UILayer/TopBar/TopBarRow/Speed1Button")
		if speed1:
			speed1.pressed.connect(func() -> void: _set_time_scale(1.0))
			_wire_button_sfx(speed1)
		var speed2 := get_node_or_null("UILayer/TopBar/TopBarRow/Speed2Button")
		if speed2:
			speed2.pressed.connect(func() -> void: _set_time_scale(2.0))
			_wire_button_sfx(speed2)
		var speed3 := get_node_or_null("UILayer/TopBar/TopBarRow/Speed3Button")
		if speed3:
			speed3.pressed.connect(func() -> void: _set_time_scale(3.0))
			_wire_button_sfx(speed3)
		var pause_btn := get_node_or_null("UILayer/TopBar/TopBarRow/PauseButton")
		if pause_btn:
			pause_btn.pressed.connect(_toggle_pause_menu)
			_wire_button_sfx(pause_btn, "open")
		var options_btn := get_node_or_null("UILayer/TopBar/TopBarRow/OptionsButton")
		if options_btn:
			options_btn.pressed.connect(_open_options_menu)
			_wire_button_sfx(options_btn, "open")
		var more_details_btn := get_node_or_null("UILayer/RightPanel/VBox/MoreDetailsButton")
		if more_details_btn:
			more_details_btn.pressed.connect(_toggle_details_expanded)
			_wire_button_sfx(more_details_btn)
		var roster_prev_btn := get_node_or_null("UILayer/RosterPanel/RosterVBox/RosterPrevButton")
		if roster_prev_btn:
			roster_prev_btn.pressed.connect(func() -> void: _scroll_roster(-220))
			_wire_button_sfx(roster_prev_btn)
		var roster_next_btn := get_node_or_null("UILayer/RosterPanel/RosterVBox/RosterNextButton")
		if roster_next_btn:
			roster_next_btn.pressed.connect(func() -> void: _scroll_roster(220))
			_wire_button_sfx(roster_next_btn)
		var roster_expand_btn := get_node_or_null("UILayer/RosterPanel/RosterVBox/RosterExpandButton")
		if roster_expand_btn:
			roster_expand_btn.pressed.connect(_toggle_roster_expanded)
			_wire_button_sfx(roster_expand_btn)
		var building_action_btn := get_node_or_null("UILayer/RightPanel/VBox/ActionCard/ActionVBox/ActionButtons/BuildingActionButton")
		if building_action_btn:
			building_action_btn.pressed.connect(_start_selected_building_upgrade)
			_wire_button_sfx(building_action_btn, "confirm")
		var output_action_btn := get_node_or_null("UILayer/RightPanel/VBox/ActionCard/ActionVBox/ActionButtons/OutputActionButton")
		if output_action_btn:
			output_action_btn.pressed.connect(_set_selected_building_output_mode)
			_wire_button_sfx(output_action_btn)
		var quest_action_btn := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestActionButton")
		if quest_action_btn:
			quest_action_btn.pressed.connect(_accept_selected_quest)
			_wire_button_sfx(quest_action_btn, "confirm")
		get_viewport().size_changed.connect(_fit_ui_to_viewport)
		GameState.gold_changed.connect(_on_gold_changed)
		GameState.building_placed.connect(_on_building_state_changed)
		GameState.building_removed.connect(_on_building_removed)
		GameState.building_upgraded.connect(_on_building_upgraded)
		GameState.building_action_changed.connect(_on_building_action_changed)
		GameState.hero_spawned.connect(_on_hero_spawned)
		GameState.hero_state_changed.connect(_on_hero_state_changed)
		GameState.hero_removed.connect(_on_hero_removed)
		GameState.quests_changed.connect(_refresh_quest_ui)
		GameState.quest_filters_changed.connect(_refresh_quest_ui)
		GameState.quest_history_changed.connect(_refresh_quest_ui)
		GameState.state_reloaded.connect(_on_state_reloaded)
		_setup_quest_menu()
		_apply_visual_design_system()
		_on_gold_changed(GameState.gold)
		_refresh_quest_ui()
		if RuntimeConfig.request_load_world:
			RuntimeConfig.request_load_world = false
			_load_world()
		_apply_panel_state()
		_fit_ui_to_viewport()
		_refresh_roster_strip()
		_refresh_top_bar()
		_toggle_event_feed(false)
		_set_status("LMB place/select  RMB rotate build  Q/E cycle  Del remove  B/C panels  K quests")
		if RuntimeConfig.is_snapshot():
			UISnapshotService.notify_world_ready(self)

func _physics_process(delta: float) -> void:
	if RuntimeConfig.is_headless():
		return  # sim is driven on-demand by CommandServer in headless mode
	sim.physics_step(delta)
	# Refresh selected hero panel each physics tick so state/position stay current
	if _selected_hero_id >= 0 and GameState.heroes.has(_selected_hero_id):
		_refresh_hero_panel(_selected_hero_id)
	elif _selected_building_id >= 0 and GameState.buildings.has(_selected_building_id):
		_refresh_building_panel(_selected_building_id)
	_refresh_top_bar()

func _unhandled_input(event: InputEvent) -> void:
	if RuntimeConfig.is_headless():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_save_world()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F2:
			_load_world()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F5:
			_save_world()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F9:
			_load_world()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_DELETE:
			_remove_selected_building()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_B:
			_toggle_left_panel()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_C:
			_toggle_right_panel()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_K:
			_toggle_quest_drawer()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and not build_manager.is_placing():
			if _is_quest_drawer_open():
				_toggle_quest_drawer()
				get_viewport().set_input_as_handled()
				return
			_toggle_pause_menu()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_Q:
			build_manager.cycle_building_type(-1)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_E:
			build_manager.cycle_building_type(1)
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _try_select_hero(event.position):
		return
	_try_select_building(event.position)

func _try_select_hero(mouse_pos: Vector2) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.from = camera.project_ray_origin(mouse_pos)
	params.to = params.from + camera.project_ray_normal(mouse_pos) * 200.0
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = 2
	var result: Dictionary = space_state.intersect_ray(params)
	if not result.is_empty() and result["collider"].has_meta("hero_id"):
		_show_hero_panel(result["collider"].get_meta("hero_id"))
		return true
	return false

func _try_select_building(mouse_pos: Vector2) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.from = camera.project_ray_origin(mouse_pos)
	params.to = params.from + camera.project_ray_normal(mouse_pos) * 200.0
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = 4
	var result: Dictionary = space_state.intersect_ray(params)
	if result.is_empty() or not result["collider"].has_meta("building_id"):
		_selected_building_id = -1
		return false
	_selected_building_id = int(result["collider"].get_meta("building_id"))
	var building: Dictionary = GameState.buildings.get(_selected_building_id, {})
	_set_status("Selected %s  (Del remove)" % building.get("type", "building"))
	_show_building_panel(_selected_building_id)
	return true

func _show_hero_panel(hero_id: int) -> void:
	if not GameState.heroes.has(hero_id):
		return
	_selected_building_id = -1
	_selected_entity_kind = "hero"
	_selected_hero_id = hero_id
	_right_panel_collapsed = false
	_refresh_hero_panel(hero_id)
	_refresh_roster_strip()
	_apply_panel_state()
	_pulse_control(get_node_or_null("UILayer/RightPanel/VBox/SummaryCard") as CanvasItem, "inspector_summary")

func _refresh_hero_panel(hero_id: int) -> void:
	if not GameState.heroes.has(hero_id):
		return
	var h: Dictionary = GameState.heroes[hero_id]
	var portrait := get_node_or_null("UILayer/RightPanel/VBox/SummaryCard/SummaryRow/PortraitPanel/PortraitMargin/PortraitTexture")
	var title_lbl := get_node_or_null("UILayer/RightPanel/VBox/Header/EntityTitle")
	var lead_lbl := get_node_or_null("UILayer/RightPanel/VBox/InspectorLeadLabel")
	var name_lbl := get_node_or_null("UILayer/RightPanel/VBox/SummaryCard/SummaryRow/SummaryText/NameLabel")
	var career_lbl := get_node_or_null("UILayer/RightPanel/VBox/SummaryCard/SummaryRow/SummaryText/CareerLabel")
	var state_lbl := get_node_or_null("UILayer/RightPanel/VBox/SummaryCard/SummaryRow/SummaryText/StateLabel")
	var summary_lbl := get_node_or_null("UILayer/RightPanel/VBox/SummaryCard/SummaryRow/SummaryText/SummaryMetaLabel")
	var level_lbl := get_node_or_null("UILayer/RightPanel/VBox/LevelLabel")
	var health_bar := get_node_or_null("UILayer/RightPanel/VBox/HealthBar")
	var health_lbl := get_node_or_null("UILayer/RightPanel/VBox/HealthLabel")
	var xp_bar := get_node_or_null("UILayer/RightPanel/VBox/XpBar")
	var primary_lbl := get_node_or_null("UILayer/RightPanel/VBox/PrimaryFactsCard/PrimaryFactsLabel")
	var action_lbl := get_node_or_null("UILayer/RightPanel/VBox/ActionCard/ActionVBox/ActionStateLabel")
	var output_lbl := get_node_or_null("UILayer/RightPanel/VBox/ActionCard/ActionVBox/OutputStateLabel")
	var gold_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/HeroGoldLabel")
	var bias_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/BiasLabel")
	var stats_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/StatsLabel")
	var skills_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/SkillsLabel")
	var trappings_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/TrappingsLabel")
	var talents_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/TalentsLabel")
	var tags_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/TagsLabel")
	var desc_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/DescriptionLabel")
	var quest_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/CurrentQuestLabel")
	var max_health := int(h.get("max_health", 0))
	var health := int(h.get("health", 0))
	var level := int(h.get("level", 1))
	var xp := int(h.get("xp", 0))
	var xp_progress := xp % 100
	if title_lbl:
		title_lbl.text = "Adventurer Sheet"
	if lead_lbl:
		lead_lbl.text = "Identity, readiness, and WFRP starter equipment."
	if portrait:
		var archetype: String = str(h.get("career_archetype", "commoner")).to_lower()
		portrait.texture = load(HERO_PORTRAITS.get(archetype, HERO_PORTRAITS["commoner"]))
	if name_lbl:
		name_lbl.text = h["name"]
		name_lbl.set("theme_override_fonts/font", _load_runtime_font(FONT_HEADING_PATH))
		name_lbl.set("theme_override_font_sizes/font_size", 21)
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if career_lbl:
		career_lbl.text = "%s\n%s" % [h.get("career_role", h["career"]), h["career"]]
		career_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		career_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if state_lbl:
		state_lbl.text = "Activity  %s" % _format_entity_state(h["state"])
		state_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		state_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if summary_lbl:
		summary_lbl.text = "Level %d  •  %dg on hand  •  %s" % [level, h.get("gold", 0), str(h.get("wound_state", "healthy")).replace("_", " ")]
		summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if health_bar:
		health_bar.max_value = max(1, max_health)
		health_bar.value = health
		health_bar.visible = true
	if xp_bar:
		xp_bar.max_value = 100
		xp_bar.value = xp_progress
		xp_bar.visible = true
	if level_lbl:
		level_lbl.text = "Level %d  •  %d XP toward the next tier" % [level, xp_progress]
	if health_lbl:
		health_lbl.text = "Health  %d / %d" % [health, max_health]
	if primary_lbl:
		var current_quest: Dictionary = h.get("current_quest", {})
		var activity := _hero_activity_summary(h)
		if not current_quest.is_empty():
			activity = "%s (%s)" % [current_quest.get("name", "?"), _format_quest_state(h.get("state", ""))]
		var wfrp_stats: Dictionary = h.get("wfrp_stats", {})
		primary_lbl.text = "Current activity  %s\nWFRP spread  WS %d  BS %d  S %d  T %d  Ag %d  Int %d  WP %d  Fel %d" % [
			activity,
			wfrp_stats.get("WS", 0),
			wfrp_stats.get("BS", 0),
			wfrp_stats.get("S", 0),
			wfrp_stats.get("T", 0),
			wfrp_stats.get("Ag", 0),
			wfrp_stats.get("Int", 0),
			wfrp_stats.get("WP", 0),
			wfrp_stats.get("Fel", 0)
		]
	if action_lbl:
		action_lbl.visible = false
	if output_lbl:
		output_lbl.visible = false
	if gold_lbl:
		gold_lbl.text = "Gold  %d" % h.get("gold", 0)
	if bias_lbl:
		bias_lbl.text = "Quest bias  %s\nService pull  %s\nParty size  %d" % [h.get("quest_bias", "-"), h.get("service_bias", "-"), int(h.get("quest_party_size", 0))]
	if stats_lbl:
		var stats: Dictionary = h.get("stats", {})
		var wfrp_stats: Dictionary = h.get("wfrp_stats", {})
		stats_lbl.text = "WFRP  WS %d  BS %d  S %d  T %d  Ag %d  Int %d  WP %d  Fel %d  W %d  Mag %d\nMapped  MGT %d  AGI %d  WIT %d  SPR %d  END %d" % [
			wfrp_stats.get("WS", 0),
			wfrp_stats.get("BS", 0),
			wfrp_stats.get("S", 0),
			wfrp_stats.get("T", 0),
			wfrp_stats.get("Ag", 0),
			wfrp_stats.get("Int", 0),
			wfrp_stats.get("WP", 0),
			wfrp_stats.get("Fel", 0),
			wfrp_stats.get("W", 0),
			wfrp_stats.get("Mag", 0),
			stats.get("might", 0),
			stats.get("agility", 0),
			stats.get("wits", 0),
			stats.get("spirit", 0),
			stats.get("endurance", 0)
		]
	if skills_lbl:
		skills_lbl.text = "Skills  %s" % _compact_list_text(h.get("skill_names", []), 6)
	if trappings_lbl:
		trappings_lbl.text = "Starting trappings  %s" % _compact_list_text(h.get("starting_trappings", []), 6)
	if talents_lbl:
		talents_lbl.text = "Starting talents  %s" % _compact_list_text(h.get("starting_talents", []), 5)
	if tags_lbl:
		tags_lbl.text = "Traits  %s" % _compact_list_text(h.get("career_tags", []), 6)
	if desc_lbl:
		desc_lbl.text = h.get("career_description", "")
	if quest_lbl:
		var current_quest: Dictionary = h.get("current_quest", {})
		if current_quest.is_empty():
			quest_lbl.text = "Current quest  None"
		else:
			quest_lbl.text = "Current quest  %s  •  Party %d" % [current_quest.get("name", "?"), int(h.get("quest_party_size", 1))]
	_refresh_details_visibility()

func _hide_hero_panel() -> void:
	_selected_hero_id = -1
	_selected_entity_kind = ""
	_refresh_roster_strip()
	_refresh_context_upgrade_button()
	_refresh_building_action_button()
	_refresh_output_action_button()
	_apply_panel_state()

func _show_building_panel(building_id: int) -> void:
	if not GameState.buildings.has(building_id):
		return
	_selected_hero_id = -1
	_selected_entity_kind = "building"
	_selected_building_id = building_id
	_right_panel_collapsed = false
	_refresh_building_panel(building_id)
	_refresh_roster_strip()
	_refresh_context_upgrade_button()
	_refresh_output_action_button()
	_apply_panel_state()
	_pulse_control(get_node_or_null("UILayer/RightPanel/VBox/SummaryCard") as CanvasItem, "inspector_summary")

func _refresh_building_panel(building_id: int) -> void:
	var building: Dictionary = GameState.buildings.get(building_id, {})
	if building.is_empty():
		return
	var portrait := get_node_or_null("UILayer/RightPanel/VBox/SummaryCard/SummaryRow/PortraitPanel/PortraitMargin/PortraitTexture")
	var title_lbl := get_node_or_null("UILayer/RightPanel/VBox/Header/EntityTitle")
	var lead_lbl := get_node_or_null("UILayer/RightPanel/VBox/InspectorLeadLabel")
	var name_lbl := get_node_or_null("UILayer/RightPanel/VBox/SummaryCard/SummaryRow/SummaryText/NameLabel")
	var career_lbl := get_node_or_null("UILayer/RightPanel/VBox/SummaryCard/SummaryRow/SummaryText/CareerLabel")
	var state_lbl := get_node_or_null("UILayer/RightPanel/VBox/SummaryCard/SummaryRow/SummaryText/StateLabel")
	var summary_lbl := get_node_or_null("UILayer/RightPanel/VBox/SummaryCard/SummaryRow/SummaryText/SummaryMetaLabel")
	var level_lbl := get_node_or_null("UILayer/RightPanel/VBox/LevelLabel")
	var health_bar := get_node_or_null("UILayer/RightPanel/VBox/HealthBar")
	var health_lbl := get_node_or_null("UILayer/RightPanel/VBox/HealthLabel")
	var xp_bar := get_node_or_null("UILayer/RightPanel/VBox/XpBar")
	var primary_lbl := get_node_or_null("UILayer/RightPanel/VBox/PrimaryFactsCard/PrimaryFactsLabel")
	var action_lbl := get_node_or_null("UILayer/RightPanel/VBox/ActionCard/ActionVBox/ActionStateLabel")
	var output_lbl := get_node_or_null("UILayer/RightPanel/VBox/ActionCard/ActionVBox/OutputStateLabel")
	var gold_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/HeroGoldLabel")
	var bias_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/BiasLabel")
	var stats_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/StatsLabel")
	var skills_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/SkillsLabel")
	var tags_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/TagsLabel")
	var desc_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/DescriptionLabel")
	var quest_lbl := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails/CurrentQuestLabel")
	var building_type: String = building.get("type", "")
	var data: Dictionary = DataLoader.buildings_by_id.get(building_type, {})
	var level: int = int(building.get("level", 1))
	var levels: Array = data.get("levels", [])
	var level_name: String = ""
	if level > 0 and level <= levels.size():
		level_name = str(levels[level - 1].get("name", ""))
	if title_lbl:
		title_lbl.text = "Building Sheet"
	if lead_lbl:
		lead_lbl.text = "Current work, town role, and the next unlock."
	if portrait:
		portrait.texture = load(BUILDING_ICONS.get(building_type, ""))
	if name_lbl:
		name_lbl.text = data.get("name", building_type.capitalize())
		name_lbl.set("theme_override_fonts/font", _load_runtime_font(FONT_HEADING_PATH))
		name_lbl.set("theme_override_font_sizes/font_size", 21)
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if career_lbl:
		career_lbl.text = "Town anchor"
		career_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		career_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if state_lbl:
		state_lbl.text = "%s" % _building_mode_name(building)
		state_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		state_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if summary_lbl:
		summary_lbl.text = "%s  •  Base %dg" % [
			level_name if level_name != "" else "Base",
			int(data.get("base_cost", 0))
		]
		summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if health_bar:
		health_bar.max_value = max(1, levels.size())
		health_bar.value = level
		health_bar.visible = true
	if xp_bar:
		xp_bar.visible = false
	if level_lbl:
		level_lbl.text = "Level %d / %d  •  %s" % [level, max(1, levels.size()), level_name]
	if health_lbl:
		health_lbl.text = "Footprint  %s" % str(data.get("footprint", [1, 1]))
	if primary_lbl:
		primary_lbl.text = "Current role  %s\nNext unlock  %s" % [
			data.get("description", ""),
			_next_upgrade_summary(building)
		]
		primary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if action_lbl:
		action_lbl.visible = true
		action_lbl.text = _building_action_summary(building)
		action_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if output_lbl:
		output_lbl.visible = true
		output_lbl.text = _building_output_summary(building)
		output_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if gold_lbl:
		gold_lbl.text = "Base cost  %dg" % int(data.get("base_cost", 0))
	if bias_lbl:
		bias_lbl.text = "Site  %.0f, %.0f\nStored output  %d" % [float(building.get("position", {}).get("x", 0.0)), float(building.get("position", {}).get("z", 0.0)), int(building.get("output_stock", 0))]
	if stats_lbl:
		stats_lbl.text = "Upgrade path  %s" % ("Available" if level < levels.size() else "Maxed")
	if skills_lbl:
		skills_lbl.text = "Output order  %s" % _building_output_action_name(building_type)
	if tags_lbl:
		var effect_names: Array = []
		if level > 0 and level <= levels.size():
			effect_names = data.get("levels", [])[level - 1].get("effects", {}).keys()
		tags_lbl.text = "Effects  %s" % _compact_list_text(effect_names, 5)
	if quest_lbl:
		quest_lbl.text = "Current use  Supports quests and town services"
	if desc_lbl:
		desc_lbl.text = data.get("description", "")
	_refresh_building_action_button()
	_refresh_output_action_button()
	_refresh_details_visibility()

func _remove_selected_building() -> void:
	if _selected_building_id < 0:
		return
	sim.remove_building(_selected_building_id)
	_set_status("Removed building")
	_selected_building_id = -1

func _toggle_pause_menu() -> void:
	if _pause_menu != null:
		_pause_menu.queue_free()
		_pause_menu = null
		get_tree().paused = false
		_refresh_top_bar()
		return
	var packed: PackedScene = load("res://scenes/ui/PauseMenu.tscn")
	if packed == null:
		return
	_pause_menu = packed.instantiate()
	_pause_menu.tree_exited.connect(func() -> void:
		_pause_menu = null
		_refresh_top_bar()
	)
	add_child(_pause_menu)
	_refresh_top_bar()

func _on_hero_state_changed(hero_id: int, _new_state: String) -> void:
	if hero_id == _selected_hero_id:
		_refresh_hero_panel(hero_id)
	_refresh_roster_strip()
	_refresh_quest_ui()

func _on_hero_spawned(_hero: Dictionary) -> void:
	_refresh_roster_strip()
	_refresh_top_bar()

func _on_hero_removed(hero_id: int) -> void:
	if hero_id == _selected_hero_id:
		_hide_hero_panel()
	_refresh_roster_strip()
	_refresh_quest_ui()

func _on_build_tavern_pressed() -> void:
	if GameState.get_building_count("tavern") > 0:
		return
	build_manager.start_placement("tavern")

func _on_build_weapons_shop_pressed() -> void:
	if GameState.get_building_count("weapons_shop") > 0:
		return
	build_manager.start_placement("weapons_shop")

func _on_build_temple_pressed() -> void:
	if GameState.get_building_count("temple") > 0:
		return
	build_manager.start_placement("temple")

func _on_gold_changed(amount: int) -> void:
	var lbl := get_node_or_null("UILayer/TopBar/TopBarRow/GoldLabel")
	if lbl:
		lbl.text = "Gold: %d" % amount
	_refresh_build_ui()
	_refresh_top_bar()

func _on_building_state_changed(_building: Dictionary) -> void:
	_refresh_build_ui()
	_refresh_quest_ui()

func _on_building_removed(_building_id: int) -> void:
	if _building_id == _selected_building_id:
		_selected_building_id = -1
		_selected_entity_kind = ""
	_refresh_building_action_button()
	_refresh_output_action_button()
	_apply_panel_state()
	_refresh_build_ui()
	_refresh_quest_ui()

func _on_building_upgraded(_building_id: int, _new_level: int) -> void:
	if _building_id == _selected_building_id and GameState.buildings.has(_building_id):
		_refresh_building_panel(_building_id)
	_refresh_build_ui()
	_refresh_quest_ui()

func _on_building_action_changed(building_id: int, _action: String) -> void:
	if building_id == _selected_building_id and GameState.buildings.has(building_id):
		_refresh_building_panel(building_id)
	_refresh_build_ui()
	_refresh_quest_ui()

func _on_state_reloaded() -> void:
	_hide_hero_panel()
	_selected_building_id = -1
	build_manager.cancel_placement()
	_refresh_build_ui()
	_refresh_quest_ui()
	_refresh_roster_strip()
	_on_gold_changed(GameState.gold)
	_set_status("Loaded save from user://questtown_save.json")
	_refresh_building_action_button()
	_refresh_output_action_button()
	_refresh_details_visibility()

func _upgrade_building_type(building_type: String) -> void:
	var building := _get_building_of_type(building_type)
	if building.is_empty():
		return
	sim.upgrade_building(int(building["id"]))

func _get_building_of_type(building_type: String) -> Dictionary:
	for building in GameState.buildings.values():
		if building["type"] == building_type:
			return building
	return {}

func _refresh_build_ui() -> void:
	_refresh_build_button("tavern", "UILayer/LeftPanel/VBox/BuildRail/BuildButton")
	_refresh_build_button("weapons_shop", "UILayer/LeftPanel/VBox/BuildRail/BuildWeaponsShopButton")
	_refresh_build_button("temple", "UILayer/LeftPanel/VBox/BuildRail/BuildTempleButton")
	_refresh_context_upgrade_button()
	_refresh_building_action_button()
	_refresh_output_action_button()

func _refresh_build_button(building_type: String, path: String) -> void:
	var button := get_node_or_null(path)
	if button == null:
		return
	var data: Dictionary = DataLoader.buildings_by_id.get(building_type, {})
	var building_name: String = data.get("name", building_type.capitalize())
	var base_cost: int = int(data.get("base_cost", data.get("cost", 0)))
	button.text = "Build %s  (%dg)" % [building_name, base_cost]
	button.icon = load(BUILDING_ICONS.get(building_type, ""))
	button.disabled = GameState.get_building_count(building_type) > 0 or GameState.gold < base_cost

func _refresh_context_upgrade_button() -> void:
	var button := get_node_or_null("UILayer/LeftPanel/VBox/ContextUpgradeButton")
	if button == null:
		return
	if _selected_building_id < 0 or not GameState.buildings.has(_selected_building_id):
		button.visible = false
		return
	var building: Dictionary = GameState.buildings[_selected_building_id]
	var building_type: String = building.get("type", "")
	var data: Dictionary = DataLoader.buildings_by_id.get(building_type, {})
	var building_name: String = data.get("name", building_type.capitalize())
	if building.is_empty():
		button.visible = false
		return

	var current_level: int = int(building.get("level", 1))
	var levels: Array = data.get("levels", [])
	var current_action: String = building.get("current_action", "idle")
	if current_level >= levels.size():
		button.visible = true
		button.text = "%s Max Level" % building_name
		button.disabled = true
		return
	if current_action != "idle":
		var progress_ratio := _action_progress_ratio(building)
		button.visible = true
		button.text = "Busy: %s  (%d%%)" % [_building_mode_name(building), int(round(progress_ratio * 100.0))]
		button.disabled = true
		return

	var next_level: Dictionary = levels[current_level]
	var next_cost: int = int(next_level.get("upgrade_cost", 0))
	button.visible = true
	button.text = "Start %s Upgrade  (L%d -> L%d, %dg)" % [building_name, current_level, current_level + 1, next_cost]
	button.disabled = GameState.gold < next_cost

func _refresh_building_action_button() -> void:
	var button := get_node_or_null("UILayer/RightPanel/VBox/ActionCard/ActionVBox/ActionButtons/BuildingActionButton")
	if button == null:
		return
	if _selected_entity_kind != "building" or _selected_building_id < 0 or not GameState.buildings.has(_selected_building_id):
		button.visible = false
		return
	var building: Dictionary = GameState.buildings[_selected_building_id]
	var building_type: String = building.get("type", "")
	var data: Dictionary = DataLoader.buildings_by_id.get(building_type, {})
	var building_name: String = data.get("name", building_type.capitalize())
	var current_level: int = int(building.get("level", 1))
	var levels: Array = data.get("levels", [])
	var current_action: String = building.get("current_action", "idle")
	button.visible = true
	if current_level >= levels.size():
		button.text = "%s Max Level" % building_name
		button.disabled = true
		return
	if current_action != "idle":
		var progress_ratio := _action_progress_ratio(building)
		button.text = "Busy: %s  (%d%%)" % [_building_mode_name(building), int(round(progress_ratio * 100.0))]
		button.disabled = true
		return
	var next_level: Dictionary = levels[current_level]
	var next_cost: int = int(next_level.get("upgrade_cost", 0))
	button.text = "Start Upgrade  (L%d -> L%d, %dg)" % [current_level, current_level + 1, next_cost]
	button.disabled = GameState.gold < next_cost

func _refresh_output_action_button() -> void:
	var button := get_node_or_null("UILayer/RightPanel/VBox/ActionCard/ActionVBox/ActionButtons/OutputActionButton")
	if button == null:
		return
	if _selected_entity_kind != "building" or _selected_building_id < 0 or not GameState.buildings.has(_selected_building_id):
		button.visible = false
		return
	var building: Dictionary = GameState.buildings[_selected_building_id]
	var building_type: String = building.get("type", "")
	var data: Dictionary = DataLoader.buildings_by_id.get(building_type, {})
	var building_name: String = data.get("name", building_type.capitalize())
	var current_action: String = building.get("current_action", "idle")
	var output_stock: int = int(building.get("output_stock", 0))
	var output_cap: int = 1 + int(building.get("level", 1))
	button.visible = true
	if current_action == "upgrading":
		button.text = "Output Paused During Upgrade"
		button.disabled = true
		return
	if current_action == "output":
		var progress_ratio := _action_progress_ratio(building)
		button.text = "Producing  (%d%%)" % int(round(progress_ratio * 100.0))
		button.disabled = true
		return
	if output_stock >= output_cap:
		button.text = "%s Output Full" % building_name
		button.disabled = true
		return
	button.text = "%s" % _building_output_action_name(building_type)
	button.disabled = false

func _setup_quest_menu() -> void:
	_quest_filter_boxes.clear()
	var summary_label := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestListColumn/QuestFilterSummaryLabel")
	if summary_label:
		summary_label.text = "Available Quests: 0"
	var controls := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestListColumn/QuestFilterControls")
	if controls:
		controls.visible = false
	var list := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestListColumn/QuestFilterList")
	if list:
		list.visible = false
	_refresh_quest_ui()

func _refresh_quest_ui() -> void:
	var summary_label := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestListColumn/QuestFilterSummaryLabel")
	if summary_label:
		var urgent_count := 0
		for quest_offer: Dictionary in GameState.quests:
			if bool(quest_offer.get("urgent", false)):
				urgent_count += 1
		var urgent_text := ""
		if urgent_count > 0:
			urgent_text = "  %d urgent." % urgent_count
		summary_label.text = "%d contracts on the board.%s Select one to inspect fit, risk, and time left." % [GameState.quests.size(), urgent_text]

	_refresh_quest_offer_cards()
	_refresh_selected_quest_detail()

	var active_summary := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestLowerRow/ActiveQuestCard/ActiveQuestVBox/ActiveQuestSummaryLabel")
	var active_list := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestLowerRow/ActiveQuestCard/ActiveQuestVBox/ActiveQuestListLabel")
	var completed_title := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestLowerRow/CompletedQuestCard/CompletedQuestVBox/CompletedQuestTitle")
	var completed_list := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestLowerRow/CompletedQuestCard/CompletedQuestVBox/CompletedQuestListLabel")
	if active_summary == null or active_list == null:
		return

	var departing_count := 0
	var on_quest_count := 0
	var returning_count := 0
	var active_lines: Array = []
	for hero: Dictionary in GameState.heroes.values():
		var hero_state: String = hero.get("state", "")
		var current_quest: Dictionary = hero.get("current_quest", {})
		if current_quest.is_empty():
			continue
		if hero_state == "departing_quest":
			departing_count += 1
		elif hero_state == "on_quest":
			on_quest_count += 1
		elif hero_state == "returning":
			returning_count += 1
		else:
			continue
		active_lines.append("%s: %s (%s)" % [
			hero.get("name", "?"),
			current_quest.get("name", "?"),
			_format_quest_state(hero_state)
		])

	if active_lines.is_empty():
		active_summary.text = "No expeditions are currently in the field."
		active_list.text = "No active expeditions."
	else:
		active_summary.text = "Departing %d   In the field %d   Returning %d" % [
			departing_count,
			on_quest_count,
			returning_count
		]
		active_list.text = "\n".join(active_lines)

	if completed_title == null or completed_list == null:
		return
	completed_title.text = "Recent Completed Quests"
	if GameState.completed_quests.is_empty():
		completed_list.text = "No quests have been completed yet."
		return
	var completed_lines: Array = []
	for entry in GameState.completed_quests.slice(max(0, GameState.completed_quests.size() - 5)):
		completed_lines.append("%s: %s (%s)" % [
			entry.get("hero_name", "?"),
			entry.get("quest_name", "?"),
			"success" if bool(entry.get("success", false)) else "failed"
		])
	completed_list.text = "\n".join(completed_lines)

func _refresh_quest_offer_cards() -> void:
	var list := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestListColumn/QuestOffersList")
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()
	if _selected_quest_id == "" and not GameState.quests.is_empty():
		_selected_quest_id = str(GameState.quests[0].get("offer_id", ""))
	var has_selected := false
	for quest_offer: Dictionary in GameState.quests:
		var offer_id := str(quest_offer.get("offer_id", ""))
		if offer_id == "":
			continue
		if offer_id == _selected_quest_id:
			has_selected = true
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 98)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var preview: Dictionary = sim.get_quest_acceptance_preview(int(quest_offer.get("offer_id", -1)))
		var state_text := "Ready to launch" if bool(preview.get("can_accept", false)) else str(preview.get("reason", "Need party"))
		var urgent: bool = bool(quest_offer.get("urgent", false))
		var title_prefix := "Urgent  " if urgent else ""
		var urgency_line := "%s  %s" % [_quest_expiry_text(quest_offer), state_text]
		button.text = "%s%s\nParty %d  D%d  %dg  %dxp\n%s" % [
			title_prefix,
			quest_offer.get("name", offer_id),
			int(quest_offer.get("party_size", 3)),
			int(quest_offer.get("difficulty", 1)),
			int(quest_offer.get("gold_reward", 0)),
			int(quest_offer.get("xp_reward", 0)),
			urgency_line
		]
		_apply_button_theme(button, "offer", offer_id == _selected_quest_id)
		var quest_type := str(quest_offer.get("type", ""))
		var quest_icon_path := str(QUEST_TYPE_ICONS.get(quest_type, ICON_BOOK_PATH))
		button.icon = _load_runtime_texture(quest_icon_path) if bool(preview.get("can_accept", false)) else _load_runtime_texture(ICON_SKULL_PATH)
		if urgent:
			button.modulate = Color(1.0, 0.97, 0.9, 1.0)
		var local_offer_id := offer_id
		button.pressed.connect(func() -> void:
			_selected_quest_id = local_offer_id
			_refresh_quest_ui()
			_pulse_control(get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestDetailHeader") as CanvasItem, "quest_detail_focus", Vector2(1.015, 1.015))
		)
		_wire_button_sfx(button)
		list.add_child(button)
	if GameState.quests.is_empty():
		var empty := Label.new()
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.text = "No quests are available. Produce rumours at the Inn to discover work."
		_apply_label_role(empty, "body", true)
		list.add_child(empty)
	elif not has_selected:
		_selected_quest_id = str(GameState.quests[0].get("offer_id", ""))

func _refresh_selected_quest_detail() -> void:
	var detail_title := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestDetailHeader/QuestDetailHeaderVBox/QuestDetailTitleLabel")
	var detail_summary := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestDetailHeader/QuestDetailHeaderVBox/QuestDetailSummaryLabel")
	var detail_kicker := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestDetailHeader/QuestDetailHeaderVBox/QuestDetailKicker")
	var reward_label := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestMetaCard/QuestMetaVBox/QuestRewardLabel")
	var xp_label := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestMetaCard/QuestMetaVBox/QuestXpLabel")
	var risk_label := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestMetaCard/QuestMetaVBox/QuestRiskLabel")
	var requirement_label := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestMetaCard/QuestMetaVBox/QuestRequirementLabel")
	var suitability_label := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestSuitabilityCard/QuestSuitabilityLabel")
	var action_button := get_node_or_null("UILayer/QuestDrawer/QuestVBox/QuestContent/QuestDetailColumn/QuestActionButton")
	var quest := _get_quest_offer(_selected_quest_id)
	if quest.is_empty():
		if detail_title:
			detail_title.text = "No quest available"
		if detail_summary:
			detail_summary.text = "Produce rumours at the Inn before the board can offer expeditions."
		if detail_kicker:
			detail_kicker.text = "Mission Board"
		if action_button:
			action_button.disabled = true
			action_button.text = "Accept Quest"
		return
	var template_id := str(quest.get("template_id", ""))
	var preview: Dictionary = sim.get_quest_acceptance_preview(int(quest.get("offer_id", -1)))
	if detail_kicker:
		detail_kicker.text = "Urgent Contract" if bool(quest.get("urgent", false)) else "Contract Board"
	if detail_title:
		detail_title.text = str(quest.get("name", template_id))
	if detail_summary:
		detail_summary.text = "%s\n%s" % [_quest_summary_text(quest), _quest_expiry_text(quest)]
	if reward_label:
		reward_label.text = "Reward  %dg treasury flow through adventurers" % int(quest.get("gold_reward", 0))
	if xp_label:
		xp_label.text = "Experience  %dxp to the party" % int(quest.get("xp_reward", 0))
	if risk_label:
		risk_label.text = "Risk  %s   Party %d   %s" % [_risk_label(int(quest.get("risk_level", 1))), int(quest.get("party_size", 3)), _quest_expiry_short_label(quest)]
	if requirement_label:
		requirement_label.text = "Requirements  %s" % _quest_requirements_text(quest)
	if suitability_label:
		suitability_label.text = _quest_suitability_text(quest, preview)
	if action_button:
		action_button.disabled = not bool(preview.get("can_accept", false))
		action_button.text = ("Accept Urgent Quest" if bool(quest.get("urgent", false)) else "Accept Quest") if bool(preview.get("can_accept", false)) else str(preview.get("reason", "Need party"))
		action_button.icon = _load_runtime_texture(ICON_SWORD_PATH) if bool(preview.get("can_accept", false)) else _load_runtime_texture(ICON_SHIELD_PATH)

func _get_quest_offer(offer_id: String) -> Dictionary:
	for quest: Dictionary in GameState.quests:
		if str(quest.get("offer_id", "")) == offer_id:
			return quest
	return {}

func _quest_requirements_text(quest: Dictionary) -> String:
	var parts: Array[String] = []
	var tavern_level := int(quest.get("min_tavern_level", 0))
	var store_level := int(quest.get("min_weapons_shop_level", 0))
	var temple_level := int(quest.get("min_temple_level", 0))
	if tavern_level > 0:
		parts.append("Inn L%d" % tavern_level)
	if store_level > 0:
		parts.append("General Store L%d" % store_level)
	if temple_level > 0:
		parts.append("Temple L%d" % temple_level)
	if parts.is_empty():
		return "No special building unlocks required"
	return ", ".join(parts)

func _quest_summary_text(quest: Dictionary) -> String:
	match str(quest.get("template_id", "")):
		"clear_rats_cellar":
			return "A cellar job with decent coin and a fair chance of scratches. Strong fit for Warrior or Rogue."
		"gather_rare_herbs":
			return "A careful forage run that benefits from preparation and sharper wits. Best suited to Wizard or Rogue."
		"investigate_strange_lights":
			return "A strange shrine rumour that asks for nerve, insight, and temple backing before the town feels safe sending people."
		_:
			return "A town opportunity for autonomous adventurers."

func _quest_suitability_text(quest: Dictionary, preview: Dictionary) -> String:
	var names: Array = []
	for career_id in quest.get("preferred_careers", []):
		match str(career_id):
			"mercenary":
				names.append("Warrior")
			"apprentice_wizard":
				names.append("Wizard")
			"thief":
				names.append("Rogue")
			_:
				names.append(str(career_id).replace("_", " ").capitalize())
	var preview_names: Array = preview.get("party_names", [])
	var party_line := "Ready party: %s" % ", ".join(preview_names) if not preview_names.is_empty() else "Launch status: %s" % str(preview.get("reason", "Waiting for a ready party"))
	return "Likely interested adventurers: %s\nRecommended party size: %d\nResolution focus: %s\n%s" % [
		", ".join(names),
		int(quest.get("party_size", 3)),
		str(quest.get("resolution_stat", "might")).capitalize(),
		party_line
	]

func _quest_expiry_minutes(expiry_ticks: int) -> float:
	return max(0.0, float(expiry_ticks) / 60.0)

func _quest_expiry_text(quest: Dictionary) -> String:
	var expiry_ticks := int(quest.get("expiry_ticks_remaining", 0))
	var minutes_left := _quest_expiry_minutes(expiry_ticks)
	if bool(quest.get("urgent", false)):
		return "Urgent offer. Expires in %.1f in-game minutes." % minutes_left
	return "Time left: %.1f in-game minutes." % minutes_left

func _quest_expiry_short_label(quest: Dictionary) -> String:
	var minutes_left := _quest_expiry_minutes(int(quest.get("expiry_ticks_remaining", 0)))
	return "Expires in %.1fm" % minutes_left

func _risk_label(risk_level: int) -> String:
	match risk_level:
		0:
			return "very low"
		1:
			return "low"
		2:
			return "moderate"
		_:
			return "high"

func _accept_selected_quest() -> void:
	if _selected_quest_id == "":
		return
	var quest := _get_quest_offer(_selected_quest_id)
	if quest.is_empty():
		return
	var result: Dictionary = sim.accept_quest(int(quest.get("offer_id", -1)))
	if result.is_empty():
		_set_status("No ready party can take that quest yet")
	else:
		_set_status("Accepted %s for %d adventurers" % [result.get("quest_name", "quest"), int(result.get("party_size", 0))])
	_refresh_quest_ui()

func _set_all_quest_filters(enabled: bool) -> void:
	for quest: Dictionary in DataLoader.quests:
		GameState.set_quest_enabled(quest.get("id", ""), enabled)

func _format_quest_state(state: String) -> String:
	match state:
		"departing_quest":
			return "leaving town"
		"on_quest":
			return "off-screen"
		"returning":
			return "heading home"
		_:
			return state.replace("_", " ")

func _save_world() -> void:
	var saved: bool = sim.save_world()
	_set_status("Saved to user://questtown_save.json" if saved else "Save failed")

func _load_world() -> void:
	var loaded: bool = sim.load_world()
	if not loaded:
		_set_status("No save file found")

func _set_status(message: String) -> void:
	var status_label := get_node_or_null("UILayer/LeftPanel/VBox/StatusCard/StatusLabel")
	if status_label:
		status_label.text = message
		_highlight_status_card()

func _toggle_details_expanded() -> void:
	_details_expanded = not _details_expanded
	_refresh_details_visibility()

func _refresh_details_visibility() -> void:
	var extra := get_node_or_null("UILayer/RightPanel/VBox/ExtraDetails")
	if extra:
		_animate_details_visibility(extra, _details_expanded)
	var button := get_node_or_null("UILayer/RightPanel/VBox/MoreDetailsButton")
	if button:
		button.text = "Less Details" if _details_expanded else "More Details"
	var building_action_btn := get_node_or_null("UILayer/RightPanel/VBox/ActionCard/ActionVBox/ActionButtons/BuildingActionButton")
	if building_action_btn:
		building_action_btn.visible = _selected_entity_kind == "building" and GameState.buildings.has(_selected_building_id)
	var output_action_btn := get_node_or_null("UILayer/RightPanel/VBox/ActionCard/ActionVBox/ActionButtons/OutputActionButton")
	if output_action_btn:
		output_action_btn.visible = _selected_entity_kind == "building" and GameState.buildings.has(_selected_building_id)

func _upgrade_selected_building() -> void:
	_start_selected_building_upgrade()

func _start_selected_building_upgrade() -> void:
	if _selected_building_id < 0:
		return
	sim.start_building_upgrade(_selected_building_id)
	if _selected_entity_kind == "building":
		_refresh_building_panel(_selected_building_id)
	_refresh_context_upgrade_button()
	_refresh_building_action_button()
	_refresh_output_action_button()

func _set_selected_building_output_mode() -> void:
	if _selected_building_id < 0:
		return
	var result: Dictionary = sim.set_building_output_mode(_selected_building_id)
	if result.is_empty():
		_set_status("That building cannot produce output right now")
	if _selected_entity_kind == "building":
		_refresh_building_panel(_selected_building_id)
	_refresh_context_upgrade_button()
	_refresh_building_action_button()
	_refresh_output_action_button()

func _building_action_summary(building: Dictionary) -> String:
	var current_action: String = building.get("current_action", "idle")
	var progress_ratio := _action_progress_ratio(building)
	if current_action == "upgrading":
		return "Current Action: Upgrading (%d%% complete)" % int(round(progress_ratio * 100.0))
	if current_action == "output":
		return "Current Action: Producing one output batch (%d%% complete)" % int(round(progress_ratio * 100.0))
	return "Current Action: Waiting for orders"

func _building_output_summary(building: Dictionary) -> String:
	var building_type: String = building.get("type", "")
	var stock: int = int(building.get("output_stock", 0))
	match building_type:
		"tavern":
			return "Rumours %d. Manual batch: each click gathers 1 fresh lead." % stock
		"weapons_shop":
			return "Supplies %d. Manual batch: each click stocks 1 supply bundle." % stock
		"temple":
			return "Healing charges %d. Manual batch: each click prepares 1 recovery use." % stock
		_:
			return "Stored Output: %d" % stock

func _action_progress_ratio(building: Dictionary) -> float:
	var required_ticks: int = max(1, int(building.get("action_required_ticks", 0)))
	var progress_ticks: int = clamp(int(building.get("action_progress_ticks", 0)), 0, required_ticks)
	return float(progress_ticks) / float(required_ticks)

func _building_level_of_type(building_type: String) -> int:
	var building := _get_building_of_type(building_type)
	if building.is_empty():
		return 0
	return int(building.get("level", 1))

func _building_mode_name(building: Dictionary) -> String:
	var current_action: String = str(building.get("current_action", "idle"))
	if current_action == "upgrading":
		return "Upgrading"
	if current_action == "output":
		return "Producing"
	return "Idle"

func _building_output_action_name(building_type: String) -> String:
	match building_type:
		"tavern":
			return "Gather Rumours"
		"weapons_shop":
			return "Stock Supplies"
		"temple":
			return "Prepare Healing"
		_:
			return "Produce Output"

func _next_upgrade_summary(building: Dictionary) -> String:
	var building_type: String = str(building.get("type", ""))
	var data: Dictionary = DataLoader.buildings_by_id.get(building_type, {})
	var current_level: int = int(building.get("level", 1))
	var levels: Array = data.get("levels", [])
	if current_level >= levels.size():
		return "Already at the highest tier"
	var next_level: Dictionary = levels[current_level]
	var next_name := str(next_level.get("name", "Next tier"))
	var effect_keys: Array = next_level.get("effects", {}).keys()
	if effect_keys.is_empty():
		return "%s for %dg" % [next_name, int(next_level.get("upgrade_cost", 0))]
	return "%s unlocks %s for %dg" % [
		next_name,
		", ".join(effect_keys),
		int(next_level.get("upgrade_cost", 0))
	]

func _hero_activity_summary(hero: Dictionary) -> String:
	var state: String = str(hero.get("state", "idling"))
	match state:
		"walking_to_service":
			var pending: Dictionary = hero.get("pending_service", {})
			var building_type: String = str(pending.get("building_type", "building")).replace("_", " ")
			var service_name: String = str(pending.get("service_type", "service"))
			return "Walking to %s for %s" % [building_type, service_name]
		"using_service":
			var pending: Dictionary = hero.get("pending_service", {})
			return "Using %s at %s" % [
				str(pending.get("service_type", "service")),
				str(pending.get("building_type", "building")).replace("_", " ")
			]
		_:
			return "No active quest"

func _toggle_left_panel() -> void:
	_left_panel_collapsed = not _left_panel_collapsed
	_apply_panel_state()

func _toggle_right_panel() -> void:
	_right_panel_collapsed = not _right_panel_collapsed
	_apply_panel_state()

func _toggle_quest_drawer() -> void:
	var drawer := get_node_or_null("UILayer/QuestDrawer")
	var scrim := get_node_or_null("UILayer/QuestScrim")
	if drawer == null:
		return
	var opening: bool = not drawer.visible
	if opening:
		drawer.visible = true
		drawer.modulate.a = 0.0
		drawer.scale = Vector2(0.985, 0.985)
		if scrim:
			scrim.visible = true
			scrim.modulate.a = 0.0
		var tween := create_tween()
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(drawer, "modulate:a", 1.0, 0.16)
		tween.tween_property(drawer, "scale", Vector2.ONE, 0.20)
		if scrim:
			tween.tween_property(scrim, "modulate:a", 1.0, 0.14)
		_refresh_quest_ui()
	else:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_IN)
		tween.tween_property(drawer, "modulate:a", 0.0, 0.14)
		tween.tween_property(drawer, "scale", Vector2(0.99, 0.99), 0.14)
		if scrim:
			tween.tween_property(scrim, "modulate:a", 0.0, 0.12)
		tween.finished.connect(func() -> void:
			drawer.visible = false
			drawer.modulate.a = 1.0
			drawer.scale = Vector2.ONE
			if scrim:
				scrim.visible = false
				scrim.modulate.a = 1.0
		)

func _is_quest_drawer_open() -> bool:
	var drawer := get_node_or_null("UILayer/QuestDrawer")
	return drawer != null and drawer.visible

func _apply_panel_state() -> void:
	var left_panel := get_node_or_null("UILayer/LeftPanel") as Control
	var left_tab := get_node_or_null("UILayer/LeftPanelTab")
	if left_panel:
		_animate_panel_slide(left_panel, not _left_panel_collapsed, Vector2(-18.0, 0.0), "left_panel")
	if left_tab:
		left_tab.visible = _left_panel_collapsed
	var right_panel := get_node_or_null("UILayer/RightPanel") as Control
	var right_tab := get_node_or_null("UILayer/RightPanelTab")
	if right_panel:
		_animate_panel_slide(right_panel, (not _right_panel_collapsed) and (_selected_entity_kind != ""), Vector2(18.0, 0.0), "right_panel")
	if right_tab:
		right_tab.visible = _right_panel_collapsed
	_fit_ui_to_viewport()

func _fit_ui_to_viewport() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var margin: float = 28.0
	var left_panel := get_node_or_null("UILayer/LeftPanel")
	if left_panel:
		var left_width: float = clamp(viewport_size.x * 0.135, 188.0, 214.0)
		left_panel.offset_left = margin
		left_panel.offset_right = margin + left_width
		left_panel.offset_top = 94.0
		left_panel.offset_bottom = -118.0
	var right_panel := get_node_or_null("UILayer/RightPanel")
	if right_panel:
		var desired_width: float = clamp(viewport_size.x * 0.158, 252.0, 300.0)
		right_panel.offset_left = -desired_width - margin - 10.0
		right_panel.offset_right = -margin - 10.0
		right_panel.offset_top = 94.0
		right_panel.offset_bottom = -118.0
		right_panel.clip_contents = true
	var right_tab := get_node_or_null("UILayer/RightPanelTab")
	if right_tab:
		right_tab.offset_left = -margin - 46.0
		right_tab.offset_right = -margin - 10.0
		right_tab.offset_top = 108.0
		right_tab.offset_bottom = 156.0
	var left_tab := get_node_or_null("UILayer/LeftPanelTab")
	if left_tab:
		left_tab.offset_left = margin
		left_tab.offset_right = margin + 36.0
		left_tab.offset_top = 108.0
		left_tab.offset_bottom = 156.0
	var roster_panel := get_node_or_null("UILayer/RosterPanel")
	if roster_panel:
		var roster_scale := 0.76 if _roster_expanded else 0.56
		var roster_width: float = clamp(viewport_size.x * roster_scale, 860.0, 1460.0)
		roster_panel.offset_left = -roster_width * 0.5
		roster_panel.offset_right = roster_width * 0.5
		roster_panel.offset_top = -132.0 if _roster_expanded else -108.0
		roster_panel.offset_bottom = -18.0
	var event_panel := get_node_or_null("UILayer/EventLogPanel")
	if event_panel:
		event_panel.offset_left = margin
		event_panel.offset_right = margin + (500.0 if _event_feed_expanded else 340.0)
		event_panel.offset_bottom = -18.0
		event_panel.offset_top = -172.0 if _event_feed_expanded else -88.0
	var quest_drawer := get_node_or_null("UILayer/QuestDrawer")
	if quest_drawer:
		quest_drawer.anchor_left = 0.09
		quest_drawer.anchor_top = 0.09
		quest_drawer.anchor_right = 0.91
		quest_drawer.anchor_bottom = 0.89
	_update_roster_controls()

func _toggle_event_feed(expanded: Variant = null) -> void:
	if expanded == null:
		_event_feed_expanded = not _event_feed_expanded
	else:
		_event_feed_expanded = bool(expanded)
	var panel := get_node_or_null("UILayer/EventLogPanel")
	if panel:
		panel.offset_top = -180.0 if _event_feed_expanded else -84.0
		panel.offset_right = 520.0 if _event_feed_expanded else 420.0
	var button := get_node_or_null("UILayer/EventLogPanel/VBox/Header/ExpandButton")
	if button:
		button.text = "Less" if _event_feed_expanded else "More"
	var event_log := get_node_or_null("UILayer/EventLogPanel")
	if event_log and event_log.has_method("set_compact_mode"):
		event_log.set_compact_mode(not _event_feed_expanded)
	if event_log is CanvasItem:
		_pulse_control(event_log as CanvasItem, "event_feed_pulse", Vector2(1.01, 1.01))

func _refresh_top_bar() -> void:
	var summary := get_node_or_null("UILayer/TopBar/TopBarRow/HeroSummaryLabel")
	if summary == null:
		return
	var gold_label := get_node_or_null("UILayer/TopBar/TopBarRow/GoldLabel")
	if gold_label:
		gold_label.text = "Treasury  %dg" % GameState.gold
	var subtitle := get_node_or_null("UILayer/TopBar/TopBarRow/TownTitleStack/TownSubtitleLabel")
	var active_expeditions := 0
	for hero in GameState.heroes.values():
		var state: String = hero.get("state", "")
		if state in ["departing_quest", "on_quest", "returning"]:
			active_expeditions += 1
	summary.text = "%d / 5 adventurers   %d expeditions   Zoom %.0f%%   %.0fx speed" % [
		GameState.heroes.size(),
		active_expeditions,
		100.0 * _get_camera_zoom_fraction(),
		Engine.time_scale
	]
	if subtitle:
		subtitle.text = "%d contracts live  •  %d buildings placed  •  inspect, prepare, then launch" % [
			GameState.quests.size(),
			GameState.buildings.size()
		]
	var quest_button := get_node_or_null("UILayer/TopBar/TopBarRow/QuestDrawerButton")
	if quest_button:
		quest_button.text = "Quest Board  (K)   %d" % GameState.quests.size()
	_refresh_speed_button_states()

func _refresh_speed_button_states() -> void:
	var speed1 := get_node_or_null("UILayer/TopBar/TopBarRow/Speed1Button")
	var speed2 := get_node_or_null("UILayer/TopBar/TopBarRow/Speed2Button")
	var speed3 := get_node_or_null("UILayer/TopBar/TopBarRow/Speed3Button")
	var pause_button := get_node_or_null("UILayer/TopBar/TopBarRow/PauseButton")
	_apply_button_theme(speed1, "chrome", is_equal_approx(Engine.time_scale, 1.0))
	_apply_button_theme(speed2, "chrome", is_equal_approx(Engine.time_scale, 2.0))
	_apply_button_theme(speed3, "chrome", is_equal_approx(Engine.time_scale, 3.0))
	_apply_button_theme(pause_button, "accent", get_tree().paused)
	if pause_button:
		pause_button.text = "Paused" if get_tree().paused else "Pause"

func _scroll_roster(delta: int) -> void:
	var scroll := get_node_or_null("UILayer/RosterPanel/RosterVBox/RosterStripScroll") as ScrollContainer
	var roster := get_node_or_null("UILayer/RosterPanel/RosterVBox/RosterStripScroll/RosterStrip") as HBoxContainer
	if scroll == null or roster == null:
		return
	var max_scroll: int = max(0, int(roster.size.x - scroll.size.x))
	scroll.scroll_horizontal = clamp(scroll.scroll_horizontal + delta, 0, max_scroll)
	_update_roster_controls()

func _toggle_roster_expanded() -> void:
	_roster_expanded = not _roster_expanded
	_fit_ui_to_viewport()
	_update_roster_controls()

func _update_roster_controls() -> void:
	var scroll := get_node_or_null("UILayer/RosterPanel/RosterVBox/RosterStripScroll") as ScrollContainer
	var roster := get_node_or_null("UILayer/RosterPanel/RosterVBox/RosterStripScroll/RosterStrip") as HBoxContainer
	var prev_button := get_node_or_null("UILayer/RosterPanel/RosterVBox/RosterPrevButton") as Button
	var next_button := get_node_or_null("UILayer/RosterPanel/RosterVBox/RosterNextButton") as Button
	var expand_button := get_node_or_null("UILayer/RosterPanel/RosterVBox/RosterExpandButton") as Button
	if scroll != null and roster != null:
		var max_scroll: int = max(0, int(roster.size.x - scroll.size.x))
		if prev_button:
			prev_button.visible = max_scroll > 0
			prev_button.disabled = scroll.scroll_horizontal <= 0
		if next_button:
			next_button.visible = max_scroll > 0
			next_button.disabled = scroll.scroll_horizontal >= max_scroll
	if expand_button:
		expand_button.text = "−" if _roster_expanded else "+"

func _refresh_roster_strip() -> void:
	var roster := get_node_or_null("UILayer/RosterPanel/RosterVBox/RosterStripScroll/RosterStrip")
	if roster == null:
		return
	for child in roster.get_children():
		child.queue_free()
	for hero_id in GameState.heroes.keys():
		var hero: Dictionary = GameState.heroes[hero_id]
		var hero_name := str(hero.get("name", "adventurer"))
		var button := Button.new()
		button.custom_minimum_size = Vector2(214, 56)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = ""
		button.clip_contents = true
		var local_hero_id := int(hero_id)
		_apply_button_theme(button, "roster", local_hero_id == _selected_hero_id)
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		button.add_child(row)

		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(28, 28)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture = load(HERO_PORTRAITS.get(str(hero.get("career_archetype", "commoner")).to_lower(), HERO_PORTRAITS["commoner"]))
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(portrait)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 1)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(info)

		var health_ratio := 0.0
		var max_health: int = max(1, int(hero.get("max_health", 1)))
		health_ratio = float(int(hero.get("health", max_health))) / float(max_health)
		var top_line := HBoxContainer.new()
		top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_line.add_theme_constant_override("separation", 6)
		info.add_child(top_line)

		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text = hero.get("name", "?")
		_apply_label_role(name_label, "body")
		name_label.set("theme_override_fonts/font", _load_runtime_font(FONT_HEADING_PATH))
		name_label.set("theme_override_font_sizes/font_size", 13)
		name_label.clip_text = true
		top_line.add_child(name_label)

		var hp_label := Label.new()
		hp_label.text = "HP %d/%d" % [
			int(hero.get("health", max_health)),
			max_health
		]
		_apply_label_role(hp_label, "meta")
		hp_label.set("theme_override_colors/font_color", UI_SUCCESS if health_ratio > 0.65 else UI_WARNING)
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		top_line.add_child(hp_label)

		var bottom_line := HBoxContainer.new()
		bottom_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bottom_line.add_theme_constant_override("separation", 6)
		info.add_child(bottom_line)

		var meta_label := Label.new()
		meta_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meta_label.text = "%s L%d" % [hero.get("career_role", hero.get("career", "?")), int(hero.get("level", 1))]
		_apply_label_role(meta_label, "meta")
		meta_label.clip_text = true
		bottom_line.add_child(meta_label)

		var state_label := Label.new()
		var wound_state := str(hero.get("wound_state", "healthy")).replace("_", " ")
		var short_state := _format_entity_state(str(hero.get("state", "idle")))
		state_label.text = wound_state if wound_state != "healthy" else short_state
		_apply_label_role(state_label, "meta")
		state_label.set("theme_override_colors/font_color", UI_ACCENT if wound_state != "healthy" else UI_TEXT_MUTED)
		state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bottom_line.add_child(state_label)

		button.pressed.connect(func() -> void:
			_show_hero_panel(local_hero_id)
			_set_status("Selected %s" % hero_name)
		)
		_wire_button_sfx(button)
		roster.add_child(button)
	await get_tree().process_frame
	_update_roster_controls()

func _set_time_scale(value: float) -> void:
	Engine.time_scale = value
	_refresh_top_bar()

func _open_options_menu() -> void:
	if menu_host == null or not menu_host.has_method("show_menu"):
		return
	var options: Control = menu_host.show_menu(OPTIONS_SCENE)
	if options != null:
		options.closed.connect(func() -> void:
			menu_host.close_menu()
			_refresh_top_bar()
		)

func _get_camera_zoom_fraction() -> float:
	if camera_controller == null:
		return 1.0
	var min_size := 8.0
	var max_size := 28.0
	var size_fraction := inverse_lerp(max_size, min_size, camera_controller.size)
	return clamp(size_fraction, 0.0, 1.0)

func prepare_snapshot_target(target: String) -> void:
	_left_panel_collapsed = false
	_right_panel_collapsed = true
	_event_feed_expanded = false
	_details_expanded = false
	_selected_entity_kind = ""
	_selected_hero_id = -1
	_selected_building_id = -1
	_selected_quest_id = ""
	_fit_ui_to_viewport()
	_toggle_event_feed(false)
	if _is_quest_drawer_open():
		_toggle_quest_drawer()
	if build_manager.is_placing():
		build_manager.cancel_placement()
	if camera_controller != null:
		camera_controller.position = Vector3(0, 20, 30)
		camera_controller.size = 18.0
	match target:
		"town_idle":
			pass
		"build_mode":
			build_manager.start_placement("temple")
		"building_selected_tavern":
			var tavern := _get_building_of_type("tavern")
			if not tavern.is_empty():
				_show_building_panel(int(tavern.get("id", -1)))
		"inspector_adventurer":
			if not GameState.heroes.is_empty():
				_show_hero_panel(int(GameState.heroes.keys()[0]))
		"quest_board_open":
			_selected_quest_id = str(GameState.quests[0].get("offer_id", "")) if not GameState.quests.is_empty() else ""
			if not _is_quest_drawer_open():
				_toggle_quest_drawer()
		"quest_selected_unavailable":
			_selected_quest_id = _first_unavailable_offer_id()
			if _selected_quest_id == "" and not GameState.quests.is_empty():
				_selected_quest_id = str(GameState.quests[0].get("offer_id", ""))
			if not _is_quest_drawer_open():
				_toggle_quest_drawer()
		"ready_to_launch":
			_selected_quest_id = _first_ready_offer_id()
			if _selected_quest_id == "" and not GameState.quests.is_empty():
				_selected_quest_id = str(GameState.quests[0].get("offer_id", ""))
			if not _is_quest_drawer_open():
				_toggle_quest_drawer()
	_apply_panel_state()
	_refresh_build_ui()
	_refresh_quest_ui()
	_refresh_roster_strip()
	_refresh_top_bar()

func _first_ready_offer_id() -> String:
	for quest_offer: Dictionary in GameState.quests:
		var preview: Dictionary = sim.get_quest_acceptance_preview(int(quest_offer.get("offer_id", -1)))
		if bool(preview.get("can_accept", false)):
			return str(quest_offer.get("offer_id", ""))
	return ""

func _first_unavailable_offer_id() -> String:
	for quest_offer: Dictionary in GameState.quests:
		var preview: Dictionary = sim.get_quest_acceptance_preview(int(quest_offer.get("offer_id", -1)))
		if not bool(preview.get("can_accept", false)):
			return str(quest_offer.get("offer_id", ""))
	return ""

func _compact_list_text(values: Array, max_items: int = 5) -> String:
	if values.is_empty():
		return "None"
	var parts: Array[String] = []
	for index in range(min(values.size(), max_items)):
		parts.append(str(values[index]))
	if values.size() > max_items:
		parts.append("+%d more" % (values.size() - max_items))
	return "  •  ".join(parts)

func get_snapshot_rect(name: String) -> Rect2i:
	var node: Control = null
	match name:
		"top_bar":
			node = get_node_or_null("UILayer/TopBar")
		"left_rail":
			node = get_node_or_null("UILayer/LeftPanel")
		"right_inspector":
			node = get_node_or_null("UILayer/RightPanel")
		"bottom_roster":
			node = get_node_or_null("UILayer/RosterPanel")
		"active_overlay":
			node = get_node_or_null("UILayer/QuestDrawer") if _is_quest_drawer_open() else get_node_or_null("UILayer/EventLogPanel")
	if node == null or not node.visible:
		return Rect2i()
	var rect := node.get_global_rect()
	return Rect2i(int(rect.position.x), int(rect.position.y), int(rect.size.x), int(rect.size.y))

func _format_entity_state(raw_state: String) -> String:
	if raw_state == "":
		return "idle"
	return raw_state.replace("_", " ").capitalize()
