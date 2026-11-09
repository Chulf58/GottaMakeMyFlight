class_name ParkSide
extends RefCounted
## The hand a one-roller guest holds its roller in at a seat where it parks
## the roller beside it: the open side when a wall stands on its hand's side
## (user ruling a-guest-pulling-a-roller-through-a-doorway-tucks-it-in-line:
## "A parked or stood roller beside a wall goes on the open side, following
## the hand-swap ruling b05a0fab and the booth precedent (BoothRoller.side)";
## boards a40fdbaf, cfe95aad). SecurityLooks.hand_of() asks it, so the hand,
## the park (RollerPark.park(), on the hand's side), the floor spot and the
## pick-up all take one side. Every seat where RollerPark stamps a faced park
## counts: a gate chair, a cafe table seat, a booth seat, a sofa or nap pod
## seat. It answers from NEAR_CELLS out on the way in, so PullSide has the
## roller in that hand (hand_of() is its "first") before the set-down starts:
## a set-down from the other hand parks on the walled side and lays the roller
## across in front of the feet.
##
## The hand is chosen once per seat and kept (stamp()) until the guest is no
## longer bound for or at that seat: chosen from the walls live on every call,
## a wall built mid-stay, or a route in and out of NEAR_CELLS, changed the hand
## with the roller lying on the floor. The stamp lives on the sim object as
## metadata and is saved (PassengerSimSave "park_side"): chosen again after a
## load, a one-bag guest's gate chair side flipped once a two-bag neighbour had
## come after it chose (board 4da2e8ff).
##
## A side is walled when the park on it (RollerPark.park(), scale 1) reaches
## into a wall (ParkWalls.inside(), PullSide.walls_near()) where the guest
## stands to park it: at a gate chair its front cell; at a cafe table seat or
## a sofa or nap pod seat the approach (slot) cell and the seat root; at a
## booth seat a wall on that edge of the approach cell (BoothRoller.walled()),
## as BoothRoller.side() lays the roller. Walled on both sides or neither, the
## hand is hand_of()'s own (`fallback`) as it chooses, kept like any other,
## and ParkWalls moves the park and the lying roller out of any wall; at a gate
## chair it is the free gap's instead (gap_hand()), so no two neighbours' rollers
## lie in one gap between chair fronts. At a gate chair the one side the lying
## roller fits comes before all of these (GateRoller.clear_hand()).

## A guest this many cells or fewer from where it parks chooses its hand.
const NEAR_CELLS := 3
## The sim metadata holding the stamps: passenger id -> [seat key, hand]. A
## loaded snapshot replaces it with the saved stamps
## (PassengerSimSave.from_snapshot()).
const STAMPS := &"park_side_hands"
const GATE_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.TO_GATE,
	Passenger.Stage.SITTING_DOWN,
	Passenger.Stage.SEATED,
	Passenger.Stage.STANDING_UP,
]
const CAFE_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.CAFE_TO_SEAT,
	Passenger.Stage.CAFE_SITTING_DOWN,
	Passenger.Stage.CAFE_SEATED,
	Passenger.Stage.CAFE_STANDING_UP,
]
const SHOP_STAGES: Array[Passenger.Stage] = [Passenger.Stage.SHOP_WALK, Passenger.Stage.SHOP_BROWSE]
## stand_hand() tries the way out to a queue stand at this many shares of its
## side distance: the step (0.14 m or less) is under the roller's width (0.33 m).
const STAND_SAMPLES := 3
## A gate stander's step from its cell's middle onto its spot shorter than this
## (m) is no step (stand_face()): spots sit 0, 0.2 or 0.4 m off the middle.
const SPOT_STEP_M := 0.05
## The way a gate stander faces with no step onto its spot and none walked to
## its cell (stand_face()): south, yaw 0, as a body drawn new faces.
const GATE_FACE := Vector2(0.0, 1.0)


