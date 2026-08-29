extends Node3D

const ASSET_PATH := "res://assets/characters/dog/dog_mint_v1_rigged.glb"


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("111722"))
	_setup_environment()
	_setup_camera()

	var model := (load(ASSET_PATH) as PackedScene).instantiate()
	add_child(model)
	_normalize_materials(model)

	var skeleton := _find_first_skeleton(model)
	if skeleton == null:
		push_error("Skeleton3D missing")
		get_tree().quit(1)
		return

	var arguments := _parse_arguments()
	var bone_name: StringName = arguments.get("bone", "LeftForeArm")
	var axis_name: String = arguments.get("axis", "x")
	var angle_degrees: float = float(arguments.get("angle", "45"))
	var bone_index := skeleton.find_bone(bone_name)
	if bone_index < 0:
		push_error("Bone missing: %s" % bone_name)
		get_tree().quit(1)
		return

	var axis := {
		"x": Vector3.RIGHT,
		"y": Vector3.UP,
		"z": Vector3.BACK,
	}.get(axis_name, Vector3.RIGHT) as Vector3
	var base_rotation := skeleton.get_bone_pose_rotation(bone_index)
	skeleton.set_bone_pose_rotation(
		bone_index,
		base_rotation * Quaternion(axis, deg_to_rad(angle_degrees)),
	)

	var label := Label.new()
	label.position = Vector2(20.0, 20.0)
	label.text = "%s · %s · %+.0f°" % [bone_name, axis_name.to_upper(), angle_degrees]
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("9fe6d5"))
	var canvas := CanvasLayer.new()
	canvas.add_child(label)
	add_child(canvas)
	print("POSE_PROBE bone=%s axis=%s angle=%s" % [bone_name, axis_name, angle_degrees])


func _parse_arguments() -> Dictionary:
	var result := {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not "=" in argument:
			continue
		var parts := argument.trim_prefix("--").split("=", true, 1)
		result[parts[0]] = parts[1]
	return result


func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("111722")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d8e7ef")
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-32.0, -28.0, 0.0)
	key_light.light_color = Color("fff2dd")
	key_light.light_energy = 1.15
	add_child(key_light)


func _setup_camera() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.36
	camera.position = Vector3(0.0, 1.16, 3.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.16, 0.0), Vector3.UP)


func _normalize_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var source_material := mesh_instance.mesh.surface_get_material(surface_index)
				if source_material is BaseMaterial3D:
					var material := source_material.duplicate() as BaseMaterial3D
					material.emission_enabled = false
					material.metallic = 0.0
					material.roughness = 0.85
					mesh_instance.set_surface_override_material(surface_index, material)
	for child in node.get_children():
		_normalize_materials(child)


func _find_first_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_first_skeleton(child)
		if found != null:
			return found
	return null
