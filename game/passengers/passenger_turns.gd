class_name PassengerTurns
extends RefCounted
## The yaw each passenger view is drawn with, eased per tick (user ruling
## passenger-turns-on-the-spot-ease-over-a-few-frames-and-anima): a new facing
## taken on the spot (standing to face a seat, a counter, a kiosk or its work,
## or setting off from a stand) turns the body from the yaw it has now to the
## new one over TURN_TICKS ticks (0.3 s of sim time) on a smoothstep, so it
## starts and ends the turn slowly, and frames draw between the yaw of the
## tick before and the yaw now with the clock's alpha, as positions are. A
## facing that changes again on the spot before the turn ends starts a new
## turn from where the body is. A walker faces its step at once, as the
## roller it pulls trails on the step's heading (CarryOnProps._trail); a
## walker whose step changes while a turn is still under way (it set off, or
## stepped on, mid-turn) is turned on from where it is to the new step over
## the ticks the turn has left, so it never jumps. Keyed by passenger id; it
## holds counts of ticks into the turn, never a sim tick, and place() starts a
## record over with no turn (a new view, a snap or a load).

## Ticks a turn takes, whatever its angle: 0.3 s at SimClock.TICK_RATE 20. At
## 1x and 60 frames a second an about-turn draws at most 14.5 degrees a frame.
const TURN_TICKS := 6
## A facing this close to the one being turned to (radians) is the same one.
const SAME_RAD := 0.001

## Passenger id -> {"prev", "cur": yaw drawn at the tick before and now,
## "from", "to": the turn's ends, "done": ticks into it, "ticks": ticks it
## takes, "walking": whether the body stepped on the tick before}.
var _turns: Dictionary = {}


## Whether `id` has a drawn yaw.
func has(id: int) -> bool:
	return _turns.has(id)


## Sets `id`'s yaw to `yaw` at once, with no turn under way; `walking` is
## whether it steps on this tick.
func place(id: int, yaw: float, walking := false) -> void:
	_turns[id] = {
		"prev": yaw,
		"cur": yaw,
		"from": yaw,
		"to": yaw,
		"done": TURN_TICKS,
		"ticks": TURN_TICKS,
		"walking": walking,
	}


## Moves `id`'s yaw on one tick toward `target`; `walking` is whether the body
## steps on this tick (and `target` is that step's heading). On the spot, or
## setting off from a stand, a new target starts a TURN_TICKS turn from the
## yaw now. Walking on from a step, the body faces `target` at once, or, with a
## turn still under way, turns on from the yaw now to it over the ticks left.
func step(id: int, target: float, walking := false) -> void:
	if not _turns.has(id):
		place(id, target, walking)
		return
	var t: Dictionary = _turns[id]
	var stepped_on: bool = walking and t["walking"]
	t["walking"] = walking
	var under_way := int(t["done"]) < int(t["ticks"])
	if stepped_on and not under_way:
		t["prev"] = target
		t["cur"] = target
		t["from"] = target
		t["to"] = target
		return
	if absf(angle_difference(float(t["to"]), target)) > SAME_RAD:
		var left := int(t["ticks"]) - int(t["done"]) if stepped_on else TURN_TICKS
		t["from"] = t["cur"]
		t["to"] = target
		t["done"] = 0
		t["ticks"] = maxi(left, 1)
	t["prev"] = t["cur"]
	t["done"] = mini(int(t["done"]) + 1, int(t["ticks"]))
	if t["done"] >= t["ticks"]:
		t["cur"] = t["to"]
	else:
		var share := smoothstep(0.0, 1.0, float(t["done"]) / float(t["ticks"]))
		t["cur"] = lerp_angle(t["from"], t["to"], share)


## The facing `id` is turning to (or faces), or `fallback` with no record.
func target(id: int, fallback: float) -> float:
	return float(_turns[id]["to"]) if _turns.has(id) else fallback


## The yaw `id` is drawn with now: between the tick before and now by `alpha`.
func drawn(id: int, alpha: float) -> float:
	var t: Dictionary = _turns[id]
	return lerp_angle(t["prev"], t["cur"], alpha)


func release(id: int) -> void:
	_turns.erase(id)


func clear() -> void:
	_turns.clear()