## The hand (0 right, 1 left) one-bag guest `p` holds its roller in: the open
## side's at a seat with a wall on one side only, as stamped for the seat,
## else `fallback`.
static func hand(sim: PassengerSim, p: Passenger, fallback: int) -> int:
	var stamps: Dictionary = sim.get_meta(STAMPS, {})
	var seat := _seat(sim, p) if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER else {}
	if seat.is_empty():
		if stamps.has(p.id):
			stamps.erase(p.id)
		return fallback
	var stamp: Array = stamps.get(p.id, [])
	if stamp.is_empty() or stamp[0] != seat["key"]:
		if not _near(p, seat["cell"]):
			return fallback
		# At a gate chair the one side the lying roller fits is the hand first
		# (GateRoller.clear_hand()), so a chair walled_tight() lets through never
		# has the roller laid into a wall. Walled on both sides or neither:
		# hand_of()'s own hand now (at a gate chair the gap's, gap_hand()), kept
		# as well, so it cannot change mid-stay either.
		var chosen := GateRoller.clear_hand(sim, p) if seat.has("out") else -1
		if chosen < 0:
			chosen = _open(sim, seat)
		if chosen < 0 and seat.has("out"):
			chosen = gap_hand(sim, p, seat["cell"], seat["out"])
		stamp = [seat["key"], chosen if chosen >= 0 else fallback]
		stamps[p.id] = stamp
		sim.set_meta(STAMPS, stamps)
	return stamp[1]


## The open side's hand at `seat` (_seat()): 0 or 1 when one side only is
## walled, -1 when both or neither.
static func _open(sim: PassengerSim, seat: Dictionary) -> int:
	var walled := [false, false]
	if seat.has("booth"):
		var front: Transform3D = seat["booth"]
		walled = [BoothRoller.walled(sim, front, -1.0), BoothRoller.walled(sim, front, 1.0)]
	else:
		for at: Transform3D in seat["spots"]:
			var walls := PullSide.walls_near(sim.grid, at.origin)
			for h in 2:
				if ParkWalls.inside(RollerPark.park(at, h, 1.0), walls):
					walled[h] = true
	if walled[0] == walled[1]:
		return -1
	return 1 if walled[0] else 0


## The hand a gate chair guest `p` with one roller lays it down with, at the
## chair front `front` facing grid way `out` with no wall on either side
## (board 1fe04f01): in the gap on its right (hand 0) between its front and the
## next front along the row, unless a roller lies or will lie in that gap from
## the next front (_line_hand()), then on its left; with its left gap taken
## too by a roller already there (_held_hand()), into the gap where the two
## rollers reach less far into each other (_less_overlap()). Two rollers
## that each clear their own guest's legs (GateRoller.LIE_SIDE_M) do not fit in
## one gap: the male sides and the roller's width make 1.18 m, and fronts are
## 1 m apart. The same right-hand gap for everyone fills a row's gaps one guest
## each in any order of arrival, and a wall that sends a roller to the left
## sends every roller to its left along the row with it. hand_of()'s own hand
## (the hand it pulled with, which turns on the way it walked in) put two
## guests coming from either end into the gap between them, and a third
## between them had both gaps taken (test_gate_roller_gaps). A two-bag
## guest's roller keeps its bag's hand (SecurityLooks.hand_of()), so a
## one-bag neighbour steers round it here, and it lies closer in
## (GateRoller.TWO_BAG_SIDE_M): two two-bag rollers whose hands face one gap
## fit in it. The seat row's middle chair lies 0.36 m to its guest's left
## (GateRoller.slide()), so the right gap this rule gives first is the side
## the guest does not shuffle toward to sit down (decision
## gate-chair-roller-lies-opposite-the-sit-down-shuffle-on-a-ch); with that gap
## taken the rule lays it left as for any chair, and GateRoller.shuffle_side()
## lays it out past the feet shuffling toward it. Only sim state: the seats,
## the walls, the stamps and who holds which chair.
static func gap_hand(sim: PassengerSim, p: Passenger, front: Vector2i, out: Vector2i) -> int:
	var left := Vector2i(out.y, -out.x)
	# The front on the right lays into this guest's right gap with its left
	# hand, the one on the left into the left gap with its right.
	var right_taken := _line_hand(sim, p, front - left, out) == 1
	var left_taken := _held_hand(sim, p, front + left, out) == 0
	if right_taken and left_taken:
		return _less_overlap(sim, p, front, out)
	return 1 if right_taken else 0


## GateRoller.slide() of the gate chair whose front is `front`, facing `out`,
## as the grid places its row; 0 where no chair has that front.
static func _slide_at(sim: PassengerSim, front: Vector2i, out: Vector2i) -> float:
	for seat: Dictionary in sim.layout.seats:
		if (
			seat["front"] == front
			and (seat["front"] as Vector2i) - (seat["cell"] as Vector2i) == out
		):
			var piece := Relocation.placement(sim.grid, seat["object_id"])
			return GateRoller.slide(piece, seat["cell"], front)
	return 0.0


