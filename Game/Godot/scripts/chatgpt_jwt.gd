extends RefCounted
## Strict RS256 OIDC validation using only the issuer's fetched JWKS.
const ISSUER := "https://auth.openai.com"
const MAX_JWT := 32768

static func base64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")

static func decode(value: String) -> PackedByteArray:
	if value.is_empty() or value.length() > MAX_JWT: return PackedByteArray()
	for c in value:
		if not c in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_": return PackedByteArray()
	if value.length() % 4 == 1: return PackedByteArray()
	return Marshalls.base64_to_raw(value.replace("-", "+").replace("_", "/") + "=".repeat((4 - value.length() % 4) % 4))

static func equal(left: String, right: String) -> bool:
	return Crypto.new().constant_time_compare(left.to_utf8_buffer(), right.to_utf8_buffer())

static func verify(token: String, jwks: Dictionary, client_id: String, nonce: String, now: int, expected_subject := "", check_nonce := true) -> Dictionary:
	if token.length() > MAX_JWT: return {}
	var parts := token.split(".")
	if parts.size() != 3: return {}
	var header = _json(decode(parts[0]))
	var claims = _json(decode(parts[1]))
	var signature := decode(parts[2])
	if header.is_empty() or claims.is_empty() or signature.is_empty(): return {}
	if header.get("alg") != "RS256" or header.has("crit") or header.has("jku") or header.has("jwk") or header.get("b64", true) != true: return {}
	var kid = header.get("kid", "")
	if not kid is String or kid.is_empty() or kid.length() > 256: return {}
	var keys = jwks.get("keys", [])
	if not keys is Array or keys.size() > 64: return {}
	var selected: Dictionary = {}
	for item in keys:
		if not item is Dictionary or item.get("kid") != kid: continue
		if not selected.is_empty(): return {} # Ambiguous key identifiers fail closed.
		selected = item
	if selected.get("kty") != "RSA" or selected.get("alg", "RS256") != "RS256" or selected.get("use", "sig") != "sig": return {}
	if selected.has("key_ops") and (not selected.key_ops is Array or not "verify" in selected.key_ops): return {}
	var public_key := public_key(selected)
	if public_key == null: return {}
	if not Crypto.new().verify(HashingContext.HASH_SHA256, (parts[0]+"."+parts[1]).sha256_buffer(), signature, public_key): return {}
	if claims.get("iss") != ISSUER: return {}
	var audience = claims.get("aud")
	if audience is String:
		if audience != client_id: return {}
	elif audience is Array:
		if not client_id in audience or (audience.size() > 1 and claims.get("azp") != client_id): return {}
	else: return {}
	if claims.has("azp") and claims.azp != client_id: return {}
	for name in ["exp", "iat"]:
		if not _number(claims.get(name)): return {}
	if int(claims.exp) <= now or int(claims.iat) > now + 60 or int(claims.iat) <= 0: return {}
	if claims.has("nbf") and (not _number(claims.nbf) or int(claims.nbf) > now + 60): return {}
	if check_nonce and (not claims.get("nonce") is String or not equal(str(claims.nonce), nonce)): return {}
	var subject = claims.get("sub", "")
	if not subject is String or subject.is_empty() or subject.length() > 255: return {}
	if not expected_subject.is_empty() and subject != expected_subject: return {}
	return claims

static func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _json(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty(): return {}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or not json.data is Dictionary: return {}
	return json.data

static func public_key(jwk: Dictionary) -> CryptoKey:
	if not jwk.get("n") is String or not jwk.get("e") is String: return null
	var modulus := decode(jwk.n)
	var exponent := decode(jwk.e)
	if modulus.size() < 256 or modulus.size() > 1024 or exponent.is_empty() or exponent.size() > 8: return null
	var rsa := _der(0x30, _integer(modulus) + _integer(exponent))
	var algorithm := PackedByteArray([0x30,0x0d,0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01,0x05,0x00])
	var spki := _der(0x30, algorithm + _der(0x03, PackedByteArray([0]) + rsa))
	var encoded := Marshalls.raw_to_base64(spki)
	var pem := "-----BEGIN PUBLIC KEY-----\n"
	for offset in range(0, encoded.length(), 64): pem += encoded.substr(offset, 64) + "\n"
	pem += "-----END PUBLIC KEY-----\n"
	var key := CryptoKey.new()
	return key if key.load_from_string(pem, true) == OK else null

static func _integer(value: PackedByteArray) -> PackedByteArray:
	while value.size() > 1 and value[0] == 0: value = value.slice(1)
	if value[0] & 0x80: value = PackedByteArray([0]) + value
	return _der(0x02, value)

static func _der(tag: int, content: PackedByteArray) -> PackedByteArray:
	var length := content.size()
	var prefix := PackedByteArray([tag])
	if length < 128: prefix.append(length)
	else:
		var bytes := PackedByteArray()
		while length > 0:
			bytes.insert(0, length & 255); length >>= 8
		prefix.append(0x80 | bytes.size()); prefix.append_array(bytes)
	return prefix + content
