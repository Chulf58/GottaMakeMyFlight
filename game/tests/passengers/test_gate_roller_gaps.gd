extends GdUnitTestSuite
## Guests at neighbouring gate chair fronts never lay two rollers in one gap
## between the fronts (ParkSide.gap_hand(), board 1fe04f01): two rollers that
## each clear their own guest's legs (GateRoller.LIE_SIDE_M) overlap there by
## up to 0.178 m. The reference world's first line of three seats in a row is
## filled in every order of arrival with every pair of hand_of() fallbacks;
## each guest chooses (SecurityLooks.hand_of() -> ParkSide.hand()) at its
## chair front, from sim state only. Two-bag guests keep their roller bag's
## hand (SecurityLooks.hand_of()) and lie closer in (GateRoller.TWO_BAG_SIDE_M);
## rows mixing them with one-bag guests are filled the same way, and a row of
## more than 32 fronts is walked to its end.

## Guest kinds in a mixed row: one roller, or two bags with the roller as bag 0
## (it lies on the right) or bag 1 (on the left).
enum Bags { ONE, TWO_RIGHT, TWO_LEFT }

## The roller shell's width across (test_gate_chair_roller_spot's shell box).
const SHELL_WIDTH_M := 0.328
## A chair whose seat lies this far or further across from its front (the seat
## row's middle chair, GateChairs.CHAIR_OFFSET_M 0.36).
const FAR_SLIDE_M := 0.2
## The least side (m) at which every body of a variant clears its roller's
## shell box grown by 1 cm, measured with test_gate_chair_roller_spot's sweep
## (sit_down at the front, seated along the shuffle): [one bag, two bags] x
## [no slide or the side away from it, short slide toward, far slide toward] x
## [male, female] x [right, left].
const LEG_NEED_M := [
	[
		[[0.39, 0.435], [0.41, 0.345]],
		[[0.425, 0.495], [0.45, 0.385]],
		[[0.565, 0.75], [0.615, 0.57]],
	],
	[
		[[0.315, 0.36], [0.335, 0.27]],
		[[0.34, 0.405], [0.36, 0.295]],
		[[0.455, 0.605], [0.47, 0.425]],
	],
]
## The worst two rollers overlap in one gap (m) per kind of shared gap in
## test_mixed_rows_share_only_where_forced(), measured at the ruling that
## accepted it (user-ruled 2026-11-09, "Legs clear, narrow shift
## (Recommended)", board 4da2e8ff): a recorded known limit, forced by a wall or
## a two-bag guest's fixed hand. No avoidable share is accepted.
const KNOWN_OVERLAP_M := {"late": 0.3592, "boxed": 0.1792, "fixed": 0.1404, "walled": 0.1780}
## How far apart neighbouring chair fronts are.
const CELL_M := 1.0
const ORDERS_3 := [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
## How many fronts the long row has (the walk was cut off at 32).
const LONG_FRONTS := 37
## The long row's first front: a free stretch of the reference world's grid.
const LONG_FROM := Vector2i(10, 60)

var _world: PassengerTestWorld
## Three seats whose fronts follow each other along the row, each the next one's
## right-hand neighbour: seat i + 1's front is seat i's front plus `_left`.
var _seats: Array = []
var _left := Vector2i.ZERO
var _guests: Array[Passenger] = []
## Guests by Bags kind, LONG_FRONTS of ONE (the first three are _guests) and
## three of each two-bag kind.
var _pool: Array = [[], [], []]


func before() -> void:
	PassengerTestWorld.tracker = self
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	for a: Dictionary in _world.sim.layout.seats:
		var out: Vector2i = (a["front"] as Vector2i) - (a["cell"] as Vector2i)
		var left := Vector2i(out.y, -out.x)
		var line := [a]
		for n in 2:
			var next := _seat_at((line[-1]["front"] as Vector2i) + left, out)
			if next.is_empty():
				break
			line.append(next)
		if line.size() == 3:
			_seats = line
			_left = left
			break
	var wanted := [LONG_FRONTS, 3, 3]
	while _pool[0].size() < wanted[0] or _pool[1].size() < 3 or _pool[2].size() < 3:
		var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		var first := SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER
		var second := SecurityLooks.bag_kind(p, 1) == SecurityLooks.Kind.ROLLER
		var kinds: Array[int] = []
		if first:
			kinds = [Bags.ONE, Bags.TWO_RIGHT]
		elif second:
			kinds = [Bags.TWO_LEFT]
		for kind in kinds:
			if _pool[kind].size() < wanted[kind]:
				p.carry_on = 1 if kind == Bags.ONE else 2
				p.cleared = true
				p.stage = Passenger.Stage.TO_EXIT
				_pool[kind].append(p)
				break
	for n in 3:
		_guests.append(_pool[Bags.ONE][n])


func after() -> void:
	if _world != null:
		_world.free_all()
	_world = null
	PassengerTestWorld.tracker = null


func _seat_at(front: Vector2i, out: Vector2i) -> Dictionary:
	for s: Dictionary in _world.sim.layout.seats:
		if s["front"] == front and (s["front"] as Vector2i) - (s["cell"] as Vector2i) == out:
			return s
	return {}


## Seats guests `who` (indices into _guests and _seats) in `order`, guest i
## arriving with hand_of()'s own hand `fallbacks[i]`, each choosing at its
## front as it arrives; the others are away. Returns the hand each chose.
func _fill(who: Array, order: Array, fallbacks: Array) -> Dictionary:
	var guests: Array = []
	for i: int in who:
		guests.append(_guests[i])
	var seats: Array = []
	for i: int in who:
		seats.append(_seats[i])
	var picked := {}
	for k in who.size():
		picked[who[k]] = k
	var at: Array = []
	for i: int in order:
		if picked.has(i):
			at.append(picked[i])
	var by_slot := _seat_guests(guests, seats, at, fallbacks)
	var hands := {}
	for k: int in by_slot:
		hands[who[k]] = by_slot[k]
	return hands


## Seats `guests` (each at the seat of the same index in `seats`) in `order`
## (indices), each choosing as it arrives: a one-bag guest ParkSide.hand() with
## fallback `fallbacks[i]` (0 when short), a two-bag one hand_of() its roller.
## Every pool guest not seated is away. Returns the hand each chose.
func _seat_guests(guests: Array, seats: Array, order: Array, fallbacks := []) -> Dictionary:
	_world.sim.remove_meta(ParkSide.STAMPS)
	for kind: Array in _pool:
		for p: Passenger in kind:
			p.stage = Passenger.Stage.TO_EXIT
			p.seat_object = 0
			p.seat_cell = Passenger.NO_CELL
			p.seat_front = Passenger.NO_CELL
			p.seat_piece = {}
	var hands := {}
	for i: int in order:
		var p: Passenger = guests[i]
		var seat: Dictionary = seats[i]
		# As GateCapacity._take_seat() seats a guest: the piece as well, so
		# GateRoller.slide_of() (its roller's side) sees the chair's slide.
		p.stage = Passenger.Stage.TO_GATE
		p.seat_object = int(seat.get("object_id", 0))
		p.seat_cell = seat["cell"]
		p.seat_front = seat["front"]
		p.seat_piece = Relocation.placement(_world.sim.grid, p.seat_object)
		p.at = seat["front"]
		var slide := GateRoller.slide(p.seat_piece, p.seat_cell, p.seat_front)
		assert_float(GateRoller.slide_of(p)).is_equal_approx(slide, 0.0001)
		if seats == _seats:
			assert_float(absf(slide)).is_greater(0.05)
		if p.carry_on > 1:
			var roller := 0 if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER else 1
			hands[i] = SecurityLooks.hand_of(_world.sim, p, roller)
		else:
			hands[i] = ParkSide.hand(_world.sim, p, fallbacks[i] if i < fallbacks.size() else 0)
	return hands


## How many gaps between neighbouring fronts in `hands` hold two rollers: guest
## i lays its left-hand roller into the gap toward i + 1, whose right-hand
## roller lies in the same gap.
static func _shared(hands: Dictionary) -> int:
	var count := 0
	for i: int in hands:
		count += int(hands[i] == 1 and hands.get(i + 1, -1) == 0)
	return count


func test_the_seats_line_up() -> void:
	print(
		(
			"seats %s, left step %s"
			% [_seats.map(func(s: Dictionary) -> Vector2i: return s["front"]), _left]
		)
	)
	assert_int(_seats.size()).is_equal(3)


## GateRoller.slide() of each of the row's seats is its chair's sideways step
## (GateChairs.CHAIR_OFFSET_M turned with the row) measured along the gap
## rule's left (a step of `_left`, the left hand's side of a guest facing out),
## so a positive slide is a shuffle into the left gap. One of the three is the
## row's middle chair (|slide| FAR_SLIDE_M or more). Seated in every order with
## every fallback, its guest lays on the side it does not shuffle toward
## (decision gate-chair-roller-lies-opposite-the-sit-down-shuffle-on-a-ch), and
## no gap holds two rollers.
func test_the_middle_chair_lays_opposite_its_shuffle() -> void:
	var far := -1
	for i in _seats.size():
		var seat: Dictionary = _seats[i]
		var piece := Relocation.placement(_world.sim.grid, seat["object_id"])
		var slide := GateRoller.slide(piece, seat["cell"], seat["front"])
		var def := BuildCatalog.get_def(piece["def"])
		var index := def.footprint(piece["anchor"], piece["facing"]).find(seat["cell"])
		var step := BuildObjectDef.rotate_point(
			Vector2(GateChairs.CHAIR_OFFSET_M[index], 0.0), piece["facing"]
		)
		var along := step.dot(Vector2(_left))
		print("seat %d chair %d slide %+.3f along the left step %+.3f" % [i, index, slide, along])
		assert_float(slide).is_equal_approx(along, 0.0001)
		if absf(slide) >= FAR_SLIDE_M:
			far = i
	assert_int(far).is_greater_equal(0)
	var piece := Relocation.placement(_world.sim.grid, _seats[far]["object_id"])
	var slide := GateRoller.slide(piece, _seats[far]["cell"], _seats[far]["front"])
	var away := 0 if slide > 0.0 else 1
	var wrong := 0
	var shared := 0
	for order: Array in ORDERS_3:
		for fallbacks: Array in [[0, 0, 0], [1, 1, 1], [1, 0, 1], [0, 1, 0]]:
			var hands := _fill([0, 1, 2], order, fallbacks)
			wrong += int(hands[far] != away)
			shared += _shared(hands)
	print(
		(
			"middle chair seat %d: on its shuffle side %d (0), shared gaps %d (0)"
			% [far, wrong, shared]
		)
	)
	assert_int(wrong).is_equal(0)
	assert_int(shared).is_equal(0)


## Two neighbours, either arriving first, any fallbacks: no gap holds two
## rollers. Control: the fallbacks that point into one gap (the left guest's
## left hand, the right one's right) are what ParkSide stamped before
## (hand_of()'s own hand, no wall), and they overlap by the printed amount.
func test_two_neighbours_never_share_a_gap() -> void:
	var shared := 0
	var cases := 0
	for order in [[0, 1], [1, 0]]:
		for f0 in 2:
			for f1 in 2:
				var hands := _fill([0, 1], order, [f0, f1, 0])
				shared += _shared(hands)
				cases += 1
	var fallbacks := {0: 1, 1: 0}
	var male := GateRoller.side(0, 0) + GateRoller.side(0, 1) + SHELL_WIDTH_M - CELL_M
	var old := 0.34 * 2.0 + SHELL_WIDTH_M - CELL_M
	print(
		(
			(
				"two neighbours: %d of %d fills share a gap (0); fallbacks %s share %d (> 0),"
				+ " overlapping %.3f m for two male rollers, %.3f m at main's 0.34 m"
			)
			% [shared, cases, fallbacks, _shared(fallbacks), male, old]
		)
	)
	assert_int(_shared(fallbacks)).is_equal(1)
	assert_float(male).is_greater(0.0)
	assert_int(shared).is_equal(0)


## Three in a row, every order of arrival and every set of fallbacks: no gap
## holds two rollers. Printed as well: the same fills under the rule that keeps
## hand_of()'s own hand when both gaps are free (a model of it here), which
## shares a gap.
func test_three_in_a_row_never_share_a_gap() -> void:
	var shared := 0
	var modelled := 0
	var cases := 0
	for order: Array in ORDERS_3:
		for bits in 8:
			var fallbacks := [bits & 1, (bits >> 1) & 1, (bits >> 2) & 1]
			var hands := _fill([0, 1, 2], order, fallbacks)
			shared += _shared(hands)
			modelled += int(_shared(_keep_fallback(order, fallbacks)) > 0)
			cases += 1
	print(
		(
			(
				"three in a row: %d gaps shared over %d fills (0); keeping the fallback"
				+ " when both gaps are free: %d of %d fills share a gap"
			)
			% [shared, cases, modelled, cases]
		)
	)
	assert_int(cases).is_equal(48)
	assert_int(shared).is_equal(0)
	assert_int(modelled).is_greater(0)


## A wall on the right of the first front: its guest lays the roller on the
## left (the wall rule first) in every order, and the row still shares no gap.
## Control: without the wall the same guest lays it on the right.
func test_the_wall_still_wins() -> void:
	var seat: Dictionary = _seats[0]
	var side := BuildGrid.SIDE_STEP.find(-_left)
	assert_int(side).is_greater_equal(0)
	var free := _fill([0, 1, 2], [0, 1, 2], [0, 0, 0])
	var made := _world.grid.apply(BuildEdit.place_wall(seat["front"], side))
	assert_bool(made.ok).is_true()
	var shared := 0
	var first: Array[int] = []
	for order: Array in ORDERS_3:
		var hands := _fill([0, 1, 2], order, [0, 0, 0])
		shared += _shared(hands)
		first.append(hands[0])
	_world.grid.apply(BuildEdit.remove_wall(seat["front"], side))
	print(
		(
			"walled on the right: first guest's hands %s (1 each), gaps shared %d (0); unwalled %s"
			% [first, shared, free]
		)
	)
	assert_int(free[0]).is_equal(0)
	assert_array(first).contains_same([1, 1, 1, 1, 1, 1])
	assert_int(shared).is_equal(0)


## The rule ParkSide.gap_hand() replaced the fallback with, modelled: keep the
## fallback while both gaps are free, else as gap_hand().
static func _keep_fallback(order: Array, fallbacks: Array) -> Dictionary:
	var hands := {}
	for i: int in order:
		var right_taken: bool = hands.get(i - 1, -1) == 1
		var left_taken: bool = hands.get(i + 1, -1) == 0
		if not right_taken and not left_taken:
			hands[i] = fallbacks[i]
		else:
			hands[i] = 1 if right_taken and not left_taken else 0
	return hands


## How far the rollers of \`a\` (laying left with \`hand_a\`) and \`b\` (one front
## to its left, laying right) reach into each other in the gap between their
## fronts, in metres, from where GateRoller.spot() lays them and the shell's
## half width at each guest's bag scale; > 0 overlaps.
static func _overlap(a: Passenger, b: Passenger) -> float:
	var into := 0.0
	for pair: Array in [[a, 1], [b, 0]]:
		var q: Passenger = pair[0]
		var spot := GateRoller.spot(q, pair[1])
		into += absf(spot.origin.x) + GateRoller.SHELL_HALF_M * SecurityLooks.bag_scale(q)
	return into - CELL_M


## Two two-bag neighbours, both roller bags, both body variants each, either
## arriving first, with no wall and with a wall on either outer side: each
## keeps its bag's hand, so the two face one gap exactly when the right one's
## roller is bag 1 and the left one's bag 0 (24 of 96 fills; no rule can move
## that without changing a hand). Those two rollers fit the gap at
## GateRoller.TWO_BAG_SIDE_M: the least clearance is printed and must be > 0.
## Control: at the one-bag sides (GateRoller.LIE_SIDE_M) two male two-bag
## rollers facing one gap overlap 0.0304 m.
func test_two_bag_neighbours_never_overlap() -> void:
	var sides := [-1, BuildGrid.SIDE_STEP.find(-_left), BuildGrid.SIDE_STEP.find(_left)]
	var walled_at := [-1, 0, 1]
	var shared := 0
	var facing := 0
	var cases := 0
	var worst := -INF
	for w in sides.size():
		if sides[w] >= 0:
			var made := _world.grid.apply(
				BuildEdit.place_wall(_seats[walled_at[w]]["front"], sides[w])
			)
			assert_bool(made.ok).is_true()
		for r0 in 2:
			for r1 in 2:
				var a: Passenger = _pool[Bags.TWO_RIGHT + r0][0]
				var b: Passenger = _pool[Bags.TWO_RIGHT + r1][1]
				for v in 4:
					a.variant = v & 1
					b.variant = v >> 1
					for order in [[0, 1], [1, 0]]:
						var hands := _seat_guests([a, b], [_seats[0], _seats[1]], order)
						cases += 1
						facing += int(r0 == 1 and r1 == 0)
						if _shared(hands) > 0:
							shared += 1
							worst = maxf(worst, _overlap(a, b))
		if sides[w] >= 0:
			_world.grid.apply(BuildEdit.remove_wall(_seats[walled_at[w]]["front"], sides[w]))
	var scale_by := SecurityLooks.TWO_BAG_SCALE
	var old := GateRoller.side(0, 0) + GateRoller.side(0, 1) + SHELL_WIDTH_M * scale_by - CELL_M
	print(
		(
			(
				"two-bag neighbours: %d of %d fills face one gap (%d with bag 1 right of"
				+ " bag 0), their rollers overlap at most %.4f m (< 0: %.3f m clear);"
				+ " at the one-bag sides two male ones overlap %.4f m (> 0)"
			)
			% [shared, cases, facing, worst, -worst, old]
		)
	)
	assert_int(cases).is_equal(96)
	assert_int(shared).is_equal(facing)
	assert_float(worst).is_less(0.0)
	assert_float(old).is_greater(0.0)


## Three in a row, each guest one-bag or two-bag with the roller as either bag,
## either body variant, in every order of arrival, with no wall and with one on
## the right of the first front: no gap holds two rollers that a choice could
## have kept apart. Each gap that does is sorted by why (printed with counts and
## the most two rollers overlap there): "fixed" (two two-bag rollers whose
## hands face it; they fit, < 0), "late" (a two-bag guest took its chair after
## its one-bag neighbour had chosen; its hand is its bag's), "boxed" (a one-bag
## guest arrived with a roller already in or bound for each gap; it takes the
## gap where the two overlap less, ParkSide._less_overlap()), "walled" (a
## one-bag guest's wall rule). Every other is "avoidable", which must be 0. With
## the two-bag guests bound first, none is late, and only boxed or walled
## guests share. Guests are seated with their chair's piece, so each roller
## lies at GateRoller.shuffle_side() for the chair's real slide. No guest's legs
## reach into its own roller in any fill (LEG_NEED_M), and each kind's worst
## overlap stays within KNOWN_OVERLAP_M, the limit the user accepted with the
## legs kept clear (board 4da2e8ff; before it, a late, boxed or walled share
## stayed within 0.029 m while the legs went 0.29 m into the roller).
func test_mixed_rows_share_only_where_forced() -> void:
	var wall_side := BuildGrid.SIDE_STEP.find(-_left)
	var why := {"fixed": 0, "late": 0, "boxed": 0, "walled": 0, "avoidable": 0}
	var most := {"fixed": -INF, "late": -INF, "boxed": -INF, "walled": -INF, "avoidable": -INF}
	var cases := 0
	var first_shared := 0
	# Per kind: how many shared gaps overlap (> 0), and the worst one's fill.
	var overlapping := {}
	var worst := {}
	# Fills where a guest's legs reach into its own roller, and the deepest.
	var legs := 0
	var leg_worst := 0.0
	for walled in [false, true]:
		if walled:
			(
				assert_bool(
					_world.grid.apply(BuildEdit.place_wall(_seats[0]["front"], wall_side)).ok
				)
				. is_true()
			)
		for kinds_at in 27:
			var kinds := [kinds_at % 3, (kinds_at / 3) % 3, kinds_at / 9]
			var guests: Array = []
			for i in 3:
				guests.append(_pool[kinds[i]][i])
			for v in 8:
				for i in 3:
					(guests[i] as Passenger).variant = (v >> i) & 1
				for order: Array in ORDERS_3:
					var hands := _seat_guests(guests, _seats, order)
					cases += 1
					var deepest := 0.0
					for i in 3:
						deepest = maxf(deepest, _leg_depth(guests[i], hands[i]))
					if deepest > 0.0:
						legs += 1
						leg_worst = maxf(leg_worst, deepest)
					var forced := {0: 1} if walled else {}
					var two_first := true
					for i in 3:
						for j in 3:
							if kinds[i] == Bags.ONE and kinds[j] != Bags.ONE:
								two_first = two_first and order.find(j) < order.find(i)
					for i in 2:
						if not (hands[i] == 1 and hands[i + 1] == 0):
							continue
						var kind := _why(i, kinds, order, hands, forced)
						why[kind] += 1
						var into := _overlap(guests[i], guests[i + 1])
						if into > 0.0:
							overlapping[kind] = int(overlapping.get(kind, 0)) + 1
						if into > most[kind]:
							worst[kind] = (
								"seats %d|%d kinds %s order %s variants %d hands %s slides %+.2f %+.2f walled %s"
								% [
									i,
									i + 1,
									kinds,
									order,
									v,
									hands,
									GateRoller.slide_of(guests[i]),
									GateRoller.slide_of(guests[i + 1]),
									walled
								]
							)
						most[kind] = maxf(most[kind], into)
						if two_first and kind not in ["fixed", "boxed", "walled"]:
							first_shared += 1
		if walled:
			_world.grid.apply(BuildEdit.remove_wall(_seats[0]["front"], wall_side))
	var line := "mixed rows: %d fills;" % cases
	for kind: String in why:
		line += " %s %d (most overlap %.4f m)" % [kind, why[kind], most[kind]]
	line += "; legs in their own roller %d fills (0), deepest %.3f m" % [legs, leg_worst]
	print(line + "; two-bag bound first, shared but not fixed, boxed or walled: %d" % first_shared)
	for kind: String in worst:
		print(
			(
				"overlapping %s: %d fills, worst %.4f m: %s"
				% [kind, overlapping.get(kind, 0), most[kind], worst[kind]]
			)
		)
	assert_int(cases).is_equal(2592)
	assert_int(why["avoidable"]).is_equal(0)
	assert_int(first_shared).is_equal(0)
	assert_int(why["fixed"]).is_greater(0)
	# The hard rule: no guest's legs in its own roller, in any fill.
	assert_int(legs).is_equal(0)
	# A user-accepted limit, not a target (user-ruled 2026-11-09, "Legs clear,
	# narrow shift (Recommended)", board 4da2e8ff): with the legs clear, a wall
	# or a two-bag guest's fixed hand can still put two rollers in one gap. The
	# bound per kind is the measured worst at the ruling, so a change that
	# makes any of them worse fails here.
	for kind: String in KNOWN_OVERLAP_M:
		assert_float(most[kind]).is_less_equal(KNOWN_OVERLAP_M[kind] + 0.0001)


## How far the legs of `q` (as seated by _seat_guests()) reach into its own
## roller laid with `hand` (GateRoller.spot()), in metres across; <= 0 is clear.
## LEG_NEED_M is the measured need, the box grown by 1 cm, so 1 cm of it is
## margin and not contact.
static func _leg_depth(q: Passenger, hand: int) -> float:
	var look := PassengerLooks.body_of(q.id, q.variant)
	var slide := GateRoller.slide_of(q)
	var toward := (hand == 1 and slide > 0.0) or (hand == 0 and slide < 0.0)
	var at := 0 if not toward else (1 if absf(slide) < GateRoller.FAR_SLIDE_M else 2)
	var scale_by := SecurityLooks.bag_scale(q)
	var variant := look / PassengerLooks.PER_VARIANT
	var need: float = LEG_NEED_M[0 if scale_by >= 1.0 else 1][at][variant][hand]
	return need - 0.01 - absf(GateRoller.spot(q, hand).origin.x)


## Why the gap between seats \`i\` and \`i + 1\` of a filled mixed row holds both
## rollers (test_mixed_rows_share_only_where_forced()): \`kinds\` per seat (Bags),
## the arrival \`order\`, the \`hands\` chosen, \`forced\` the hand a wall gives a
## seat's front.
static func _why(
	i: int, kinds: Array, order: Array, hands: Dictionary, forced: Dictionary
) -> String:
	if kinds[i] != Bags.ONE and kinds[i + 1] != Bags.ONE:
		return "fixed"
	var later := i if order.find(i) > order.find(i + 1) else i + 1
	if kinds[later] != Bags.ONE:
		return "late"
	if forced.has(later):
		return "walled"
	# Its other gap as it stood when it chose: on its right (later - 1 laying
	# left) when it laid left, else on its left (later + 1 laying right), held
	# or bound before it came, or (on the right) a chair nobody held yet that
	# the walls along the row would send left.
	var when := order.find(later)
	if hands[later] == 1:
		var right := later - 1
		if right >= 0:
			var held: bool = order.find(right) < when and hands[right] == 1
			if held or _will_lay_left(right, kinds, order, when, forced):
				return "boxed"
	else:
		var on_left := later + 1
		if on_left <= 2 and hands[on_left] == 0 and order.find(on_left) < when:
			return "boxed"
	return "avoidable"


## Whether seat \`j\`, not there yet when the guest arriving \`when\`-th chose,
## was bound by the walls along the row to lay left (ParkSide._line_hand()'s
## answer for a chair nobody holds).
static func _will_lay_left(
	j: int, kinds: Array, order: Array, when: int, forced: Dictionary
) -> bool:
	if order.find(j) < when:
		return false
	if forced.has(j):
		return forced[j] == 1
	return j > 0 and _will_lay_left(j - 1, kinds, order, when, forced)


## A row of LONG_FRONTS gate chair fronts (laid into the layout for the test)
## with a wall on the right of the first: the guest at the far end, first to
## arrive and LONG_FRONTS - 1 fronts from the wall, lays its roller on the left
## as the wall sends every roller along the row, and then the rest of the row,
## arriving from the wall end, shares no gap. Control: without the wall the
## same guest lays it on the right. A walk cut off at 32 fronts missed the wall
## and laid the far guest's roller on the right, into its neighbour's gap.
func test_a_long_row_walks_past_32_fronts() -> void:
	var out := Vector2i(0, 1)
	var left := Vector2i(out.y, -out.x)
	var row: Array[Dictionary] = []
	for j in LONG_FRONTS:
		var front := LONG_FROM + left * j
		row.append({"key": "long %d" % j, "object_id": 0, "cell": front - out, "front": front})
	var guests: Array = _pool[Bags.ONE]
	var order := [LONG_FRONTS - 1]
	for j in LONG_FRONTS - 1:
		order.append(j)
	var kept: Array[Dictionary] = _world.sim.layout.seats.duplicate()
	var side := BuildGrid.SIDE_STEP.find(-left)
	# A copy each time: a grid edit rebuilds the layout, clearing its seats.
	_world.sim.layout.seats = row.duplicate()
	var free := _seat_guests(guests, row, order)
	var made := _world.grid.apply(BuildEdit.place_wall(row[0]["front"], side))
	_world.sim.layout.seats = row.duplicate()
	var hands := _seat_guests(guests, row, order)
	_world.grid.apply(BuildEdit.remove_wall(row[0]["front"], side))
	_world.sim.layout.seats = kept
	var far := LONG_FRONTS - 1
	var lefts := 0
	for j: int in hands:
		lefts += int(hands[j] == 1)
	print(
		(
			(
				"long row of %d fronts, wall placed %s: far guest's hand %d (1), %d of %d"
				+ " lay left, gaps shared %d (0); unwalled far hand %d (0), shared %d"
			)
			% [
				LONG_FRONTS,
				made.ok,
				hands[far],
				lefts,
				hands.size(),
				_shared(hands),
				free[far],
				_shared(free)
			]
		)
	)
	assert_bool(made.ok).is_true()
	assert_int(free[far]).is_equal(0)
	assert_int(_shared(free)).is_equal(0)
	assert_int(hands[far]).is_equal(1)
	assert_int(_shared(hands)).is_equal(0)
