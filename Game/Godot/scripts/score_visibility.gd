extends RefCounted
## Presentation only: hovering never extends a game's throw deadline.
const HIDE_SECONDS := 5.0
const RESTORE_SECONDS := 0.2
var revision := -1
var game := ""
var hide_at := -1.0
var hovering := false
var restore_at := -1.0
var restore_from := 1.0
var alpha := 0.0
var expired := true

func update(data: Dictionary, now: float, inside: bool) -> float:
	var available: bool = data.get("panel_available",data.get("shown",false))
	if not available: return 0.0
	if revision != int(data.revision) or game != str(data.get("game","catch")):
		revision = int(data.revision); game = str(data.get("game","catch"))
		if data.active:
			expired = false; hide_at = -1.0
		elif float(data.get("ended_at",-1.0))>=0.0:
			expired = false; hide_at = float(data.ended_at)+HIDE_SECONDS
			# A late frame cannot resurrect a window that already expired.
			if not hovering and now>=hide_at: expired = true
	if expired: alpha = 0.0; hovering = false; return alpha
	if data.active:
		alpha = 1.0; hovering = inside; restore_at = -1.0
		return alpha
	if hide_at<0.0: return 0.0
	if inside and not hovering:
		restore_from = alpha; restore_at = now
	elif not inside and hovering:
		hide_at = now+HIDE_SECONDS
		# Finish the restore smoothly even if the pointer crosses very quickly.
	if restore_at>=0.0:
		alpha = lerpf(restore_from,1.0,smoothstep(0.0,RESTORE_SECONDS,now-restore_at))
		if now-restore_at>=RESTORE_SECONDS: restore_at = -1.0
	elif inside: alpha = 1.0
	else: alpha = 1.0-smoothstep(hide_at-2.0,hide_at,now)
	if not inside and now>=hide_at: expired = true; alpha = 0.0
	# Entering on the exact terminal frame does not revive a closed window.
	hovering = inside and not expired
	return alpha
