extends RefCounted
## Only Windows DPAPI ciphertext is persisted; never a bundled or plain-text key.
const MAGIC := "DOLIKE-AI-KEY-1\n"
const MAX_KEY_BYTES := 16384
const MAX_FILE_BYTES := 65536
var _native: Object
var _path := ""

func setup(native_model: Object, root_path: String) -> void:
	_native = native_model
	_path = root_path.path_join("credential.bin") if not root_path.is_empty() else ""

func has_key() -> bool:
	return not load_key().is_empty()

func load_key() -> String:
	if not _available() or _path.is_empty() or not FileAccess.file_exists(_path): return ""
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null: return ""
	var count := file.get_length()
	if count <= MAGIC.length() or count > MAX_FILE_BYTES:
		file.close()
		return ""
	var header := file.get_buffer(MAGIC.length()).get_string_from_ascii()
	if header != MAGIC:
		file.close()
		return ""
	var encrypted := file.get_buffer(count-MAGIC.length())
	file.close()
	var plain: PackedByteArray = _native.call("decrypt_desktop_secret", encrypted)
	if plain.is_empty() or plain.size() > MAX_KEY_BYTES: return ""
	var key := plain.get_string_from_utf8()
	plain.fill(0)
	if key.is_empty() or "\n" in key or "\r" in key: return ""
	return key

func save_key(value: String) -> Error:
	if not _available(): return ERR_UNAVAILABLE
	if _path.is_empty(): return ERR_UNCONFIGURED
	var key := value.strip_edges()
	var plain := key.to_utf8_buffer()
	if plain.is_empty() or plain.size()>MAX_KEY_BYTES or "\n" in key or "\r" in key:
		plain.fill(0)
		return ERR_INVALID_PARAMETER
	var encrypted: PackedByteArray = _native.call("encrypt_desktop_secret", plain)
	plain.fill(0)
	if encrypted.is_empty() or encrypted.size()>MAX_FILE_BYTES-MAGIC.length(): return FAILED
	var error := DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	if error != OK: return error
	var temporary := _path+".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_buffer(MAGIC.to_ascii_buffer())
	file.store_buffer(encrypted)
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(temporary, _path)
	if error != OK and FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)
	return error

func clear_key() -> Error:
	if _path.is_empty(): return ERR_UNCONFIGURED
	var error := OK
	for candidate in [_path, _path+".tmp"]:
		if not FileAccess.file_exists(candidate): continue
		var removed := DirAccess.remove_absolute(candidate)
		if removed != OK: error = removed
	return error

func _available() -> bool:
	return OS.get_name() == "Windows" and is_instance_valid(_native) \
		and _native.has_method("encrypt_desktop_secret") and _native.has_method("decrypt_desktop_secret")
