class_name LandsideDefinition
extends Resource
## The fixed road past the terminal and the build spots beside it (decision
## landside-arrivals-fixed-road-past-the-terminal-player-builds), as authored
## 1-D lanes: polylines whose lengths the sim uses in whole mm. Cars enter at
## the start of `road_in` (the near carriageway, curb side), queue for the
## curb or turn off for a car park, and leave along `road_out` or a lot's exit.
## The BuildGrid covers only the terminal's interior; all of this is off-grid.
##
## Traffic keeps right. The road runs along x with the terminal to the north
## (more negative z): the near carriageway, on the terminal side of
## `centre_line_z`, is westbound (toward -x) with the curb on a car's right,
## and the far carriageway is eastbound (toward +x). Every stretch of lane
## that runs along the road keeps the centre line on the car's left
## (problem() refuses one that does not); stretches across the road (a turn
## into a car park, a lot exit) are not along it and are not checked.

## The road's centre line, between the two carriageways.
@export var centre_line_z := -50.0
@export var road_in := PackedVector3Array()
## From the curb on, off the map.
@export var road_out := PackedVector3Array()
## The free drop-off curb a new game starts with (decision
## landside-start-a-new-game-comes-with-a-small-free-drop-off-c).
@export var curb: LandsideCurb
## Car park spots; a new game has none built.
@export var lots: Array[LandsideLotSpot] = []
## Places for more curb bays; a new game has none built.
@export var curb_spots: Array[LandsideCurbSpot] = []


## Every berth, the starter curb's first and then each curb spot's in order.
## A berth index (LandsideVehicle.stop) counts through this list whether or
## not the curb spot holding it is built.
func berth_count() -> int:
	var total := curb.berths.size()
	for spot in curb_spots:
		total += spot.berths.size()
	return total


func berth_position(index: int) -> Vector3:
	var at := _berth_at(index)
	return curb.berths[at[1]] if at[0] < 0 else curb_spots[at[0]].berths[at[1]]


## Where the passengers of the car in berth `index` step out.
func berth_get_out(index: int) -> Vector3:
	var at := _berth_at(index)
	return curb.get_out[at[1]] if at[0] < 0 else curb_spots[at[0]].get_out[at[1]]


## The curb spot berth `index` belongs to, or -1 for the starter curb.
func berth_spot(index: int) -> int:
	return _berth_at(index)[0]


## [curb spot or -1, berth within it].
func _berth_at(index: int) -> Array:
	if index < curb.berths.size():
		return [-1, index]
	var left := index - curb.berths.size()
	for i in curb_spots.size():
		if left < curb_spots[i].berths.size():
			return [i, left]
		left -= curb_spots[i].berths.size()
	push_error("LandsideDefinition: berth %d does not exist" % index)
	return [-1, 0]


## A polyline's length in whole mm, each segment rounded on its own.
static func length_mm(points: PackedVector3Array) -> int:
	var total := 0
	for i in range(1, points.size()):
		total += roundi(points[i - 1].distance_to(points[i]) * 1000.0)
	return total


## The point `mm` along a polyline, clamped to its ends.
static func point_at(points: PackedVector3Array, mm: int) -> Vector3:
	var left := maxi(mm, 0)
	for i in range(1, points.size()):
		var segment := roundi(points[i - 1].distance_to(points[i]) * 1000.0)
		if left <= segment:
			var t := float(left) / segment if segment > 0 else 0.0
			return points[i - 1].lerp(points[i], t)
		left -= segment
	return points[points.size() - 1]


## The flat unit direction of travel `mm` along a polyline.
static func heading_at(points: PackedVector3Array, mm: int) -> Vector3:
	var left := maxi(mm, 0)
	for i in range(1, points.size()):
		var segment := roundi(points[i - 1].distance_to(points[i]) * 1000.0)
		if left < segment or i == points.size() - 1:
			var d := points[i] - points[i - 1]
			d.y = 0.0
			return d.normalized() if d.length() > 0.0 else Vector3.FORWARD
		left -= segment
	return Vector3.FORWARD


## "" when the definition can be driven, otherwise what is wrong.
func problem() -> String:
	if road_in.size() < 2 or road_out.size() < 2:
		return "road_in and road_out need at least two points each"
	if curb == null or curb.berths.is_empty() or curb.berths.size() != curb.get_out.size():
		return "the curb needs berths, each with a get-out point"
	if curb.stop_mm <= 0 or curb.stop_mm > length_mm(road_in):
		return "the curb's stop is not on road_in"
	for i in lots.size():
		var found := _lot_problem(lots[i])
		if found != "":
			return "lot spot %d %s" % [i, found]
	for i in curb_spots.size():
		var spot := curb_spots[i]
		if spot == null or spot.berths.is_empty() or spot.berths.size() != spot.get_out.size():
			return "curb spot %d needs berths, each with a get-out point" % i
	return _keep_right_problem()


func _lot_problem(lot: LandsideLotSpot) -> String:
	if lot == null or lot.slots.is_empty() or lot.access.size() < 2 or lot.exit.size() < 2:
		return "needs slots, an access lane and an exit lane"
	if lot.footprint.x <= 0.0 or lot.footprint.y <= 0.0:
		return "needs a footprint"
	if lot.branch_mm <= 0 or lot.branch_mm >= curb.stop_mm:
		return "does not branch off road_in before the curb"
	if lot.crossing.is_empty():
		return "has no pedestrian crossing"
	return ""


func _keep_right_problem() -> String:
	var lanes := {"road_in": road_in, "road_out": road_out}
	for i in lots.size():
		lanes["lot %d access" % i] = lots[i].access
		lanes["lot %d exit" % i] = lots[i].exit
	for lane_name in lanes:
		var segment := wrong_side_segment(lanes[lane_name])
		if segment >= 0:
			return "%s segment %d drives on the left of the road" % [lane_name, segment]
	return ""


## The first segment of `points` that runs along the road (more along x than
## along z) with the centre line on the car's right, or -1 when every such
## segment keeps right. Godot's left of a flat direction (dx, 0, dz) is
## (dz, 0, -dx).
func wrong_side_segment(points: PackedVector3Array) -> int:
	for i in range(1, points.size()):
		var d := points[i] - points[i - 1]
		if absf(d.x) <= absf(d.z):
			continue
		var middle := (points[i] + points[i - 1]) * 0.5
		if -d.x * (centre_line_z - middle.z) <= 0.0:
			return i - 1
	return -1
