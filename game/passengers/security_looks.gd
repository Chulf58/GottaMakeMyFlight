class_name SecurityLooks
extends RefCounted
## What a passenger at security looks like on this tick, read from its
## SecurityRuntime phase (Security 7/8). Pure: it reads the sim and the lane
## geometry (SecurityLanes) and returns where the passenger wants to stand,
## which way it faces, where its tray is and where each carry-on bag is.
## PassengerViews and CarryOnProps draw from it; nothing here keeps state.
##
## At a lane: UNPACK steps toward the tray table and faces it; the bags move
## from the hands into a tray on the tray table, one by one as the unpack work
## runs. ARCH on the first pass: the tray rides the X-ray belt beside the
## passenger. PICKUP steps toward the pickup table, the tray waits there and
## the bags go back to the hands one by one. TO_BERTH, RETURN and LEAVE carry
## the bags. REPACK puts them on the floor in front of the passenger, who faces
## the return route it walks next, so it picks them up ahead of it rather
## than behind (from where a bag would pass through the body). On the second
## pass, after a repack, the passenger puts its bags on a tray again when it
## reaches the unpack cell, and they ride the belt as on the first pass. At
## the basic scanner: SCAN carries the bags, REPACK puts them on the floor
## where the passenger stands, which holds the scanner. Outside security the
## bags are carried, and set down while seated (bag_homes(), floor_spot()) or
## on an activity visit (activity_floor()).
##
## Shared cells: the next queue front walks onto the unpack cell while the
## passenger before it still unpacks there, and a returner crosses the unpack
## cell on its second pass. A queue front of a lane therefore stops at the
## unpack cell's queue-side edge (QUEUE_EDGE_M from its centre) while another
## admitted passenger of that lane unpacks or is in ARCH within CLEAR_M of the
## unpack centre.

enum Home { NONE, HAND, TRAY, FLOOR }
enum Tray { NONE, IN, RIDE, OUT }
## The kinds of carry-on bag (decision carry-on-bag-kinds-backpack-shoulder-or-
## tote-bag-small-rolle): looks only, the sim never reads them.
enum Kind { CASE, BACKPACK, SHOULDER, ROLLER }
## How a kind is carried while its home is HAND: the hard case in the hand,
## the backpack worn on the back, the tote on one shoulder, the roller pulled.
enum Carry { HAND, BACK, SHOULDER, PULL }

## The interior kit piece that draws each kind.
const KIND_PIECES := {
	Kind.CASE: "carry_on_bag",
	Kind.BACKPACK: "carry_backpack",
	Kind.SHOULDER: "carry_shoulder_bag",
	Kind.ROLLER: "carry_roller",
}
const KIND_CARRY := {
	Kind.CASE: Carry.HAND,
	Kind.BACKPACK: Carry.BACK,
	Kind.SHOULDER: Carry.SHOULDER,
	Kind.ROLLER: Carry.PULL,
}

## How far an unpacking or picking-up passenger steps toward its table.
const STEP_M := 0.15
## The step to the tray table eases out over this much of the arch walk, so
## the body walks off it into the arch rather than sideways (setting_off()).
const SETOFF_EASE_M := 0.3
## Where a held-back queue front stands, from the unpack cell's centre.
const QUEUE_EDGE_M := 0.5
## A passenger in ARCH this near the unpack centre still holds the queue back:
## past the arch for one leaving, and the whole crossing for a returner, who
## starts its ARCH one cell to the side of the unpack cell.
const CLEAR_M := 1.05
## Two bags are drawn at this scale so both fit one tray.
const TWO_BAG_SCALE := 0.55
## A floor bag's centre, in front of the passenger.
const FLOOR_AHEAD_M := 0.56
## Two floor bags stand this far either side of the passenger's line.
const FLOOR_APART_M := 0.16
## A bag at a gate chair lies at the sitter's feet, this far ahead.
const SEAT_AHEAD_M := 0.62
## How far ahead of a gate chair's front (m, out of the chair) each of a two-bag
## guest's floor bags lies (gate_two_bag()), per body variant (0 male, 1
## female) and per bag (0 on the right, 1 on the left): the toe of that foot in
## the idle clip, the bag's back half at TWO_BAG_SCALE (0.132 m, a hard case)
## and 1 cm (board fc38d1b2). The male idle stance has the left foot 0.347 m
## ahead, the right 0.194 m; the female 0.190 m and 0.064 m.
const GATE_TWO_AHEAD_M := [[0.34, 0.49], [0.21, 0.34]]
## A bag at a cafe seat lies beside the chair, this far to the sitter's right.
const CAFE_BESIDE_M := 0.45
## A bag set down by a sofa or nap pod visitor stands upright on the floor
## beside the seat, on the side of the hand that carries it, its back face this
## far out from the seat's root (Mount_SitRoot) and its thickness (0.23 m at
## most) toward the legs (0.15 m out): inside the piece's own width (0.42 m
## out from a pod's or a sofa end seat's root, where a wall can stand). Lying
## flat, a hard case was 0.35 m across and went into the wall or the shin.
const ACTIVITY_BESIDE_M := 0.40
## And its middle this far ahead of the seat's root: the widest bag (0.39 m
## across) keeps 0.04 m clear of the piece's front, 0.15 m behind the root.
const ACTIVITY_AHEAD_M := 0.15
## A bag a showering visitor sets down stands upright outside the cubicle
## door the same way, its back face this far out from the cubicle's middle line
## (inside the cubicle's width, where a wall can stand beside the cell in front
## of the door) and its thickness toward the line, clear of the legs walking
## in (0.15 m out), on the side of the hand that carries it as the visitor
## faces the door.
const SHOWER_BAG_SIDE_M := 0.41
## Its middle this far out from the cubicle's middle: the widest bag (0.39 m
## across) keeps 0.03 m clear of the door's face at 0.42 m.
const SHOWER_BAG_OUT_M := 0.65
## A bag in a toilet stall stands upright on its end (STALL_UPRIGHT) with its
## back face this far out from the stall's footprint centre: against the inside
## of the closed door's leaves (0.881 m, less a 0.02 m gap), so the deepest bag
## (0.226 m) keeps 0.635 m out, clear of the seated and standing feet (about
## 0.55 m). Lying flat it was 0.35 m deep and the feet stood in it.
const STALL_BAG_M := 0.861
## A stall bag's own axes in the frame of a passenger facing out of the door:
## its length (z) up, so a roller stands on its wheels and a backpack's loop is
## on top; its back face (y = 0, a roller's rods) against the door and its
## front (a case's handle face) toward the seat; its width (x) across.
const STALL_UPRIGHT := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)


