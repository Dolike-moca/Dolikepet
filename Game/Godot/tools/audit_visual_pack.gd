extends SceneTree
var rows: Array[String] = []
func scan(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir==null: return
	for folder in dir.get_directories(): scan(path.path_join(folder))
	for file in dir.get_files():
		var full := path.path_join(file)
		rows.append(full+":"+FileAccess.get_sha256(full))
func _initialize() -> void:
	for path in ["res://assets","res://model","res://shaders","res://.godot/imported"]: scan(path)
	rows.sort()
	print("VISUAL ASSETS HASH: "+"\n".join(rows).sha256_text()+" FILES "+str(rows.size()))
	quit()
