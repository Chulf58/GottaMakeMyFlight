class_name CarryPlace
extends RefCounted
## Puts the bags of one drawn passenger in place and stamps their moves
## (CarryOnProps.draw() calls place_bags()): a bag's transform for its home,
## its move's start and progress, and whether the move is hand-led. Split out of
## carry_on_props.gd (board 79212dcd).

## A bag in a tray rests on the tray's floor, this far above its mount.
const TRAY_FLOOR_M := 0.012
## A roller going to the pull (not hand-led, reach_blend) has its rods in for
## this much of the move; they then come out to the hand.
const ROLLER_LAND := 0.85
## A shoulder bag going to the shoulder is in place by this much of the move,
## when its strap starts to stretch (reach_blend).
const STRAP_PLACED := 0.85
## A roller lying on the floor whose way out of the walls a wall edit changed
## slides to its new spot this far (m) in a tick (_off_walls()), a fifth of a
## walk's step in a tick (0.098 m), instead of moving there in one frame: a
## wall built on the edge of a gate chair's front cell moved it 0.079 m in a
## tick (board 4cb91d64).
const SLIDE_M_PER_TICK := 0.02


## Puts the bags of one passenger in place: those going to a hand, and those
## in a hand-led move (CarryLead), which follow the hand, from the pose
## (_on_pose(), _unposed()); all but the settled ones going to a hand in
## draw(), which works out each moving bag's plan (its hand's targets) before
## the arms are posed. Every bag's new move is stamped, whichever are placed.
static func place_bags(
	props: CarryOnProps,
	held: Dictionary,
	body: Node3D,
	tray_xf: Transform3D,
	now: float,
	placing: CarryOnProps.Placing
) -> void:
	var bags: Array = held["bags"]
	var homes: Array = held["homes"]
	for i in bags.size():
		var bag: Dictionary = bags[i]
		var node: Node3D = bag["node"]
		var kind: SecurityLooks.Kind = bag["kind"]
		var hand_home: bool = homes[i] == SecurityLooks.Home.HAND
		var stamp: bool = bag["home"] != bag["place"] or RollerPark.restamps(bag)
		if (
			not stamp
			and not leading(bag, now)
			and (placing == CarryOnProps.Placing.HAND) != hand_home
		):
			continue
		# A bag going to a hand is only stamped here (draw()), so its place
		# (and a roller's follower) is worked out once, when it is placed; one
		# in a hand-led move is placed here too, for its hand's targets.
		var stamp_only: bool = placing == CarryOnProps.Placing.NOT_HAND and hand_home
		var want_reach := [CarryOnProps.REACH_BUILT_M]
		var want := node.global_transform
		if not stamp_only or leading(bag, now):
			want = bag_transform(props, held, body, tray_xf, i, homes[i], want_reach)
		# A change of hand moves the bag across like a change of home.
		if stamp:
			_stamp(props, held, bag, body, want, i)
			if stamp_only and not leading(bag, now):
				continue
			if stamp_only:
				want = bag_transform(props, held, body, tray_xf, i, homes[i], want_reach)
		bag["placed"] = int(bag.get("placed", 0)) + 1
		var k := progress_of(bag, now)
		# The body this placement goes with, for the next move's start.
		bag["body_at"] = body.global_transform
		bag["settled"] = k >= 1.0
		bag["placed_k"] = k
		bag["carry_placed"] = bag["carry"]
		var to_hand: bool = homes[i] == SecurityLooks.Home.HAND
		var reach: float = want_reach[0]
		if k < 1.0:
			var to_pull: bool = to_hand and bag["carry"] == SecurityLooks.Carry.PULL
			var blend := reach_blend(
				kind, k, to_pull if kind == SecurityLooks.Kind.ROLLER else to_hand
			)
			# Hand-led: a strap or rods as they were while the bag waits at its
			# start, as they end up once it is at its end.
			if leading(bag, now):
				blend = CarryLead.carry_t(k, bag)
			reach = lerpf(bag["reach_from"], reach, blend)
			if RollerPark.queued(bag):
				# Stood in a queue the bar is at a set height (RollerPark.queue_reach()).
				var bar_in := (
					CarryHand.bar_z(props, node, CarryOnProps.REACH_BUILT_M)
					- CarryOnProps.REACH_BUILT_M
				)
				reach = RollerPark.queue_reach(bag, k, want_reach[0], bar_in, held["scale"])
		props._set_reach(node, kind, reach)
		# A shoulder bag is in place by STRAP_PLACED of its move, so its strap
		# stretches (reach_blend) from a bag already on the shoulder, not
		# through the strap hand raised at the chest.
		if to_hand and kind == SecurityLooks.Kind.SHOULDER and not leading(bag, now):
			k = minf(k / STRAP_PLACED, 1.0)
		var holder := -1
		if k >= 1.0:
			node.global_transform = want
			if to_hand and bag["carry"] in [SecurityLooks.Carry.HAND, SecurityLooks.Carry.PULL]:
				holder = held["hands"][i]
		elif bag.get("swap", false):
			var swapped := CarryHand.swap_transform(props, held, body, i, k)
			props._set_reach(node, kind, swapped[1])
			node.global_transform = swapped[0]
			holder = held["hands"][i]
		else:
			var frame := body.global_transform
			var start_now: Transform3D = bag.get("from_world", frame * (bag["from"] as Transform3D))
			if leading(bag, now) and CarryLead.start_of(bag)[0] == CarryLead.End.WORN:
				# A worn bag waits on the body as posed now (one sitting down moves it).
				start_now = carry_transform(
					props, held, body, i, [CarryOnProps.REACH_BUILT_M], bag["carry_from"]
				)
			var hand: int = held["hands"][i]
			var in_stall: bool = held.get("in_stall", false)
			if leading(bag, now) and CarryLead.is_pull_swap(bag, in_stall):
				start_now = CarryLead.pull_swap_start(bag, frame, now)
			var flags := {
				"in_stall": in_stall,
				"hand_carry": bag["carry"] == SecurityLooks.Carry.HAND,
				"from_floor": int(bag.get("was", -1)) / 4 == SecurityLooks.Home.FLOOR,
				"to_floor": homes[i] == SecurityLooks.Home.FLOOR,
				"hand": SecurityLooks.worn_side(i) if kind == SecurityLooks.Kind.SHOULDER else hand,
				"clear": StallCarry.STALL_CLEAR_M if in_stall else CarryOnProps.TRANSFER_CLEAR_M,
				"yaw": body.rotation.y,
			}
			if not leading(bag, now):
				node.global_transform = CarryLead.path(
					start_now, want, k, frame, bag["from"], flags
				)
			else:
				# A roller's queue stand parks by the body's variant; PassengerViews sets it.
				assert(kind != SecurityLooks.Kind.ROLLER or body.has_meta(&"body"), "no body index")
				var drawn := {
					"hand": hand,
					"grips": [props.grip_of(body, 0), props.grip_of(body, 1)],
					"shoulders_y": [props._shoulder_of(body, 0).y, props._shoulder_of(body, 1).y],
					"bar_z":
					(
						CarryHand.bar_z(props, node, props._reach_of(node, kind))
						if kind == SecurityLooks.Kind.ROLLER
						else 0.0
					),
					"scale": held["scale"],
					"look":
					int(body.get_meta(&"body")) if kind == SecurityLooks.Kind.ROLLER else -1,
					"strap_top":
					(
						CarryOnProps._in_piece(props._part(node, "Strap_Top"), node).origin
						if kind == SecurityLooks.Kind.SHOULDER
						else Vector3.ZERO
					),
				}
				var plan := CarryLead.plan(bag, k, start_now, want, frame, flags, drawn)
				bag["lead"] = plan
				holder = plan["holder"]
				var placed: Transform3D = plan["xf"]
				if holder >= 0:
					var at: Vector3 = placed.basis * (plan["anchor"] as Vector3)
					placed = Transform3D(placed.basis, props.grip_of(body, holder) - at)
				node.global_transform = placed
		bag["held_by"] = holder
		if holder >= 0:
			bag["held_at"] = node.global_transform.affine_inverse() * props.grip_of(body, holder)


