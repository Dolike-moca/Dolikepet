extends Node
## Official public-client OIDC/PKCE flow. Credentials never leave this app's vault.
signal changed
signal failed(message: String)
signal token_ready(token: String, request_id: int)
signal first_plan_connected
const JWT = preload("res://scripts/chatgpt_jwt.gd")
const Request = preload("res://scripts/chatgpt_http.gd")
const ISSUER := "https://auth.openai.com"
const AUTHORIZE := ISSUER + "/api/accounts/authorize"
const TOKEN := ISSUER + "/api/accounts/oauth/token"
const RESOURCE := "https://api.openai.com/v1"
const SCOPES := "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
const MAGIC := "DOLIKE-CHATGPT-1\n"
var status := "尚未连接 ChatGPT 账户"
var busy := false
var active_id := ""
var models: Array = []
var selected_model := ""
# Explicit credential replacement/sign-out, unlike routine refresh/status updates.
var session_revision := 0
var _root := ""
var _native: Object
var _network := false
var _host := ""
var _profiles: Dictionary = {}
var _metadata: Dictionary = {}
var _jwks: Dictionary = {}
var _server: TCPServer
var _peers: Array = []
var _pending := {}
var _serial := 0
var _requests: Array[Node] = []
var _retry_client := ""
var _refresh_lock := ""
var _token_waiting := false
var _token_request_id := 0
var _logging_out := false
var _rotation_id := ""
# Explicit local fixtures only; never an endpoint/configuration exposed to users.
var browser_opener: Callable
var request_override: Callable
var clock_override: Callable

func setup(native_model: Object, root_path: String, network_allowed := true) -> void:
	_native = native_model; _root = root_path.path_join("chatgpt"); _network = network_allowed
	_load()
	status = "已保存 ChatGPT 账户，使用前会核验可用模型" if not active_id.is_empty() else "尚未连接 ChatGPT 账户"
	if bool(_active().get("refresh_pending", false)): status = "上次会话更新未完成，请重新登录 ChatGPT"
	changed.emit()

func accounts() -> Array:
	var result: Array = []
	for id in _profiles:
		var profile: Dictionary = _profiles[id]
		result.append({"id":id,"label":_label(profile),"signed_in":not str(profile.get("refresh_token", "")).is_empty() or not str(profile.get("access_token", "")).is_empty()})
	return result

func active_label() -> String:
	return _label(_profiles[active_id]) if _profiles.has(active_id) else "尚未登录"

func can_infer() -> bool:
	var profile := _active()
	return not _logging_out and not profile.is_empty() and _direct(profile) \
		and (not bool(profile.get("refresh_pending", false)) or _rotation_id == active_id) \
		and (not str(profile.get("refresh_token", "")).is_empty() or (_expires(profile) > _now() + 30 and not str(profile.get("access_token", "")).is_empty()))

func begin_login(registration_id: String = "", request_consent := false) -> bool:
	if busy: return false
	if not _network: _error("当前运行环境未启用账户联网"); return false
	if not _vault_available(): _error("此环境无法安全保存登录凭据"); return false
	if not registration_id.is_empty() and not _profiles.has(registration_id): return false
	if _profiles.size() >= 8 and registration_id.is_empty(): _error("已保存 8 个账户，请使用已有账户登录"); return false
	if not _ensure_host(): _error("无法保存此设备的登录标识"); return false
	_serial += 1
	var verifier := JWT.base64url(Crypto.new().generate_random_bytes(48))
	_server = TCPServer.new()
	if _server.listen(0, "127.0.0.1") != OK: _server = null; _error("无法启动本机登录回调，请稍后重试"); return false
	var profile: Dictionary = _profiles.get(registration_id, {})
	var client := str(profile.get("client_id", _retry_client if not _retry_client.is_empty() else "dynamic_agent_client"))
	_pending = {"id":registration_id,"client":client,"nonce":JWT.base64url(Crypto.new().generate_random_bytes(32)),
		"state":JWT.base64url(Crypto.new().generate_random_bytes(32)),"verifier":verifier,
		"redirect":"http://127.0.0.1:%d/auth/callback" % _server.get_local_port(),
		"started":Time.get_ticks_msec(),"consent":request_consent}
	busy = true; status = "正在准备 ChatGPT 登录…"; changed.emit()
	_prepare_login(_serial)
	return true

