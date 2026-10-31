extends RefCounted
## Body coverage for the crossing probe (board item comic-life-and-variety-
## passengers-varied-so-the-crowd-never): each sent passenger is given the
## gender whose body (PassengerLooks.body_of its id) no sent passenger had yet,
## so a run with as many roles as bodies sends every body through security;
## the report names the bodies sent and the ones that never were.


## Sets p's variant so its body is one not in `seen` (body -> passenger id),
## records it and returns true; returns false, p untouched, when both bodies
## its id draws were sent already.
static func take(p: Passenger, seen: Dictionary) -> bool:
	for variant in 2:
		var body := PassengerLooks.body_of(p.id, variant)
		if not seen.has(body):
			p.variant = variant
			seen[body] = p.id
			print("SEND_BODY passenger=%d body=%s" % [p.id, PassengerLooks.BODIES[body]])
			return true
	return false


## Prints the bodies sent (with the passenger that showed each) and returns
## the names of those never sent.
static func report(seen: Dictionary) -> Array[String]:
	var sent: Array[String] = []
	var missing: Array[String] = []
	for body in PassengerLooks.BODIES.size():
		var stem := PassengerLooks.BODIES[body]
		if seen.has(body):
			sent.append("%s=%d" % [stem, seen[body]])
		else:
			missing.append(stem)
	print(
		(
			"BODIES sent=%d of %d: %s missing=%s"
			% [sent.size(), seen.size() + missing.size(), sent, missing]
		)
	)
	return missing
