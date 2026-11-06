extends RefCounted
## Body coverage for the crossing probe (board item comic-life-and-variety-
## passengers-varied-so-the-crowd-never): each sent passenger is given the
## gender whose body (PassengerLooks.body_of its id) no sent passenger had yet,
## so a run with as many roles as bodies sends every body through security;
## the report names the bodies sent and the ones that never were.

## Key in the seen dictionary for the body -> times-sent counts (not a body index).
const USES := "uses"


## Sets p's variant so its body is one not in `seen` (body -> passenger id),
## records it and returns true; returns false, p untouched, when both bodies
## its id draws were sent already. With `reuse` (a run with more roles than
## bodies) it never returns false: once both bodies were sent it gives p the one
## sent least often, counting each send under USES in `seen`.
static func take(p: Passenger, seen: Dictionary, reuse := false) -> bool:
	for variant in 2:
		var body := PassengerLooks.body_of(p.id, variant)
		if not seen.has(body):
			p.variant = variant
			seen[body] = p.id
			seen.get_or_add(USES, {})[body] = 1
			print("SEND_BODY passenger=%d body=%s" % [p.id, PassengerLooks.BODIES[body]])
			return true
	if not reuse:
		return false
	var uses: Dictionary = seen[USES]
	var least := 0
	if uses[PassengerLooks.body_of(p.id, 1)] < uses[PassengerLooks.body_of(p.id, 0)]:
		least = 1
	var reused := PassengerLooks.body_of(p.id, least)
	p.variant = least
	uses[reused] += 1
	print("SEND_BODY passenger=%d body=%s (reused)" % [p.id, PassengerLooks.BODIES[reused]])
	return true


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
			% [sent.size(), PassengerLooks.BODIES.size(), sent, missing]
		)
	)
	return missing