func _prepare_login(serial: int) -> void:
	if not await _discover(serial) or serial != _serial: return
	var query := {"client_id":_pending.client,"ext_agent_host_id":_host,"response_type":"code",
		"redirect_uri":_pending.redirect,"scope":SCOPES,"resource":RESOURCE,"state":_pending.state,
		"nonce":_pending.nonce,"code_challenge_method":"S256","code_challenge":JWT.base64url(str(_pending.verifier).sha256_buffer())}
	if _pending.client == "dynamic_agent_client": query.agent_name_hint = "Dolikepet"
	elif _profiles.has(_pending.id):
		var profile: Dictionary = _profiles[_pending.id]
		# The documented no-ID-hint path shows the account selector. Do not put
		# a retained token into the system browser's launch URL/command line.
		if not str(profile.get("email", "")).is_empty(): query.login_hint = profile.email
	if bool(_pending.consent): query.prompt = "consent"
	var url := AUTHORIZE + "?" + _form(query)
	var error: int = int(browser_opener.call(url)) if browser_opener.is_valid() else OS.shell_open(url)
	if error != OK: _abort("无法打开系统浏览器，请检查默认浏览器设置"); return
	status = "请在浏览器完成登录与授权（5 分钟内有效）"; changed.emit()

func _process(_dt: float) -> void:
	if _server == null: return
	if Time.get_ticks_msec() - int(_pending.get("started", 0)) > 300000:
		_abort("登录已超时，请重新点击 Continue with ChatGPT"); return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if _peers.size() >= 8: peer.disconnect_from_host()
		else: _peers.append({"peer":peer,"bytes":PackedByteArray(),"at":Time.get_ticks_msec()})
	for item in _peers.duplicate():
		var peer: StreamPeerTCP = item.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - int(item.at) > 3000:
			peer.disconnect_from_host(); _peers.erase(item); continue
		var count := peer.get_available_bytes()
		if count <= 0: continue
		if item.bytes.size() + count > 16384: _respond(peer, 431, "Request too large"); _peers.erase(item); continue
		var data := peer.get_data(count)
		if data[0] != OK: peer.disconnect_from_host(); _peers.erase(item); continue
		item.bytes.append_array(data[1])
		var raw: String = item.bytes.get_string_from_utf8()
		if not "\r\n\r\n" in raw: continue
		var query := _callback_query(raw)
		if query.is_empty(): _respond(peer, 400, "Invalid callback"); _peers.erase(item); continue
		if not JWT.equal(str(query.get("state", "")), str(_pending.state)):
			_respond(peer, 400, "Invalid state"); _peers.erase(item); continue
		_respond(peer, 200, "Login received. You may return to Dolikepet.")
		_peers.erase(item)
		_handle_callback(query)
		return

func _callback_query(raw: String) -> Dictionary:
	var lines := raw.split("\r\n")
	var first := lines[0].split(" ")
	if first.size() != 3 or first[0] != "GET" or first[2] != "HTTP/1.1": return {}
	var expected_host := "127.0.0.1:%d" % _server.get_local_port()
	var hosts := 0
	for line in lines:
		if line.to_lower().begins_with("host:"):
			hosts += 1
			if line.substr(5).strip_edges() != expected_host: return {}
	if hosts != 1 or not first[1].begins_with("/auth/callback?"): return {}
	var result := {}
	for part in first[1].substr("/auth/callback?".length()).split("&"):
		var pair := part.split("=", true, 1)
		if pair.size() != 2: return {}
		var key := pair[0].replace("+", " ").uri_decode()
		if result.has(key): return {}
		result[key] = pair[1].replace("+", " ").uri_decode()
	return result

