class_name PassengerTurns
extends RefCounted
## The yaw each passenger view is drawn with, eased per tick (user ruling
## passenger-turns-on-the-spot-ease-over-a-few-frames-and-anima): a new facing
## turns the body from the yaw it has now to the new one over TURN_TICKS ticks
## (0.3 s of sim time) on a smoothstep, so it starts and ends the turn slowly,
## and frames draw between the yaw of the tick before and the yaw now with the
## clock's alpha, as positions are. A facing that changes again before the
## turn ends starts a new turn from where the body is. Keyed by passenger id;
## it holds a count of ticks into the turn, never a sim tick, and place()
## starts a record over with no turn (a new view, a snap or a load).

## Ticks a turn takes, whatever its angle: 0.3 s at SimClock.TICK_RATE 20. At
## 1x and 60 frames a second an about-turn draws at most 14.5 degrees a frame.
const TURN_TICKS := 6
## A facing this close to the one being turned to (radians) is the same one.
const SAME_RAD := 0.001

## Passenger id -> {"prev", "cur": yaw drawn at the tick before and now,
## "from", "to": the turn's ends, "done": ticks into it}.
var _turns: Dictionary = {}


## Whether `id` has a drawn yaw.
func has(id: int) -> bool:
	return _turns.has(id)


## Sets `id`'s yaw to `yaw` at once, with no turn under way.
func place(id: int, yaw: float) -> void:
	_turns[id] = {"prev": yaw, "cur": yaw, "from": yaw, "to": yaw, "done": TURN_TICKS}


## Moves `id`'s yaw on one tick toward `target`. A target other than the one
## being turned to starts a new turn from the yaw now.
func step(id: int, target: float) -> void:
	if not _turns.has(id):
		place(id, target)
		return
	var t: Dictionary = _turns[id]
	if absf(angle_difference(float(t["to"]), target)) > SAME_RAD:
		t["from"] = t["cur"]
		t["to"] = target
		t["done"] = 0
	t["prev"] = t["cur"]
	t["done"] = mini(int(t["done"]) + 1, TURN_TICKS)
	if t["done"] >= TURN_TICKS:
		t["cur"] = t["to"]
	else:
		var share := smoothstep(0.0, 1.0, float(t["done"]) / TURN_TICKS)
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
