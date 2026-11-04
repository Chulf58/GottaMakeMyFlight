extends GdUnitTestSuite
## A roller swap between the hand and the pull that turns back while still
## under way, through the real sim and views (CarryOnProps, CarrySwap; board
## 6981b7ac part 3, Sol review): the roller is drawn on from where it was, in
## both directions, also with its follower off the straight-behind line (as
## after a corner). Equal shares toward the pull are not enough: the old
## swap's trailing end has to be kept too.
##
## The world is SecurityTestWorld's lane; a walker pulling its roller there is
## made late (lifted by its bar) and on time again by hand.

## Largest move of the roller's axle or origin, or of its rods' length, at
## the turn (no time passes between the two draws).
const TURN_M := 0.01
## Largest turn of the roller's basis at the turn.
const TURN_DEGREES := 2.0

var _worlds: Array[SecurityTestWorld] = []
var _views: Array[PassengerViews] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for v in _views:
		v.free()
	_views.clear()
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


## A swap to the hand turned back to the pull, and a swap to the pull turned
## back to the hand, each mid-way: at the turn the roller's axle, origin, rods
## and basis and the holding grip stay where they were drawn. The follower is
## set 0.6 m out and 0.95 m back before the lift (Sol's corner case; one
## started afresh sits about 0.3 m out, 1.0 m back). Control: each swap is
## under way (0 < k < 1) and turns back (the lift bit flips, still a swap).
func test_a_swap_turned_back_goes_on_from_where_the_roller_is() -> void:
	var w := SecurityTestWorld.make(true)
	_worlds.append(w)
	var views := PassengerTestWorld.views()
	views.clock = w.world.clock
	views.sim = w.world.sim
	add_child(views)
	_views.append(views)
	var props := views.carry_on_props()
	var id := _send_roller(w)
	assert_int(id).is_not_equal(-1)
	var p := w.world.passenger(id)
	var pulled := false
	for i in 2000:
		w.world.step()
		_drawn(views, props, id)
		if _pulled_settled(props, p):
			pulled = true
			break
	assert_bool(pulled).override_failure_message("never pulling outside security").is_true()
	# The sim stops here (the walker stands), so it never sets the lateness back:
	# the views alone go on with the clock.
	w.world.clock.ticked.disconnect(w.world.sim.on_tick)
	_off_axis(views, props, id)
	# To the hand (late), three ticks on (k 0.5), then back to the pull at the same
	# instant (sync() of the props alone: the views would move the body on).
	var lift := _flip(w, views, props, id, true)
	assert_bool(lift).override_failure_message("the lift never started").is_true()
	p.late = true
	for i in 3:
		p.late = true
		w.world.step()
		_drawn(views, props, id)
	var before := _drawn(views, props, id)
	p.late = false
	props.sync()
	var after := _drawn(views, props, id)
	_assert_turned(before, after, false, "to the hand, turned back to the pull")
	# To the pull, one tick on, then back to the hand at the same instant.
	p.late = false
	w.world.step()
	before = _drawn(views, props, id)
	p.late = true
	props.sync()
	after = _drawn(views, props, id)
	_assert_turned(before, after, true, "to the pull, turned back to the hand")


func _send_roller(w: SecurityTestWorld) -> int:
	for i in 40:
		var id := w.send(1)
		var p := w.world.passenger(id)
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			return id
		p.cleared = true
		p.stage = Passenger.Stage.TO_GATE
	return -1


func _pulled_settled(props: CarryOnProps, p: Passenger) -> bool:
	var bag := props.bag_state(p.id, 0)
	return (
		not p.stage in [Passenger.Stage.SECURITY_QUEUE, Passenger.Stage.SECURITY]
		and bag.get("carry", -1) == SecurityLooks.Carry.PULL
		and int(bag.get("place", -2)) >= 0
		and int(bag["place"]) / 4 == SecurityLooks.Home.HAND
		and props.transfer_progress(p.id, 0) >= 1.0
		and bag.has("axle_now")
	)


## Sets the pulled roller's follower 0.6 m out on the pulling hand's side and
## 0.95 m back (body frame), as a corner leaves it, and draws it there.
func _off_axis(views: PassengerViews, props: CarryOnProps, id: int) -> void:
	var held: Dictionary = props._held[id]
	var bag: Dictionary = held["bags"][0]
	var body := views.node_for(id)
	var frame := Transform3D(Basis(Vector3.UP, body.rotation.y), body.global_position)
	var out := -1.0 if int(held["hands"][0]) == 0 else 1.0
	bag["drawn_axle"] = frame * Vector3(out * 0.6, 0.0, -0.95)
	bag["drawn_at"] = props._now()
	_drawn(views, props, id)


## Steps until the roller's lift bit is `lifted` with a swap under way (the
## walker made late or on time each tick); whether it did.
func _flip(
	w: SecurityTestWorld, views: PassengerViews, props: CarryOnProps, id: int, lifted: bool
) -> bool:
	var p := w.world.passenger(id)
	for i in 4:
		p.late = lifted
		w.world.step()
		var state := _drawn(views, props, id)
		if state["lifted"] == lifted and state["swap"] and state["k"] < 1.0:
			return true
	return false


## Draws the views and places the bags going to a hand, as the skeleton's
## report does in the game (CarryOnProps._unposed); returns the roller as
## drawn.
func _drawn(views: PassengerViews, props: CarryOnProps, id: int) -> Dictionary:
	views.draw()
	var held: Dictionary = props._held.get(id, {})
	var body := views.node_for(id)
	if held.is_empty() or body == null:
		return {}
	var now := props._now()
	props._place_bags(held, body, props._tray_transform(held, body), now, CarryOnProps.Placing.HAND)
	var bag: Dictionary = held["bags"][0]
	var node: Node3D = bag["node"]
	return {
		"xf": node.global_transform,
		"axle": node.global_transform * CarryOnProps.ROLLER_AXLE,
		"rods": props._reach_of(node, SecurityLooks.Kind.ROLLER),
		"grip": props.grip_of(body, held["hands"][0]),
		"k": props.transfer_progress(id, 0),
		"lifted": int(bag.get("place", 0)) % 2 == 1,
		"swap": bag.get("swap", false),
	}


func _assert_turned(before: Dictionary, after: Dictionary, lifted: bool, what: String) -> void:
	var axle: float = (before["axle"] as Vector3).distance_to(after["axle"])
	var origin: float = (before["xf"] as Transform3D).origin.distance_to(after["xf"].origin)
	var rods: float = absf(float(before["rods"]) - float(after["rods"]))
	var a: Quaternion = (before["xf"] as Transform3D).basis.get_rotation_quaternion()
	var b: Quaternion = (after["xf"] as Transform3D).basis.get_rotation_quaternion()
	var turn := rad_to_deg(a.angle_to(b))
	var grip: float = (before["grip"] as Vector3).distance_to(after["grip"])
	print(
		(
			"%s: k %.3f -> %.3f, axle %.4f m, origin %.4f m, rods %.4f, basis %.2f deg, grip %.4f m"
			% [what, before["k"], after["k"], axle, origin, rods, turn, grip]
		)
	)
	assert_bool(before["swap"] and before["k"] > 0.0 and before["k"] < 1.0).is_true()
	assert_bool(after["swap"] and after["lifted"] == lifted).is_true()
	assert_float(axle).is_less(TURN_M)
	assert_float(origin).is_less(TURN_M)
	assert_float(rods).is_less(TURN_M)
	assert_float(turn).is_less(TURN_DEGREES)
	assert_float(grip).is_less(TURN_M)
