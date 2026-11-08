class_name GroundPlanner
extends RefCounted
## Books the ground a plane needs, as rectangles with times, and gives each
## flight its taxi pauses (decision runway-and-taxi-technical-design-movement-
## plan-analytic-bookings-planned-pauses, sections 5 and 6). Pure: no scene, no
## nodes, nothing saved. The caller passes each flight's phase paths (Airside.
## phase_path) and the hold line points, and plans every flight again from them.
##
## Bookings ({"rect", "from", "to", "owner", "kind"}) are world xz
## rectangles held over half-open tick windows. Two flights clash when their
## rectangles overlap with area and their windows overlap.
## - A taxi route's straight runs are cut into SLICE_M slices on one fixed world
##   grid (never re-cut when gates change), each as wide as the plane's
##   footprint. A slice is booked from the tick the footprint first touches it
##   until its tail and wings are clear.
## - A corner (a turn of the route, or the turn from the entry heading) is one
##   box covering the whole turn, booked while the footprint touches it.
## - The runway is one block: the arrival holds it from APPROACH until it has
##   turned off, the departure from the tick it touches it to DEPARTED.
## - A parked plane books its footprint. Pushback books the class's swing
##   square (StandEnvelope), the parked footprint and every lane slice the
##   swing square touches, together, for the whole phase. A plane waiting at a
##   hold line books its footprint for the pause; the slices and corners it
##   touched before and after are booked per leg, not across the pause.
## - Takeoff books the corner box of its line-up turn; the runway covers the rest.
## Windows are analytic: the footprint's bounds move linearly with distance on
## each piece of the route, and MovementPlan's smoothstep legs are inverted in
## closed form.
##
## The footprint (footprint()) is about the pose point, nose along the heading:
## for every member of the class, it covers both the door-aligned model
## (PlaneClasses.stand_offset, as PlaneView draws it today) and the model
## centred on the pose point (PlaneModels' model_offset, the convention
## own_swing_radius and so StandEnvelope are built on), so it holds whichever
## pivot board 13e98b04 settles on. While the heading turns (8 m either side of
## a corner, MovementPlan.CORNER_BLEND) the footprint is bounded by a square of
## half width reach about the pose point.
##
## Planning (plan_all): flights in order of first start tick, then id. Each is
## first tried with no pause; a taxi phase that does not fit then takes the
## shortest pause (PAUSE_STEP_TICKS up to MAX_PAUSE_TICKS) at the earliest hold
## line where it fits. Hold lines (holds()): H_IN and H_RWY on the stubs, and
## H_g on the gate's lead-in at gate_hold_z(). A flight's own bookings never
## clash with each other, so whether a phase's option fits does not depend on
## the other phase's, and each phase picks on its own. Nothing fits:
## TAXI_BUSY. A flight's plan depends only on the flights before it, so as long
## as every issued flight starts before every unissued one, accepting,
## reassigning or ending contracts and placing works never change a plane
## already flying. The planner restarts (stops checking against what it booked
## before) when a flight starts after every booking has ended, as it does each
## quiet night. A departure outside FIRST_DEPARTURE_MINUTE to
## LAST_DEPARTURE_MINUTE would remove that night, so it is refused with
## QUIET_NIGHT.
##
## Not guaranteed: that the drawn plane stays inside its swing square through
## the pushback turn (board 13e98b04 owns that), and that a route is the one
## Airside gives. A route segment off the axes is booked by its footprint's
## bounding box, which is safe but wide.