## The hand of one-bag guest `p` at the chair front `front` (facing `out`)
## whose gaps both hold or will hold a neighbour's roller: the gap where its
## roller and the neighbour's reach the less far (GateRoller.reach()), the
## right on a tie. A neighbour not there yet reaches as far as the widest
## one-bag roller (GateRoller.LIE_SIDE_M at full size).
static func _less_overlap(sim: PassengerSim, p: Passenger, front: Vector2i, out: Vector2i) -> int:
	var left := Vector2i(out.y, -out.x)
	var look := PassengerLooks.body_of(p.id, p.variant)
	var slide := _slide_at(sim, front, out)
	var right := GateRoller.reach(look, 0, 1.0, slide) + _reach(sim, p, front - left, out, 1)
	var on_left := GateRoller.reach(look, 1, 1.0, slide) + _reach(sim, p, front + left, out, 0)
	return 1 if on_left < right else 0


## How far into the gap on its `hand` side the roller at the gate chair front
## `front` (facing `out`) reaches: its holder's (_holder()), else the widest
## one-bag roller's.
static func _reach(
	sim: PassengerSim, me: Passenger, front: Vector2i, out: Vector2i, hand: int
) -> float:
	var held := _holder(sim, me, front, out)
	if not held.is_empty():
		var q: Passenger = held[0]
		var look := PassengerLooks.body_of(q.id, q.variant)
		return GateRoller.reach(look, hand, SecurityLooks.bag_scale(q), GateRoller.slide_of(q))
	var slide := _slide_at(sim, front, out)
	var widest := 0.0
	for variant in GateRoller.LIE_SIDE_M.size():
		var look := variant * PassengerLooks.PER_VARIANT
		widest = maxf(widest, GateRoller.reach(look, hand, 1.0, slide))
	return widest


## The hand a roller at the gate chair whose front is `front`, facing `out`,
## lies or will lie on, from the row to its right: a guest's there
## (_held_hand()); else the open side's when one side is walled (_open());
## else the left when the front on its right lays into its gap (the same, along
## the row), else the right; -1 where no chair has that front. A chair nobody
## holds yet answers for whoever comes. The row is walked front by front to its
## end, however long (the grid has up to BuildGrid.MAX_SIDE_CELLS a side): a
## walk cut off at 32 fronts missed a wall past them and laid two rollers in
## one gap.
static func _line_hand(sim: PassengerSim, me: Passenger, front: Vector2i, out: Vector2i) -> int:
	var fronts := {}
	for seat: Dictionary in sim.layout.seats:
		if (seat["front"] as Vector2i) - (seat["cell"] as Vector2i) == out:
			fronts[seat["front"]] = true
	var left := Vector2i(out.y, -out.x)
	var at := front
	# Each step is one front further right on a straight line, so the walk
	# visits no front twice and ends within the count of fronts.
	for n in fronts.size():
		if not fronts.has(at):
			return -1 if n == 0 else 0
		var held := _held_hand(sim, me, at, out)
		if held >= 0:
			return held
		var walled := _open(sim, {"spots": [_frame(sim, at, out)]})
		if walled >= 0:
			return walled
		at -= left
	return -1 if fronts.is_empty() else 0


## The hand the roller of the guest (not `me`) bound for or at the gate chair
## whose front is `front`, facing `out`, lies or will lie on, as chosen
## (_holder()); -1 for none or none chosen yet.
static func _held_hand(sim: PassengerSim, me: Passenger, front: Vector2i, out: Vector2i) -> int:
	var held := _holder(sim, me, front, out)
	return -1 if held.is_empty() else int(held[1])


## [the guest (not `me`) bound for or at the gate chair whose front is `front`,
## facing `out`, with a roller, the hand that roller lies or will lie on]: a
## two-bag guest's roller's own hand (SecurityLooks.hand_of()), a one-bag
## guest's stamp for that chair; empty for none or none chosen yet.
static func _holder(sim: PassengerSim, me: Passenger, front: Vector2i, out: Vector2i) -> Array:
	for q in sim._passengers:
		if q == me or q.is_done() or q.stage not in GATE_STAGES or q.seat_front != front:
			continue
		if q.seat_cell == Passenger.NO_CELL or q.seat_front - q.seat_cell != out:
			continue
		var roller := -1
		for i in mini(q.carry_on, 2):
			if roller < 0 and SecurityLooks.bag_kind(q, i) == SecurityLooks.Kind.ROLLER:
				roller = i
		if roller < 0:
			continue
		if q.carry_on > 1:
			return [q, roller]
		var stamp: Array = (sim.get_meta(STAMPS, {}) as Dictionary).get(q.id, [])
		if not stamp.is_empty() and stamp[0] == "gate %s" % q.seat_cell:
			return [q, stamp[1]]
	return []


