extends RefCounted

const TOWN_LOCATION_ID := "questtown_centre"
const TARGET_TOWN_ANCHOR := Vector2(0.50, 0.54)
const EDGE_MARGIN := Vector2(92.0, 72.0)

const TREE_TEXTURES := [
	"res://assets/ui/generated_map/trees/pine_tree_1.png",
	"res://assets/ui/generated_map/trees/pine_tree_2.png",
]
const HILL_TEXTURES := [
	"res://assets/ui/generated_map/hills/round_hill_1.png",
	"res://assets/ui/generated_map/hills/round_hill_2.png",
]
const MOUNTAIN_TEXTURES := [
	"res://assets/ui/generated_map/mountains/sharp_mountain_2.png",
	"res://assets/ui/generated_map/mountains/sharp_mountain_4.png",
]

func generate(canvas_size: Vector2, locations: Array, routes: Array, seed: int = 1337) -> Dictionary:
	var layout := _layout_locations(canvas_size, locations)
	var positions: Dictionary = layout.get("positions", {})
	return {
		"positions": positions,
		"transform": layout.get("transform", {}),
		"terrain_decorations": _build_terrain_decorations(canvas_size, locations, positions, seed),
		"river_paths": _build_river_paths(canvas_size, positions),
	}

func project_anchor(canvas_size: Vector2, anchor_variant: Variant, transform: Dictionary) -> Vector2:
	var raw_point := _anchor_to_canvas(canvas_size, anchor_variant)
	if transform.is_empty():
		return raw_point
	var town_raw: Vector2 = transform.get("town_raw", Vector2.ZERO)
	var town_target: Vector2 = transform.get("town_target", canvas_size * TARGET_TOWN_ANCHOR)
	var scale := float(transform.get("scale", 1.0))
	var delta: Vector2 = transform.get("delta", Vector2.ZERO)
	return town_target + (raw_point - town_raw) * scale + delta

func _layout_locations(canvas_size: Vector2, locations: Array) -> Dictionary:
	var raw_positions := {}
	for location_variant in locations:
		if not (location_variant is Dictionary):
			continue
		var location: Dictionary = location_variant
		var location_id := str(location.get("id", ""))
		if location_id == "":
			continue
		raw_positions[location_id] = _anchor_to_canvas(canvas_size, location.get("position", location.get("anchor_position", {})))
	if not raw_positions.has(TOWN_LOCATION_ID):
		return {"positions": raw_positions, "transform": {}}
	var town_target := Vector2(canvas_size.x * TARGET_TOWN_ANCHOR.x, canvas_size.y * TARGET_TOWN_ANCHOR.y)
	var town_raw: Vector2 = raw_positions[TOWN_LOCATION_ID]
	var translated_points: Array = []
	for point_variant in raw_positions.values():
		var point: Vector2 = point_variant
		translated_points.append(point - town_raw + town_target)
	var bounds := _bounds_from_points(translated_points)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return {
			"positions": raw_positions,
			"transform": {
				"town_raw": town_raw,
				"town_target": town_target,
				"scale": 1.0,
				"delta": Vector2.ZERO,
			}
		}
	var usable_size := canvas_size - EDGE_MARGIN * 2.0
	var scale: float = min(usable_size.x / max(1.0, bounds.size.x), usable_size.y / max(1.0, bounds.size.y))
	scale = min(scale, 1.0)
	var scaled_points: Array = []
	for point_variant in translated_points:
		var point: Vector2 = point_variant
		scaled_points.append(town_target + (point - town_target) * scale)
	var scaled_bounds := _bounds_from_points(scaled_points)
	var bounds_center := scaled_bounds.position + scaled_bounds.size * 0.5
	var desired_center := Vector2(canvas_size.x * 0.5, canvas_size.y * 0.5)
	var delta := desired_center - bounds_center
	var centered := {}
	for location_id_variant in raw_positions.keys():
		var location_id := str(location_id_variant)
		var point: Vector2 = raw_positions[location_id]
		centered[location_id] = town_target + (point - town_raw) * scale + delta
	return {
		"positions": centered,
		"transform": {
			"town_raw": town_raw,
			"town_target": town_target,
			"scale": scale,
			"delta": delta,
		}
	}