## A new move of `bag` (bag `i`) to `want`: it starts where the bag is, held in
## the passenger's frame (so a bag picked up while walking stays ahead of the
## legs), or fixed in the world when it starts on the floor or in a tray (the
## hand reaches it there, CarryLead). Its clock is the tick sync() saw the
## change on, not the frame it is drawn in; a new bag's move is over at once,
## so its start is never drawn.
static func _stamp(
	props: CarryOnProps, held: Dictionary, bag: Dictionary, body: Node3D, want: Transform3D, i: int
) -> void:
	var node: Node3D = bag["node"]
	var kind: SecurityLooks.Kind = bag["kind"]
	var start := want if bag["home"] == -1 else node.global_transform
	bag["from"] = start_frame(bag, body).affine_inverse() * start
	# A hand-led move whose hand was still reaching for the bag has not left
	# its start: the new move starts there, as that one did (its "was",
	# "carry_from" and "from_holder" kept), not in the hand it was going to,
	# and on that move's clock, so the reach is not started again (a bag
	# stamped again every few ticks would wait at its start for ever).
	var unmoved := CarryLead.at_start(bag, bag.get("placed_k", 1.0))
	if not unmoved:
		# The carry it was drawn with last, not one sync() saw in between (a
		# frame can run several ticks).
		bag["carry_from"] = bag.get(
			"carry_placed", bag.get("carry_was", SecurityLooks.KIND_CARRY[kind])
		)
		# Where the hand held it at the start, in its own frame, and the hand
		# still holding it when its last move had not ended (CarryLead.start_of).
		bag["anchor_from"] = bag.get("held_at", CarryOnProps.grip_anchor(kind))
		bag["from_holder"] = -1 if bag.get("settled", true) else int(bag.get("held_by", -1))
		bag["was"] = bag["home"]
	var at: int = bag["was"]
	bag.erase("from_world")
	bag.erase("lead")
	var homes: Array = held["homes"]
	if held.get("in_stall", false) and homes[i] == SecurityLooks.Home.FLOOR:
		# Set down in a toilet stall, a bag starts fixed in the stall: the body
		# shuffles back to the seat as it sits and would drag a start held in
		# its frame through its knees. One from the hand starts upright over its
		# place by the door (StallCarry.set_down_start).
		bag["from_world"] = body.global_transform * bag["from"]
		if bag["carry"] == SecurityLooks.Carry.HAND:
			var box := CarryOnProps.bag_box(kind)
			bag["from_world"] = StallCarry.set_down_start(want, box, StallCarry.lowest(start, box))
	elif at >= 0 and (at / 4 == SecurityLooks.Home.TRAY or ActivityCarry.fixed_start(held, at)):
		# A bag in a tray or at an activity's fixed spot waits there for the
		# hand; one on the floor keeps its place by the walker, so a walker never
		# steps into it.
		bag["from_world"] = start
	if not unmoved:
		bag["since"] = bag["changed"] - (CarryOnProps.TRANSFER_TICKS if bag["home"] == -1 else 0.0)
	# Hand-led or not is decided now and kept to the end of the move (and so is
	# its reach and length, CarryLead.stamp_move).
	bag["led"] = leads(held, bag)
	var in_stall: bool = held.get("in_stall", false)
	CarryLead.stamp_move(
		bag, in_stall, homes[i], body.global_transform, held.get("sit_face", NAN), unmoved
	)
	BoothRoller.fix_start(bag, held.get("booth", false), props.sim, body.global_transform)
	# A queue stand keeps the walls round where it is drawn (RollerPark.queue_frame_of())
	# for its ParkWalls backstop (RollerPark.plan()), as a seat's park does.
	if RollerPark.queued(bag) and props.sim != null:
		var stood := RollerPark.queue_frame_of(bag, body.global_transform).origin
		bag["queue_walls"] = PullSide.walls_near(props.sim.grid, stood)
	bag["home"] = bag["place"]
	bag["reach_from"] = props._reach_of(node, kind)


