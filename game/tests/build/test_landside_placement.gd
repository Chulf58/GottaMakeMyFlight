class_name TestLandsidePlacement
extends GdUnitTestSuite
## The landside build rules (LandsidePlacement, Landside 3/4): the tools snap
## to the nearest free authored spot of their kind on the y = 0 plane, refuse
## off a spot, a spot already built and an empty wallet, keep the price paid
## so a removal refunds half, and refuse a removal while a car is in the spot
## (undo is in test_landside_placement_undo.gd). The preview carries capacity
## and the walk to the nearest landside door, so which spot to take is a choice.

const STARTER := preload("res://landside/starter_landside.tres")
const SHELL := preload("res://build/toon_terminal_shell.tres")
const START_MONEY := 20000
const LOT_PRICE := 1200
const BAY_PRICE := 300

## Points inside each authored spot's footprint.
const IN_LOT_0 := Vector3(32.0, 0.0, -22.0)
const IN_MULTI := Vector3(0.0, 0.0, -8.0)
const IN_BAY_0 := Vector3(4.0, 0.0, -57.0)
const IN_BAY_1 := Vector3(20.0, 0.0, -57.0)
const NOWHERE := Vector3(200.0, 0.0, 100.0)

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


func _run(from: int, to: int) -> void:
	for t in range(from, to):
		_sim.step(t, true, _rng)


## One car parked in lot 0, which must be built.
func _park_a_car() -> void:
	var bookings: Array[int] = [1]
	_sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, bookings)
	_run(1, 1500)
	assert_int(_sim.lot_cars(0)).is_equal(1)


func test_a_lot_tool_snaps_to_the_spot_under_the_pointer_and_pays_for_it() -> void:
	var plan := _placement.plan_build(
		LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0 + Vector3(5, 0, 3)
	)
	assert_bool(plan.result.ok).is_true()
	assert_int(plan.spot).is_equal(0)
	assert_vector(plan.centre).is_equal(STARTER.lots[0].centre)
	assert_int(plan.price).is_equal(LOT_PRICE)
	assert_bool(_placement.apply(plan, null).ok).is_true()
	assert_array(_sim.lots_built).is_equal([true, false])
	assert_int(_sim.lots_paid[0]).is_equal(LOT_PRICE)
	assert_int(_wallet.balance).is_equal(START_MONEY - LOT_PRICE)


func test_each_tool_finds_the_spot_of_its_own_kind() -> void:
	var lot := _placement.plan_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0)
	assert_int(lot.spot).is_equal(0)
	var multi := _placement.plan_build(LandsidePlacement.Kind.MULTI_STOREY, IN_MULTI)
	assert_int(multi.spot).is_equal(1)
	assert_bool(multi.result.ok).is_true()
	var bay := _placement.plan_build(LandsidePlacement.Kind.CURB, IN_BAY_1)
	assert_int(bay.spot).is_equal(1)
	# A multi-storey tool over a surface lot's ground is on no spot of its kind.
	var wrong := _placement.plan_build(LandsidePlacement.Kind.MULTI_STOREY, IN_LOT_0)
	assert_int(wrong.result.reason).is_equal(BuildResult.Reason.LANDSIDE_NOT_ON_SPOT)
	var wrong_way := _placement.plan_build(LandsidePlacement.Kind.SURFACE_LOT, IN_MULTI)
	assert_int(wrong_way.result.reason).is_equal(BuildResult.Reason.LANDSIDE_NOT_ON_SPOT)


func test_the_tool_snaps_to_the_nearest_free_spot() -> void:
	# On the line between the two bays, inside bay 1's edge and 1 m from bay 0's.
	var between := Vector3(13.0, 0.0, -57.0)
	assert_int(_placement.plan_build(LandsidePlacement.Kind.CURB, between).spot).is_equal(1)
	assert_bool(_build(LandsidePlacement.Kind.CURB, between).ok).is_true()
	# Bay 1 is built now: the same point snaps to the nearest free one, bay 0.
	var again := _placement.plan_build(LandsidePlacement.Kind.CURB, between)
	assert_int(again.spot).is_equal(0)
	assert_bool(again.result.ok).is_true()


func test_a_pointer_a_little_outside_the_footprint_still_snaps_but_not_far() -> void:
	# Lot 0 ends at z -5.5; 3 m beyond is inside the snap margin, 13.5 m is not.
	var near := _placement.plan_build(LandsidePlacement.Kind.SURFACE_LOT, Vector3(32, 0, -2.5))
	assert_int(near.spot).is_equal(0)
	var far := _placement.plan_build(LandsidePlacement.Kind.SURFACE_LOT, Vector3(32, 0, 8))
	assert_int(far.result.reason).is_equal(BuildResult.Reason.LANDSIDE_NOT_ON_SPOT)