const TAXI_BUSY := "taxi_busy"
const TAXI_BUSY_TEXT := "taxi lane busy at that time"
const QUIET_NIGHT := "quiet_night"
## Departures 07:00 to 21:00 (OfferBoard draws only these), so every night
## from about 22:02 to 04:52 holds no booking.
const FIRST_DEPARTURE_MINUTE := 7 * 60
const LAST_DEPARTURE_MINUTE := 21 * 60
const SLICE_M := 8.0
## Booking kinds.
const SLICE := "slice"
const CORNER := "corner"
const RUNWAY := "runway"
const PARKED := "parked"
const PUSHBACK := "pushback"
const WAIT := "wait"
const WORKS := "works"
## Hold line names, a pause's "hold".
const HOLD_IN := "hold_in"
const HOLD_GATE := "hold_gate"
const HOLD_RUNWAY := "hold_runway"
const WORKS_OWNER := "works"
const TAXI_STATES: Array[int] = [FlightSim.State.TAXI_IN, FlightSim.State.TAXI_OUT]
## The phase whose path's end direction a phase enters on, as PlaneView reads it.
const PREVIOUS_MOVE := {
	FlightSim.State.TAXI_IN: FlightSim.State.LANDING,
	FlightSim.State.TAXI_OUT: FlightSim.State.PUSHBACK,
	FlightSim.State.TAKEOFF: FlightSim.State.TAXI_OUT,
}
## A hold point this close to a route is on it.
const ON_ROUTE_M := 0.01
const BUCKET_TICKS := 200.0
const EPSILON := 0.000001

## How many times plan_all() restarted on a quiet stretch.
var restarts := 0
var _hold_in: Vector3
var _hold_runway: Vector3
var _bookings: Array[Dictionary] = []
## Bucket index -> the bookings whose window meets that bucket.
var _buckets := {}
var _held_until := -INF


## `hold_in` and `hold_runway` are the hold lines on the east and west stubs
## (Airside's HoldIn and HoldRunway waypoints).
func _init(hold_in: Vector3, hold_runway: Vector3) -> void:
	_hold_in = hold_in
	_hold_runway = hold_runway


## A flight to plan: its id, plane class, StandPlacement stand, FlightSim
## schedule starts, and its paths by FlightSim.State for LANDING, TAXI_IN,
## PUSHBACK, TAXI_OUT and TAKEOFF (Airside.phase_path).
static func request(
	id: String, plane_class: String, stand: Dictionary, starts: Array, routes: Dictionary
) -> Dictionary:
	return {"id": id, "class": plane_class, "stand": stand, "starts": starts, "routes": routes}


## The class's footprint about the pose point: "ahead" (nose), "behind"
## (tail), "half_width" (wingtip) and "reach", the farthest corner.
static func footprint(plane_class: String) -> Dictionary:
	var ahead := 0.0
	var behind := 0.0
	var half := 0.0
	for model: String in PlaneClasses.CLASSES[plane_class]["models"]:
		var shape: Dictionary = PlaneModels.PLANES[model]
		var offset := PlaneClasses.stand_offset(model)
		var centred: float = shape["length"] / 2.0
		ahead = maxf(ahead, maxf(centred, offset.z + shape["nose"]))
		behind = maxf(behind, maxf(centred, shape["tail"] - offset.z))
		half = maxf(half, shape["half_span"] + absf(offset.x))
	var reach := Vector2(maxf(ahead, behind), half).length()
	return {"ahead": ahead, "behind": behind, "half_width": half, "reach": reach}


## The runway block a plane of `plane_class` holds: the whole runway, as wide as
## its footprint either side of the centreline.
static func runway_rect(plane_class: String) -> Rect2:
	var half: float = footprint(plane_class)["half_width"]
	var reach := StandPlacement.ZONE_HALF_LENGTH_M
	return Rect2(-reach, StandPlacement.RUNWAY_Z - half, 2.0 * reach, 2.0 * half)


## Whether the flight departs inside the day, so the quiet night stays.
static func keeps_quiet_night(starts: Array) -> bool:
	var minute := GameCalendar.minute_of_day(starts[FlightSim.State.PUSHBACK])
	return minute >= FIRST_DEPARTURE_MINUTE and minute <= LAST_DEPARTURE_MINUTE


## Plans every request (request()) in time order after placing the `fixed`
## bookings (works). Returns id -> {"ok", "reason" ("", TAXI_BUSY or
## QUIET_NIGHT), "pauses": state -> MovementPlan pause ({} for none),
## "bookings"}. A refused flight books nothing.
func plan_all(requests: Array, fixed: Array = []) -> Dictionary:
	_clear()
	restarts = 0
	_add(fixed)
	var order := requests.duplicate()
	order.sort_custom(_before)
	var out := {}
	for one: Dictionary in order:
		# A quiet stretch: nothing held can meet this flight or any after it.
		if not _buckets.is_empty() and float(one["starts"][0]) >= _held_until:
			_buckets.clear()
			restarts += 1
		out[one["id"]] = _plan(one)
	return out


