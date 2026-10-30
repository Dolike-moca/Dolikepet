extends SceneTree
## Synthetic signed identity, fake HTTPS and isolated DPAPI vault. No real account.
const Auth = preload("res://scripts/chatgpt_auth.gd")
const JWT = preload("res://scripts/chatgpt_jwt.gd")
class SaveFaultAuth extends "res://scripts/chatgpt_auth.gd":
	var reject_final_save := false
	var reject_index_save := false
	func _save_profile(id: String, profile: Dictionary) -> bool:
		if reject_final_save and not bool(profile.get("refresh_pending", false)): return false
		return super._save_profile(id, profile)
	func _save_index() -> bool:
		return false if reject_index_save else super._save_index()
var auth
var key: CryptoKey
var jwks := {}
var url := ""
var requests: Array = []
var failure_messages: Array = []
var checks := 0
var failures: Array[String] = []
var last_token := ""
var last_token_id := -1
var delay_refresh := false
var delay_revoke := false
var now := 1800000000
var token_subject := "fixture-user"
var grant_direct := true
var revoke_ok := true
var refreshes := 0
var next_client := "oaiapp_fixture_a"
var refresh_fault := ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("CHATGPT AUTH: " + message)

func signed(claims: Dictionary, algorithm := "RS256") -> String:
	var header := JWT.base64url(JSON.stringify({"alg":algorithm,"kid":"fixture-rsa","typ":"JWT"}).to_utf8_buffer())
	var body := JWT.base64url(JSON.stringify(claims).to_utf8_buffer())
	var message := header + "." + body
	return message + "." + JWT.base64url(Crypto.new().sign(HashingContext.HASH_SHA256, message.sha256_buffer(), key))

func claim(client := "oaiapp_fixture_a", nonce := "fixture-nonce") -> Dictionary:
	return {"iss":Auth.ISSUER,"sub":token_subject,"aud":client,"nonce":nonce,"iat":now-10,"exp":now+3600,
		"email":"fixture@example.invalid","name":"Fixture"}

func browser(value: String) -> int:
	url = value; return OK

func fake_request(target: String, method: int, body: String, access: String) -> Dictionary:
	requests.append({"url":target,"method":method,"body":body,"access":access})
	if target.ends_with("openid-configuration"):
		return good({"issuer":Auth.ISSUER,"authorization_endpoint":Auth.AUTHORIZE,"token_endpoint":Auth.TOKEN,
			"jwks_uri":Auth.ISSUER+"/.well-known/jwks.json","revocation_endpoint":Auth.ISSUER+"/api/accounts/oauth/revoke"})
	if target.ends_with("jwks.json"): return good(jwks)
	if target == Auth.TOKEN:
		var fields := form(body)
		var client: String = fields.client_id
		var nonce: String = str(auth._pending.get("nonce", ""))
		if fields.grant_type == "refresh_token":
			refreshes += 1
			if delay_refresh: await create_timer(0.04).timeout
		var identity := claim(client, nonce)
		if fields.grant_type == "refresh_token" and refresh_fault == "identity": identity.sub = "different-person"
		var token := {"access_token":"fixture-access-"+str(refreshes),"refresh_token":"fixture-refresh-"+str(refreshes),"id_token":signed(identity),
			"token_type":"Bearer","expires_in":3600,"scope":Auth.SCOPES if grant_direct else "openid email profile"}
		if fields.grant_type == "refresh_token" and refresh_fault == "format": token.erase("refresh_token")
		return good(token)
	if target.ends_with("/models"):
		return good({"models":[{"slug":"fixture-hidden","display_name":"hidden","visibility":"hidden"},
			{"slug":"fixture-model","display_name":"Fixture Model","visibility":"list"},
			{"slug":"fixture-second","display_name":"Second Model","visibility":"list"}]})
	if target.ends_with("/revoke"):
		if delay_revoke: await create_timer(0.04).timeout
		return {"ok":revoke_ok,"status":200 if revoke_ok else 400,"data":{},"empty":true}
	return {"ok":false,"status":404,"data":{}}
func good(data: Dictionary) -> Dictionary: return {"ok":true,"status":200,"data":data}
func form(body: String) -> Dictionary:
	var parsed := {}
	for field in body.split("&"):
		var pair := field.split("=", true, 1)
		if pair.size() == 2: parsed[pair[0].uri_decode()] = pair[1].uri_decode()
	return parsed

