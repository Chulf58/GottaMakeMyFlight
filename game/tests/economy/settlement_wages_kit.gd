class_name SettlementWagesKit
extends RefCounted
## Test support for staff wages: a bare floored room with a bound Settlement
## and no automatic staffing, so only the members a case hires exist. The clock
## is moved to just before a midnight with near_midnight() or cross().

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const START_BALANCE := 1000

var world: PassengerTestWorld
var settlement: Settlement
## Every wages_charged emission, as [day, paid, owed].
var charges: Array = []

var _suite: GdUnitTestSuite


func _init(suite: GdUnitTestSuite) -> void:
	_suite = suite
	remake()


## A fresh world (the old one is freed) whose settlement has seen day 0: a
## bare floored room, or `on_world` when a case needs a real terminal.
func remake(on_world: PassengerTestWorld = null) -> void:
	free_all()
	charges = []
	world = on_world
	if world == null:
		world = PassengerTestWorld.make(
			PassengerTestWorld.floored(Vector2i(8, 6)), FlightSim.schedule_starts(1000000)
		)
	world.auto_staff = false
	world.sim.wallet.credit(START_BALANCE)
	settlement = _suite.auto_free(Settlement.new())
	settlement.staff = world.staff
	settlement.bind(world.sim, world.sim.wallet)
	settlement.wages_charged.connect(
		func(day: int, paid: int, owed: int) -> void: charges.append([day, paid, owed])
	)
	world.step()


func free_all() -> void:
	if world != null:
		world.free_all()
		world = null


func hire(role: StaffMember.Role, count := 1) -> void:
	for i in count:
		_suite.assert_int(world.staff.hire(role)).is_greater(0)


## Sets the clock so that `ticks` more ticks reach the first tick of `day`.
func near_midnight(day: int, ticks: int) -> void:
	var data := world.clock.to_snapshot()
	data["tick"] = str(GameCalendar.day_start(day) - ticks)
	_suite.assert_bool(world.clock.from_snapshot(data)).is_true()


## Runs the clock through the midnight that starts `day`.
func cross(day: int) -> void:
	near_midnight(day, 3)
	for i in 6:
		world.step()


## Everything a save holds of the wages: the settlement, wallet and clock, as
## JSON would hand them back.
func save() -> Dictionary:
	var parts := {
		"settlement": settlement.to_snapshot(),
		"wallet": world.sim.wallet.to_snapshot(),
		"clock": world.clock.to_snapshot(),
	}
	return JSON.parse_string(JSON.stringify(parts)) as Dictionary


## Loads a save() into the running world.
func load_save(data: Dictionary) -> void:
	_suite.assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	_suite.assert_bool(world.sim.wallet.from_snapshot(data["wallet"])).is_true()
	_suite.assert_bool(settlement.from_snapshot(data["settlement"])).is_true()