## Every booking the last plan_all() made, fixed ones first, in the order they
## were made, across restarts.
func bookings() -> Array[Dictionary]:
	return _bookings.duplicate()


## The z of every gate's lead-in hold line H_g: the south edge of the band lane
## traffic sweeps (the lane plus the widest half span of any model) plus the
## farthest any model's nose reaches ahead of its pose point, drawn door-aligned
## (PlaneClasses.stand_offset). The same rule as the paving lane's
## Airside.lead_in_hold() (about -245.52); point this at it once both are on
## main.
static func gate_hold_z() -> float:
	var half_span := 0.0
	var nose := 0.0
	for model: String in PlaneModels.PLANES:
		var shape: Dictionary = PlaneModels.PLANES[model]
		half_span = maxf(half_span, shape["half_span"])
		nose = maxf(nose, PlaneClasses.stand_offset(model).z + shape["nose"])
	return StandPlacement.TAXI_LANE_Z + half_span + nose


## Gate `stand`'s lead-in hold line H_g, or Vector3.INF when its pushback ends
## at or north of gate_hold_z() (north-row stands have none).
static func gate_hold(stand: Dictionary) -> Vector3:
	var back := StandPlacement.pushback_end(stand)
	if back.z <= gate_hold_z():
		return Vector3.INF
	return Vector3(back.x, 0.0, gate_hold_z())


## The hold lines on the route of taxi phase `state`, earliest first:
## {"hold": name, "hold_s": metres along the route}. H_IN and H_RWY are on the
## stubs, H_g (gate_hold()) on the gate's lead-in.
func holds(req: Dictionary, state: int) -> Array[Dictionary]:
	var route: PackedVector3Array = req["routes"][state]
	var gate := gate_hold(req["stand"])
	var out: Array[Dictionary] = []
	var points := {}
	if gate != Vector3.INF:
		points[HOLD_GATE] = gate
	if state == FlightSim.State.TAXI_IN:
		points[HOLD_IN] = _hold_in
	else:
		points[HOLD_RUNWAY] = _hold_runway
	for hold: String in points:
		var at := along(route, points[hold])
		if at >= 0.0:
			out.append({"hold": hold, "hold_s": at})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["hold_s"] < b["hold_s"])
	return out


## The pauses taxi phase `state` may take, in the order they are tried: none,
## then each length from the shortest, at each hold line from the earliest.
## Only pauses MovementPlan.is_valid() accepts are listed.
func phase_options(req: Dictionary, state: int) -> Array[Dictionary]:
	var route: PackedVector3Array = req["routes"][state]
	var budget := _budget(req, state)
	var out: Array[Dictionary] = [{}]
	var lines := holds(req, state)
	var ticks := MovementPlan.PAUSE_STEP_TICKS
	while ticks <= MovementPlan.MAX_PAUSE_TICKS:
		for line in lines:
			var pause := {"hold": line["hold"], "hold_s": line["hold_s"], "ticks": ticks}
			if MovementPlan.is_valid(MovementPlan.taxi(route, budget, pause)):
				out.append(pause)
		ticks += MovementPlan.PAUSE_STEP_TICKS
	return out


