extends SceneTree
## Real settings/auth controls with an in-memory account service. No browser,
## credentials, network, saved user settings or food directories are touched.
const Settings = preload("res://scripts/pet_settings.gd")

class FakeAuth extends Node:
	signal changed
	signal first_plan_connected
	var busy := false
	var active_id := ""
	var status := "请选择账户或登录"
	var models: Array = []
	var selected_model := ""
	var records: Array = []
	var logins: Array = []
	var deleted: Array[String] = []
	var signing_in := false
	func accounts() -> Array: return records.duplicate(true)
	func active_label() -> String:
		for entry in records:
			if entry.id == active_id: return str(entry.label)
		return "尚未登录"
	func can_infer() -> bool: return not active_id.is_empty()
	func is_signing_in() -> bool: return signing_in
	func begin_login(id: String = "", force: bool = false) -> bool:
		logins.append({"id":id,"force":force})
		busy = true; signing_in = true; status = "正在登录"; changed.emit(); return true
	func cancel_login() -> void:
		busy = false; signing_in = false; status = "已取消登录"; changed.emit()
	func logout() -> void:
		for entry in records:
			if entry.id == active_id: entry.signed_in = false
		changed.emit()
	func delete_account(id: String) -> bool:
		if busy: return false
		for index in records.size():
			if records[index].id != id: continue
			records.remove_at(index); deleted.append(id)
			if active_id == id:
				active_id = ""; models.clear(); selected_model = ""
			status = "已删除本机账户记录"; changed.emit(); return true
		return false
	func select_account(id: String) -> void:
		for entry in records:
			if entry.id == id:
				active_id = id; models = [{"slug":"fixture-model","display_name":"Fixture Model"}]
				selected_model = "fixture-model"; changed.emit(); return
	func select_model(slug: String) -> void: selected_model = slug; changed.emit()
	func refresh_models() -> void: changed.emit()
	func acknowledge_plan() -> void: pass
	func seed() -> void:
		records = [{"id":"account-a","label":"猫猫 A · fixture-a@example.invalid","signed_in":true},
			{"id":"account-b","label":"猫猫 B · fixture-b@example.invalid","signed_in":true}]
		select_account("account-a")

class FakeService extends Node:
	signal state_changed
	var auth: Node
	var busy := false
	var status := "使用测试账户界面"
	var settings := {"enabled":true,"auth_method":"chatgpt","model":"gpt-6-luna",
		"personality":"原始风格","proactive":false,"memory_enabled":true,
		"auto_memory_enabled":true,"include_pet_state":true}
	func bind_auth(value: Node) -> void: auth = value
	func has_key() -> bool: return false
	func ready_to_chat() -> bool: return auth.can_infer()
	func apply_settings(_draft: Dictionary, _key: String = "", _erase: bool = false) -> Error: return OK
	func test_connection() -> bool: return false

var checks := 0
var failures: Array[String] = []
var output := ""
var settings
var service := FakeService.new()
var auth := FakeAuth.new()

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	call_deferred("run")