## The lane geometry of the station `p` is admitted at or queues for, or {}
## at a basic scanner or anywhere else.
static func lane_of(sim: PassengerSim, p: Passenger) -> Dictionary:
	var lanes := sim.layout.security_lanes
	if p.station == 0 or not lanes.is_complete(p.station):
		return {}
	return lanes.lane(p.station)


## A grid step as a world direction.
static func world_dir(step: Vector2i) -> Vector3:
	return Vector3(step.x, 0.0, step.y)


## Where `p` wants to be drawn, from its sim position: a step toward the table
## at UNPACK and PICKUP, held back at the queue edge as the header says, the
## step to the tray table easing out as it sets off into the arch
## (setting_off()), and zero otherwise. PassengerViews moves the drawn offset
## toward it at walking speed, and sets it exactly while setting off.
static func target_offset(sim: PassengerSim, p: Passenger) -> Vector3:
	var lane := lane_of(sim, p)
	if lane.is_empty():
		return Vector3.ZERO
	if p.stage == Passenger.Stage.SECURITY_QUEUE:
		return _queue_hold(sim, p, lane)
	if p.stage != Passenger.Stage.SECURITY:
		return Vector3.ZERO
	match p.security_phase:
		SecurityRuntime.Phase.UNPACK, SecurityRuntime.Phase.PICKUP:
			return world_dir(lane["side"]) * STEP_M
	if setting_off(sim, p):
		var walked := _arch_walked_mm(p) / (SETOFF_EASE_M * 1000.0)
		return world_dir(lane["side"]) * STEP_M * (1.0 - smoothstep(0.0, 1.0, walked))
	return Vector3.ZERO


## Whether `p` walks its first pass's arch walk from the unpack cell (ARCH, the
## path still the one from the unpack cell to the arch cell). The step to the
## tray table eases out over its first SETOFF_EASE_M (target_offset()), set
## from how far it has walked, and it faces as setoff_yaw() says.
static func setting_off(sim: PassengerSim, p: Passenger) -> bool:
	if p.stage != Passenger.Stage.SECURITY or p.security_phase != SecurityRuntime.Phase.ARCH:
		return false
	var lane := lane_of(sim, p)
	return not lane.is_empty() and p.path.size() >= 2 and p.path[0] == lane["unpack"]


