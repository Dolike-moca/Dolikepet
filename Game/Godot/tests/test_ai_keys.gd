extends SceneTree
## DPAPI roundtrip with a fake key; requires an explicit isolated _work directory.
const KeyStore = preload("res://scripts/ai_key_store.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("AI KEYS: "+label)

func run() -> void:
	var directory := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--root="): directory = arg.trim_prefix("--root=").replace("\\", "/")
	var fixture_base := ProjectSettings.globalize_path("res://../../_work/").replace("\\", "/").simplify_path().trim_suffix("/") + "/"
	directory = directory.simplify_path()
	if not directory.is_absolute_path() or not directory.to_lower().begins_with(fixture_base.to_lower()) or directory.ends_with("/") or directory.contains("猫的饭盆") or directory.contains("猫的胃袋"):
		printerr("AI key test requires --root=<project _work/isolated-directory>")
		quit(2)
		return
	var native = ClassDB.instantiate("GDCubismUserModel")
	check(native!=null and native.has_method("encrypt_desktop_secret") and native.has_method("decrypt_desktop_secret"), "native DPAPI methods are registered")
	if not failures.is_empty():
		if native != null: native.free()
		quit(1)
		return
	var store := KeyStore.new()
	store.setup(native, directory)
	check(store.clear_key()==OK, "fixture starts empty")
	check(not store.has_key(), "empty vault reports no key")
	var fixture_key := "fixture-only-not-a-real-api-key-1234567890"
	check(store.save_key(fixture_key)==OK, "DPAPI encrypts fixture key")
	check(store.load_key()==fixture_key and store.has_key(), "same Windows account decrypts key")
	var bytes := FileAccess.get_file_as_bytes(directory.path_join("credential.bin"))
	check(not fixture_key.to_utf8_buffer().hex_encode() in bytes.hex_encode(), "file never contains plain-text fixture key")
	check(not FileAccess.file_exists(directory.path_join("credential.bin.tmp")), "atomic save leaves no temporary file")
	check(store.save_key(fixture_key+"-replaced")==OK and store.load_key()==fixture_key+"-replaced", "atomic replacement retains latest key")
	check(store.save_key("")==ERR_INVALID_PARAMETER and store.load_key()==fixture_key+"-replaced", "invalid save preserves previous key")
	check(native.encrypt_desktop_secret(PackedByteArray()).is_empty(), "empty encryption rejected")
	check(native.decrypt_desktop_secret(PackedByteArray([1,2,3])).is_empty(), "invalid encrypted data rejected")
	var corrupted := FileAccess.open(directory.path_join("credential.bin"), FileAccess.WRITE)
	corrupted.store_string(KeyStore.MAGIC)
	corrupted.store_buffer(PackedByteArray([1,2,3]))
	corrupted.close()
	check(store.load_key().is_empty(), "corrupt credential fails closed")
	check(store.clear_key()==OK and not FileAccess.file_exists(directory.path_join("credential.bin")), "clear removes encrypted credential")
	check(store.clear_key()==OK, "clearing absent credential is idempotent")
	native.free()
	print(JSON.stringify({"suite":"ai_keys","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