## Whether a move of `bag` stamped now is hand-led (CarryLead): every move but
## a roller's between the hand and the pull by its bar (CarryHand.swap_transform, held
## by the bar throughout), in a toilet stall too (board item c7b0e7be). Kept in
## the bag's "led" to the move's end, so a move never changes mode.
static func leads(_held: Dictionary, bag: Dictionary) -> bool:
	return not bag.get("swap", false)


## Whether `bag` is in a hand-led move now (leads(), as stamped): moving.
static func leading(bag: Dictionary, now: float) -> bool:
	return bag.has("since") and progress_of(bag, now) < 1.0 and bag.get("led", false)


## The body frame a new move of `bag` starts in: the body as it was when the
## bag was last placed, for a bag settled on the body (in the hand, on the
## back or the shoulder), so a body that turned since (as one sitting down
## in a toilet stall turns round on the spot) takes the bag round with it as
## the hand does; the body now for anything else (a bag on the floor or in a
## tray, a pulled roller on its wheels, one already moving).
static func start_frame(bag: Dictionary, body: Node3D) -> Transform3D:
	var held_by_body: bool = (
		int(bag["home"]) >= 0
		and int(bag["home"]) / 4 == SecurityLooks.Home.HAND
		and bag.get("settled", false)
		and bag.get("carry_placed", SecurityLooks.Carry.PULL) != SecurityLooks.Carry.PULL
		and bag.has("body_at")
	)
	return bag["body_at"] if held_by_body else body.global_transform