func _handle_callback(query: Dictionary) -> void:
	_close_listener()
	if query.has("error"): _abort("你取消了 ChatGPT 登录或授权"); return
	var client := str(query.get("client_id", _pending.client))
	if not _client_valid(client) or (_pending.client != "dynamic_agent_client" and client != _pending.client):
		_abort("登录返回的客户端身份不一致，请重新登录"); return
	var code = query.get("code", "")
	if not code is String or code.is_empty() or code.length() > 8192: _abort("登录回调缺少有效授权码"); return
	_pending.client = client
	status = "正在验证 ChatGPT 账户…"; changed.emit()
	_exchange(code, _serial)

func _exchange(code: String, serial: int) -> void:
	var result: Dictionary = await _request(TOKEN, HTTPClient.METHOD_POST, _form({"grant_type":"authorization_code",
		"client_id":_pending.client,"code":code,"code_verifier":_pending.verifier,"redirect_uri":_pending.redirect,"resource":RESOURCE}))
	if serial != _serial: return
	if not result.ok:
		_retry_client = str(_pending.client)
		_abort("登录凭据交换失败，请重新登录" if _oauth_error(result) == "invalid_grant" else "暂时无法完成登录，请检查网络后重试")
		return
	var token: Dictionary = result.data
	var identity: Dictionary = await _validate_token(token, str(_pending.client), str(_pending.nonce), str(_profiles.get(_pending.id, {}).get("subject", "")), true, serial)
	if serial != _serial: return
	if identity.is_empty(): _abort("账户身份验证未通过，原有账户保持不变"); return
	var profile := _profile(token, identity, str(_pending.client))
	if profile.is_empty(): _abort("登录令牌格式不完整，请重新登录"); return
	var id := (ISSUER + "\n" + str(identity.sub) + "\n" + str(_pending.client)).sha256_text()
	var previous: Dictionary = _profiles.get(id, {})
	profile["welcomed"] = bool(previous.get("welcomed", false))
	profile["model"] = str(previous.get("model", ""))
	var catalog: Array = []
	if _direct(profile):
		catalog = await _catalog(str(profile.access_token), serial)
		if serial != _serial: return
	if not _save_profile(id, profile): _abort("无法安全保存登录凭据，原有账户保持不变"); return
	_profiles[id] = profile
	if id == active_id: session_revision += 1
	_retry_client = ""
	# Keep the old active account if a new eligible account's model request failed.
	if _direct(profile) and catalog.is_empty():
		var saved := _save_index()
		_finish(); status = "账户已保存，但无法取得可用模型；请在账户列表重试" if saved else "账户已验证，但配置保存失败；请检查存储权限后重试"
		changed.emit(); return
	var previous_active := active_id
	active_id = id; models = catalog; _choose_model(profile)
	if not _save_index():
		active_id = previous_active; models = []; selected_model = ""
		_finish(); _error("账户已验证，但配置保存失败；请检查存储权限后重试"); return
	_finish()
	status = "ChatGPT 账户已连接" if _direct(profile) else "账户已登录，但未授权使用 ChatGPT 方案；可重新授权"
	changed.emit()
	if serial == _serial and active_id == id and _direct(profile) and not bool(profile.welcomed): first_plan_connected.emit()

func cancel_login() -> void:
	# Let rotating refresh/revocation finish; stopping a chat is not signing out.
	if _pending.is_empty() and _server == null: return
	_serial += 1; _token_waiting = false
	_cancel_requests(); _close_listener(); _pending = {}; busy = false; _unlock()
	status = "账户操作已取消"; changed.emit()

func is_signing_in() -> bool:
	return not _pending.is_empty() or _server != null

