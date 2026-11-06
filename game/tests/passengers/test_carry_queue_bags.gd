class_name TestCarryQueueBags
extends GdUnitTestSuite
## Security queuers drawn with the most carry-on bags a passenger can have
## (CarryOnTraits.MAX_BAGS, decision carry-on-at-security-costs-time-only-0-2-
## carry-on-bags-add-s), through the real sim and views (board 61df7fce). A
## queuer holding 3 bags threw a script error in CarryArmPose.pose_arms
## (SecurityLooks.hand_of() gave the third bag hand 2), but no passenger has 3:
## the draw stops at MAX_BAGS and a save with more is refused. These cases go
## red if the cap is raised without the arms learning a third bag.
##
## The world is SecurityTestWorld's basic scanner.

var _w: SecurityTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _w != null:
		_w.world.free_all()
		_w = null


## Every bag a passenger can carry has a hand of its own: 0 or 1, and two
## bags never share one.
func test_every_bag_up_to_the_cap_has_a_hand_of_its_own() -> void:
	_w = SecurityTestWorld.make(false)
	var id := _w.send(CarryOnTraits.MAX_BAGS)
	var p := _w.world.passenger(id)
	var hands: Array[int] = []
	for i in p.carry_on:
		hands.append(SecurityLooks.hand_of(_w.world.sim, p, i))
	print("bags %d hands %s" % [p.carry_on, hands])
	assert_int(hands.size()).is_equal(CarryOnTraits.MAX_BAGS)
	for hand in hands:
		assert_int(hand).is_between(0, 1)
	assert_int(hands.count(hands[0])).is_equal(1)


## Queuers with MAX_BAGS bags are drawn tick by tick with no script error
## (gdUnit4 fails the case on one), and each arm whose hand holds a bag in
## hand or a pulled roller holds it. Control: two queuers were drawn in the
## queue and at least one arm held a bag.
func test_security_queuers_with_the_most_bags_are_drawn_with_their_arms_holding() -> void:
	_w = SecurityTestWorld.make(false)
	var bags := CarryOnTraits.MAX_BAGS
	_w.send_all([[bags, false, false], [bags, false, false], [bags, false, false]])
	_views = PassengerTestWorld.views()
	_views.clock = _w.world.clock
	_views.sim = _w.world.sim
	add_child(_views)
	var queue_frames := 0
	var holding := 0
	for t in 900:
		_w.world.step()
		_views.draw()
		var queuers := 0
		for id in _w.world.sim.queue_of(_w.station):
			var p := _w.world.passenger(id)
			if p.stage != Passenger.Stage.SECURITY_QUEUE or _views.node_for(id) == null:
				continue
			queuers += 1
			holding += _assert_arms_hold(p)
		if queuers >= 2:
			queue_frames += 1
		if queue_frames >= 10:
			break
	print("queue frames with two queuers %d, arms holding %d" % [queue_frames, holding])
	assert_int(queue_frames).is_equal(10)
	assert_int(holding).is_greater(0)


## Asserts every in-hand bag of `p` has its arm holding it; returns how many.
func _assert_arms_hold(p: Passenger) -> int:
	var body := _views.node_for(p.id)
	var arms: Array = []
	for side in 2:
		arms.append(body.find_child("CarryArm%d" % side, true, false))
	var homes := SecurityLooks.bag_homes(_w.world.sim, p)
	var held := 0
	for i in p.carry_on:
		var carry := SecurityLooks.carry_of(p, i)
		if homes[i] != SecurityLooks.Home.HAND:
			continue
		if carry not in [SecurityLooks.Carry.HAND, SecurityLooks.Carry.PULL]:
			continue
		var hand := SecurityLooks.hand_of(_w.world.sim, p, i)
		var arm := arms[hand] as CarryArm
		assert_object(arm).is_not_null()
		assert_bool(arm.holds).is_true()
		held += 1
	return held