## How far a strap or rod has gone from its old length to its new one at `k`
## of a move: a shoulder strap stretches in the last 15% of the move, as the
## bag comes in from outside the hip with the hand already up (CarryArmPose.pose_arms), and
## goes slack early; a roller's rods come out only once it is down behind the
## body and go in before it rises.
static func reach_blend(kind: SecurityLooks.Kind, k: float, to_hand: bool) -> float:
	if kind == SecurityLooks.Kind.ROLLER:
		# The rods stay in until the roller is down behind (ROLLER_LAND) and go
		# in before it rises.
		if to_hand:
			return clampf((k - ROLLER_LAND) / (1.0 - ROLLER_LAND), 0.0, 1.0)
		return clampf(k * 3.0, 0.0, 1.0)
	if kind != SecurityLooks.Kind.SHOULDER:
		return k
	if to_hand:
		return clampf((k - STRAP_PLACED) / (1.0 - STRAP_PLACED), 0.0, 1.0)
	return clampf(k / 0.4, 0.0, 1.0)


## How far `bag` is through its move at sim time `now` (1 when settled or
## not started).
static func progress_of(bag: Dictionary, now: float) -> float:
	if not bag.has("since"):
		return 1.0
	return clampf((now - bag["since"]) / CarryLead.ticks_of(bag), 0.0, 1.0)


static func tray_transform(props: CarryOnProps, held: Dictionary, body: Node3D) -> Transform3D:
	return CarryTray.placed(props.sim.grid, held["lane"], held["tray_at"], body.global_position)


