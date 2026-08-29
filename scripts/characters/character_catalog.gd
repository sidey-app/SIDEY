class_name CharacterCatalog
extends RefCounted

const DEFAULT_CHARACTER_ID := "minty_pup"
const ENTRIES := {
	"minty_pup": {
		"id": "minty_pup",
		"display_name": "Minty Pup",
		"model_path": "res://assets/characters/dog/dog_mint_v1_rigged.glb",
		"rig_profile": "minty_pup",
	},
}


static func all() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for character_id in ENTRIES:
		result.append((ENTRIES[character_id] as Dictionary).duplicate(true))
	return result


static func has(character_id: String) -> bool:
	return ENTRIES.has(character_id)


static func get_entry(character_id: String) -> Dictionary:
	if not ENTRIES.has(character_id):
		return {}
	return (ENTRIES[character_id] as Dictionary).duplicate(true)


static func rig_profile(character_id: String) -> CharacterRigProfile:
	match str(get_entry(character_id).get("rig_profile", "")):
		"minty_pup":
			return CharacterRigProfile.minty_pup()
		_:
			return null