func request_access_token(request_id: int = 0) -> void:
	if _logging_out: _error("正在退出账户，请稍后重新登录"); return
	_token_request_id = request_id
	var profile := _active()
	if profile.is_empty() or not _direct(profile): _error("请先登录 ChatGPT 并授权使用方案"); return
	if bool(profile.get("refresh_pending", false)):
		if busy and _rotation_id == active_id: _token_waiting = true; return
		_error("上次会话更新未完成，请重新登录 ChatGPT"); return
	if _expires(profile) > _now() + 60 and not str(profile.get("access_token", "")).is_empty() and not selected_model.is_empty():
		token_ready.emit(str(profile.access_token), request_id); return
	if busy:
		if _pending.is_empty() and not status.contains("退出"):
			_token_waiting = true # Share one in-flight refresh; never rotate twice.
			return
		_error("账户正在更新，请稍后重试"); return
	if not _network: _error("当前运行环境未启用账户联网"); return
	_token_waiting = true; busy = true; _serial += 1; status = "正在更新 ChatGPT 会话…"; changed.emit()
	_refresh_and_models(_serial, active_id)

func select_account(id: String) -> void:
	if busy or not _profiles.has(id): return
	var previous := active_id
	active_id = id
	if not _save_index(): active_id = previous; _error("账户选择无法保存，请检查存储权限"); return
	models = []; selected_model = ""
	status = "正在载入所选账户的模型…"; changed.emit()
	if not _network: status = "当前运行环境未启用账户联网"; changed.emit(); return
	busy = true; _serial += 1
	_refresh_and_models(_serial, id)

func select_model(slug: String) -> void:
	if busy: return
	for model in models:
		if str(model.slug) == slug and _profiles.has(active_id):
			var previous := selected_model
			selected_model = slug; _profiles[active_id]["model"] = slug
			if not _save_profile(active_id, _profiles[active_id]):
				selected_model = previous; _profiles[active_id]["model"] = previous
				_error("模型选择暂时无法保存"); return
			changed.emit(); return

func refresh_models() -> void:
	if not active_id.is_empty(): select_account(active_id)

func _refresh_and_models(serial: int, id: String) -> void:
	var profile: Dictionary = _profiles.get(id, {}).duplicate(true)
	if profile.is_empty() or not _direct(profile): _finish(); _error("此账户尚未授权使用 ChatGPT 方案"); return
	if bool(profile.get("refresh_pending", false)): _finish(); _error("上次会话更新未完成，请重新登录 ChatGPT"); return
	if _expires(profile) <= _now() + 60 or str(profile.get("access_token", "")).is_empty():
		if str(profile.get("refresh_token", "")).is_empty(): _finish(); _error("登录已过期，请重新登录 ChatGPT"); return
		if not _lock(id): _finish(); _error("另一个桌宠正在更新此账户，请稍后重试"); return
		# Re-read after acquiring the cross-process rotation lock.
		var latest := _read_profile(id)
		if not latest.is_empty(): profile = latest
		if bool(profile.get("refresh_pending", false)):
			_profiles[id] = profile; _finish(); _error("上次会话更新未完成，请重新登录 ChatGPT"); return
		if _expires(profile) <= _now() + 60:
			# Mark the old refresh token unusable on disk BEFORE sending it. A
			# crash or any later validation/save failure must never replay it.
			var guarded := profile.duplicate(true)
			guarded["refresh_pending"] = true
			if not _save_profile(id, guarded):
				_finish(); _error("无法安全准备会话更新，请检查存储权限后重试"); return
			_profiles[id] = guarded; _rotation_id = id
			var result: Dictionary = await _request(TOKEN, HTTPClient.METHOD_POST, _form({"grant_type":"refresh_token",
				"client_id":profile.client_id,"refresh_token":profile.refresh_token,"resource":RESOURCE}))
			if serial != _serial: _unlock(); return
			if not result.ok:
				var code := _oauth_error(result)
				if code in ["invalid_grant","invalid_refresh_token","token_expired","refresh_token_expired","refresh_token_invalidated","refresh_token_reused"]:
					_erase_tokens(guarded); _profiles[id] = guarded; _save_profile(id, guarded)
				_unlock(); _finish(); _error("登录已失效，请重新登录 ChatGPT" if code.begins_with("invalid") or code.contains("token") else "未能确认会话更新结果，请重新登录 ChatGPT"); return
			var token: Dictionary = result.data
			var identity: Dictionary = {"sub":profile.subject,"email":profile.get("email", ""),"name":profile.get("name", "")}
			if not str(token.get("id_token", "")).is_empty():
				identity = await _validate_token(token, str(profile.client_id), "", str(profile.subject), false, serial)
				if serial != _serial: _unlock(); return
				if identity.is_empty(): _unlock(); _finish(); _error("更新后的账户身份验证失败，请重新登录"); return
			# Refresh may omit scopes/ID token; retain them as permitted by OAuth.
			if not token.has("scope"): token.scope = " ".join(profile.get("scopes", []))
			if not token.has("id_token"): token.id_token = profile.get("id_token", "")
			var updated := _profile(token, identity, str(profile.client_id))
			if updated.is_empty() or str(updated.get("refresh_token", "")).is_empty(): _unlock(); _finish(); _error("更新会话的令牌不完整，请重新登录"); return
			updated["model"] = profile.get("model", ""); updated["welcomed"] = profile.get("welcomed", false)
			if not _save_profile(id, updated): _unlock(); _finish(); _error("无法安全保存更新后的会话，请重新登录"); return
			profile = updated; _profiles[id] = profile
		_unlock()
	_profiles[id] = profile
	if not _direct(profile): _finish(); _error("此账户未授权使用 ChatGPT 方案"); return
	var catalog: Array = await _catalog(str(profile.access_token), serial)
	if serial != _serial: return
	if catalog.is_empty(): _finish(); _error("无法取得此账户的可用模型，请稍后重试"); return
	models = catalog; _choose_model(profile)
	var should_emit := _token_waiting
	var request_id := _token_request_id
	_finish(); status = "ChatGPT 账户已就绪"; changed.emit()
	if should_emit and serial == _serial and active_id == id and request_id == _token_request_id:
		token_ready.emit(str(profile.access_token), request_id)

