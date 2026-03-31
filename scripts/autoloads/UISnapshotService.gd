extends Node
## Rendered UI snapshot mode. Builds deterministic fixture states, captures PNGs, and exits.

const DEFAULT_TARGETS := [
	"town_idle",
	"build_mode",
	"building_selected_tavern",
	"inspector_adventurer",
	"quest_board_open",
	"quest_selected_unavailable",
	"ready_to_launch",
]

var _running: bool = false

func notify_world_ready(world: Node) -> void:
	if not RuntimeConfig.is_snapshot() or _running:
		return
	_running = true
	call_deferred("_run_snapshot_session", world)

func _run_snapshot_session(world: Node) -> void:
	if world == null:
		get_tree().quit(1)
		return
	_apply_snapshot_runtime()
	var output_dir := ProjectSettings.globalize_path(RuntimeConfig.snapshot_output_dir)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var manifest := {
		"application": ProjectSettings.get_setting("application/config/name", "QuestTown"),
		"timestamp": Time.get_datetime_string_from_system(),
		"resolution": {
			"x": RuntimeConfig.snapshot_resolution.x,
			"y": RuntimeConfig.snapshot_resolution.y,
		},
		"targets": [],
		"git": _git_info(),
	}
	for target in RuntimeConfig.snapshot_targets:
		await _prepare_target(world, target)
		await _settle_frames(10)
		var entry := _capture_target(world, target, output_dir)
		manifest["targets"].append(entry)
	var manifest_path := output_dir.path_join("manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(manifest, "\t"))
	get_tree().quit()

func _apply_snapshot_runtime() -> void:
	DisplayServer.window_set_size(RuntimeConfig.snapshot_resolution)
	Engine.time_scale = 1.0

func _prepare_target(world: Node, target: String) -> void:
	if RuntimeConfig.snapshot_load_path != "":
		world.sim.load_world(RuntimeConfig.snapshot_load_path)
	else:
		_build_fixture_state(world, target)
	world.prepare_snapshot_target(target)

func _build_fixture_state(world: Node, target: String) -> void:
	world.sim.reset_world(RuntimeConfig.seed_value if RuntimeConfig.seed_value != 0 else 4242)
	world.sim.place_building("tavern", Vector3(0, 0, 0))
	world.sim.place_building("weapons_shop", Vector3(4, 0, -1))
	world.sim.place_building("temple", Vector3(-4, 0, 1))
	world.sim.upgrade_building(int(world.sim.get_building_of_type("tavern").get("id", -1)))
	world.sim.upgrade_building(int(world.sim.get_building_of_type("weapons_shop").get("id", -1)))
	world.sim.set_building_output_mode(int(world.sim.get_building_of_type("tavern").get("id", -1)))
	world.sim.set_building_output_mode(int(world.sim.get_building_of_type("weapons_shop").get("id", -1)))
	world.sim.set_building_output_mode(int(world.sim.get_building_of_type("temple").get("id", -1)))
	match target:
		"town_idle", "build_mode", "building_selected_tavern":
			world.sim.step_ticks(1200)
		"inspector_adventurer", "quest_board_open", "ready_to_launch":
			world.sim.step_ticks(1800)
		"quest_selected_unavailable":
			world.sim.reset_world(4242)
			world.sim.place_building("tavern", Vector3(0, 0, 0))
			world.sim.set_building_output_mode(int(world.sim.get_building_of_type("tavern").get("id", -1)))
			world.sim.step_ticks(420)
		_:
			world.sim.step_ticks(1200)

func _settle_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame
		RenderingServer.force_draw()

func _capture_target(world: Node, target: String, output_dir: String) -> Dictionary:
	var image := world.get_viewport().get_texture().get_image()
	image.flip_y()
	var target_dir := output_dir.path_join(target)
	DirAccess.make_dir_recursive_absolute(target_dir)
	var full_path := target_dir.path_join("full.png")
	image.save_png(full_path)
	var crops := {
		"top_bar": world.get_snapshot_rect("top_bar"),
		"left_rail": world.get_snapshot_rect("left_rail"),
		"right_inspector": world.get_snapshot_rect("right_inspector"),
		"bottom_roster": world.get_snapshot_rect("bottom_roster"),
		"active_overlay": world.get_snapshot_rect("active_overlay"),
	}
	var crop_paths := {}
	for key in crops.keys():
		var rect: Rect2i = crops[key]
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		var clipped := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		if clipped.size.x <= 0 or clipped.size.y <= 0:
			continue
		var cropped := Image.create(clipped.size.x, clipped.size.y, false, image.get_format())
		cropped.blit_rect(image, clipped, Vector2i.ZERO)
		var crop_path := target_dir.path_join("%s.png" % key)
		cropped.save_png(crop_path)
		crop_paths[key] = crop_path
	return {
		"target": target,
		"full": full_path,
		"crops": crop_paths,
	}

func _git_info() -> Dictionary:
	var output := []
	var result := OS.execute("git", ["rev-parse", "--short", "HEAD"], output, true)
	return {
		"available": result == OK,
		"commit": output[0].strip_edges() if result == OK and not output.is_empty() else "",
	}