## What taxi phase `state` books with `pause` ({} for none): its slices and
## corners per leg, its runway block and, with a pause, its waiting footprint.
static func phase_bookings(req: Dictionary, state: int, pause := {}) -> Array[Dictionary]:
	var route: PackedVector3Array = req["routes"][state]
	var fp := footprint(req["class"])
	var plan := MovementPlan.taxi(route, _budget(req, state), pause)
	var hold_s: float = plan["hold_s"]
	var entry := MovementPlan.exit_dir(req["routes"][PREVIOUS_MOVE[state]])
	var pieces := _pieces(route, entry, fp, [hold_s])
	var start := float(req["starts"][state])
	var owner: String = req["id"]
	var out: Array[Dictionary] = []
	var cells := _cells(route, entry, fp)
	for rect: Rect2 in cells:
		for leg in [0, 1]:
			var window := _leg_window(plan, pieces, rect, leg)
			if window[0] <= window[1]:
				out.append(_booking(rect, start + window[0], start + window[1], owner, cells[rect]))
	var runway := runway_rect(req["class"])
	var on_runway := _leg_window(plan, pieces, runway, 0)
	var after := _leg_window(plan, pieces, runway, 1)
	var starts: Array = req["starts"]
	if state == FlightSim.State.TAXI_IN:
		var off := maxf(on_runway[1], after[1]) if after[0] <= after[1] else on_runway[1]
		out.append(_booking(runway, starts[FlightSim.State.APPROACH], start + off, owner, RUNWAY))
	else:
		var on := on_runway[0] if on_runway[0] <= on_runway[1] else after[0]
		out.append(_booking(runway, start + on, starts[FlightSim.State.DEPARTED], owner, RUNWAY))
	if not pause.is_empty():
		var wait_at := _flat(MovementPlan.point_at(route, hold_s))
		var heading := _flat(MovementPlan.heading_at(route, hold_s, entry))
		var rect := _footprint_rect(wait_at, heading, fp)
		if _in_turn(route, entry, hold_s):
			rect = _square(wait_at, fp["reach"])
		# The same sums as the legs' windows, so the three meet with no gap.
		var from := start + _leg_time(plan, hold_s, 0)
		var to := start + _leg_time(plan, hold_s, 1)
		out.append(_booking(rect, from, to, owner, WAIT))
	return out


## What a flight books whatever its pauses: parked, pushback and the takeoff
## line-up.
static func fixed_bookings(req: Dictionary) -> Array[Dictionary]:
	var starts: Array = req["starts"]
	var stand: Dictionary = req["stand"]
	var plane_class: String = req["class"]
	var fp := footprint(plane_class)
	var owner: String = req["id"]
	var parked := _footprint_rect(_flat(StandPlacement.stand_point(stand)), Vector2(0, 1), fp)
	var at_stand: int = starts[FlightSim.State.AT_STAND]
	var push: int = starts[FlightSim.State.PUSHBACK]
	var out_start: int = starts[FlightSim.State.TAXI_OUT]
	var out: Array[Dictionary] = [_booking(parked, at_stand, push, owner, PARKED)]
	var swing: Rect2 = StandEnvelope.rects(stand, plane_class)[0]
	out.append(_booking(swing, push, out_start, owner, PUSHBACK))
	out.append(_booking(parked, push, out_start, owner, PUSHBACK))
	var half: float = fp["half_width"]
	var first := floori(swing.position.x / SLICE_M)
	for j in range(first, ceili(swing.end.x / SLICE_M)):
		var slice := Rect2(j * SLICE_M, StandPlacement.TAXI_LANE_Z - half, SLICE_M, 2.0 * half)
		if slice.intersects(swing):
			out.append(_booking(slice, push, out_start, owner, SLICE))
	var takeoff: PackedVector3Array = req["routes"][FlightSim.State.TAKEOFF]
	var entry := MovementPlan.exit_dir(req["routes"][FlightSim.State.TAXI_OUT])
	var start := float(starts[FlightSim.State.TAKEOFF])
	var ticks := float(starts[FlightSim.State.DEPARTED]) - start
	var length := MovementPlan.path_length(takeoff)
	var pieces := _pieces(takeoff, entry, fp, [])
	for zone in _turn_zones(takeoff, entry):
		var box := _corner_box(takeoff, zone, fp)
		var touch := _touch(pieces, box, 0.0, length)
		if touch[0] <= touch[1]:
			var from := start + ticks * sqrt(maxf(touch[0], 0.0) / length)
			var to := start + ticks * sqrt(minf(touch[1], length) / length)
			out.append(_booking(box, from, to, owner, CORNER))
	return out


## Whether none of `list` clashes with a booking of another owner since the
## last restart.
func fits(list: Array) -> bool:
	for booking: Dictionary in list:
		for bucket in _bucket_range(booking):
			for held: Dictionary in _buckets.get(bucket, []):
				if held["owner"] != booking["owner"] and clash(held, booking):
					return false
	return true


## Whether two bookings overlap in time and, with area, in space.
static func clash(a: Dictionary, b: Dictionary) -> bool:
	if not (a["from"] < b["to"] and b["from"] < a["to"]):
		return false
	return (a["rect"] as Rect2).intersects(b["rect"])