func der(data: PackedByteArray, position: int) -> Dictionary:
	var tag := data[position]; position += 1
	var length := int(data[position]); position += 1
	if length & 128:
		var bytes := length & 127; length = 0
		for _n in bytes: length = (length << 8) | data[position]; position += 1
	return {"tag":tag,"body":data.slice(position, position+length),"next":position+length}

func public_jwk() -> Dictionary:
	var pem := key.save_to_string(true)
	var base64 := ""
	for line in pem.split("\n"):
		if not line.begins_with("---"): base64 += line.strip_edges()
	var outer := der(Marshalls.base64_to_raw(base64), 0)
	var first := der(outer.body, 0)
	var rsa: PackedByteArray = outer.body
	if first.tag == 0x30:
		var bits := der(outer.body, first.next)
		rsa = der(bits.body.slice(1), 0).body
	var n := der(rsa, 0)
	var e := der(rsa, n.next)
	var modulus: PackedByteArray = n.body
	if modulus[0] == 0: modulus = modulus.slice(1)
	return {"kty":"RSA","use":"sig","alg":"RS256","kid":"fixture-rsa","n":JWT.base64url(modulus),"e":JWT.base64url(e.body)}

func complete_login() -> void:
	auth._handle_callback({"state":auth._pending.state,"code":"fixture-auth-code","client_id":next_client})
	await process_frame

func loopback(raw: String) -> String:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", auth._server.get_local_port())
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED: break
		await process_frame
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: return ""
	peer.put_data(raw.to_utf8_buffer())
	var response := ""
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var count := peer.get_available_bytes()
		if count > 0:
			var bytes := peer.get_data(count)
			if bytes[0] == OK: response += bytes[1].get_string_from_utf8()
		if not response.is_empty() or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: break
		await process_frame
	peer.disconnect_from_host()
	return response

