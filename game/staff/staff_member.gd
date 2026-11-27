class_name StaffMember
extends RefCounted
## One hired staff member as plain data: its role, whether it is idle, walking
## to a station, on duty there or walking out after being fired, and where it
## stands. A member in the pool
## (at NO_CELL) is off the floor; it enters through the terminal's entrance
## when it is sent to a station. Distances are whole millimetres, as for
## passengers (Passenger.segment_mm).

## SHOP: a server at a cafe or kiosk counter (ShopCounters). CLEANER: works no
## station; it walks to a mess or a full bin, its job (CleanerJobs). GATE: a
## gate agent at a gate desk (GateDesks.DESK). RAMP: airside ramp agent for
## baggage shuttles, pushback tugs and marshalling (RampDispatch).
enum Role { CHECKIN, SECURITY, SHOP, CLEANER, GATE, RAMP }
enum RampJob { NONE, SHUTTLE, PUSHBACK, MARSHAL }
## WALKING_OUT: fired, on its way to the entrance; no longer staff.
## LEAVING_SHIFT: overnight off-shift walkout to the entrance; still staff.
## OFF_SHIFT: off the floor overnight (at NO_CELL); still staff.
## TO_BREAK: walking to a break room spot during a lull; still staff.
## ON_BREAK: resting in a break room, recovering energy; still staff.
## A cleaner is TO_STATION while it walks to its job and ON_DUTY while it
## cleans or empties it.
enum State {
	IDLE,
	TO_STATION,
	ON_DUTY,
	WALKING_OUT,
	LEAVING_SHIFT,
	OFF_SHIFT,
	TO_BREAK,
	ON_BREAK,
}
## The post it works at its station (StaffPosts): PRIMARY opens the station,
## HELPER (at a whole security lane only) speeds up its repacks.
enum Slot { PRIMARY, HELPER }
enum BagCarry { NONE, TO_BIN, TO_EXIT }

const NO_CELL := Vector2i(-1, -1)
const ENERGY_MAX := 100
const ENERGY_MIN := 0
## Energy drain: 1 point per 180 on-duty ticks (~9 game-min; ~70 pts per 10.5h shift).
const DRAIN_INTERVAL_TICKS := 180
## Base energy recovery in a break room: 100 per tick toward 1200 (= 12 ticks/pt).
## RoomPrestige.break_recovery_bonus_percent adds +0..10 per tick.
const RECOVERY_BASE_RATE := 100
const RECOVERY_THRESHOLD := 1200
const TIRED_THRESHOLD := 25
const BREAK_SEEK_THRESHOLD := 35
const BREAK_DONE_THRESHOLD := 95
const TIRED_WORK_FACTOR := 0.80
const LEVEL_MIN := 1
const LEVEL_MAX := 3
const LEVEL_SPEED_PERCENTS: Array[int] = [100, 115, 130]

var id := 0
var role: Role = Role.CHECKIN
var state: State = State.IDLE
## The desk or scanner it walks to or works at; 0 when idle or walking out.
var station := 0
## Which post at `station` it walks to or works; PRIMARY while it has none.
var slot: Slot = Slot.PRIMARY
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
## A cleaner's job: the mess id, or the bin object id when job_bin is set; 0
## with no job. It holds the claim on it (MessSim.claim(); a bin's claim is
## this job, CleanerJobs.bin_holder()), so no other cleaner takes it.
var job := 0
var job_bin := false
## Ticks of cleaning or emptying left while on duty at its job; 0 otherwise.
var work_left := 0
## Bag disposal carry after finishing a clean or emptying a bin.
var bag_carry: BagCarry = BagCarry.NONE
var bag_target := 0
## Ticks remaining before an idle cleaner sets out on a corridor/bin patrol.
var patrol_wait := 0
## StaffSim._replan() turned it back from a cell that went: `at` is that cell
## until it reaches the one it left (path[1]). Cleared on arriving there.
var backing_out := false
var ramp_job: RampJob = RampJob.NONE
var ramp_shuttle_id := 0
var ramp_flight_id := ""
var energy := ENERGY_MAX
var energy_ticks := 0
var break_room := 0
var break_spot := NO_CELL
var level := LEVEL_MIN
var display_name := ""
var quirks: Array[String] = []


func is_tired() -> bool:
	return energy <= TIRED_THRESHOLD


func is_on_break() -> bool:
	return state == State.TO_BREAK or state == State.ON_BREAK


func level_speed_percent() -> int:
	var idx := clampi(level, LEVEL_MIN, LEVEL_MAX) - LEVEL_MIN
	return LEVEL_SPEED_PERCENTS[idx]


func level_speed_factor() -> float:
	return float(level_speed_percent()) / 100.0


func work_speed_percent() -> int:
	var base := level_speed_percent()
	@warning_ignore("integer_division")
	return (base * 4) / 5 if is_tired() else base


func work_speed_factor() -> float:
	return level_speed_factor() * (TIRED_WORK_FACTOR if is_tired() else 1.0)


## Exact tick-derived work steps completed on `tick` for `speed_percent`
## (80, 92, 100, 104, 115, 130). Equals 1 every tick at 100%, skips
## posmod(tick, 5) == 0 at 80%, and telescopes cleanly over skipped ranges.
static func steps_on_tick(tick: int, speed_percent: int) -> int:
	if speed_percent == 100:
		return 1
	@warning_ignore("integer_division")
	var next_cum := ((tick + 1) * speed_percent) / 100
	@warning_ignore("integer_division")
	var cur_cum := (tick * speed_percent) / 100
	return next_cum - cur_cum


func in_pool() -> bool:
	return at == NO_CELL


func is_walking_to_exit() -> bool:
	return state == State.WALKING_OUT or state == State.LEAVING_SHIFT


## Walking to or working a helper post.
func is_helper() -> bool:
	return station != 0 and slot == Slot.HELPER


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