func test_off_every_spot_is_refused_and_nothing_changes() -> void:
	for kind in [LandsidePlacement.Kind.CURB, LandsidePlacement.Kind.SURFACE_LOT]:
		var result := _build(kind, NOWHERE)
		assert_bool(result.ok).is_false()
		assert_int(result.reason).is_equal(BuildResult.Reason.LANDSIDE_NOT_ON_SPOT)
	assert_array(_sim.lots_built).is_equal([false, false])
	assert_array(_sim.curbs_built).is_equal([false, false])
	assert_int(_wallet.balance).is_equal(START_MONEY)
	assert_int(_placement.undo_size()).is_equal(0)


func test_a_spot_already_built_is_refused() -> void:
	assert_bool(_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0).ok).is_true()
	var result := _build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0)
	assert_int(result.reason).is_equal(BuildResult.Reason.LANDSIDE_SPOT_TAKEN)
	assert_int(_wallet.balance).is_equal(START_MONEY - LOT_PRICE)
	assert_int(_placement.undo_size()).is_equal(1)


func test_an_unaffordable_build_is_refused_with_nothing_spent() -> void:
	assert_bool(_wallet.from_snapshot({"balance": str(LOT_PRICE - 1)})).is_true()
	var result := _build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0)
	assert_int(result.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_bool(_sim.lots_built[0]).is_false()
	assert_int(_wallet.balance).is_equal(LOT_PRICE - 1)
	# A curb bay is cheaper and still affordable.
	assert_bool(_build(LandsidePlacement.Kind.CURB, IN_BAY_0).ok).is_true()
	assert_int(_wallet.balance).is_equal(LOT_PRICE - 1 - BAY_PRICE)
	# Exactly the price is enough.
	assert_bool(_wallet.from_snapshot({"balance": str(LOT_PRICE)})).is_true()
	assert_bool(_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0).ok).is_true()
	assert_int(_wallet.balance).is_equal(0)


func test_removal_refunds_half_the_price_that_was_paid() -> void:
	assert_bool(_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0).ok).is_true()
	assert_bool(_build(LandsidePlacement.Kind.CURB, IN_BAY_0).ok).is_true()
	var after_builds := START_MONEY - LOT_PRICE - BAY_PRICE
	assert_int(_wallet.balance).is_equal(after_builds)
	var plan := _placement.plan_remove(IN_LOT_0)
	assert_int(plan.price).is_equal(LOT_PRICE / 2)
	assert_bool(_placement.apply(plan, null).ok).is_true()
	assert_bool(_sim.lots_built[0]).is_false()
	assert_int(_wallet.balance).is_equal(after_builds + LOT_PRICE / 2)
	assert_bool(_remove(IN_BAY_0).ok).is_true()
	assert_int(_wallet.balance).is_equal(after_builds + LOT_PRICE / 2 + BAY_PRICE / 2)
	# Nothing is built there any more.
	assert_object(_placement.plan_remove(IN_LOT_0)).is_null()


func test_a_spot_built_for_free_refunds_nothing() -> void:
	_placement.wallet = null
	var plan := _placement.plan_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0)
	assert_int(plan.price).is_equal(0)
	assert_bool(_placement.apply(plan, null).ok).is_true()
	assert_int(_sim.lots_paid[0]).is_equal(0)
	_placement.wallet = _wallet
	assert_int(_placement.plan_remove(IN_LOT_0).price).is_equal(0)
	assert_bool(_remove(IN_LOT_0).ok).is_true()
	assert_int(_wallet.balance).is_equal(START_MONEY)


func test_removal_is_refused_while_a_car_is_in_the_spot() -> void:
	assert_bool(_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0).ok).is_true()
	_park_a_car()
	var plan := _placement.plan_remove(IN_LOT_0)
	assert_int(plan.result.reason).is_equal(BuildResult.Reason.LANDSIDE_OCCUPIED)
	assert_str(plan.text).contains("1 car is still in it")
	var balance := _wallet.balance
	assert_int(_remove(IN_LOT_0).reason).is_equal(BuildResult.Reason.LANDSIDE_OCCUPIED)
	assert_bool(_sim.lots_built[0]).is_true()
	assert_int(_wallet.balance).is_equal(balance)