func logout() -> void:
	if active_id.is_empty() or busy: return
	cancel_login(); _serial += 1; busy = true; _logging_out = true
	var profile := _active().duplicate(true)
	var signed_out := profile.duplicate(true)
	_erase_tokens(signed_out)
	_profiles[active_id] = signed_out
	session_revision += 1
	var local_cleared := _save_profile(active_id, signed_out)
	if not local_cleared:
		local_cleared = DirAccess.remove_absolute(_root.path_join(active_id + ".bin")) == OK
	models = []; selected_model = ""; status = "正在退出 ChatGPT…"; changed.emit()
	_logout(_serial, profile, local_cleared)

func delete_account(id: String) -> bool:
	# Local removal is separate from logout/revocation. Never replace the selected
	# billing account implicitly, and never interrupt a rotating refresh token.
	if busy or not _id_valid(id) or not _profiles.has(id): return false
	if not _lock(id): _error("此账户正在另一处更新，请稍后再删除"); return false
	for suffix in [".bin.tmp", ".bin"]:
		var path := _root.path_join(id + suffix)
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
			_unlock(); _error("本机账户凭据无法删除，请检查存储权限后重试"); return false
	_serial += 1; _token_waiting = false
	_profiles.erase(id)
	if active_id == id:
		active_id = ""; models = []; selected_model = ""; session_revision += 1
	var saved := _save_index()
	_unlock()
	# A failed index write must never restore credentials after their removal.
	# On restart, the loader ignores any stale entry whose vault file is absent.
	if not saved:
		_error("本机凭据已删除，但账户列表保存失败；请检查存储权限后重试")
		return false
	status = "已删除本机账户记录与登录凭据；其他账户保持不变"
	changed.emit()
	return true