## The seat `p` is bound for or at with its roller: {"key": the seat's
## identity, "cell": where it parks, and "spots": the frames it parks from
## (facing out of the seat), or "booth": the approach frame}; empty when none.
static func _seat(sim: PassengerSim, p: Passenger) -> Dictionary:
	if p.stage in GATE_STAGES and p.seat_cell != Passenger.NO_CELL:
		if p.seat_front == Passenger.NO_CELL:
			return {}
		var out := p.seat_front - p.seat_cell
		var front := _frame(sim, p.seat_front, out)
		return {"key": "gate %s" % p.seat_cell, "cell": p.seat_front, "spots": [front], "out": out}
	if p.stage in CAFE_STAGES:
		var visit := sim.cafes.visit_of(p.id)
		if visit == null or visit.seat.is_empty():
			return {}
		var cell: Vector2i = visit.seat["approach"]
		var approach := _frame(sim, cell, visit.seat["facing"])
		var key := "cafe %s %s" % [visit.seat["cell"], cell]
		if sim.cafes.booth_roller(p):
			return {"key": key, "cell": cell, "booth": approach}
		var root := BuildObjectDef.seat_root_world(sim.grid, visit.seat)
		return {"key": key, "cell": cell, "spots": [approach, Transform3D(approach.basis, root)]}
	if p.stage not in SHOP_STAGES:
		return {}
	var shop := sim.shops.visit_of(p.id)
	if shop == null or shop.slot.is_empty():
		return {}
	var record := shop.piece if not shop.piece.is_empty() else sim.grid.get_object(shop.display)
	var kind: int = ActivityPoses.KINDS.get(record.get("def", &""), ActivityPoses.Kind.NONE)
	if kind != ActivityPoses.Kind.SEAT and kind != ActivityPoses.Kind.RECLINE:
		return {}
	var slot: Vector2i = shop.slot["approach"]
	var out := TerminalLayout.front_of(record["facing"])
	var at := _frame(sim, slot, out)
	var root := ActivityPoses.spot_of(sim.grid, record, shop.index)
	return {
		"key": "shop %d %d" % [shop.display, shop.index],
		"cell": slot,
		"spots": [at, Transform3D(at.basis, root)],
	}


## Whether `p` is NEAR_CELLS or fewer from `cell` (either way on the grid).
static func _near(p: Passenger, cell: Vector2i) -> bool:
	var d := (p.at - cell).abs()
	return maxi(d.x, d.y) <= NEAR_CELLS


## The frame (world, on the floor) at `cell` facing grid way `out`.
static func _frame(sim: PassengerSim, cell: Vector2i, out: Vector2i) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, atan2(out.x, out.y)), sim.grid.cell_to_world(cell))


## The hand (0 right, 1 left) a roller pulled in `hand` is stood up with in a
## queue (RollerPark.queue_stand(); decision a-roller-stood-in-a-queue-beside-
## a-wall-goes-on-the-passenge): the other hand when the way out to the stand
## on `hand`'s side (RollerPark.queue_park() in `frame`, at `scale_by`, body
## look `look`) meets one of `boxes` (walls and furniture, PullSide's boxes)
## and the way to the other side's does not; else `hand`. The way is the stand
## at STAND_SAMPLES shares of its side distance, each step less than the
## roller's width, so a wall the stand would stand wholly past (a body 0.1 m
## from a wall's face, the stand's near edge 0.27 m out) counts as well as one
## it stands in. Walled on both sides or neither, the usual side stands, and
## RollerPark.plan() moves the stand out of the walls it stands in (ParkWalls).
static func stand_hand(
	frame: Transform3D, hand: int, scale_by: float, look: int, boxes: Array
) -> int:
	var walled := [false, false]
	var side := RollerPark.queue_side(look)
	for h in 2:
		for n in range(1, STAND_SAMPLES + 1):
			var out := side * n / float(STAND_SAMPLES)
			var at := RollerPark.park(frame, h, scale_by, RollerPark.PARK_AHEAD_M, out)
			walled[h] = walled[h] or ParkWalls.inside(at, boxes)
	return 1 - hand if walled[hand] and not walled[1 - hand] else hand


