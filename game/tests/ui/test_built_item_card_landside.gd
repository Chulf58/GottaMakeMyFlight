class_name TestBuiltItemCardLandside
extends GdUnitTestSuite
## Rich BuiltItemCard stats for Surface Lot, Multi-Storey Car Park, and Curb Bay
## plus translation and messages.pot coverage (decision
## parking-and-landside-gameplay-popups-2-berth-curb-shortest-walk-routing).

const STARTER := preload("res://landside/starter_landside.tres")
const SURFACE := 0
const MULTI_STOREY := 1

var _world: PassengerTestWorld
var _landside: LandsideSim
var _mode: BuildMode
var _card: BuiltItemCard
var _rng := RandomNumberGenerator.new()


func before_test() -> void:
	_rng.seed = 31
	var grid := PassengerTestWorld.floored(Vector2i(14, 14))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(7, 13), 2)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_landside = auto_free(LandsideSim.new())
	assert_bool(_landside.use_definition(STARTER)).is_true()
	_landside.wallet = _world.sim.wallet
	_world.sim.landside = _landside
	_mode = auto_free(BuildMode.new())
	_mode.landside = _landside
	add_child(_mode)
	_mode.set_process(false)
	_card = auto_free(BuiltItemCard.new())
	_card.sim = _world.sim
	_card.build_mode = _mode
	_card.selection = BuiltSelection.new()
	add_child(_card)


func after_test() -> void:
	PseudoLocale.disable()
	_world.free_all()


func _select_landside(lot_kind: LandsidePlacement.Kind, spot: int) -> void:
	_card.selection.clear()
	_card.selection.kind = BuiltSelection.Kind.LANDSIDE
	_card.selection.lot_kind = lot_kind
	_card.selection.spot = spot
	_card.invalidate()
	_card.refresh()


func _step_landside(from: int, to: int) -> void:
	for t in range(from, to):
		_world.sim.tick = t
		_landside.step(t, true, _rng)


func test_surface_lot_card_shows_fee_earned_today_parked_diverted_and_occupancy() -> void:
	assert_bool(_landside.build_lot(SURFACE, 1200)).is_true()
	_select_landside(LandsidePlacement.Kind.SURFACE_LOT, SURFACE)
	assert_str(_card.name_text()).is_equal("Surface lot")
	assert_str(_card.field_text("fee")).is_equal("Parking fee: $20")
	assert_str(_card.field_text("earned")).is_equal("Earned today: $0")
	assert_str(_card.field_text("parked")).is_equal("Parked today: 0 cars")
	assert_str(_card.field_text("diverted")).is_empty()
	assert_str(_card.field_text("queue")).is_equal("Occupancy: 0/12 spaces")

	# Park 1 car, then fill all 12 and divert 1.
	var first: Array[int] = [1]
	_landside.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, first)
	_step_landside(1, 500)
	_card.refresh()
	assert_str(_card.field_text("earned")).is_equal("Earned today: $20")
	assert_str(_card.field_text("parked")).is_equal("Parked today: 1 car")
	assert_str(_card.field_text("queue")).is_equal("Occupancy: 1/12 spaces")
	assert_str(_card.field_text("diverted")).is_empty()

	for i in 12:
		var booking: Array[int] = [i + 2]
		_landside.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, booking)
	_step_landside(500, 2000)
	_card.refresh()
	assert_str(_card.field_text("earned")).is_equal("Earned today: $240")
	assert_str(_card.field_text("parked")).is_equal("Parked today: 12 cars")
	assert_str(_card.field_text("diverted")).is_equal("Diverted today: 1 car")
	assert_str(_card.field_text("queue")).is_equal("Occupancy: 12/12 spaces")

	# Next game day (Day 1 midnight = 21600 < STAY_MIN_TICKS 28800) resets
	# today's earnings, parked and diverted counts while all 12 cars remain parked.
	var next_day := GameCalendar.day_start(1, 0)
	_step_landside(next_day, next_day + 1)
	_card.refresh()
	assert_str(_card.field_text("earned")).is_equal("Earned today: $0")
	assert_str(_card.field_text("parked")).is_equal("Parked today: 0 cars")
	assert_str(_card.field_text("diverted")).is_empty()
	assert_str(_card.field_text("queue")).is_equal("Occupancy: 12/12 spaces")