## Bag `i`'s transform for its home now; `reach` gets its strap or rod length.
static func bag_transform(
	props: CarryOnProps,
	held: Dictionary,
	body: Node3D,
	tray_xf: Transform3D,
	i: int,
	home: int,
	reach: Array
) -> Transform3D:
	var scale_by: float = held["scale"]
	var kind: SecurityLooks.Kind = held["bags"][i]["kind"]
	var yaw := Basis(Vector3.UP, body.rotation.y)
	var count: int = held["bags"].size()
	match home:
		SecurityLooks.Home.TRAY:
			var at := SecurityLooks.in_tray(i, count, CarryOnProps.bag_size(kind).z)
			# Centred by its bounds: a grab loop or a grip bar makes a kind
			# longer at one end.
			at.z -= CarryOnProps.bag_box(kind).get_center().z * scale_by
			at.y += TRAY_FLOOR_M
			return Transform3D(tray_xf.basis.scaled(Vector3.ONE * scale_by), tray_xf * at)
		SecurityLooks.Home.FLOOR:
			var fixed := ActivityCarry.fixed_place(
				held, CarryOnProps.bag_box(kind), scale_by, i, count
			)
			if not fixed.is_empty():
				return _off_walls(props, held, i, kind, fixed[0])
			# From where the sim draws the body, not where it stands while it
			# sets its roller down (SitHold.offset()), so the bag stays put.
			var id: int = props._body_ids.get(body, -1)
			var at := Transform3D(yaw, body.global_position - props.views.sit_offset(id))
			if held["floor_at"][i] != null:
				at = held["floor_at"][i]
			elif kind != SecurityLooks.Kind.ROLLER and count >= 2:
				# A two-bag guest's bag at a gate chair lies fixed at the chair
				# front (SecurityLooks.gate_two_front()), not in the drawn body's
				# frame, which moves off the tick's sit offset while the body
				# eases into the seat (board fc38d1b2).
				var p: Passenger = props.sim.get_passenger(id) if id >= 0 else null
				var gate: Variant = (
					SecurityLooks.gate_two_front(props.sim, p) if p != null else null
				)
				if gate != null:
					at = gate
			var laid_in := RollerPark.lay_frame(held["bags"][i], at)
			var placed: Transform3D = laid_in * held["floor"][i]
			placed.origin.y = props.sim.grid.origin.y
			var scaled := Transform3D(placed.basis.scaled(Vector3.ONE * scale_by), placed.origin)
			return _off_walls(props, held, i, kind, scaled, laid_in.origin)
	return carry_transform(props, held, body, i, reach)


## A roller lying on the floor at `xf` (world) moved out of the walls round it
## (ParkWalls.shift(), PullSide.walls_near()), as its set-down's move draws it
## (this is that move's end, "want") and as it lies settled after it: at a
## seat walled on both sides the floor spot beside the feet reached into the
## wall, and only the move was kept out of it, so the settled roller snapped
## back in (board a40fdbaf). Worked out from `xf` and `home` (the frame it is
## laid in: the chair front at a gate chair, ParkWalls.shift()'s home, so it
## never goes out through a wall's far face, board f1fc1e54; none for an
## activity visit's fixed spot), so it is the same on every frame and after a
## load. Not in a toilet stall, whose walls are the stall's own.
##
## The way out is kept on bag `i` ("wall_off": the spot `xf` it is for, the
## grid's edit count, and a slide) and worked out again only when the spot or
## the edit count (WallEdits) changes, not on every draw (board 4cb91d64). A
## grid edit with the spot unchanged slides the roller from where the kept slide
## had it at the edit's tick to the new way out (slid()); any other change, a
## new spot or a first draw, puts it there at once, as before. What it does not
## guarantee: two edits with no draw between them slide from the way out before
## the first, not from where the first edit's slide had it at the second.
static func _off_walls(
	props: CarryOnProps,
	held: Dictionary,
	i: int,
	kind: SecurityLooks.Kind,
	xf: Transform3D,
	home := ParkWalls.NO_HOME
) -> Transform3D:
	if kind != SecurityLooks.Kind.ROLLER or held.get("in_stall", false) or props.sim == null:
		return xf
	var edits := WallEdits.of(props)
	var bag: Dictionary = held["bags"][i]
	var off: Dictionary = bag.get("wall_off", {})
	var same: bool = not off.is_empty() and off["at"] == xf and off.get("home") == home
	if not same or off["count"] != edits.count:
		var to := ParkWalls.shift(xf, PullSide.walls_near(props.sim.grid, xf.origin), home)
		var from := to
		var since := -INF
		if same:
			from = slid(off, edits.at)
			since = edits.at
		off = {"at": xf, "home": home, "count": edits.count, "from": from, "to": to, "since": since}
		bag["wall_off"] = off
	xf.origin += slid(off, props._tick())
	return xf