## The yaw a lane passenger is drawn with from UNPACK until it walks into the
## arch, or NAN where it does not apply (PassengerViews then turns it as any
## other). It turns from `from` (the yaw it had when UNPACK began, or NAN for
## the way it walked onto the unpack cell, arrival_yaw()) to the tray table
## over PassengerTurns.TURN_TICKS from the start of UNPACK, and to the arch's
## axis over as many ticks from the tick its last bag goes in the tray
## (LANE_UNPACK_BAG_TICKS of work left), so it stands turned most of the way
## when ARCH starts and finishes the turn on its first strides, read from how
## far it has walked at its pace. A one-bag passenger turns back before it
## has fully faced the table. Turned only once the walk began, the body was
## still 16 to 51 degrees off the axis at the arch's entry and its feet
## reached 0.45 to 0.65 m out against a 0.38 m half opening (finding
## why-does-the-body-reach-past-the-security-lane-arch-s-0-38-m). Set from the
## start yaw, the work left and the walk, never stepped from the yaw drawn
## before, so a view first drawn mid-turn (a load, a new view) draws the same
## yaw when it started from the way it walked in.
static func setoff_yaw(sim: PassengerSim, p: Passenger, from := NAN) -> float:
	if p.stage != Passenger.Stage.SECURITY:
		return NAN
	var lane := lane_of(sim, p)
	if lane.is_empty():
		return NAN
	var turn := float(PassengerTurns.TURN_TICKS)
	var toward := 1.0
	var back := 0.0
	if p.security_phase == SecurityRuntime.Phase.UNPACK:
		var done := SecurityRuntime.work_for(SecurityRuntime.Phase.UNPACK, p) - p.security_work
		toward = smoothstep(0.0, 1.0, done / turn)
		back = SecurityRuntime.LANE_UNPACK_BAG_TICKS - p.security_work
	elif setting_off(sim, p):
		# UNPACK is last drawn with one tick of work left, and ARCH's first tick
		# has walked one step already.
		var pace := PassengerSim.RUN_MM if p.late else PassengerSim.WALK_MM
		back = SecurityRuntime.LANE_UNPACK_BAG_TICKS - 1 + _arch_walked_mm(p) / float(pace)
	else:
		return NAN
	if is_nan(from):
		from = arrival_yaw(sim, p)
	var axis := -Vector2(lane["front"])
	var table := Vector2(lane["side"])
	var at_table := lerp_angle(from, atan2(table.x, table.y), toward)
	return lerp_angle(at_table, atan2(axis.x, axis.y), smoothstep(0.0, 1.0, back / turn))


## The yaw a lane passenger faces as it reaches the unpack cell: along the last
## step of the path it walked there (an empty lane may be walked into from the
## side), or along the arch's axis with no step (a queue front held back at the
## cell's edge faces the lane). Read from the saved path, so a view first drawn
## during UNPACK starts its turn from the same yaw.
static func arrival_yaw(sim: PassengerSim, p: Passenger) -> float:
	var lane := lane_of(sim, p)
	var way := -Vector2(lane["front"]) if not lane.is_empty() else Vector2.ZERO
	var last := mini(p.path_index, p.path.size() - 1)
	if last >= 1 and p.path[last] == p.at:
		way = Vector2(p.path[last] - p.path[last - 1])
	return atan2(way.x, way.y)


## How far `p` has walked along its path, in millimetres.
static func _arch_walked_mm(p: Passenger) -> int:
	var mm := p.seg_mm
	for i in mini(p.path_index, p.path.size() - 1):
		mm += Passenger.segment_mm(p.path[i], p.path[i + 1])
	return mm


## The ground direction (x, z) `p` faces while it works, or ZERO to keep its
## heading: the tray table at UNPACK, the pickup table at PICKUP, the return
## route at a lane's REPACK, and the lane while a queue front is held back.
static func face(sim: PassengerSim, p: Passenger) -> Vector2:
	var lane := lane_of(sim, p)
	if lane.is_empty():
		return Vector2.ZERO
	if p.stage == Passenger.Stage.SECURITY_QUEUE:
		var held := _queue_hold(sim, p, lane) != Vector3.ZERO
		return -Vector2(lane["front"]) if held else Vector2.ZERO
	if p.stage != Passenger.Stage.SECURITY:
		return Vector2.ZERO
	match p.security_phase:
		SecurityRuntime.Phase.UNPACK, SecurityRuntime.Phase.PICKUP:
			return Vector2(lane["side"])
		SecurityRuntime.Phase.REPACK:
			return Vector2(lane["front"])
	return Vector2.ZERO


## Where the tray of `p` is: on the tray table at UNPACK, riding the belt in
## ARCH, on the pickup table at PICKUP. A returner's ARCH starts beside the
## unpack cell, so its tray appears once it reaches the unpack cell.
static func tray(sim: PassengerSim, p: Passenger) -> Tray:
	if p.stage != Passenger.Stage.SECURITY or lane_of(sim, p).is_empty():
		return Tray.NONE
	match p.security_phase:
		SecurityRuntime.Phase.UNPACK:
			return Tray.IN
		SecurityRuntime.Phase.ARCH:
			return Tray.RIDE if _on_passage(sim, p) else Tray.NONE
		SecurityRuntime.Phase.PICKUP:
			return Tray.OUT
	return Tray.NONE