func _build_terrain_decorations(canvas_size: Vector2, locations: Array, positions: Dictionary, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var decorations: Array = []
	for location_variant in locations:
		if not (location_variant is Dictionary):
			continue
		var location: Dictionary = location_variant
		var location_id := str(location.get("id", ""))
		if not positions.has(location_id):
			continue
		var position: Vector2 = positions[location_id]
		var location_type := str(location.get("location_type", ""))
		match location_type:
			"woods":
				decorations.append_array(_cluster_decorations(position, TREE_TEXTURES, 7, Vector2(96, 72), Vector2(26, 34), 0.40, rng))
			"graveyard":
				decorations.append_array(_cluster_decorations(position + Vector2(-10, 8), HILL_TEXTURES, 3, Vector2(56, 26), Vector2(42, 30), 0.28, rng))
			"ruins":
				decorations.append_array(_cluster_decorations(position + Vector2(-12, -6), HILL_TEXTURES, 2, Vector2(46, 22), Vector2(34, 24), 0.22, rng))
			"watchtower":
				decorations.append_array(_cluster_decorations(position + Vector2(0, -48), MOUNTAIN_TEXTURES, 2, Vector2(42, 18), Vector2(54, 40), 0.22, rng))
	if positions.has("watch_hut"):
		decorations.append_array(_cluster_decorations(positions["watch_hut"] + Vector2(-84, -62), MOUNTAIN_TEXTURES, 3, Vector2(74, 24), Vector2(68, 48), 0.24, rng))
	if positions.has("graveyard_hill"):
		decorations.append_array(_cluster_decorations(positions["graveyard_hill"] + Vector2(24, -22), MOUNTAIN_TEXTURES, 2, Vector2(38, 18), Vector2(56, 42), 0.18, rng))
	if positions.has("broken_ford"):
		decorations.append({
			"kind": "wash",
			"position": positions["broken_ford"] + Vector2(48, -18),
			"size": Vector2(92, 32),
			"color": Color(0.44, 0.35, 0.18, 0.08),
		})
	if positions.has("stone_bridge"):
		decorations.append({
			"kind": "wash",
			"position": positions["stone_bridge"] + Vector2(-2, -16),
			"size": Vector2(118, 26),
			"color": Color(0.44, 0.35, 0.18, 0.07),
		})
	return decorations

func _build_river_paths(canvas_size: Vector2, positions: Dictionary) -> Array:
	var rivers: Array = []
	if positions.has("stone_bridge") and positions.has("broken_ford"):
		var stone_bridge: Vector2 = positions["stone_bridge"]
		var broken_ford: Vector2 = positions["broken_ford"]
		var river_curve := Curve2D.new()
		var source := Vector2(stone_bridge.x - 30.0, -26.0)
		var bend_a := stone_bridge + Vector2(-42.0, -84.0)
		var bend_b := stone_bridge + Vector2(-12.0, -8.0)
		var bend_c := broken_ford + Vector2(56.0, -18.0)
		var mouth := Vector2(-48.0, broken_ford.y + 24.0)
		var raw_points := [source, bend_a, bend_b, bend_c, mouth]
		for point_index in range(raw_points.size()):
			var tangent := _curve_tangent(raw_points, point_index)
			river_curve.add_point(raw_points[point_index], -tangent, tangent)
		rivers.append({
			"points": river_curve.get_baked_points(),
			"width": 5.0,
			"inner_width": 2.6,
			"color": Color(0.29, 0.25, 0.16, 0.42),
			"inner_color": Color(0.83, 0.88, 0.91, 0.32),
		})
	return rivers

func _cluster_decorations(center: Vector2, texture_paths: Array, count: int, spread: Vector2, size_range: Vector2, alpha: float, rng: RandomNumberGenerator) -> Array:
	var decorations: Array = []
	for index in range(count):
		var offset := Vector2(
			rng.randf_range(-spread.x * 0.5, spread.x * 0.5),
			rng.randf_range(-spread.y * 0.5, spread.y * 0.5)
		)
		var base_size := rng.randf_range(size_range.x, size_range.y)
		decorations.append({
			"kind": "icon",
			"texture_path": str(texture_paths[index % texture_paths.size()]),
			"position": center + offset,
			"size": Vector2(base_size, base_size),
			"rotation": rng.randf_range(-0.06, 0.06),
			"alpha": alpha + rng.randf_range(-0.05, 0.05),
		})
	return decorations

func _curve_tangent(points: Array, index: int) -> Vector2:
	if points.size() <= 1:
		return Vector2.ZERO
	if index == 0:
		return (points[1] - points[0]) * 0.22
	if index == points.size() - 1:
		return (points[index] - points[index - 1]) * 0.22
	return (points[index + 1] - points[index - 1]) * 0.18

func _anchor_to_canvas(canvas_size: Vector2, anchor_variant: Variant) -> Vector2:
	var anchor: Dictionary = anchor_variant if anchor_variant is Dictionary else {}
	return Vector2(
		float(anchor.get("x", 0.5)) * canvas_size.x,
		float(anchor.get("y", 0.5)) * canvas_size.y
	)

func _bounds_from_points(points: Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var first: Vector2 = points[0]
	var min_x := first.x
	var max_x := first.x
	var min_y := first.y
	var max_y := first.y
	for point_variant in points:
		var point: Vector2 = point_variant
		min_x = min(min_x, point.x)
		max_x = max(max_x, point.x)
		min_y = min(min_y, point.y)
		max_y = max(max_y, point.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
