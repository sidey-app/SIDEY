extends SceneTree

const ASSET_PATH := "res://assets/characters/dog/dog_mint_v1_rigged.glb"

var _skeletons: Array[Skeleton3D] = []
var _meshes: Array[MeshInstance3D] = []
var _animation_players: Array[AnimationPlayer] = []


func _initialize() -> void:
	var packed_scene := load(ASSET_PATH) as PackedScene
	if packed_scene == null:
		push_error("ASSET_MISSING path=%s" % ASSET_PATH)
		quit(1)
		return

	var instance := packed_scene.instantiate()
	_collect(instance)

	print("ASSET path=%s" % ASSET_PATH)
	print("ROOT name=%s class=%s" % [instance.name, instance.get_class()])
	print("TREE")
	_print_tree(instance)
	print("SKELETON_COUNT value=%d" % _skeletons.size())
	for skeleton in _skeletons:
		var bone_names := PackedStringArray()
		for bone_index in skeleton.get_bone_count():
			bone_names.append(skeleton.get_bone_name(bone_index))
		print("SKELETON path=%s bones=%d names=%s" % [
			instance.get_path_to(skeleton),
			skeleton.get_bone_count(),
			", ".join(bone_names),
		])

	print("MESH_COUNT value=%d" % _meshes.size())
	for mesh_instance in _meshes:
		var mesh := mesh_instance.mesh
		var surface_summaries := PackedStringArray()
		if mesh != null:
			for surface_index in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface_index)
				var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
				var material := mesh.surface_get_material(surface_index)
				var triangles := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
				surface_summaries.append("surface=%d vertices=%d triangles=%d material=%s" % [
					surface_index,
					vertices.size(),
					triangles,
					material.resource_name if material != null else "<none>",
				])
		print("MESH path=%s aabb_position=%s aabb_size=%s details=%s" % [
			instance.get_path_to(mesh_instance),
			mesh.get_aabb().position if mesh != null else Vector3.ZERO,
			mesh.get_aabb().size if mesh != null else Vector3.ZERO,
			"; ".join(surface_summaries),
		])

	print("ANIMATION_PLAYER_COUNT value=%d" % _animation_players.size())
	for animation_player in _animation_players:
		for animation_name in animation_player.get_animation_list():
			var animation := animation_player.get_animation(animation_name)
			var track_paths := PackedStringArray()
			for track_index in animation.get_track_count():
				track_paths.append(str(animation.track_get_path(track_index)))
			print("ANIMATION player=%s name=%s length=%.6f loop=%s tracks=%d autoplay=%s" % [
				instance.get_path_to(animation_player),
				animation_name,
				animation.length,
				animation.loop_mode,
				animation.get_track_count(),
				animation_player.autoplay,
			])
			print("ANIMATION_TRACKS name=%s paths=%s" % [animation_name, ", ".join(track_paths)])

	instance.free()
	quit()


func _collect(node: Node) -> void:
	if node is Skeleton3D:
		_skeletons.append(node)
	elif node is MeshInstance3D:
		_meshes.append(node)
	elif node is AnimationPlayer:
		_animation_players.append(node)

	for child in node.get_children():
		_collect(child)


func _print_tree(node: Node, depth := 0) -> void:
	print("%s%s [%s]" % ["  ".repeat(depth), node.name, node.get_class()])
	for child in node.get_children():
		_print_tree(child, depth + 1)