## Where each of the carry-on bags of `p` is (Home), one entry per bag, for
## the whole visit: in hand, on the floor while seated at a gate chair, a
## cafe seat or in a toilet stall, and at security as the header says.
static func bag_homes(sim: PassengerSim, p: Passenger) -> Array[Home]:
	var out: Array[Home] = []
	if p.stage == Passenger.Stage.SECURITY:
		for i in p.carry_on:
			out.append(_security_home(sim, p, i))
		return out
	var seated := _seated(sim, p)
	for i in p.carry_on:
		var down := seated or _lost_chair_roller(p, i)
		out.append(Home.FLOOR if down and not _rolled_up(sim, p, i) else Home.HAND)
	return out


## Whether bag `index` of `p` is a roller on the floor of a gate chair that
## was removed while `p` stands up from it (the sim clears the seat and the
## walker keeps rising). It stays down until the stand-up has run
## (_rolled_up()), as with the chair there: taken at once, the pick-up began
## on a body still rising.
static func _lost_chair_roller(p: Passenger, index: int) -> bool:
	return (
		p.stage == Passenger.Stage.STANDING_UP
		and p.seat_object == 0
		and bag_kind(p, index) == Kind.ROLLER
	)


## Whether bag `index` of `p` is a roller taken off the floor into the pull
## while `p` stands up from a gate chair or a cafe seat: once it is up,
## STAND_UP_TICKS in (decision standing-up-with-a-roller-stand-up-then-pick-up-
## then-walk). It stands ParkRecovery.UP_HOLD_TICKS more while the roller is
## picked up, at a gate chair's front (ParkRecovery.stand_up_ticks()) or where
## it sat at a cafe seat (CafeSim.up_ticks()). Started on a body still rising,
## the hand fell short and the bag jumped into it; at a cafe seat the pick-up
## began RollerPark.UP_LEAD_TICKS before the stand-up ended (board 2c659e42).
static func _rolled_up(sim: PassengerSim, p: Passenger, index: int) -> bool:
	if p.stage not in [Passenger.Stage.STANDING_UP, Passenger.Stage.CAFE_STANDING_UP]:
		return false
	if bag_kind(p, index) != Kind.ROLLER:
		return false
	return sim.tick - p.stage_tick >= PassengerSim.STAND_UP_TICKS


## Which hand holds bag `index` of `p` when it is carried: 0 the right, 1 the
## left. Two bags take one hand each. One bag is in the right hand, unless
## the cell beside the passenger on its right, for the way it walks (or last
## walked), is closed off by a wall or holds an object (a lane part, a desk)
## and the left is open: then the left, so the bag passes on the open side.
## On an activity visit the way is the one it faces to set its bags down
## (_stay_step), so the bag goes down on the open side. Near a booth seat or a
## sofa or nap pod where a roller parks beside the guest, ParkSide has the
## last word: the open side when only one side is walled.
static func hand_of(sim: PassengerSim, p: Passenger, index: int) -> int:
	if p.carry_on > 1:
		return index
	return ParkSide.hand(sim, p, _cell_hand(sim, p))


## hand_of()'s one-cell look for a one-bag guest: 1 (the left) when the cell
## beside it on its right is closed and the one on its left open, else 0.
static func _cell_hand(sim: PassengerSim, p: Passenger) -> int:
	var step := _stay_step(sim, p)
	if step == Vector2i.ZERO and p.path.size() >= 2:
		var at := clampi(p.path_index, 0, p.path.size() - 2)
		step = p.path[at + 1] - p.path[at]
	if step == Vector2i.ZERO:
		return 0
	var right := world_dir(step).cross(Vector3.UP)
	var right_step := Vector2i(signi(roundi(right.x)), signi(roundi(right.z)))
	var cell := p.at
	if _closed(sim.grid, cell, right_step) and not _closed(sim.grid, cell, -right_step):
		return 1
	return 0


## The grid way an activity visitor (ActivityPoses.kind not NONE) faces as it
## sets its bags down and picks them up: out of the piece on a sofa or nap pod
## seat, into it at the shower's door. Zero for any other passenger. Its
## visit's path is only its own cell (ShopSim clears it), so the way it walked
## in is gone; this way comes from the piece, the same after a load.
static func _stay_step(sim: PassengerSim, p: Passenger) -> Vector2i:
	var kind := ActivityPoses.kind(sim, p)
	if kind == ActivityPoses.Kind.NONE:
		return Vector2i.ZERO
	var out := ActivityPoses.stay_frame(sim, p).basis.z
	var step := Vector2i(roundi(out.x), roundi(out.z))
	return -step if kind == ActivityPoses.Kind.SHOWER else step


## The kind of carry-on bag `index` of `p`: a fixed hash of the passenger's id
## and the bag's index, so a save, a load and a replay draw the same bags
## without any saved state, and the sim RNG is not drawn from. A second bag
## never repeats a backpack or a roller (one back, one trailer).
static func bag_kind(p: Passenger, index: int) -> Kind:
	var first := _mix(p.id * 2) % Kind.size() as Kind
	if index == 0:
		return first
	var second := _mix(p.id * 2 + 1) % Kind.size() as Kind
	if second == first and (first == Kind.BACKPACK or first == Kind.ROLLER):
		second = (first + 1 + _mix(p.id * 2 + 7) % (Kind.size() - 1)) % Kind.size() as Kind
	return second


