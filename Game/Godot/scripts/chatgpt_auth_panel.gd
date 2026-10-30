extends VBoxContainer
## Explicit account connection only; choosing the billing path belongs to AI settings.
const SettingsTheme = preload("res://scripts/settings_theme.gd")
var auth: Node
var account := OptionButton.new()
var model := OptionButton.new()
var login := Button.new()
var add := Button.new()
var relogin := Button.new()
var logout_button := Button.new()
var delete_account_button := Button.new()
var delete_confirmation := ConfirmationDialog.new()
var cancel := Button.new()
var reauthorize := Button.new()
var reload_models := Button.new()
var status_label := Label.new()
var welcome := AcceptDialog.new()
var _ids: Array[String] = []
var _slugs: Array[String] = []
var _delete_id := ""

func _ready() -> void:
	add_theme_constant_override("separation", 7)
	var explanation := Label.new()
	explanation.text = "使用 ChatGPT 登录，无需填写 API Key。"
	explanation.tooltip_text = "是否可用取决于账户方案、地区与授权范围。"
	_hint(explanation); add_child(explanation)
	account.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account.fit_to_longest_item = false; account.clip_text = true
	_row("账户").add_child(account)
	account.item_selected.connect(func(index: int):
		if is_instance_valid(auth) and index >= 0 and index < _ids.size() and not _ids[index].is_empty(): auth.select_account(_ids[index]))
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	add_child(actions)
	login.text = "Continue with ChatGPT"
	login.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	login.add_theme_stylebox_override("normal", SettingsTheme.box(Color("f0f0f0")))
	login.add_theme_color_override("font_color", Color("171717"))
	login.add_theme_color_override("font_hover_color", Color("171717"))
	login.add_theme_stylebox_override("hover", SettingsTheme.box(Color("ffffff")))
	login.tooltip_text = "打开系统浏览器登录；桌宠不会读取你的密码"
	login.pressed.connect(func():
		if is_instance_valid(auth): auth.begin_login(auth.active_id))
	actions.add_child(login)
	add.text = "添加账户"; add.pressed.connect(func():
		if is_instance_valid(auth): auth.begin_login())
	actions.add_child(add)
	relogin.text = "重新登录"; relogin.tooltip_text = "重新验证当前账户；取消登录会保留原有凭据"
	relogin.pressed.connect(func():
		if is_instance_valid(auth) and not auth.busy and not str(auth.active_id).is_empty(): auth.begin_login(str(auth.active_id)))
	actions.add_child(relogin)
	logout_button.text = "退出"; logout_button.pressed.connect(func():
		if is_instance_valid(auth): auth.logout())
	actions.add_child(logout_button)
	delete_account_button.text = "删除账户"
	delete_account_button.tooltip_text = "只删除所选账户的本机记录与登录凭据，不删除 OpenAI 账户"
	delete_account_button.pressed.connect(_confirm_delete)
	actions.add_child(delete_account_button)
	cancel.text = "取消登录"; cancel.pressed.connect(func():
		if is_instance_valid(auth): auth.cancel_login())
	actions.add_child(cancel)
	var model_row := _row("模型")
	model.size_flags_horizontal = Control.SIZE_EXPAND_FILL; model_row.add_child(model)
	model.fit_to_longest_item = false; model.clip_text = true
	model.item_selected.connect(func(index: int):
		if is_instance_valid(auth) and index >= 0 and index < _slugs.size(): auth.select_model(_slugs[index]))
	reload_models.text = "刷新"; reload_models.pressed.connect(func():
		if is_instance_valid(auth): auth.refresh_models())
	model_row.add_child(reload_models)
	reauthorize.text = "授权使用 ChatGPT 方案"
	reauthorize.pressed.connect(func():
		if is_instance_valid(auth) and not auth.active_id.is_empty(): auth.begin_login(auth.active_id, true))
	add_child(reauthorize)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 10)
	add_child(status_row)
	_hint(status_label); status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(status_label)
	var usage := LinkButton.new(); usage.text = "用量管理 ↗"
	usage.tooltip_text = "在浏览器查看 ChatGPT 账户用量"
	usage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	usage.pressed.connect(func(): OS.shell_open("https://chatgpt.com/settings/usage"))
	status_row.add_child(usage)
	var immediate := Label.new()
	immediate.text = "账户操作即时生效；删除仅限本机。接入方式需保存。"
	immediate.tooltip_text = "删除账户不会删除 OpenAI 账户、其他已保存账户、聊天记录或记忆。"
	_hint(immediate); add_child(immediate)
	delete_confirmation.title = "删除本机账户"
	delete_confirmation.ok_button_text = "删除本机记录"; delete_confirmation.cancel_button_text = "取消"
	delete_confirmation.exclusive = false; delete_confirmation.transient = false
	delete_confirmation.confirmed.connect(_delete_confirmed)
	delete_confirmation.canceled.connect(func(): _delete_id = "")
	add_child(delete_confirmation)
	welcome.title = "ChatGPT 账户已连接"
	welcome.dialog_text = "已授权使用 ChatGPT 方案。\n\n选择「ChatGPT 账户」并保存后，符合条件的 AI 请求将使用该账户的方案额度或可用点数。你可在 ChatGPT 设置中管理用量与撤销授权。"
	welcome.ok_button_text = "知道了"
	welcome.exclusive = false; welcome.transient = false
	welcome.min_size = Vector2i(400, 180)
	welcome.confirmed.connect(func():
		if is_instance_valid(auth): auth.acknowledge_plan())
	add_child(welcome)
	_refresh()

