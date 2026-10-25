extends RefCounted
## A small additive dip, independent of the ongoing dizziness clock.
const OMEGA := 14.0
var amount := 0.0
var velocity := 0.0

func reset() -> void:
	amount = 0.0
	velocity = 0.0

func bump() -> void:
	# Preserve the current pose when another contact arrives during recovery.
	velocity = minf(38.0, maxf(0.0, velocity) + 38.0)

func update(dt: float) -> void:
	var impulse := velocity + OMEGA * amount
	var decay := exp(-OMEGA * dt)
	amount = (amount + impulse * dt) * decay
	velocity = (velocity - OMEGA * impulse * dt) * decay
	if amount > 1.15:
		amount = 1.15
		velocity = minf(0.0, velocity)
	if amount < 0.0001 and absf(velocity) < 0.002: reset()