func run() -> void:
	key = Crypto.new().generate_rsa(2048)
	jwks = {"keys":[public_jwk()]}
	var claims := claim()
	check(not JWT.verify(signed(claims),jwks,next_client,"fixture-nonce",now).is_empty(),"signed ID token validates")
	check(JWT.verify(signed(claims),jwks,next_client,"wrong",now).is_empty(),"nonce mismatch rejected")
	check(JWT.verify(signed(claims),jwks,"oaiapp_other","fixture-nonce",now).is_empty(),"audience mismatch rejected")
	check(JWT.verify(signed(claims),jwks,next_client,"fixture-nonce",now+4000).is_empty(),"expired ID token rejected")
	check(JWT.verify(signed(claims,"none"),jwks,next_client,"fixture-nonce",now).is_empty(),"algorithm confusion rejected")
	claims.iss = "https://attacker.invalid"
	check(JWT.verify(signed(claims),jwks,next_client,"fixture-nonce",now).is_empty(),"issuer mismatch rejected")
	claims = claim(); claims.iat = now + 500
	check(JWT.verify(signed(claims),jwks,next_client,"fixture-nonce",now).is_empty(),"future-issued identity rejected")
	claims = claim(); claims.aud = [next_client,"second-audience"]
	check(JWT.verify(signed(claims),jwks,next_client,"fixture-nonce",now).is_empty(),"multiple audiences require matching azp")
	claims.azp = next_client
	check(not JWT.verify(signed(claims),jwks,next_client,"fixture-nonce",now).is_empty(),"valid multi-audience authorized party")
	check(JWT.verify(signed(claim()),jwks,next_client,"fixture-nonce",now,"wrong-subject").is_empty(),"returning identity must match")
	var native = ClassDB.instantiate("GDCubismUserModel")
	auth = Auth.new(); root.add_child(auth)
	var fixture := ProjectSettings.globalize_path("res://../../_work/tests/chatgpt-auth/%d" % OS.get_process_id())
	auth.clock_override = func(): return now
	auth.browser_opener = browser; auth.request_override = fake_request
	auth.setup(native,fixture,true)
	auth.token_ready.connect(func(token: String, request_id: int): last_token = token; last_token_id = request_id)
	auth.failed.connect(func(message: String): failure_messages.append(message))
	check(not auth.can_infer(),"new install cannot infer")
	check(auth.begin_login(),"login begins with local listener")
	check(auth._server.get_local_port() > 0 and auth._server.is_listening(),"listener binds chosen loopback port")
	var query := form(url.split("?",true,1)[1])
	check(query.client_id == "dynamic_agent_client" and query.agent_name_hint == "Dolikepet","dynamic registration uses app's true name")
	check(query.redirect_uri.begins_with("http://127.0.0.1:") and query.redirect_uri.ends_with("/auth/callback"),"callback exact loopback host and path")
	check(query.ext_agent_host_id.begins_with("urn:uuid:") and query.ext_agent_host_id.length() == 45,"stable random host ID")
	check(query.code_challenge == JWT.base64url(str(auth._pending.verifier).sha256_buffer()),"PKCE S256 challenge")
	check(query.scope.contains("chatgpt.tokens.use.direct") and query.resource == Auth.RESOURCE,"explicit plan permission requested")
	var raw := "GET /auth/callback?code=test&state=%s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n\r\n" % [auth._pending.state,auth._server.get_local_port()]
	check(not auth._callback_query(raw).is_empty(),"correct callback HTTP accepted")
	check(auth._callback_query(raw.replace("Host: 127.0.0.1", "Host: attacker.invalid")).is_empty(),"untrusted callback host rejected")
	check(auth._callback_query(raw.replace("code=test", "code=test&code=other")).is_empty(),"duplicate callback parameter rejected")
	check(auth._callback_query(raw.replace("/auth/callback?", "/callback?")).is_empty(),"wrong callback path rejected")
	var initial_host: String = auth._host
	var bad: String = await loopback(raw.replace(str(auth._pending.state), "bad-state"))
	check(bad.begins_with("HTTP/1.1 400") and auth.busy and auth._server != null,"wrong-state TCP callback cannot end pending login")
	var returned: String = await loopback(raw.replace("code=test", "code=fixture-auth-code&client_id=" + next_client))
	check(returned.begins_with("HTTP/1.1 200"),"real loopback callback received and acknowledged")
	await process_frame
	check(auth.accounts().size() == 1 and auth.can_infer(),"verified identity and grant saved")
	check(auth.models.size() == 2 and auth.selected_model == "fixture-model","model catalog preserves visible ordering")
	check(last_token.is_empty(),"login never emits inference credential unsolicited")
	var id: String = auth.active_id
	var vault := FileAccess.get_file_as_bytes(auth._root.path_join(id + ".bin"))
	check(not vault.get_string_from_ascii().contains("fixture-access"),"credentials persisted as ciphertext")
	auth.request_access_token()
	check(last_token == "fixture-access-0","explicit token request receives validated account token")
	auth.select_model("fixture-second")
	check(auth.selected_model == "fixture-second","account model selection")
	auth._profiles[id].expires_at = now-1; auth._save_profile(id,auth._profiles[id])
	last_token = ""; auth.request_access_token(); await process_frame
	check(refreshes == 1 and last_token == "fixture-access-1","expired token rotates through one refresh")
	check(auth._profiles[id].refresh_token == "fixture-refresh-1","replacement refresh token retained")
	check(auth.selected_model == "fixture-second","refresh retains chosen available model")
	last_token = ""; delay_refresh = true
	auth._profiles[id].expires_at = now-1; auth._save_profile(id,auth._profiles[id])
	auth.request_access_token(100); auth.request_access_token(101)
	check(not auth.delete_account(id), "deletion cannot interrupt an in-flight rotating refresh")
	auth.select_model("fixture-model"); auth.cancel_login()
	check(auth.busy and auth.selected_model == "fixture-second","cancel-login and model switch do not abort rotating refresh")
	await create_timer(0.08).timeout
	check(refreshes == 2 and last_token_id == 101 and last_token == "fixture-access-2","concurrent token demand shares one refresh and emits latest request ID")
	delay_refresh = false
	var fresh := Auth.new(); root.add_child(fresh); fresh.setup(native,fixture,false)
	check(fresh._host == initial_host and fresh.active_id == id,"restart retains host and account mapping")
	check(fresh._profiles[id].refresh_token == "fixture-refresh-2","encrypted credentials reload")
	fresh.queue_free(); await process_frame
	var retained: Dictionary = auth._profiles[id].duplicate(true)
	var retained_vault := FileAccess.get_file_as_bytes(auth._root.path_join(id + ".bin"))
	var revision: int = auth.session_revision
	check(auth.begin_login(id), "explicit relogin starts for the selected registration")
	var canceled_state: String = auth._pending.state
	check(not auth.begin_login(id) and not auth.delete_account(id), "duplicate login and deletion are rejected during authentication")
	auth.cancel_login()
	check(auth._profiles[id] == retained and FileAccess.get_file_as_bytes(auth._root.path_join(id + ".bin")) == retained_vault and auth.session_revision == revision, "canceling relogin preserves old credentials and session identity")
	check(auth.begin_login(id),"returning login begins")
	check(str(auth._pending.state) != canceled_state, "relogin retry uses fresh transaction state")
	query = form(url.split("?",true,1)[1])
	check(query.client_id == next_client and not query.has("agent_name_hint") and not query.has("id_token_hint"),"reauthorization reuses client without exposing a token in the browser launch URL")
	check(query.ext_agent_host_id == initial_host,"reauthorization does not create new host")
	token_subject = "wrong-person"
	await complete_login()
	check(auth.active_id == id and auth._profiles[id].subject == "fixture-user","wrong returning subject cannot replace existing account")
	check(auth._profiles[id] == retained and auth.session_revision == revision, "failed reauthentication leaves prior credentials and session revision unchanged")
	token_subject = "fixture-user"
	check(auth.begin_login(id), "same-account reauthentication can retry after validation failure")
	await complete_login()
	check(auth.active_id == id and auth.selected_model == "fixture-second" and auth.session_revision == revision + 1, "successful same-account relogin changes session revision even with unchanged account and model")
	check(auth.begin_login(),"second registration begins")
	next_client = "oaiapp_fixture_b"; grant_direct = false
	await complete_login()
	check(auth.accounts().size() == 2 and not auth.can_infer(),"identity-only consent retained without inference")
	check(auth.active_id != id and auth.active_label().ends_with("ture_b"),"same-email registrations have distinct labels")
	var second_id: String = auth.active_id
	auth.select_account(id); await process_frame
	check(auth.active_id == id and auth.can_infer(),"can switch to original account without mixing tokens")
	revoke_ok = false; delay_revoke = true; auth.logout()
	check(auth.busy and not auth.can_infer() and auth._profiles[id].access_token.is_empty(),"sign-out disables and clears token before network revocation finishes")
	auth.cancel_login()
	check(auth.busy and not auth.can_infer(),"cancel-login cannot revive a signing-out session")
	await create_timer(0.08).timeout
	check(not auth.can_infer() and auth._profiles[id].access_token.is_empty() and auth._profiles[id].refresh_token.is_empty(),"sign-out clears selected account tokens")
	check(auth.status.contains("未确认远端撤销"),"unconfirmed remote revocation is explained")
	check(auth.active_id == id and auth._host == initial_host,"sign-out retains registration and host")
	auth.begin_login(id); query = form(url.split("?",true,1)[1])
	check(not query.has("id_token_hint") and query.client_id == "oaiapp_fixture_a","post-logout login reuses client without old token hint")
	auth.cancel_login()
	check(not auth.busy and auth._server == null and auth._pending.is_empty(),"cancel closes listener and clears attempt")
	check(not auth._auth_url("https://auth.openai.com.attacker.invalid/jwks"),"discovery host restriction")
	check(not auth._client_valid("dynamic_agent_client"),"dynamic entrypoint never stored as issued client")
	check(not auth._credential("bad\r\nInjected: token"),"credential header controls rejected")
	grant_direct = true; next_client = "oaiapp_fixture_c"
	check(auth.begin_login(), "third isolated account is added for removal isolation")
	await complete_login()
	var third_id: String = auth.active_id
	var third_vault := FileAccess.get_file_as_bytes(auth._root.path_join(third_id + ".bin"))
	var requests_before := requests.size()
	check(not auth.delete_account("../outside") and not auth.delete_account("f".repeat(64)), "removal rejects traversal and unknown registration IDs")
	check(auth.delete_account(second_id) and auth.active_id == third_id and auth.can_infer(), "removing another saved account preserves the selected valid account")
	check(not FileAccess.file_exists(auth._root.path_join(second_id + ".bin")) and requests.size() == requests_before, "account deletion clears only the local vault without remote account requests")
	var revision_before_delete: int = auth.session_revision
	var temporary_vault := FileAccess.open(auth._root.path_join(third_id + ".bin.tmp"),FileAccess.WRITE)
	temporary_vault.store_buffer(third_vault); temporary_vault.close()
	check(auth.delete_account(third_id) and auth.active_id.is_empty() and auth.models.is_empty() and auth.selected_model.is_empty(), "deleting active account clears selection and models without silently switching billing")
	check(auth.session_revision == revision_before_delete + 1 and auth._profiles.has(id) and auth.accounts().size() == 1, "active deletion invalidates old session while preserving the other registration")
	check(not FileAccess.file_exists(auth._root.path_join(third_id + ".bin")) and not FileAccess.file_exists(auth._root.path_join(third_id + ".bin.tmp")) and not third_vault.is_empty(), "selected encrypted credential file and incomplete temporary save are removed")
	var after_delete := Auth.new(); root.add_child(after_delete); after_delete.setup(native,fixture,false)
	check(after_delete.accounts().size() == 1 and after_delete.active_id.is_empty() and after_delete._host == initial_host, "restart preserves remaining registrations and unselected state after deletion")
	after_delete.queue_free(); await process_frame
	auth.queue_free(); await process_frame
	for mode in ["save", "identity", "format"]:
		auth = SaveFaultAuth.new(); root.add_child(auth)
		auth.clock_override = func(): return now
		auth.browser_opener = browser; auth.request_override = fake_request
		var case_root := fixture.path_join("rotation-" + mode)
		auth.setup(native, case_root, true)
		grant_direct = true; refresh_fault = ""; next_client = "oaiapp_failure_" + mode
		auth.begin_login(); await complete_login()
		var profile_id: String = auth.active_id
		check(not profile_id.is_empty() and auth.can_infer(), mode + " rotation fixture signed in")
		auth._profiles[profile_id].expires_at = now - 1
		auth._save_profile(profile_id, auth._profiles[profile_id])
		auth.reject_final_save = mode == "save"
		refresh_fault = mode
		var before_refresh := refreshes
		auth.request_access_token(500); await process_frame
		check(refreshes == before_refresh + 1 and not auth.can_infer(), mode + " failure blocks inference after one consumed refresh")
		check(bool(auth._profiles[profile_id].get("refresh_pending", false)), mode + " failure retains durable consumed-token guard")
		auth.request_access_token(501); auth.refresh_models(); await process_frame
		check(refreshes == before_refresh + 1, mode + " failure never resubmits old refresh within same process")
		var restarted := Auth.new(); root.add_child(restarted)
		restarted.clock_override = func(): return now
		restarted.request_override = fake_request
		restarted.setup(native, case_root, true)
		check(not restarted.can_infer() and restarted._profiles[profile_id].refresh_token.is_empty(), mode + " restart cannot load old refresh for use")
		restarted.request_access_token(502); restarted.refresh_models(); await process_frame
		check(refreshes == before_refresh + 1, mode + " restart never resubmits consumed refresh")
		restarted.queue_free(); auth.queue_free(); await process_frame
	auth = SaveFaultAuth.new(); root.add_child(auth)
	auth.clock_override = func(): return now
	auth.browser_opener = browser; auth.request_override = fake_request
	var removal_root := fixture.path_join("remove-index-failure")
	auth.setup(native, removal_root, true)
	refresh_fault = ""; next_client = "oaiapp_remove_failure"
	auth.begin_login(); await complete_login()
	var removed_id: String = auth.active_id
	auth.reject_index_save = true
	check(not auth.delete_account(removed_id) and auth.active_id.is_empty() and not auth.can_infer(), "index-save failure reports partial removal without reviving deleted credentials")
	check(auth.status.contains("账户列表保存失败") and not FileAccess.file_exists(auth._root.path_join(removed_id + ".bin")), "failed deletion-index write explains the outcome and leaves no usable vault")
	var removal_restart := Auth.new(); root.add_child(removal_restart); removal_restart.setup(native,removal_root,false)
	check(removal_restart.accounts().is_empty() and not removal_restart.can_infer(), "stale index cannot resurrect removed credentials on restart")
	removal_restart.queue_free(); auth.queue_free(); await process_frame
	native.free()
	print("ChatGPT auth: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
