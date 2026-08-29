extends SceneTree

const CHARACTER_ASSET := "res://assets/characters/dog/dog_mint_v1_rigged.glb"
const CharacterRowScript := preload("res://scripts/characters/character_row.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ResourceLoader.exists(CHARACTER_ASSET):
		print("SIDEY_CHARACTER_SMOKE_SKIPPED asset_missing=%s" % CHARACTER_ASSET)
		quit(0)
		return
	var root := Node3D.new()
	root.name = "CharacterSmokeRoot"
	get_root().add_child(root)
	var row := CharacterRowScript.new() as CharacterRow
	root.add_child(row)
	var configure_error := row.configure_debug(5)
	if configure_error != OK or row.character_count() != 5:
		push_error("SIDEY_CHARACTER_SMOKE_FAILED error=%d count=%d" % [configure_error, row.character_count()])
		quit(1)
		return
	row.set_all_motion_states(CharacterState.Value.TYPING, true)
	await process_frame
	row.set_all_motion_states(CharacterState.Value.OFFLINE_SLEEP, true)
	await process_frame
	row.set_all_motion_states(CharacterState.Value.ONLINE_IDLE, true)
	await process_frame
	print("SIDEY_CHARACTER_SMOKE_OK count=%d duplicate_character=minty_pup" % row.character_count())
	quit(0)
