class_name TestLandsidePlacementUndo
extends GdUnitTestSuite
## Undoing the landside build tools (LandsidePlacement.undo(), Landside 3/4):
## a build gives back the whole price, a removal takes its refund back, a close
## opens the car park again, and an undo that cannot be done (a car is in the
## spot, the money is short) is refused with nothing changed.

const STARTER := preload("res://landside/starter_landside.tres")
const SHELL := preload("res://build/toon_terminal_shell.tres")
const START_MONEY := 20000
const LOT_PRICE := 1200

const IN_LOT_0 := Vector3(32.0, 0.0, -22.0)
const IN_BAY_0 := Vector3(4.0, 0.0, -57.0)

var _sim: LandsideSim
var _wallet: Wallet
var _placement: LandsidePlacement
var _rng := RandomNumberGenerator.new()


func before_test() -> void:
	_sim = auto_free(LandsideSim.new())
	assert_bool(_sim.use_definition(STARTER)).is_true()
	_sim.wallet = Wallet.new(0)
	_wallet = Wallet.new(START_MONEY)
	_placement = LandsidePlacement.new()
	_placement.sim = _sim
	_placement.shell = SHELL
	_placement.wallet = _wallet
	_rng.seed = 3


func _build(kind: LandsidePlacement.Kind, point: Vector3) -> BuildResult:
	return _placement.apply(_placement.plan_build(kind, point), null)


func _remove(point: Vector3) -> BuildResult:
	return _placement.apply(_placement.plan_remove(point), null)


## One car parked in lot 0, which must be built.
func _park_a_car() -> void:
	var bookings: Array[int] = [1]
	_sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, bookings)
	for t in range(1, 1500):
		_sim.step(t, true, _rng)
	assert_int(_sim.lot_cars(0)).is_equal(1)


func test_undoing_a_build_gives_back_the_whole_price() -> void:
	assert_bool(_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0).ok).is_true()
	assert_bool(_placement.has_undo_for(null)).is_true()
	assert_bool(_placement.undo().ok).is_true()
	assert_bool(_sim.lots_built[0]).is_false()
	assert_int(_sim.lots_paid[0]).is_equal(0)
	assert_int(_wallet.balance).is_equal(START_MONEY)
	assert_object(_placement.undo()).is_null()


func test_undoing_a_build_is_refused_while_a_car_is_in_it() -> void:
	assert_bool(_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0).ok).is_true()
	_park_a_car()
	var balance := _wallet.balance
	var result := _placement.undo()
	assert_int(result.reason).is_equal(BuildResult.Reason.LANDSIDE_OCCUPIED)
	assert_bool(_sim.lots_built[0]).is_true()
	assert_int(_wallet.balance).is_equal(balance)
	assert_int(_placement.undo_size()).is_equal(1)


func test_undoing_a_removal_builds_it_again_at_its_old_price() -> void:
	assert_bool(_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0).ok).is_true()
	assert_bool(_placement.apply(_placement.plan_toggle(IN_LOT_0), null).ok).is_true()
	assert_bool(_remove(IN_LOT_0).ok).is_true()
	assert_int(_wallet.balance).is_equal(START_MONEY - LOT_PRICE + LOT_PRICE / 2)
	assert_bool(_placement.undo().ok).is_true()
	assert_bool(_sim.lots_built[0]).is_true()
	assert_bool(_sim.lots_closed[0]).is_true()
	assert_int(_sim.lots_paid[0]).is_equal(LOT_PRICE)
	assert_int(_wallet.balance).is_equal(START_MONEY - LOT_PRICE)


func test_undoing_a_removal_is_refused_when_the_refund_cannot_be_taken_back() -> void:
	assert_bool(_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0).ok).is_true()
	assert_bool(_remove(IN_LOT_0).ok).is_true()
	assert_bool(_wallet.from_snapshot({"balance": "0"})).is_true()
	var result := _placement.undo()
	assert_int(result.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_bool(_sim.lots_built[0]).is_false()
	assert_int(_placement.undo_size()).is_equal(2)


func test_undoing_a_close_opens_the_car_park_again() -> void:
	assert_bool(_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0).ok).is_true()
	assert_bool(_placement.apply(_placement.plan_toggle(IN_LOT_0), null).ok).is_true()
	assert_bool(_sim.lot_open(0)).is_false()
	assert_bool(_placement.undo().ok).is_true()
	assert_bool(_sim.lot_open(0)).is_true()


func test_a_landside_action_is_ordered_among_the_grid_ones_by_the_receipt_it_follows() -> void:
	var first := BuildReceipt.new()
	var second := BuildReceipt.new()
	var plan := _placement.plan_build(LandsidePlacement.Kind.CURB, IN_BAY_0)
	assert_bool(_placement.apply(plan, first).ok).is_true()
	assert_bool(_placement.has_undo_for(first)).is_true()
	assert_bool(_placement.has_undo_for(second)).is_false()
	assert_bool(_placement.has_undo_for(null)).is_false()
