class_name Passenger
extends RefCounted
## One passenger as plain data, owned by PassengerSim. Distances are integer
## millimetres and times integer ticks, so a save restores the exact state.
## The journey stage and the stuck status are separate: a stuck passenger
## keeps its stage and says why it cannot go on.

enum Stage {
	SPAWNED,
	TO_CHECKIN,
	CHECKIN_QUEUE,
	CHECKIN,
	TO_SECURITY,
	SECURITY_QUEUE,
	SECURITY,
	TO_GATE,
	SITTING_DOWN,
	SEATED,
	STANDING,
	STANDING_UP,
	TO_EXIT,
	APRON,
	MADE,
	MISSED,
}

enum Stuck { NONE, NO_CHECKIN, NO_SECURITY, QUEUE_FULL, NO_ROUTE, EXIT_BLOCKED }

const STRAIGHT_MM := 1000
const DIAGONAL_MM := 1414
const NO_CELL := Vector2i(-1, -1)
const MOOD_START := 70

var id := 0
var flight_id := ""
## 0 or 1: which Toon character draws this passenger.
var variant := 0
var spawn_tick := 0
## The tick its flight starts boarding.
var boarding_tick := 0
var stage: Stage = Stage.SPAWNED
var stuck: Stuck = Stuck.NONE
## The tick the current stage began (sitting and standing durations).
var stage_tick := 0
## The cell the passenger last reached.
var at := NO_CELL
## The committed path, path[path_index] == at while it is walked.
var path: Array[Vector2i] = []
var path_index := 0
## Progress along the step from path[path_index] to the next cell.
var seg_mm := 0
## The station (object id) chosen for the current queue stage, 0 for none.
var station := 0
var service_end := 0
var seat_object := 0
var seat_cell := NO_CELL
var seat_front := NO_CELL
var exit_object := 0
## The apron walk from the exit door to the plane door, world x and z.
var apron: Array[Vector2] = []
var apron_mm := 0
var mood := MOOD_START
var late := false
var cleared := false
## Set when an edit touched the committed path; replanned on the next tick.
var needs_replan := false
var outcome_tick := -1
## Everything walked so far, path and apron.
var odometer_mm := 0


static func segment_mm(a: Vector2i, b: Vector2i) -> int:
	return DIAGONAL_MM if a.x != b.x and a.y != b.y else STRAIGHT_MM


static func path_mm(cells: Array[Vector2i]) -> int:
	var mm := 0
	for i in range(1, cells.size()):
		mm += segment_mm(cells[i - 1], cells[i])
	return mm


## Octile distance in millimetres: the length of the best open-floor path.
static func octile_mm(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return DIAGONAL_MM * mini(dx, dy) + STRAIGHT_MM * absi(dx - dy)


func is_moving() -> bool:
	return path_index < path.size() - 1


func is_done() -> bool:
	return stage == Stage.MADE or stage == Stage.MISSED


## Commits a path that starts at `at`.
func set_path(cells: Array[Vector2i]) -> void:
	path = cells
	path_index = 0
	seg_mm = 0


func clear_path() -> void:
	path = [at]
	path_index = 0
	seg_mm = 0


## The last cell of the committed path, or `at` when there is none.
func path_end() -> Vector2i:
	return path[path.size() - 1] if not path.is_empty() else at


func remaining_mm() -> int:
	var mm := -seg_mm
	for i in range(path_index, path.size() - 1):
		mm += segment_mm(path[i], path[i + 1])
	return maxi(mm, 0)


## Walks `mm` along the path. Leftover distance at the end is dropped.
func walk(mm: int) -> void:
	if not is_moving():
		return
	odometer_mm += mini(mm, remaining_mm())
	seg_mm += mm
	while path_index < path.size() - 1:
		var length := segment_mm(path[path_index], path[path_index + 1])
		if seg_mm < length:
			return
		seg_mm -= length
		path_index += 1
		at = path[path_index]
	seg_mm = 0


## Grid-space position (cell centres at +0.5) between `at` and the next cell.
func grid_position() -> Vector2:
	var here := Vector2(at) + Vector2(0.5, 0.5)
	if not is_moving() or seg_mm == 0:
		return here
	var next := path[path_index + 1]
	var t := seg_mm / float(segment_mm(at, next))
	return here.lerp(Vector2(next) + Vector2(0.5, 0.5), t)


func apron_total_mm() -> int:
	var mm := 0
	for i in range(1, apron.size()):
		mm += apron_segment_mm(i)
	return mm


func apron_segment_mm(i: int) -> int:
	return roundi(apron[i - 1].distance_to(apron[i]) * 1000.0)


## World x and z along the apron walk at the current progress.
func apron_position() -> Vector2:
	var left := apron_mm
	for i in range(1, apron.size()):
		var length := apron_segment_mm(i)
		if left <= length:
			return apron[i - 1].lerp(apron[i], left / float(maxi(length, 1)))
		left -= length
	return apron[apron.size() - 1]