func _logout(serial: int, profile: Dictionary, local_cleared: bool) -> void:
	var confirmed := str(profile.get("refresh_token", "")).is_empty()
	if not confirmed and _network:
		if await _discover(serial, false):
			for attempt in 2:
				var result: Dictionary = await _request(str(_metadata.revocation_endpoint), HTTPClient.METHOD_POST,
					_form({"token":profile.refresh_token,"token_type_hint":"refresh_token","client_id":profile.client_id}))
				if serial != _serial: return
				confirmed = bool(result.ok) and int(result.status) == 200
				if confirmed or (int(result.status) > 0 and int(result.status) < 500): break
				if attempt == 0: await get_tree().create_timer(0.5).timeout
	if serial != _serial: return
	_finish()
	if not local_cleared: _error("已停止使用账户，但本地凭据清除失败；请检查存储权限，并在 ChatGPT 设置中断开应用"); return
	status = "已退出 ChatGPT" if confirmed else "已在本机退出；未确认远端撤销，可在 ChatGPT 设置中断开应用"
	changed.emit()

func acknowledge_plan() -> void:
	if not _profiles.has(active_id): return
	_profiles[active_id]["welcomed"] = true
	_save_profile(active_id, _profiles[active_id])

func _discover(serial: int, report := true) -> bool:
	if not _metadata.is_empty(): return true
	var result: Dictionary = await _request(ISSUER + "/.well-known/openid-configuration")
	if serial != _serial: return false
	var data: Dictionary = result.data
	if not result.ok or data.get("issuer") != ISSUER or data.get("authorization_endpoint") != AUTHORIZE or data.get("token_endpoint") != TOKEN \
		or not _auth_url(str(data.get("jwks_uri", ""))) or not _auth_url(str(data.get("revocation_endpoint", ""))):
		if report: _abort("无法核验 OpenAI 登录服务，请检查网络后重试")
		return false
	_metadata = data
	return true

func _validate_token(token: Dictionary, client: String, nonce: String, subject: String, check_nonce: bool, serial: int) -> Dictionary:
	if not await _discover(serial) or serial != _serial: return {}
	# Fetch current signing keys per authorization; never trust JWT jku/jwk headers.
	var result: Dictionary = await _request(str(_metadata.jwks_uri))
	if serial != _serial or not result.ok: return {}
	_jwks = result.data
	return JWT.verify(str(token.get("id_token", "")), _jwks, client, nonce, _now(), subject, check_nonce)

func _catalog(access: String, serial: int) -> Array:
	var result: Dictionary = await _request(RESOURCE + "/models", HTTPClient.METHOD_GET, "", access)
	if serial != _serial or not result.ok: return []
	var raw = result.data.get("models", [])
	if not raw is Array: return []
	var entries: Array = []
	var slugs: Array = []
	for model in raw:
		if not model is Dictionary or model.get("visibility") != "list": continue
		if not model.get("slug") is String or not model.get("display_name") is String: continue
		var slug: String = model.slug
		if slug.is_empty() or slug.length() > 128 or slugs.has(slug): continue
		entries.append({"slug":slug,"display_name":str(model.display_name).left(120)}); slugs.append(slug)
		if entries.size() >= 100: break
	return entries

func _request(url: String, method := HTTPClient.METHOD_GET, body := "", access := "") -> Dictionary:
	if request_override.is_valid(): return await request_override.call(url, method, body, access)
	if not _network: return {"ok":false,"status":0,"data":{}}
	var request := Request.new()
	add_child(request); _requests.append(request)
	var headers := PackedStringArray(["Accept: application/json"])
	if method == HTTPClient.METHOD_POST: headers.append("Content-Type: application/x-www-form-urlencoded")
	if not access.is_empty(): headers.append("Authorization: Bearer " + access)
	if not request.send(url, method, headers, body):
		_requests.erase(request); request.queue_free(); return {"ok":false,"status":0,"data":{}}
	var result: Dictionary = await request.finished
	_requests.erase(request); request.queue_free()
	return result