func test_close_then_drain_then_remove() -> void:
	assert_bool(_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0).ok).is_true()
	_park_a_car()
	var close := _placement.plan_toggle(IN_LOT_0)
	assert_bool(close.closes).is_true()
	assert_str(close.text).contains("click to close it")
	assert_bool(_placement.apply(close, null).ok).is_true()
	assert_bool(_sim.lots_closed[0]).is_true()
	assert_str(_placement.plan_toggle(IN_LOT_0).text).contains("click to open it")
	assert_int(_remove(IN_LOT_0).reason).is_equal(BuildResult.Reason.LANDSIDE_OCCUPIED)
	var leaves := _sim.get_vehicle(_sim.vehicle_ids()[0]).leave_tick
	_run(leaves, leaves + 600)
	assert_int(_sim.lot_cars(0)).is_equal(0)
	assert_bool(_remove(IN_LOT_0).ok).is_true()
	assert_bool(_sim.lots_closed[0]).is_false()
	assert_int(_wallet.balance).is_equal(START_MONEY - LOT_PRICE + LOT_PRICE / 2)
	# A removed lot has nothing to close.
	assert_object(_placement.plan_toggle(IN_LOT_0)).is_null()


func test_a_preview_names_the_capacity_and_the_walk_to_the_nearest_door() -> void:
	var lot := _placement.plan_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0)
	assert_int(lot.capacity).is_equal(12)
	assert_str(lot.text).contains("Surface lot: 12 spaces")
	assert_str(lot.text).contains("m walk to the nearest landside door")
	var multi := _placement.plan_build(LandsidePlacement.Kind.MULTI_STOREY, IN_MULTI)
	assert_int(multi.capacity).is_equal(36)
	assert_str(multi.text).contains("Multi-storey car park: 36 spaces")
	var bay := _placement.plan_build(LandsidePlacement.Kind.CURB, IN_BAY_0)
	assert_int(bay.capacity).is_equal(2)
	assert_str(bay.text).contains("Curb bay: 2 berths")


func test_the_spot_nearer_the_doors_has_the_shorter_walk() -> void:
	var near_bay := _placement.plan_build(LandsidePlacement.Kind.CURB, IN_BAY_1)
	var far_bay := _placement.plan_build(LandsidePlacement.Kind.CURB, IN_BAY_0)
	print("walks: bay 0 %.1f, bay 1 %.1f" % [far_bay.walk_m, near_bay.walk_m])
	assert_float(near_bay.walk_m).is_less(far_bay.walk_m)
	# Bay 1 (x 12 to 28) lets its passengers out 5.0 m and 5.3 m from landside
	# doors C and D; bay 0 (x -4 to 12) 10.1 m and 16.0 m from door C.
	assert_float(near_bay.walk_m).is_equal_approx(5.1, 0.1)
	assert_float(far_bay.walk_m).is_equal_approx(13.0, 0.1)
	# The surface lot is by door D; the multi-storey is further, and its
	# upper levels add the stairs.
	var lot := _placement.plan_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0)
	var multi := _placement.plan_build(LandsidePlacement.Kind.MULTI_STOREY, IN_MULTI)
	print("walks: surface lot %.1f, multi-storey %.1f" % [lot.walk_m, multi.walk_m])
	assert_float(lot.walk_m).is_less(multi.walk_m)


func test_without_a_shell_the_preview_has_no_walk() -> void:
	_placement.shell = null
	var plan := _placement.plan_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0)
	assert_float(plan.walk_m).is_equal(-1.0)
	assert_str(plan.text).is_equal("Surface lot: 12 spaces")


func test_the_ghost_marks_every_free_spot_and_tints_the_one_under_the_pointer() -> void:
	var parent: Node3D = auto_free(Node3D.new())
	var valid := StandardMaterial3D.new()
	var invalid := StandardMaterial3D.new()
	var marker := StandardMaterial3D.new()
	var plan := _placement.plan_build(LandsidePlacement.Kind.CURB, IN_BAY_0)
	var spots := _placement.free_spot_plans(LandsidePlacement.Kind.CURB)
	assert_int(spots.size()).is_equal(2)
	LandsidePlacement.draw(parent, spots, plan, valid, invalid, marker)
	assert_int(parent.get_child_count()).is_equal(2)
	var marked := 0
	var tinted := 0
	for child in parent.get_children():
		var material := (child as MeshInstance3D).material_override
		marked += int(material == marker)
		tinted += int(material == valid)
	assert_int(marked).is_equal(1)
	assert_int(tinted).is_equal(1)
	# Built, the spot is no longer offered.
	assert_bool(_build(LandsidePlacement.Kind.CURB, IN_BAY_0).ok).is_true()
	assert_int(_placement.free_spot_plans(LandsidePlacement.Kind.CURB).size()).is_equal(1)