## The first tick at or after `after` from which the runway is clear of every
## booking of the last plan_all() for `ticks` ticks: where runway works can go.
func works_gap(after: float, ticks: float) -> float:
	var block := runway_rect(PlaneClasses.LARGE)
	var windows: Array[Dictionary] = []
	for held in _bookings:
		if (held["rect"] as Rect2).intersects(block):
			windows.append(held)
	windows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["from"] < b["from"])
	var at := after
	for window in windows:
		if window["to"] <= at:
			continue
		if window["from"] >= at + ticks:
			break
		at = window["to"]
	return at


## Runway works from `start` for `ticks` ticks as a fixed booking for plan_all().
static func works_booking(start: float, ticks: float) -> Dictionary:
	return _booking(runway_rect(PlaneClasses.LARGE), start, start + ticks, WORKS_OWNER, WORKS)


## Metres along `route` to `point` when it lies on the route (within
## ON_ROUTE_M), else -1.
static func along(route: PackedVector3Array, point: Vector3) -> float:
	var run := 0.0
	var flat := _flat(point)
	for i in range(1, route.size()):
		var a := _flat(route[i - 1])
		var b := _flat(route[i])
		var length := route[i - 1].distance_to(route[i])
		var on := Geometry2D.get_closest_point_to_segment(flat, a, b)
		if on.distance_to(flat) <= ON_ROUTE_M:
			return run + a.distance_to(on) * (length / a.distance_to(b) if a != b else 0.0)
		run += length
	return -1.0


## The pieces of `route` between its corners, the ends of each turn and the
## `cuts`: [from_s, to_s, start point, end point, low offset, high offset],
## where the footprint is the box from point + low to point + high and the
## point moves in a straight line from start to end.
static func _pieces(
	route: PackedVector3Array, entry: Vector3, fp: Dictionary, cuts: Array
) -> Array:
	var length := MovementPlan.path_length(route)
	var marks := {0.0: true, length: true}
	var run := 0.0
	for i in range(1, route.size()):
		run += route[i - 1].distance_to(route[i])
		marks[run] = true
	var zones := _turn_zones(route, entry)
	for zone in zones:
		marks[zone.x] = true
		marks[zone.y] = true
	for cut: float in cuts:
		marks[clampf(cut, 0.0, length)] = true
	var keys := marks.keys()
	keys.sort()
	var reach: float = fp["reach"]
	var out := []
	for k in range(1, keys.size()):
		var from: float = keys[k - 1]
		var to: float = keys[k]
		if to - from <= EPSILON:
			continue
		var a := _flat(MovementPlan.point_at(route, from))
		var b := _flat(MovementPlan.point_at(route, to))
		var middle := (from + to) / 2.0
		var low := Vector2(-reach, -reach)
		var high := Vector2(reach, reach)
		var turning := false
		for zone in zones:
			turning = turning or (middle > zone.x and middle < zone.y)
		if not turning and a.distance_to(b) > EPSILON:
			var box := _footprint_rect(Vector2.ZERO, (b - a).normalized(), fp)
			low = box.position
			high = box.end
		out.append([from, to, a, b, low, high])
	return out


## The stretches of distance along `route` over which the heading turns:
## MovementPlan.CORNER_BLEND either side of each change of direction, the
## entry heading counted.
static func _turn_zones(route: PackedVector3Array, entry: Vector3) -> Array[Vector2]:
	var length := MovementPlan.path_length(route)
	var blend := MovementPlan.CORNER_BLEND
	var last := MovementPlan.flat_dir(Vector3.ZERO, entry)
	var run := 0.0
	var out: Array[Vector2] = []
	for i in range(1, route.size()):
		var step := route[i - 1].distance_to(route[i])
		if step <= 0.0:
			continue
		var dir := MovementPlan.flat_dir(route[i - 1], route[i])
		if dir.dot(last) < 1.0 - EPSILON:
			out.append(Vector2(maxf(run - blend, 0.0), minf(run + blend, length)))
		last = dir
		run += step
	return out


static func _in_turn(route: PackedVector3Array, entry: Vector3, at: float) -> bool:
	for zone in _turn_zones(route, entry):
		if at >= zone.x and at <= zone.y:
			return true
	return false


