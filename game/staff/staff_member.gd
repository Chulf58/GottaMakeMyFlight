class_name StaffMember
extends RefCounted
## One hired staff member as plain data: its role, whether it is idle, walking
## to a station, on duty there or walking out after being fired, and where it
## stands. A member in the pool
## (at NO_CELL) is off the floor; it enters through the terminal's entrance
## when it is sent to a station. Distances are whole millimetres, as for
## passengers (Passenger.segment_mm).

enum Role { CHECKIN, SECURITY }
## WALKING_OUT: fired, on its way to the entrance; no longer staff.
enum State { IDLE, TO_STATION, ON_DUTY, WALKING_OUT }

const NO_CELL := Vector2i(-1, -1)

var id := 0
var role: Role = Role.CHECKIN
var state: State = State.IDLE
## The desk or scanner it walks to or works at; 0 when idle or walking out.
var station := 0
var at := NO_CELL
## The committed path, starting at the cell it set out from; empty in the pool.
var path: Array[Vector2i] = []
var path_index := 0
## Progress from `at` towards the next path cell.
var seg_mm := 0
## An edit touched the rest of the path: plan again before the next step.
var needs_replan := false
## The last search found no station to go to; the next waits for its beat.
var search_failed := false
## Fired while a passenger was in service at its station: it stays on duty
## until that service ends, then leaves (StaffSim.fire()).
var leaving := false
## StaffSim._replan() turned it back from a cell that went: `at` is that cell
## until it reaches the one it left (path[1]). Cleared on arriving there.
var backing_out := false


func in_pool() -> bool:
	return at == NO_CELL


func is_moving() -> bool:
	return path_index < path.size() - 1


## Commits a path that starts at `at`.
func set_path(cells: Array[Vector2i]) -> void:
	path = cells
	path_index = 0
	seg_mm = 0


## Stops where it stands; in the pool there is no path at all.
func clear_path() -> void:
	path.clear()
	backing_out = false
	if not in_pool():
		path.append(at)
	path_index = 0
	seg_mm = 0


func path_end() -> Vector2i:
	return path[path.size() - 1] if not path.is_empty() else at


## Walks `mm` along the path. Leftover distance at the end is dropped.
func walk(mm: int) -> void:
	if not is_moving():
		return
	seg_mm += mm
	while path_index < path.size() - 1:
		var length := Passenger.segment_mm(path[path_index], path[path_index + 1])
		if seg_mm < length:
			return
		seg_mm -= length
		path_index += 1
		at = path[path_index]
		backing_out = false
	seg_mm = 0


## Grid-space position (cell centres at +0.5) between `at` and the next cell.
func grid_position() -> Vector2:
	var here := Vector2(at) + Vector2(0.5, 0.5)
	if not is_moving() or seg_mm == 0:
		return here
	var next := path[path_index + 1]
	var t := seg_mm / float(Passenger.segment_mm(at, next))
	return here.lerp(Vector2(next) + Vector2(0.5, 0.5), t)