func test_multi_storey_and_curb_bay_cards_show_translated_rows() -> void:
	assert_bool(_landside.build_lot(MULTI_STOREY, 5000)).is_true()
	var car: Array[int] = [1]
	_landside.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, car)
	_step_landside(1, 500)
	_select_landside(LandsidePlacement.Kind.MULTI_STOREY, MULTI_STOREY)
	assert_str(_card.field_text("fee")).is_equal("Parking fee: $35")
	assert_str(_card.field_text("earned")).is_equal("Earned today: $35")
	assert_str(_card.field_text("parked")).is_equal("Parked today: 1 car")
	assert_str(_card.field_text("queue")).is_equal("Occupancy: 1/31 spaces")

	assert_bool(_landside.build_curb(0, 300)).is_true()
	_select_landside(LandsidePlacement.Kind.CURB, 0)
	assert_str(_card.field_text("fee")).is_equal("Parking fee: Free")
	assert_str(_card.field_text("queue")).is_equal("Occupancy: 0/2 berths")
	assert_str(_card.field_text("earned")).is_empty()
	assert_str(_card.field_text("parked")).is_empty()

	# tr() lines go through pseudolocalization; tr_n() plural lines go through TranslationServer.
	PseudoLocale.enable(0.4)
	_select_landside(LandsidePlacement.Kind.MULTI_STOREY, MULTI_STOREY)
	for field in ["status", "fee", "earned"]:
		assert_str(_card.field_text(field)).override_failure_message(field).starts_with("[")
	_select_landside(LandsidePlacement.Kind.CURB, 0)
	for field in ["status", "fee"]:
		assert_str(_card.field_text(field)).override_failure_message(field).starts_with("[")
	PseudoLocale.disable()

	var tr_test := Translation.new()
	tr_test.locale = TranslationServer.get_locale()
	tr_test.add_plural_message(
		"Occupancy: {cars}/{capacity} space",
		PackedStringArray(["X_SPACE {cars}/{capacity}", "X_SPACES {cars}/{capacity}"])
	)
	tr_test.add_plural_message(
		"Parked today: {count} car", PackedStringArray(["X_PARKED_1 {count}", "X_PARKED_N {count}"])
	)
	TranslationServer.add_translation(tr_test)
	_select_landside(LandsidePlacement.Kind.MULTI_STOREY, MULTI_STOREY)
	assert_str(_card.field_text("queue")).is_equal("X_SPACES 1/31")
	assert_str(_card.field_text("parked")).is_equal("X_PARKED_1 1")
	TranslationServer.remove_translation(tr_test)


func test_new_landside_and_unlock_msgids_are_in_messages_pot() -> void:
	var entries := PotEntries.parse(FileAccess.get_file_as_string("res://locale/messages.pot"))
	var singular := [
		"Parking fee: Free",
		"Parking fee: ${fee}",
		"Earned today: ${amount}",
		# gdlint:ignore = max-line-length
		"cafe and bins, security lane, baggage, kiosk, screen, plants, benches, curb bay, surface lot, medium runway",
		# gdlint:ignore = max-line-length
		"food and services: bar, restaurant, grab-and-go, info desk, pharmacy, exchange, ATM, lounge, car park gate, large runway",
	]
	for id: String in singular:
		assert_int(PotEntries.complete(entries, "", id)).override_failure_message(id).is_equal(1)
	var plurals := [
		["Occupancy: {cars}/{capacity} berth", "Occupancy: {cars}/{capacity} berths"],
		["Occupancy: {cars}/{capacity} space", "Occupancy: {cars}/{capacity} spaces"],
		["Parked today: {count} car", "Parked today: {count} cars"],
		["Diverted today: {count} car", "Diverted today: {count} cars"],
	]
	for pair in plurals:
		(
			assert_int(PotEntries.complete(entries, "", pair[0], pair[1]))
			. override_failure_message(pair[0])
			. is_equal(1)
		)