func _profile(token: Dictionary, identity: Dictionary, client: String) -> Dictionary:
	if str(token.get("token_type", "")).to_lower() != "bearer" or not token.get("access_token") is String or str(token.access_token).is_empty(): return {}
	for field in ["access_token", "refresh_token", "id_token"]:
		if token.has(field) and not _credential(str(token[field]), field == "access_token"): return {}
	if str(token.access_token).length() > 16384 or not JWT._number(token.get("expires_in")) or float(token.expires_in) <= 0: return {}
	if not token.get("scope") is String: return {}
	return {"issuer":ISSUER,"subject":str(identity.sub),"email":str(identity.get("email", "")).left(254),
		"name":str(identity.get("name", "")).left(100),"client_id":client,"access_token":token.access_token,
		"refresh_token":str(token.get("refresh_token", "")),"id_token":str(token.get("id_token", "")),
		"scopes":Array(str(token.scope).split(" ", false)),"expires_at":_now() + mini(int(token.expires_in), 86400),
		"earliest_refresh_at":token.get("earliest_refresh_at", 0)}

static func _credential(value: String, required := false) -> bool:
	if value.is_empty(): return not required
	if value.length() > 32768: return false
	for index in value.length():
		var point := value.unicode_at(index)
		if point <= 32 or point >= 127: return false
	return true

func _choose_model(profile: Dictionary) -> void:
	selected_model = ""
	for model in models:
		if model.slug == profile.get("model", ""): selected_model = model.slug
	if selected_model.is_empty() and not models.is_empty(): selected_model = str(models[0].slug)
	if _profiles.has(active_id): _profiles[active_id]["model"] = selected_model

func _active() -> Dictionary: return _profiles.get(active_id, {})
func _direct(profile: Dictionary) -> bool: return "chatgpt.tokens.use.direct" in profile.get("scopes", [])
func _expires(profile: Dictionary) -> int: return int(profile.get("expires_at", 0))
func _now() -> int: return int(clock_override.call()) if clock_override.is_valid() else int(Time.get_unix_time_from_system())
func _label(profile: Dictionary) -> String:
	var name := str(profile.get("email", profile.get("name", "ChatGPT")))
	if name.is_empty(): name = "ChatGPT 账户"
	return name + " · " + str(profile.get("client_id", "")).right(6)
func _oauth_error(result: Dictionary) -> String:
	var value = result.get("data", {}).get("error", "")
	return str(value.get("code", "")) if value is Dictionary else str(value)
static func _client_valid(client: String) -> bool:
	if not client.begins_with("oaiapp_") or client.length() > 256: return false
	for character in client:
		if not character in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-": return false
	return true
static func _auth_url(url: String) -> bool:
	return url.begins_with(ISSUER + "/") and not "#" in url and not "?" in url and not "\\" in url
