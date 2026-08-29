class_name TypingKeyboard
extends Node3D


func _ready() -> void:
	position = Vector3(0.0, 0.66, 0.37)
	rotation_degrees = Vector3(58.0, 0.0, 0.0)

	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color("223348")
	body_material.metallic = 0.08
	body_material.roughness = 0.82

	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.58, 0.035, 0.20)
	body_mesh.material = body_material
	var body := MeshInstance3D.new()
	body.name = "KeyboardBody"
	body.mesh = body_mesh
	add_child(body)

	var key_material := StandardMaterial3D.new()
	key_material.albedo_color = Color("86cfc1")
	key_material.roughness = 0.9

	var key_mesh := BoxMesh.new()
	key_mesh.size = Vector3(0.050, 0.012, 0.040)
	key_mesh.material = key_material
	for row_index in 2:
		for column_index in 8:
			var key := MeshInstance3D.new()
			key.name = "Key_%d_%d" % [row_index, column_index]
			key.mesh = key_mesh
			key.position = Vector3(
				-0.225 + column_index * 0.064 + row_index * 0.015,
				0.024,
				-0.035 + row_index * 0.070,
			)
			add_child(key)