## How bag `index` of `p` is carried while in hand (Carry).
static func carry_of(p: Passenger, index: int) -> Carry:
	return KIND_CARRY[bag_kind(p, index)]


## The side a worn shoulder bag hangs on: 0 the right, 1 the left, by its
## index (stable, so a narrow cell never moves it across).
static func worn_side(index: int) -> int:
	return index % 2


## A 32-bit integer mixer (a non-negative result).
static func _mix(value: int) -> int:
	var x := value & 0xFFFFFFFF
	x = ((x >> 16) ^ x) * 0x45D9F3B & 0xFFFFFFFF
	x = ((x >> 16) ^ x) * 0x45D9F3B & 0xFFFFFFFF
	return (x >> 16) ^ x


## Whether `p` carries its bags in front of the body: when the cell it stands
## on, or the next cell it walks into, is closed on both flanks for the way it
## walks (decision in-a-cell-closed-on-both-sides-a-passenger-carries-their-
## bag). A side-carried bag reaches about 0.55-0.6 m out, more than such a
## cell leaves. Standing still, the cell it stands on and its last step count.
## Held in a boarding file (RollerPark.filed_still()) its path is open but it
## takes no step, so it counts as standing: with no step taken on the path it
## reads as it did before the path (false), as no path does, else the cell it
## stands on and its last step count (board aa2db71d: a stander held at the
## gate read the step it had not taken, and its stood roller tipped).
## A basic scanner booth's cells count as closed on both sides, standing or
## walking (decision basic-scanner-booth-passengers-carry-their-bags-in-front-
## and): its panels leave about 0.41 m either side of the centre line.
static func carry_front(sim: PassengerSim, p: Passenger) -> bool:
	if in_booth_passage(sim, p):
		return true
	if p.path.size() < 2:
		return false
	var held := p.is_moving() and RollerPark.filed_still(sim, p)
	if held and p.path_index == 0:
		return false
	var at := p.path_index - 1 if held else clampi(p.path_index, 0, p.path.size() - 2)
	var step := p.path[at + 1] - p.path[at]
	if step == Vector2i.ZERO:
		return false
	var right := world_dir(step).cross(Vector3.UP)
	var flank := Vector2i(signi(roundi(right.x)), signi(roundi(right.z)))
	var cells: Array[Vector2i] = [p.at]
	if p.is_moving() and not held:
		cells.append(p.path[at + 1])
	for cell in cells:
		if _closed(sim.grid, cell, flank) and _closed(sim.grid, cell, -flank):
			return true
	return false


## Whether `p` stands in a basic scanner booth, walks into one now, or waits
## at a booth's entry cell in the security queue (or, still on its way to
## security, walks into or stands on its own booth's entry): there its bags are carried
## in front and its free arms tucked in (CarryOnProps). The entry counts so the
## turn has ended before the bags reach the booth's rails; leaving, the cell it
## stands on stays a booth cell until it arrives in the cell past the booth.
static func in_booth_passage(sim: PassengerSim, p: Passenger) -> bool:
	if in_booth(sim.grid, p.at):
		return true
	var queued := p.stage == Passenger.Stage.SECURITY_QUEUE or p.stage == Passenger.Stage.SECURITY
	if queued and _booth_entry(sim, p.at):
		return true
	# Arrived at its own entry on the way, it joins the queue next tick.
	if p.stage == Passenger.Stage.TO_SECURITY and _own_entry(sim, p, p.at):
		return true
	if not p.is_moving() or p.path.size() < 2:
		return false
	var at := clampi(p.path_index, 0, p.path.size() - 2)
	var next := p.path[at + 1]
	if in_booth(sim.grid, next):
		return true
	# Walking up to the entry it starts a step early, so the turn (after a
	# roller's lift into the hand, CarryOnProps) ends before the booth's rails.
	if queued:
		return _booth_entry(sim, next)
	# So does a walker still on its way to security that walks into its own
	# booth's entry: with no queue it is admitted there without stopping, and
	# started at the entry it was still turning 1.4 m out.
	return p.stage == Passenger.Stage.TO_SECURITY and _own_entry(sim, p, next)


## Whether `cell` is the entry cell of the basic scanner `p` chose (its station).
static func _own_entry(sim: PassengerSim, p: Passenger, cell: Vector2i) -> bool:
	var passage: Array = sim.layout.passages.get(p.station, [])
	return passage.size() > 1 and passage[0] == cell and in_booth(sim.grid, passage[1])


## Whether `cell` is the entry cell of a basic scanner's passage.
static func _booth_entry(sim: PassengerSim, cell: Vector2i) -> bool:
	var layout: TerminalLayout = sim.layout
	for id: int in layout.scanners:
		var passage: Array = layout.passages.get(id, [])
		if not passage.is_empty() and passage[0] == cell and in_booth(sim.grid, passage[1]):
			return true
	return false