static func _form(data: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in data: parts.append(str(key).uri_encode() + "=" + str(data[key]).uri_encode())
	return "&".join(parts)
func _respond(peer: StreamPeerTCP, code: int, text: String) -> void:
	var bytes := text.to_utf8_buffer()
	peer.put_data(("HTTP/1.1 %d Result\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\nContent-Length: %d\r\n\r\n" % [code,bytes.size()]).to_utf8_buffer() + bytes)
	peer.disconnect_from_host()
func _close_listener() -> void:
	if _server != null: _server.stop(); _server = null
	for item in _peers: item.peer.disconnect_from_host()
	_peers.clear()
func _cancel_requests() -> void:
	for request in _requests.duplicate():
		if is_instance_valid(request): request.cancel()
func _finish() -> void:
	busy = false; _pending = {}; _token_waiting = false; _logging_out = false; _rotation_id = ""; _close_listener(); _unlock()
func _abort(message: String) -> void:
	_serial += 1; _cancel_requests(); _finish(); _error(message)
func _error(message: String) -> void:
	status = message; changed.emit(); failed.emit(message)
func _erase_tokens(profile: Dictionary) -> void:
	for key in ["access_token","refresh_token","id_token"]: profile[key] = ""
	profile.expires_at = 0

func _vault_available() -> bool:
	return OS.get_name() == "Windows" and is_instance_valid(_native) and _native.has_method("encrypt_desktop_secret") and _native.has_method("decrypt_desktop_secret")
func _ensure_host() -> bool:
	if _host.is_empty():
		var bytes := Crypto.new().generate_random_bytes(16)
		bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128
		var value := bytes.hex_encode()
		_host = "urn:uuid:%s-%s-%s-%s-%s" % [value.substr(0,8),value.substr(8,4),value.substr(12,4),value.substr(16,4),value.substr(20,12)]
	return _save_index()
func _load() -> void:
	if _root.is_empty(): return
	var index := _read_json(_root.path_join("accounts.json"), 32768)
	var host := str(index.get("host", ""))
	if host.begins_with("urn:uuid:") and host.length() == 45: _host = host
	var ids = index.get("accounts", [])
	if ids is Array:
		for id in ids.slice(0,8):
			if not id is String or not _id_valid(id): continue
			var profile := _read_profile(id)
			if not profile.is_empty(): _profiles[id] = profile
	active_id = str(index.get("active", "")) if _profiles.has(str(index.get("active", ""))) else ""
func _save_index() -> bool:
	return _write(_root.path_join("accounts.json"), JSON.stringify({"schema":1,"host":_host,"active":active_id,"accounts":_profiles.keys()}).to_utf8_buffer())
func _save_profile(id: String, profile: Dictionary) -> bool:
	if not _vault_available() or not _id_valid(id): return false
	var bytes := JSON.stringify(profile).to_utf8_buffer()
	if bytes.size() > 16384: bytes.fill(0); return false
	var encrypted: PackedByteArray = _native.call("encrypt_desktop_secret", bytes)
	bytes.fill(0)
	if encrypted.is_empty(): return false
	return _write(_root.path_join(id + ".bin"), MAGIC.to_utf8_buffer() + encrypted)
func _read_profile(id: String) -> Dictionary:
	if not _vault_available() or not _id_valid(id): return {}
	var file := FileAccess.open(_root.path_join(id + ".bin"), FileAccess.READ)
	if file == null or file.get_length() > 65536: return {}
	if file.get_buffer(MAGIC.length()).get_string_from_utf8() != MAGIC: return {}
	var plain: PackedByteArray = _native.call("decrypt_desktop_secret", file.get_buffer(file.get_length() - MAGIC.length()))
	var profile := JWT._json(plain); plain.fill(0)
	if profile.get("issuer") != ISSUER or not _client_valid(str(profile.get("client_id", ""))) or str(profile.get("subject", "")).is_empty(): return {}
	if (ISSUER + "\n" + str(profile.subject) + "\n" + str(profile.client_id)).sha256_text() != id: return {}
	if bool(profile.get("refresh_pending", false)):
		# A pending marker survives crashes and failed replacement writes.
		# Keep only the registration mapping; never load its old tokens for use.
		_erase_tokens(profile)
	return profile
static func _id_valid(value: String) -> bool:
	if value.length() != 64: return false
	for character in value:
		if not character in "0123456789abcdef": return false
	return true
static func _read_json(path: String, limit: int) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > limit: return {}
	return JWT._json(file.get_buffer(file.get_length()))
static func _write(path: String, bytes: PackedByteArray) -> bool:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes); file.flush()
	var error := file.get_error(); file.close()
	if error == OK: error = DirAccess.rename_absolute(path + ".tmp", path)
	return error == OK
func _lock(id: String) -> bool:
	var path := _root.path_join(id + ".refresh-lock")
	var owner := path.path_join("owner.json")
	if DirAccess.dir_exists_absolute(path):
		var old := _read_json(owner, 1024)
		if old.has("pid") and not OS.is_process_running(int(old.pid)):
			DirAccess.remove_absolute(owner); DirAccess.remove_absolute(path)
	if DirAccess.make_dir_absolute(path) != OK: return false
	_refresh_lock = path
	if not _write(owner, JSON.stringify({"pid":OS.get_process_id()}).to_utf8_buffer()): _unlock(); return false
	return true
func _unlock() -> void:
	if _refresh_lock.is_empty(): return
	DirAccess.remove_absolute(_refresh_lock.path_join("owner.json"))
	DirAccess.remove_absolute(_refresh_lock)
	_refresh_lock = ""
func _exit_tree() -> void:
	_serial += 1; _cancel_requests(); _close_listener(); _unlock()