## Chooses the side of the queue stand asked for on roller `bag` of guest `p`
## (RollerPark.restamps()) on the sim tick it is asked, in CarryOnProps.sync(),
## and the frame it is drawn in: the frame (stand_frame()) of where `sim` has
## `p` stand (stand_at()) facing its way there (stand_face()), kept on `bag`
## ("queue_frame", [its "still_from", the frame]) for RollerPark.plan() to
## place the stand in, and RollerPark.side_first() with the open side's hand
## (stand_hand()) of the walls and furniture round it in that frame. Only sim
## state decides both, never the drawn body, so one state stands one side
## whatever way the view draws the body, and a body turning in the stand does
## not take the roller round or across with it (anti-pattern view-state-
## stepped-on-from-the-previous-draw-makes-a-carry-p; a body drawn the other
## way stood the roller chosen for its left in the wall on its right). Chosen
## once a still spell: asked again once its change of hand is made, the side
## and the frame are kept. A two-bag guest keeps a bag in each hand
## (SecurityLooks.hand_of(), PullSide), so its stand keeps its side, in the
## frame kept as well, and RollerPark.plan() moves it out of the walls
## (ParkWalls). With no way to face known the stand is drawn in the body's
## frame as before (no "queue_frame").
static func choose_stand(sim: PassengerSim, p: Passenger, bag: Dictionary) -> void:
	if not RollerPark.restamps(bag):
		return
	var spell := float(bag.get("still_from", NAN))
	var kept: Array = bag.get("queue_frame", [])
	if not kept.is_empty() and float(kept[0]) == spell:
		return
	var face := stand_face(sim, p)
	if face == Vector2.ZERO:
		bag.erase("queue_frame")
		return
	var frame := stand_frame(stand_at(sim, p), face)
	bag["queue_frame"] = [spell, frame]
	if p.carry_on > 1:
		return
	var boxes := PullSide.walls_near(sim.grid, frame.origin)
	boxes.append_array(PullSide.pieces_near(sim.grid, frame.origin))
	var look := PassengerLooks.body_of(p.id, p.variant)
	var hand := CarryLead.hand_of(bag["place"])
	hand = stand_hand(frame, hand, SecurityLooks.bag_scale(p), look, boxes)
	RollerPark.side_first(bag, hand)


## Where (world) `sim` has `p` stand while it waits still in a queue: its sim
## position and the offset it is drawn at by a held security queue front
## (SecurityLooks.target_offset(), which the drawn body walks to), the point
## PassengerViews draws a queuer at once it has stood still.
static func stand_at(sim: PassengerSim, p: Passenger) -> Vector3:
	return sim.world_position(p) + SecurityLooks.target_offset(sim, p)


## The ground way (x, z) `p` of `sim` waits facing in a queue, from sim state
## only (choose_stand()): what its body turns to there (PassengerViews), its
## security lane's front or its cafe counter; at the gate (on its standing
## spot, standing or setting off with no path yet) the way it stepped over
## from the middle of the spot's cell onto the spot (PassengerSim.world_position()
## over SHUFFLE_TICKS: the drawn body turns to that step), or with no step (a
## spot on its cell's middle) the way it walked onto that cell (Passenger.
## stand_from, kept by GateCapacity.to_spot(), which clears the path), as the
## body keeps facing; else the step of its path it walks next or walked last (a
## boarding file's way on, the way it came to its place); else at the gate
## GATE_FACE (it walked none); else ZERO. Every part is saved sim state, so a
## load faces the same way.
static func stand_face(sim: PassengerSim, p: Passenger) -> Vector2:
	var face := SecurityLooks.face(sim, p)
	if face == Vector2.ZERO:
		face = Vector2(sim.cafes.counter_facing(p))
	var spot := sim.standing.spot_of(p.id)
	var on_spot := (
		spot != StandingSpots.NO_SPOT
		and (p.stage == Passenger.Stage.STANDING or RollerPark.setting_off(sim, p))
	)
	if face == Vector2.ZERO and on_spot:
		var over := sim.standing.world_of(sim.grid, spot) - sim.grid.cell_to_world(p.at)
		if Vector2(over.x, over.z).length() > SPOT_STEP_M:
			face = Vector2(over.x, over.z)
	if face == Vector2.ZERO and on_spot and p.stand_from != Passenger.NO_CELL:
		face = Vector2(p.at - p.stand_from)
	if face == Vector2.ZERO and p.path.size() >= 2:
		var at := clampi(p.path_index, 0, p.path.size() - 2)
		face = Vector2(p.path[at + 1] - p.path[at])
	if face == Vector2.ZERO and on_spot:
		face = GATE_FACE
	return face


## The frame (world, on the floor) a queue stand is chosen and drawn in
## (stand_hand(), RollerPark.plan()): at `at`, facing ground way `face`.
static func stand_frame(at: Vector3, face: Vector2) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, atan2(face.x, face.y)), at)