## Every rectangle a taxi along `route` may touch, -> its kind: the slices of
## each straight run, reaching past its ends by the footprint's length, and
## the box of each turn.
static func _cells(route: PackedVector3Array, entry: Vector3, fp: Dictionary) -> Dictionary:
	var out := {}
	var reach := maxf(fp["ahead"], fp["behind"])
	var half: float = fp["half_width"]
	for i in range(1, route.size()):
		var a := _flat(route[i - 1])
		var b := _flat(route[i])
		if a.distance_to(b) <= EPSILON:
			continue
		var along_x := absf(b.x - a.x) >= absf(b.y - a.y)
		var low := minf(a.x, b.x) if along_x else minf(a.y, b.y)
		var high := maxf(a.x, b.x) if along_x else maxf(a.y, b.y)
		for j in range(floori((low - reach) / SLICE_M), ceili((high + reach) / SLICE_M)):
			var rect := Rect2(j * SLICE_M, a.y - half, SLICE_M, 2.0 * half)
			if not along_x:
				rect = Rect2(a.x - half, j * SLICE_M, 2.0 * half, SLICE_M)
			out[rect] = SLICE
	for zone in _turn_zones(route, entry):
		out[_corner_box(route, zone, fp)] = CORNER
	return out


## The box the footprint stays in while the heading turns over `zone`: the
## route there, grown by the footprint's reach.
static func _corner_box(route: PackedVector3Array, zone: Vector2, fp: Dictionary) -> Rect2:
	var box := Rect2(_flat(MovementPlan.point_at(route, zone.x)), Vector2.ZERO)
	box = box.expand(_flat(MovementPlan.point_at(route, zone.y)))
	var run := 0.0
	for i in range(1, route.size()):
		run += route[i - 1].distance_to(route[i])
		if run > zone.x and run < zone.y:
			box = box.expand(_flat(route[i]))
	return box.grow(fp["reach"])


## Ticks into the phase over which leg `leg` (0 before the pause, 1 after it)
## of `plan` touches `rect`: [first, last], or first > last for never. Spans are
## PackedFloat64Array, not Vector2, which holds 32-bit floats.
static func _leg_window(
	plan: Dictionary, pieces: Array, rect: Rect2, leg: int
) -> PackedFloat64Array:
	var hold_s: float = plan["hold_s"]
	var length: float = plan["length"]
	var leg_from := 0.0 if leg == 0 else hold_s
	var leg_to := hold_s if leg == 0 else length
	if leg == 1 and hold_s >= length:
		return _never()
	var touch := _touch(pieces, rect, leg_from, leg_to)
	if touch[0] > touch[1]:
		return _never()
	# A touch at a leg's end is put exactly on it, so the leg's window meets the
	# wait's or the next phase's with no gap.
	if touch[0] <= leg_from + EPSILON:
		touch[0] = leg_from
	if touch[1] >= leg_to - EPSILON:
		touch[1] = leg_to
	return PackedFloat64Array([_leg_time(plan, touch[0], leg), _leg_time(plan, touch[1], leg)])


## The tick into the phase at which leg `leg` of `plan` is `at` metres along.
static func _leg_time(plan: Dictionary, at: float, leg: int) -> float:
	var hold_s: float = plan["hold_s"]
	var t1: float = plan["t1"]
	if leg == 0:
		return t1 * _unfraction(at / hold_s) if hold_s > 0.0 else 0.0
	var rest: float = plan["length"] - hold_s
	var back: float = t1 + plan["pause_ticks"]
	return back + float(plan["t2"]) * _unfraction((at - hold_s) / rest)


## The inverse of MovementPlan.fraction() (smoothstep) on 0 to 1.
static func _unfraction(share: float) -> float:
	# The ends are exact, so a leg's window ends on the very tick the pause or
	# the next leg starts (the closed form gives 0.9999999999999999 at 1).
	if share <= 0.0:
		return 0.0
	if share >= 1.0:
		return 1.0
	return 0.5 - sin(asin(1.0 - 2.0 * share) / 3.0)


## The smallest and largest distance from `from_s` to `to_s` at which the
## footprint touches `rect` (edges included): (min, max), or min > max for none.
static func _touch(pieces: Array, rect: Rect2, from_s: float, to_s: float) -> PackedFloat64Array:
	var out := PackedFloat64Array([INF, -INF])
	for piece: Array in pieces:
		if piece[0] < from_s - EPSILON or piece[1] > to_s + EPSILON:
			continue
		var span := _piece_touch(piece, rect)
		if span[0] <= span[1]:
			out = PackedFloat64Array([minf(out[0], span[0]), maxf(out[1], span[1])])
	return out


