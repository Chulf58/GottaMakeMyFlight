class_name TestPlaytestViewDrift
extends GdUnitTestSuite
## The view_drift anomaly measures a passenger's drawn node against where
## PassengerViews means to draw it (draw_position), not against the sim's
## cell-based spot. A gate sitter in a middle chair is drawn 0.36 m beside
## that spot, so measuring from the sim would raise a false alarm for a 1.2 m
## drift away from it and miss a 1.6 m drift towards it.

const MAIN := "res://main/main.tscn"
const HOOK := preload("res://debug/playtest_hook.gd")
const DIR := "user://playtest_view_drift_test"

var _main: Node
var _hook: Node
var _sim: PassengerSim
var _views: PassengerViews
var _id := 0


func before() -> void:
	_main = load(MAIN).instantiate()
	var clock := _main.get_node("SimClock") as SimClock
	clock.seed_rng(7)
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	add_child(_main)
	clock.set_paused(true)
	_hook = HOOK.new()
	_hook.configure(true, DIR)
	add_child(_hook)
	_hook.attach(_main)
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	_id = _sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
	# Seat it by hand in the middle cell of a seat row, as the sim would.
	var p := _sim.get_passenger(_id)
	for seat: Dictionary in _sim.layout.seats:
		var record := _sim.grid.get_object(seat["object_id"])
		var cells := BuildCatalog.get_def(record["def"]).footprint(
			record["anchor"], record["facing"]
		)
		if cells.find(seat["cell"]) == 1:
			p.stage = Passenger.Stage.SEATED
			p.seat_object = seat["object_id"]
			p.seat_cell = seat["cell"]
			p.seat_front = seat["front"]
			p.at = seat["front"]
			break
	_views.sync()
	_views.draw()


func after() -> void:
	_hook.detach()
	_hook.free()
	_main.free()
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute("%s/%s" % [DIR, name])
	DirAccess.remove_absolute(DIR)


## The open view_drift anomaly for the sitter, or {} for none.
func _drift_after_moving(by: Vector3) -> Dictionary:
	var node := _views.node_for(_id)
	var target := _views.to_global(_views.draw_position(_sim.get_passenger(_id)))
	node.global_position = target + by
	_hook.run_checks()
	for record in _hook.anomalies():
		if record["kind"] == "view_drift" and record["subject"] == "passenger:%d" % _id:
			return record
	return {}


## Sideways from the sim's spot to the chair, as a unit vector, and its length.
func _chair_step() -> Vector3:
	var p := _sim.get_passenger(_id)
	return _views.to_global(_views.draw_position(p)) - _views.to_global(_sim.world_position(p))


func test_the_sitter_is_in_a_middle_chair_beside_the_sim_spot() -> void:
	assert_int(_id).is_not_equal(0)
	assert_int(_sim.get_passenger(_id).stage).is_equal(Passenger.Stage.SEATED)
	print("chair step %s" % _chair_step())
	assert_float(_chair_step().length()).is_equal_approx(0.36, 0.001)
	assert_dict(_drift_after_moving(Vector3.ZERO)).is_empty()


func test_a_drift_away_from_the_sim_spot_under_the_limit_raises_nothing() -> void:
	var away := _chair_step().normalized() * 1.2
	var record := _drift_after_moving(away)
	print("1.2 m away from the sim spot: %s" % [record])
	assert_dict(record).is_empty()


func test_a_drift_towards_the_sim_spot_over_the_limit_is_raised() -> void:
	var towards := -_chair_step().normalized() * 1.6
	var record := _drift_after_moving(towards)
	print("1.6 m towards the sim spot: %s" % [record])
	assert_dict(record).is_not_empty()
	var detail: Dictionary = record["detail"]
	assert_float(float(detail["drift_m"])).is_equal_approx(1.6, 0.01)
	assert_bool(detail.has("target")).is_true()
	_drift_after_moving(Vector3.ZERO)