## Whether `cell` lies inside a basic scanner booth (a security_scanner).
static func in_booth(grid: BuildGrid, cell: Vector2i) -> bool:
	return def_at(grid, cell) == &"security_scanner"


## Whether `p` stands in a security lane's arch or walks into one now: there
## its free arms tuck in as at a basic scanner booth (CarryOnProps), since the
## arch is narrowed to fit inside its cell beside a wall (decision security-
## lane-arch-is-narrowed-to-fit-inside-its-cell-beside-a). Its bags are in the
## tray then, so nothing goes to the front. Leaving, the arch cell counts until
## it arrives in the cell past it.
static func in_arch_passage(sim: PassengerSim, p: Passenger) -> bool:
	if def_at(sim.grid, p.at) == SecurityLanes.ARCH:
		return true
	if not p.is_moving() or p.path.size() < 2:
		return false
	var at := clampi(p.path_index, 0, p.path.size() - 2)
	return def_at(sim.grid, p.path[at + 1]) == SecurityLanes.ARCH


## The def id of the object on `cell`, or an empty name.
static func def_at(grid: BuildGrid, cell: Vector2i) -> StringName:
	var id := grid.object_at(cell)
	return StringName(grid.get_object(id).get("def", "")) if id != 0 else &""


## Whether either straight part of a (possibly diagonal) step out of `cell`
## is closed (_side_closed).
static func _closed(grid: BuildGrid, cell: Vector2i, toward: Vector2i) -> bool:
	if toward.x != 0 and _side_closed(grid, cell, Vector2i(toward.x, 0)):
		return true
	return toward.y != 0 and _side_closed(grid, cell, Vector2i(0, toward.y))


## The scale every bag of `p` is drawn at.
static func bag_scale(p: Passenger) -> float:
	return TWO_BAG_SCALE if p.carry_on > 1 else 1.0


## Bag `index` of `count`, relative to the tray's mount: centred for one bag,
## end to end along the tray's length for two.
static func in_tray(index: int, count: int, bag_length: float) -> Vector3:
	if count < 2:
		return Vector3.ZERO
	var half := bag_length * TWO_BAG_SCALE * 0.5 + 0.003
	return Vector3(0.0, 0.0, half if index == 0 else -half)


## Where floor bag `index` of `count` of `p` lies, in the passenger's frame
## (+z ahead, +x its left, on the floor): at the feet of a gate chair (a
## two-bag guest's in the chair front's frame, gate_two_bag()), beside
## a cafe seat (the table is ahead), upright against the door inside a toilet
## stall (stall_floor()), and ahead of a repacking passenger. One bag lies
## across the passenger's line, two lie along it side by side, each on the side
## of the hand that carries it (bag i in hand i, 0 the right, -x), so the hands
## do not cross to set them down or pick them up (in a stall, two stand side by
## side across it).
static func floor_spot(sim: PassengerSim, p: Passenger, index: int, count: int) -> Transform3D:
	var across := Basis(Vector3.UP, PI / 2.0) if count < 2 else Basis.IDENTITY
	var side := 0.0 if count < 2 else (-FLOOR_APART_M if index == 0 else FLOOR_APART_M)
	var where := StageKinds.location(p.stage)
	if where == StageKinds.Location.FACILITY_SEAT and _in_stall(sim, p):
		# On the stall's floor against the door, ahead of the feet.
		var stall := sim.toilets.visit_of(p.id).stall
		var out := world_dir(stall["front"])
		var body := Transform3D(Basis(Vector3.UP, atan2(out.x, out.z)), sim.world_position(p))
		var spot := body.affine_inverse() * stall_floor(stall, index, count)
		spot.origin.y = 0.0
		return spot
	if where == StageKinds.Location.FACILITY_SEAT:
		# Beside the chair, lying along it, bag 0 ahead of bag 1.
		var along := 0.0 if count < 2 else -side
		return Transform3D(Basis.IDENTITY, Vector3(-CAFE_BESIDE_M, 0.0, along))
	if count >= 2 and gate_two_front(sim, p) != null:
		# In the chair front's frame (gate_two_front(), CarryPlace lays it there),
		# ahead of the toes of the body standing at the front: SEAT_AHEAD_M ahead
		# of the sim's spot, which goes back into the seat while the body is
		# still drawn standing at the front (SitHold), lay on its own foot (board
		# fc38d1b2).
		return gate_two_bag(PassengerLooks.body_of(p.id, p.variant), index)
	if where == StageKinds.Location.GATE_SEAT:
		return Transform3D(across, Vector3(side, 0.0, SEAT_AHEAD_M))
	return Transform3D(across, Vector3(side, 0.0, FLOOR_AHEAD_M))


