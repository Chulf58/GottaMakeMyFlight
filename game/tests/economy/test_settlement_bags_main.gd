class_name TestSettlementBagsMain
extends GdUnitTestSuite
## Baggage B4 on the real main scene: the Settlement and the AirportRating both
## follow the scene's own BaggageSim. One boot of main.tscn for the file.

const MAIN := "res://main/main.tscn"

var _main: Node
var _bags: BaggageSim


func before() -> void:
	_main = load(MAIN).instantiate()
	add_child(_main)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	_bags = _main.get_node("BaggageSim")


func after() -> void:
	_main.free()


func test_the_settlement_and_the_rating_follow_the_scenes_bag_sim() -> void:
	var settlement := _main.get_node("Settlement") as Settlement
	var rating := _main.get_node("AirportRating") as AirportRating
	assert_object(settlement.baggage).is_same(_bags)
	assert_object(rating.baggage).is_same(_bags)
	assert_bool(_bags.bag_settled.is_connected(settlement._on_bag_settled)).is_true()
	assert_bool(_bags.bag_settled.is_connected(rating._on_bag_settled)).is_true()


func test_a_missed_bag_on_the_scene_reaches_the_rating() -> void:
	var rating := _main.get_node("AirportRating") as AirportRating
	var before: int = rating.parts()["bags_missed"]
	_bags.bag_settled.emit(1, 1, "GMF101", false)
	assert_int(rating.parts()["bags_missed"]).is_equal(before + 1)
