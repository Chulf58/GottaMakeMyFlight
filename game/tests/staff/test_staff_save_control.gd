class_name TestStaffSaveControl
extends GdUnitTestSuite
## A save around a leaving member whose service has just ended, checked against
## an UNSAVED control world (Sol review of the whole-world save, finding 1).
## Two worlds from one seed hire an agent, fire it while it checks a passenger
## in, and play until that service ends within a tick. Then one world is saved
## and a third loads that save. StaffSim.to_snapshot() only reads: the save
## neither removes the member nor emits staff_changed, and all three worlds let
## it go on the same next tick and match on every tick after.

const CHECKIN := StaffMember.Role.CHECKIN
const SEED := 5
const LIMIT_TICKS := 1500
const COMPARE_TICKS := 300

var _control: PassengerTestWorld
var _saved: PassengerTestWorld
var _loaded: PassengerTestWorld
var _run := {}


func before() -> void:
	PassengerTestWorld.tracker = self
	_control = _world()
	_saved = _world()
	var id := _hire_and_serve([_control, _saved])
	var desk := _control.staff.get_member(id).station
	for world in [_control, _saved]:
		assert_bool(world.staff.fire(CHECKIN)).is_true()
	# Play until the service ends during a tick: the member is still there,
	# leaving, until the next tick's staff step.
	while _in_service(_control, desk) and _control.clock.tick < LIMIT_TICKS:
		_step([_control, _saved])
	_run["service_ended"] = not _in_service(_control, desk)
	_run["present_before_save"] = _saved.staff.get_member(id) != null
	var changes := [0]
	_saved.staff.staff_changed.connect(func() -> void: changes[0] += 1)
	var text := StaffTestKit.save_text(_saved)
	_run["changes_during_save"] = changes[0]
	_run["present_after_save"] = _saved.staff.get_member(id) != null
	_run["same_after_save"] = _sig(_saved) == _sig(_control)
	_loaded = StaffTestKit.load_world(text)
	_run["loaded_leaving"] = _loaded.staff.get_member(id).leaving
	_run["same_after_load"] = _sig(_loaded) == _sig(_control)
	var left := {_control: -1, _saved: -1, _loaded: -1}
	var first_bad := {_saved: -1, _loaded: -1}
	for i in COMPARE_TICKS:
		_step([_control, _saved, _loaded])
		for world in left:
			if left[world] < 0 and world.staff.get_member(id) == null:
				left[world] = world.clock.tick
		for world in first_bad:
			if first_bad[world] < 0 and _sig(world) != _sig(_control):
				first_bad[world] = world.clock.tick
	_run["saved_at"] = _saved.clock.tick - COMPARE_TICKS
	_run["left"] = [left[_control], left[_saved], left[_loaded]]
	_run["first_bad"] = [first_bad[_saved], first_bad[_loaded]]


func after() -> void:
	PassengerTestWorld.tracker = null


func _world() -> PassengerTestWorld:
	var world := PassengerTestWorld.reference_world(SEED)
	world.auto_staff = false
	for i in 4:
		world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	return world


## Hires one agent in each world and plays until it is on duty with a
## passenger in check-in at its desk. Returns the agent's id.
func _hire_and_serve(worlds: Array) -> int:
	var id := 0
	for world in worlds:
		id = world.staff.hire(CHECKIN)
	var m := _control.staff.get_member(id)
	while _control.clock.tick < LIMIT_TICKS:
		_step(worlds)
		if m.state == StaffMember.State.ON_DUTY and _in_service(_control, m.station):
			break
	assert_bool(_in_service(_control, m.station)).is_true()
	return id


static func _in_service(world: PassengerTestWorld, station: int) -> bool:
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		if p.station == station and p.stage == Passenger.Stage.CHECKIN:
			return true
	return false


static func _step(worlds: Array) -> void:
	for world in worlds:
		world.step()


static func _sig(world: PassengerTestWorld) -> String:
	return "%s#%s" % [StaffTestKit.signature(world.staff), world.signature()]


func test_the_save_came_right_after_the_leaving_members_service_ended() -> void:
	assert_bool(_run["service_ended"]).is_true()
	assert_bool(_run["present_before_save"]).is_true()
	assert_bool(_run["loaded_leaving"]).is_true()


func test_the_save_only_reads() -> void:
	assert_int(_run["changes_during_save"]).is_equal(0)
	assert_bool(_run["present_after_save"]).is_true()
	assert_bool(_run["same_after_save"]).is_true()
	assert_bool(_run["same_after_load"]).is_true()


func test_the_member_leaves_on_the_same_tick_in_every_world() -> void:
	var left: Array = _run["left"]
	assert_int(left[0]).is_equal(_run["saved_at"] + 1)
	assert_array(left).is_equal([left[0], left[0], left[0]])


func test_saved_and_loaded_worlds_match_the_unsaved_control_on_every_tick() -> void:
	assert_array(_run["first_bad"]).is_equal([-1, -1])
