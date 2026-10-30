extends RefCounted
## Only companion data, in the explicit directory supplied by the application.
## Credentials are stored separately by ai_key_store and never enter this JSON.

const MAX_BYTES := 524288
var root_path := ""
var last_error: Error = OK

func setup(path: String) -> void:
	root_path = ProjectSettings.globalize_path(path).simplify_path() if not path.is_empty() else ""

func load_data() -> Dictionary:
	last_error = OK
	if root_path.is_empty():
		last_error = ERR_INVALID_PARAMETER
		return {}
	var path := root_path.path_join("companion.json")
	if not FileAccess.file_exists(path):
		# Recover only our own interrupted atomic replacement.
		if FileAccess.file_exists(path + ".bak"):
			path += ".bak"
		else:
			return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = FileAccess.get_open_error()
		return {}
	if file.get_length() > MAX_BYTES:
		last_error = ERR_OUT_OF_MEMORY
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		last_error = ERR_PARSE_ERROR
		return {}
	return parsed

func save_data(data: Dictionary) -> Error:
	if root_path.is_empty(): return ERR_INVALID_PARAMETER
	var error := DirAccess.make_dir_recursive_absolute(root_path)
	if error != OK: return error
	var content := JSON.stringify(data, "\t")
	if content.to_utf8_buffer().size() > MAX_BYTES: return ERR_OUT_OF_MEMORY
	var path := root_path.path_join("companion.json")
	var temporary := path + ".tmp"
	var backup := path + ".bak"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(content)
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK: return error
	var had_previous := FileAccess.file_exists(path)
	# After recovery the .bak can be the only durable copy. Retain it until
	# the new primary is committed, including when the final rename fails.
	if had_previous and FileAccess.file_exists(backup):
		error = DirAccess.remove_absolute(backup)
		if error != OK: return error
	if had_previous:
		error = DirAccess.rename_absolute(path, backup)
		if error != OK: return error
	error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		if had_previous: DirAccess.rename_absolute(backup, path)
		return error
	if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
	return OK