## The distances on one piece at which its footprint touches `rect`.
static func _piece_touch(piece: Array, rect: Rect2) -> PackedFloat64Array:
	var from: float = piece[0]
	var size: float = piece[1] - from
	var a: Vector2 = piece[2]
	var rate: Vector2 = ((piece[3] as Vector2) - a) / size
	var low: Vector2 = a + piece[4]
	var high: Vector2 = a + piece[5]
	var span := PackedFloat64Array([0.0, size])
	for axis in 2:
		span = _keep(span, low[axis], rate[axis], rect.end[axis], true)
		span = _keep(span, high[axis], rate[axis], rect.position[axis], false)
	return PackedFloat64Array([from + span[0], from + span[1]])


## `span` cut to where value + rate * u stays at or under `bound` (`below`) or
## at or over it.
static func _keep(
	span: PackedFloat64Array, value: float, rate: float, bound: float, below: bool
) -> PackedFloat64Array:
	if absf(rate) <= EPSILON:
		return span if (value <= bound if below else value >= bound) else _never()
	var cross := (bound - value) / rate
	if (rate > 0.0) == below:
		return PackedFloat64Array([span[0], minf(span[1], cross)])
	return PackedFloat64Array([maxf(span[0], cross), span[1]])


## The axis-aligned box around the footprint at `at` facing `heading` (flat x, z).
static func _footprint_rect(at: Vector2, heading: Vector2, fp: Dictionary) -> Rect2:
	var side := Vector2(heading.y, -heading.x) * float(fp["half_width"])
	var nose := at + heading * float(fp["ahead"])
	var tail := at - heading * float(fp["behind"])
	var box := Rect2(nose + side, Vector2.ZERO).expand(nose - side)
	return box.expand(tail + side).expand(tail - side)


## An empty span: first after last.
static func _never() -> PackedFloat64Array:
	return PackedFloat64Array([1.0, 0.0])


static func _square(at: Vector2, half: float) -> Rect2:
	return Rect2(at - Vector2(half, half), Vector2(2.0 * half, 2.0 * half))


static func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)


static func _budget(req: Dictionary, state: int) -> float:
	return float(req["starts"][state + 1]) - float(req["starts"][state])


static func _booking(
	rect: Rect2, from: float, to: float, owner: String, kind: String
) -> Dictionary:
	return {"rect": rect, "from": from, "to": to, "owner": owner, "kind": kind}


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a["starts"][0] != b["starts"][0]:
		return a["starts"][0] < b["starts"][0]
	return a["id"] < b["id"]


## Plans one flight against what is held now and books it.
func _plan(req: Dictionary) -> Dictionary:
	if not keeps_quiet_night(req["starts"]):
		return {"ok": false, "reason": QUIET_NIGHT, "pauses": {}, "bookings": []}
	var chosen := {}
	var all := fixed_bookings(req)
	var ok := fits(all)
	for state in TAXI_STATES:
		if not ok:
			break
		ok = false
		for pause in phase_options(req, state):
			var list := phase_bookings(req, state, pause)
			if fits(list):
				chosen[state] = pause
				all.append_array(list)
				ok = true
				break
	if not ok:
		return {"ok": false, "reason": TAXI_BUSY, "pauses": {}, "bookings": []}
	_add(all)
	return {"ok": true, "reason": "", "pauses": chosen, "bookings": all}


func _add(list: Array) -> void:
	for booking: Dictionary in list:
		_bookings.append(booking)
		_held_until = maxf(_held_until, booking["to"])
		for bucket in _bucket_range(booking):
			if not _buckets.has(bucket):
				_buckets[bucket] = []
			_buckets[bucket].append(booking)


func _clear() -> void:
	_bookings.clear()
	_buckets.clear()
	_held_until = -INF


static func _bucket_range(booking: Dictionary) -> Array:
	var first := floori(float(booking["from"]) / BUCKET_TICKS)
	var last := floori(float(booking["to"]) / BUCKET_TICKS)
	return range(first, last + 1)