func setup(value: Node) -> void:
	if is_instance_valid(auth):
		if auth.changed.is_connected(_refresh): auth.changed.disconnect(_refresh)
		if auth.first_plan_connected.is_connected(_welcome): auth.first_plan_connected.disconnect(_welcome)
	auth = value
	if is_instance_valid(auth):
		auth.changed.connect(_refresh); auth.first_plan_connected.connect(_welcome)
	if is_node_ready(): _refresh()

func _refresh() -> void:
	if not is_node_ready(): return
	var valid := is_instance_valid(auth)
	var busy: bool = valid and auth.busy
	_ids.clear(); account.clear()
	var entries: Array = auth.accounts() if valid else []
	var selected: bool = false
	for entry in entries:
		if str(entry.id) == str(auth.active_id): selected = true
	if not entries.is_empty() and not selected:
		_ids.append(""); account.add_item("请选择账户")
	if valid:
		for entry in entries:
			_ids.append(str(entry.id)); account.add_item(str(entry.label) + ("" if bool(entry.signed_in) else "（已退出）"))
	if _ids.is_empty(): account.add_item("尚未登录")
	elif selected: account.select(_ids.find(str(auth.active_id)))
	else: account.select(0)
	account.disabled = busy or entries.is_empty()
	login.disabled = not valid or busy
	login.visible = entries.is_empty()
	add.disabled = not valid or busy or entries.size() >= 8
	relogin.disabled = not valid or busy or not selected
	logout_button.disabled = not valid or busy or not selected
	delete_account_button.disabled = not valid or busy or not selected
	for button in [relogin, logout_button, delete_account_button]: button.visible = not entries.is_empty()
	cancel.visible = valid and auth.is_signing_in()
	add.visible = not entries.is_empty()
	_slugs.clear(); model.clear()
	if valid:
		for item in auth.models:
			_slugs.append(str(item.slug)); model.add_item(str(item.display_name))
	if _slugs.is_empty(): model.add_item("登录后按账户获取可用模型")
	elif _slugs.has(str(auth.selected_model)): model.select(_slugs.find(str(auth.selected_model)))
	model.disabled = busy or _slugs.is_empty()
	reload_models.disabled = not valid or busy or not selected
	reauthorize.visible = valid and selected and not auth.can_infer() and not busy
	status_label.text = str(auth.status) if valid else "账户服务准备中"
	if delete_confirmation.visible:
		delete_confirmation.get_ok_button().disabled = not valid or busy or not _ids.has(_delete_id)

func _confirm_delete() -> void:
	if not is_instance_valid(auth) or auth.busy or str(auth.active_id).is_empty(): return
	_delete_id = str(auth.active_id)
	delete_confirmation.dialog_text = "删除以下账户在本机保存的记录和登录凭据？\n\n%s\n\n其他账户、聊天记录和记忆会保留。这不会删除你的 OpenAI 账户。" % str(auth.active_label())
	delete_confirmation.get_ok_button().disabled = false
	delete_confirmation.popup_centered(Vector2i(430, 230))

func _delete_confirmed() -> void:
	# The confirmation belongs to the account shown when it was opened. A later
	# picker change must never make the same confirmation remove another account.
	var id := _delete_id; _delete_id = ""
	if not id.is_empty() and is_instance_valid(auth) and not auth.busy: auth.delete_account(id)

func _welcome() -> void:
	if is_node_ready(): welcome.popup_centered(Vector2i(440, 230))

func _row(caption: String) -> HBoxContainer:
	var row := HBoxContainer.new(); row.custom_minimum_size.y = 32; add_child(row)
	var label := Label.new(); label.text = caption; label.custom_minimum_size.x = 100; row.add_child(label)
	return row

func _hint(label: Label) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", SettingsTheme.MUTED)