## The frame (world, on the floor) a two-bag guest `p`'s floor bags that are
## not a roller lie in at a gate chair (gate_two_bag()), fixed while the body
## stands at the front, eases into the seat and back out: the chair front's
## cell centre facing out of the chair. Null when `p` is not sitting down,
## seated or standing up at a gate chair.
static func gate_two_front(sim: PassengerSim, p: Passenger) -> Variant:
	if StageKinds.location(p.stage) != StageKinds.Location.GATE_SEAT:
		return null
	if p.seat_cell == Passenger.NO_CELL:
		return null
	var front_at := sim.grid.cell_to_world(p.seat_front)
	var out := front_at - sim.grid.cell_to_world(p.seat_cell)
	return Transform3D(Basis(Vector3.UP, atan2(out.x, out.z)), front_at)


## Where floor bag `index` of a two-bag guest of body `look`
## (PassengerLooks.BODIES index) lies at a gate chair, in the chair front's
## frame (the front cell's centre on the floor, +z out of the chair): along the
## line, FLOOR_APART_M out on the side of the hand that carries it, ahead of
## that foot's toe (GATE_TWO_AHEAD_M).
static func gate_two_bag(look: int, index: int) -> Transform3D:
	var variant := clampi(look / PassengerLooks.PER_VARIANT, 0, GATE_TWO_AHEAD_M.size() - 1)
	var side := -FLOOR_APART_M if index == 0 else FLOOR_APART_M
	return Transform3D(Basis.IDENTITY, Vector3(side, 0.0, GATE_TWO_AHEAD_M[variant][index]))