func screenshot(name: String) -> void:
	if output.is_empty(): return
	DirAccess.make_dir_recursive_absolute(output)
	await process_frame
	await RenderingServer.frame_post_draw
	settings.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	root.add_child(auth); root.add_child(service); service.bind_auth(auth)
	settings = Settings.new(); settings.ai_service = service; root.add_child(settings)
	await process_frame
	settings.show_settings(false, 60, 180); settings._select_page(3)
	var ai = settings.ai_panel
	var panel = ai.auth_panel
	verify(panel.visible and panel.auth == auth, "settings displays the actual ChatGPT panel")
	verify(panel.relogin.disabled and panel.delete_account_button.disabled and panel.logout_button.disabled, "no account disables relogin deletion and logout")
	verify(not panel.login.disabled and panel.account.get_item_text(panel.account.selected).contains("尚未登录"), "no account offers login and the empty placeholder")
	panel.login.pressed.emit()
	verify(auth.logins.size() == 1 and auth.logins.back().id.is_empty(), "first login starts a fresh account authorization")
	verify(panel.cancel.visible and panel.login.disabled and panel.add.disabled, "login in flight exposes cancel and blocks duplicate login")
	panel.cancel.pressed.emit()
	verify(not auth.busy and not panel.cancel.visible, "cancel restores the idle controls")

	auth.seed()
	ai.personality.text = "尚未保存：猫猫活泼一点"
	ai.model.text = "draft-model"
	ai.quiet_enabled.button_pressed = false
	var saved_draft: String = ai.personality.text
	verify(not panel.relogin.disabled and not panel.delete_account_button.disabled, "selected account enables both account management actions")
	panel.relogin.pressed.emit()
	verify(auth.logins.back().id == "account-a", "relogin uses the selected account ID")
	verify(panel.relogin.disabled and panel.delete_account_button.disabled and panel.account.disabled and panel.logout_button.disabled, "busy auth disables switching relogin deletion and logout")
	panel.cancel.pressed.emit()
	verify(ai.personality.text == saved_draft and ai.model.text == "draft-model" and not ai.quiet_enabled.button_pressed, "authorization refresh keeps unsaved settings fields")
	await screenshot("chatgpt-account-actions")

	# Cancellation must not remove data. The confirmation belongs to the ID at
	# opening time; account switching while it is open must not retarget deletion.
	panel.delete_account_button.pressed.emit()
	verify(panel.delete_confirmation.visible, "delete opens a confirmation dialog")
	verify(panel.delete_confirmation.dialog_text.contains("fixture-a") and panel.delete_confirmation.dialog_text.contains("本机"), "confirmation names the selected record and its local scope")
	panel.delete_confirmation.canceled.emit(); panel.delete_confirmation.hide()
	verify(auth.deleted.is_empty() and auth.records.size() == 2, "canceling deletion preserves every account")
	panel.delete_account_button.pressed.emit()
	auth.select_account("account-b")
	panel.delete_confirmation.confirmed.emit(); panel.delete_confirmation.hide()
	verify(auth.deleted == ["account-a"] and auth.records.size() == 1 and auth.records[0].id == "account-b", "confirmation remains bound to its original account after selection changes")
	verify(auth.active_id == "account-b", "deleting another record preserves the active account")
	verify(ai.personality.text == saved_draft and ai.model.text == "draft-model", "deletion does not discard the AI settings draft")

	# A login starting after the confirmation opened must block its stale action.
	auth.seed(); panel.delete_account_button.pressed.emit()
	auth.busy = true; auth.changed.emit()
	var count: int = auth.deleted.size()
	panel.delete_confirmation.confirmed.emit(); panel.delete_confirmation.hide()
	verify(auth.deleted.size() == count and auth.records.size() == 2, "confirmation rechecks busy state before deletion")
	auth.busy = false; auth.changed.emit()
	panel.delete_account_button.pressed.emit()
	panel.delete_confirmation.confirmed.emit(); panel.delete_confirmation.hide()
	verify(auth.active_id.is_empty() and auth.records.size() == 1 and auth.records[0].id == "account-b", "deleting active account preserves other records without automatically switching")
	verify(panel._ids[panel.account.selected].is_empty() and panel.account.get_item_text(panel.account.selected).contains("请选择"), "remaining records show an explicit unselected placeholder")
	verify(panel.relogin.disabled and panel.delete_account_button.disabled and panel.logout_button.disabled, "unselected state cannot reauthorize or delete a different account")
	await screenshot("chatgpt-after-deletion")
	var index: int = panel._ids.find("account-b")
	panel.account.item_selected.emit(index)
	verify(auth.active_id == "account-b" and not panel.relogin.disabled, "user can explicitly select the remaining account")
	panel.delete_account_button.pressed.emit()
	panel.delete_confirmation.confirmed.emit(); panel.delete_confirmation.hide()
	verify(auth.records.is_empty() and auth.active_id.is_empty(), "deleting the final record returns to a fresh account state")
	verify(panel.account.get_item_text(panel.account.selected).contains("尚未登录") and not panel.login.disabled, "last deletion restores first-login controls")
	verify(ai.personality.text == saved_draft and ai.model.text == "draft-model" and service.settings.personality == "原始风格", "account actions neither save nor replace unrelated settings drafts")

	settings.queue_free(); service.queue_free(); auth.queue_free(); await process_frame
	for failure in failures: printerr("CHATGPT AUTH UI: " + failure)
	print("ChatGPT auth UI: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
