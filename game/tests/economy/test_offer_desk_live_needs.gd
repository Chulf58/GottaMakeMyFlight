class_name TestOfferDeskLiveNeeds
extends GdUnitTestSuite
## OfferDesk.live_needs: the bag traits need a ready bag room and Shoppers a
## ready shop or food room (OfferTraits needs), read from the desk's BaggageSim
## and its grid; with no BaggageSim neither is live.

var _clock: SimClock
var _flights: FlightSim


func before_test() -> void:
	_clock = auto_free(SimClock.new())
	_flights = auto_free(FlightSim.new())
	_flights.bind_clock(_clock)


func _needs(grid: BuildGrid) -> Dictionary:
	var bags: BaggageSim = auto_free(BaggageSim.new())
	bags.bind(_clock, _flights, grid, null)
	var desk: OfferDesk = auto_free(OfferDesk.new())
	desk.baggage = bags
	return desk.live_needs()


func test_a_bare_terminal_meets_neither_need() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var needs := _needs(grid)
	assert_bool(needs[OfferTraits.NEEDS_BAGS]).is_false()
	assert_bool(needs[OfferTraits.NEEDS_SHOPS]).is_false()


func test_a_ready_bag_room_makes_the_bag_traits_live() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	BagRoomKit.add(grid)
	var needs := _needs(grid)
	assert_bool(needs[OfferTraits.NEEDS_BAGS]).is_true()
	assert_bool(needs[OfferTraits.NEEDS_SHOPS]).is_false()


func test_a_ready_kiosk_makes_shoppers_live_and_bare_floor_does_not() -> void:
	var floor_only := BuildGrid.new()
	ShopTestLayout.build(floor_only, [])
	assert_bool(_needs(floor_only)[OfferTraits.NEEDS_SHOPS]).is_false()
	var kiosk := BuildGrid.new()
	ShopTestLayout.build(kiosk, ["air"])
	assert_bool(_needs(kiosk)[OfferTraits.NEEDS_SHOPS]).is_true()


func test_without_baggage_neither_need_is_live() -> void:
	var desk: OfferDesk = auto_free(OfferDesk.new())
	assert_dict(desk.live_needs()).is_equal(
		{OfferTraits.NEEDS_BAGS: false, OfferTraits.NEEDS_SHOPS: false}
	)