## Where each of the `count` floor bags of an activity visitor `p` stands, in
## the world (empty for any other passenger): fixed while the body steps onto
## its seat and off, or into the shower and out (ActivityPoses.stay_frame).
## Each stands upright on its end (a roller on its wheels) on the floor, its
## back face (y = 0) outward and its thickness toward the body: by a sofa or
## nap pod seat in front of the piece, beside the legs on the side of the hand
## that carries it (ACTIVITY_BESIDE_M, ACTIVITY_AHEAD_M); at the shower
## outside the door, on the side of its hand as the visitor faces the door
## (SHOWER_BAG_SIDE_M, SHOWER_BAG_OUT_M). Each origin is on the floor;
## CarryOnProps lifts a bag by its own bounds onto it (on_floor()).
static func activity_floor(sim: PassengerSim, p: Passenger, count: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var kind := ActivityPoses.kind(sim, p)
	if kind == ActivityPoses.Kind.NONE:
		return out
	var frame := ActivityPoses.stay_frame(sim, p)
	var shower := kind == ActivityPoses.Kind.SHOWER
	for i in count:
		# +1 on the left of one facing out of the piece, -1 on its right; facing
		# the shower's door the hands swap sides.
		var side := 1.0 if hand_of(sim, p, i) == 1 else -1.0
		if shower:
			side = -side
		# Its length (z) up, its back (y) outward.
		var upright := Basis(Vector3(0.0, 0.0, -side), Vector3(-side, 0.0, 0.0), Vector3.UP)
		var at := Vector3(side * ACTIVITY_BESIDE_M, 0.0, ACTIVITY_AHEAD_M)
		if shower:
			at = Vector3(side * SHOWER_BAG_SIDE_M, 0.0, SHOWER_BAG_OUT_M)
		out.append(frame * Transform3D(upright, at))
	return out


## A floor bag of bounds `box` (scale 1) at `spot` (activity_floor()) drawn at
## `scale_by`: lifted so its lowest point is on the floor under the spot
## (the CarryOnProps placement of an activity visitor's floor bags).
static func on_floor(spot: Transform3D, box: AABB, scale_by: float) -> Transform3D:
	var placed := Transform3D(spot.basis.scaled(Vector3.ONE * scale_by), spot.origin)
	return placed.translated(Vector3.UP * (spot.origin.y - StallCarry.lowest(placed, box)))


## Whether the edge of `cell` toward `toward` (a straight grid step) has a
## wall, or the cell beyond holds an object.
static func _side_closed(grid: BuildGrid, cell: Vector2i, toward: Vector2i) -> bool:
	var side := BuildGrid.SIDE_STEP.find(toward)
	if side < 0:
		return false
	return grid.has_wall(cell, side) or grid.object_at(cell + toward) != 0


## Whether `p` sits at a gate chair, a cafe seat or in a toilet stall (or is
## sitting down or standing up there), or has its bags down on an activity
## visit (ActivityPoses.bags_down: on a sofa or nap pod seat, or at the
## shower). Stepping into or out of a stall is not seated: the bags stay in
## hand.
static func _seated(sim: PassengerSim, p: Passenger) -> bool:
	if ActivityPoses.bags_down(sim, p):
		return true
	var where := StageKinds.location(p.stage)
	if where == StageKinds.Location.GATE_SEAT and p.seat_object != 0:
		return true
	if where != StageKinds.Location.FACILITY_SEAT:
		return false
	return sim.cafes.seat_facing(p) != Vector2i.ZERO or _in_stall(sim, p)


## Whether `p` sits down, sits or stands up in a toilet stall, facing out of
## its door.
static func _in_stall(sim: PassengerSim, p: Passenger) -> bool:
	return sim.toilets.use_facing(p) != Vector2i.ZERO


## Where floor bag `index` of `count` stands in `stall` (a ToiletLayout
## entry), in the world, a point fixed in the stall (the body shuffles between
## Mount_Turn and Mount_Use above it): STALL_UPRIGHT turned to face out of the
## door, its back face STALL_BAG_M out from the footprint centre, one bag on the
## centre line and two FLOOR_APART_M either side of it (each on its hand's
## side), its origin on the floor
## (CarryOnProps lifts a bag by its own bounds so it stands on the floor).
static func stall_floor(stall: Dictionary, index: int, count: int) -> Transform3D:
	var out := world_dir(stall["front"])
	var facing := Basis(Vector3.UP, atan2(out.x, out.z))
	var centre: Vector3 = stall["use"] - out * ToiletLayout.USE_M
	# Each of two bags on the side of the hand that carries it (bag i in hand i,
	# 0 the right, -x), so they do not cross over as they are picked up.
	var side := 0.0 if count < 2 else (-FLOOR_APART_M if index == 0 else FLOOR_APART_M)
	var at := centre + out * STALL_BAG_M + facing * Vector3(side, 0.0, 0.0)
	return Transform3D(facing * STALL_UPRIGHT, at)


static func _security_home(sim: PassengerSim, p: Passenger, i: int) -> Home:
	var on_lane := not lane_of(sim, p).is_empty()
	var phase := p.security_phase as SecurityRuntime.Phase
	var done := SecurityRuntime.work_for(phase, p) - p.security_work
	var home := Home.HAND
	match phase:
		SecurityRuntime.Phase.REPACK:
			home = Home.FLOOR
		SecurityRuntime.Phase.UNPACK:
			var in_tray := (
				SecurityRuntime.LANE_UNPACK_TICKS + i * SecurityRuntime.LANE_UNPACK_BAG_TICKS
			)
			home = Home.TRAY if done >= in_tray else Home.HAND
		SecurityRuntime.Phase.ARCH:
			home = Home.TRAY if _on_passage(sim, p) else Home.HAND
		SecurityRuntime.Phase.PICKUP:
			var out_of_tray := (
				SecurityRuntime.LANE_PICKUP_TICKS + i * SecurityRuntime.LANE_PICKUP_BAG_TICKS
			)
			home = Home.TRAY if done < out_of_tray else Home.HAND
	if not on_lane and home == Home.TRAY:
		home = Home.HAND
	return home


## Whether a lane passenger in ARCH has reached the passage: always on the
## first pass; on a returner's second pass once it stands on the unpack cell
## (its path runs from the return route's end through the passage), and from
## then on to the end of ARCH. The arch walk's last step, from the arch cell
## onto the pickup cell, is a new path: read by its index alone, the bags left
## the tray with the body between the posts, and the hand reached across them
## for the belt (user ruling "Pick up after the arch", board 0dd2c787 item b).
static func _on_passage(sim: PassengerSim, p: Passenger) -> bool:
	if not p.incident_resolved or p.path_index >= 1:
		return true
	var route: Array = lane_of(sim, p).get("return_route", [])
	return not route.is_empty() and p.at != route.back()


## A queue front of a lane stops at the unpack cell's queue-side edge while
## another admitted passenger of the lane unpacks or is in ARCH near the
## unpack centre. The offset grows as it walks in, so the hold is continuous.
static func _queue_hold(sim: PassengerSim, p: Passenger, lane: Dictionary) -> Vector3:
	var unpack := sim.grid.cell_to_world(lane["unpack"])
	var front := world_dir(lane["front"])
	var rel := sim.world_position(p) - unpack
	var ahead := rel.dot(front)
	if ahead >= QUEUE_EDGE_M or (rel - front * ahead).length() > 0.3:
		return Vector3.ZERO
	if not _crossing_busy(sim, p, unpack):
		return Vector3.ZERO
	return front * (QUEUE_EDGE_M - ahead)


static func _crossing_busy(sim: PassengerSim, p: Passenger, unpack: Vector3) -> bool:
	var record := sim.security.record_of(p.station)
	for id: int in record.get("admitted", []):
		if id == p.id:
			continue
		var other := sim.get_passenger(id)
		match other.security_phase:
			SecurityRuntime.Phase.UNPACK:
				return true
			SecurityRuntime.Phase.ARCH:
				if sim.world_position(other).distance_to(unpack) < CLEAR_M:
					return true
	return false
