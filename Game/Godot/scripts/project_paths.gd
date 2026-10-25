extends RefCounted
## A shared resolver for development, installed Runtime, and relocatable builds.
static func game_root() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://..").simplify_path()
	var executable := OS.get_executable_path().get_base_dir()
	for relative in ["..", "../..", "."]:
		var candidate := executable.path_join(relative).simplify_path()
		if FileAccess.file_exists(candidate.path_join("Start-Godot-Pet.cmd")):
			return candidate
	return executable

static func development_mode() -> bool:
	return "--dev" in OS.get_cmdline_user_args()