## The shift (world) of a floor roller's slide `off` (_off_walls()'s
## "wall_off") at sim tick `now`: from its "from" toward its "to" by at most
## SLIDE_M_PER_TICK a tick since its "since". Read before "since" (the clock
## gone back) it is at its end.
static func slid(off: Dictionary, now: float) -> Vector3:
	var gone: float = now - float(off["since"])
	if gone < 0.0:
		return off["to"]
	return (off["from"] as Vector3).move_toward(off["to"], SLIDE_M_PER_TICK * gone)


## A carried bag's transform, its kind's way (the header), or `carry`'s way.
static func carry_transform(
	props: CarryOnProps, held: Dictionary, body: Node3D, i: int, reach: Array, carry := -1
) -> Transform3D:
	var scale_by: float = held["scale"]
	var node: Node3D = held["bags"][i]["node"]
	match held["bags"][i]["carry"] if carry < 0 else carry:
		SecurityLooks.Carry.BACK:
			return CarryWorn.worn_back(
				props._spine_of(body), body.rotation.y, scale_by, body.get_meta(&"body", -1)
			)
		SecurityLooks.Carry.SHOULDER:
			var side := SecurityLooks.worn_side(i)
			var joint := props._shoulder_of(body, side)
			var hung := CarryWorn.shoulder(
				joint,
				body.global_position,
				body.rotation.y,
				side,
				scale_by,
				props._reach_base(props._part(node, "Strap_Reach")),
				CarryWorn.stoop_shift(
					props._rig(body)["stoop"], props._rig(body)["pivot"].global_position, joint
				)
			)
			reach[0] = hung[1]
			return hung[0]
		SecurityLooks.Carry.PULL:
			var grip := props.grip_of(body, held["hands"][i])
			# The axle this draw stepped to (_step_hand_bags).
			var axle: Vector3 = held["bags"][i].get("axle_now", Vector3.INF)
			if not axle.is_finite():
				axle = RollerPull.drawn(props, held["bags"][i], body, scale_by, held["hands"][i])
			var rods := props._reach_base(props._part(node, "Pull_Reach"))
			reach[0] = RollerPull.pull_length(grip, axle, scale_by, rods.z)
			return RollerPull.pulled(grip, axle, scale_by)
	return CarryHand.case_transform(props, held, body, i)


## The edits of the grid a CarryOnProps draws on, counted, and the sim tick of
## the last (BuildGrid.edit_applied and graph_changed, the latter also after a
## load), so _off_walls() works a floor roller's way out again only after an
## edit and starts its slide at the edit's tick, not at the first draw after
## it. Kept on the CarryOnProps (META) and watching a new grid when the sim's
## changes.
class WallEdits:
	extends RefCounted
	const META := &"carry_wall_edits"
	var count := 0
	var at := 0.0
	var grid: BuildGrid
	var clock: SimClock

	## `props`' WallEdits, watching its sim's grid.
	static func of(props: CarryOnProps) -> WallEdits:
		# get_meta(key, null) still prints an engine error on a missing key.
		var edits: WallEdits = props.get_meta(META) if props.has_meta(META) else null
		if edits == null:
			edits = WallEdits.new()
			props.set_meta(META, edits)
		edits.clock = props.clock
		edits.watch(props.sim.grid)
		return edits

	## Watches `on` from now (a change of grid counts as an edit).
	func watch(on: BuildGrid) -> void:
		if on == grid:
			return
		if grid != null:
			grid.edit_applied.disconnect(_on_edit)
			grid.graph_changed.disconnect(_on_graph)
		grid = on
		on.edit_applied.connect(_on_edit)
		on.graph_changed.connect(_on_graph)
		_bump()

	func _on_edit(_edit: BuildEdit, _result: BuildResult) -> void:
		_bump()

	func _on_graph(_cells: Array[Vector2i]) -> void:
		_bump()

	func _bump() -> void:
		count += 1
		at = float(clock.tick) if clock != null else 0.0
