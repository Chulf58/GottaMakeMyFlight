class_name TestVipMarker
extends GdUnitTestSuite
## The VIP crown over the passenger an accepted VIP incident marked (board
## 2348c245, VipMarker). Boots the real main scene, so PassengerViews reads the
## real IncidentDirector it is wired to. The incident is put into the director
## through from_snapshot(), the same door a load uses: the marking itself
## (IncidentMajors.spawned) is the incidents suite's subject, not this one's.
## The crown shows over the marked passenger only, goes when the incident is
## done, and after a load shows over the loaded VIP, not the one marked before
## the load (anti-pattern a-per-id-view-record-holding-a-sim-tick-must-start-
## over-on-l).

const SEED := 23_481_126
const PASSENGERS_WANTED := 3
const SEARCH_LIMIT := 12000

var _path := SaveTestKit.run_path("test_vip_marker")
var _main: Node
var _views: PassengerViews
var _sim: PassengerSim
var _director: IncidentDirector
var _run := {}


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_views = _main.get_node("PassengerViews")
	_sim = _main.get_node("PassengerSim")
	_director = _main.get_node("IncidentDirector")
	SaveTestKit.start_airport(_main)
	var ticks := 0
	while _views.active_count() < PASSENGERS_WANTED and ticks < SEARCH_LIMIT:
		SaveTestKit.step(_main)
		ticks += 1
	var ids := _drawn_ids()
	_run["drawn"] = ids.size()
	if ids.size() < 2:
		return
	var first: int = ids[0]
	var second: int = ids[1]
	_run["first"] = first
	_run["second"] = second
	_run["before_any"] = _crowned()
	# Marked: the crown shows on the next tick's sync.
	_run["set_first"] = _set_vip(first, IncidentCatalogue.ACCEPTED)
	SaveTestKit.step(_main)
	_run["marked"] = _crowned()
	_run["saved"] = SaveTestKit.save_game(_main).save_to_file(_path)
	# Done (the VIP made the flight): the crown goes on the next tick.
	_run["set_done"] = _set_vip(first, IncidentCatalogue.DONE)
	SaveTestKit.step(_main)
	_run["after_done"] = _crowned()
	# Another passenger marked, then the save with the first one marked loaded,
	# with no tick run after it (SaveTestKit.step leaves the clock paused).
	_run["set_second"] = _set_vip(second, IncidentCatalogue.ACCEPTED)
	SaveTestKit.step(_main)
	_run["before_load"] = _crowned()
	_run["loaded"] = SaveTestKit.save_game(_main).load_from_file(_path)
	_run["after_load"] = _crowned()


func after() -> void:
	if _main != null:
		_main.free()
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


## Puts one VIP incident marking `target` into the director in `state`, in
## place of any other, through the snapshot a load would give it.
func _set_vip(target: int, state: String) -> bool:
	var data := _director.to_snapshot()
	var p := _sim.get_passenger(target)
	var incident := {
		"id": data["next_id"],
		"kind": IncidentCatalogue.VIP,
		"roll_day": 1,
		"state": state,
		"fire_tick": 0,
		"cell": [-1, -1],
		"mess_id": 0,
		"place": "",
		"outcome": IncidentMajors.BONUS if state == IncidentCatalogue.DONE else "",
		"shown": false,
		"plan":
		{
			"flight": p.flight_id,
			"departs": 0,
			"bonus": IncidentTuning.VIP_BONUS_MONEY,
			"target": target,
			"good_mood": IncidentTuning.VIP_GOOD_MOOD,
			"miss_half_stars": IncidentTuning.VIP_MISS_HALF_STARS,
		},
	}
	data["incidents"] = [incident]
	data["next_id"] = int(data["next_id"]) + 1
	return _director.from_snapshot(data)


func _drawn_ids() -> Array[int]:
	var out: Array[int] = []
	for id in _sim.passenger_ids():
		if _views.node_for(id) != null:
			out.append(id)
	return out


## The drawn passengers whose crown is shown, as ids.
func _crowned() -> Array[int]:
	var out: Array[int] = []
	for id in _drawn_ids():
		var crown := _views.node_for(id).get_node(VipMarker.SPRITE) as Sprite3D
		if crown.visible:
			out.append(id)
	return out


func test_the_world_was_set_up() -> void:
	assert_int(_run["drawn"]).is_greater_equal(2)
	assert_bool(_run["set_first"]).is_true()
	assert_bool(_run["set_done"]).is_true()
	assert_bool(_run["set_second"]).is_true()
	assert_bool(_run["saved"]).is_true()
	assert_bool(_run["loaded"]).is_true()


func test_no_crown_shows_before_any_vip() -> void:
	assert_array(_run["before_any"]).is_empty()


func test_the_crown_shows_over_the_marked_passenger_only() -> void:
	assert_array(_run["marked"]).contains_exactly([_run["first"]])


func test_the_crown_goes_when_the_vip_incident_is_done() -> void:
	assert_array(_run["after_done"]).is_empty()


func test_a_load_shows_the_crown_over_the_loaded_vip_only() -> void:
	# Control: before the load the crown was over the second passenger.
	assert_array(_run["before_load"]).contains_exactly([_run["second"]])
	assert_bool(_main.get_node("SimClock").paused).is_true()
	assert_array(_run["after_load"]).contains_exactly([_run["first"]])


func test_the_crown_is_laid_out_over_the_head_with_its_texture() -> void:
	var node := _views.node_for(_run["first"])
	var crown := node.get_node(VipMarker.SPRITE) as Sprite3D
	assert_bool(node.get_meta(&"vip", false)).is_true()
	assert_float(crown.position.y).is_greater_equal(NeedIcons.LIFT_M)
	assert_object(crown.texture).is_same(VipMarker.texture())


func test_the_crown_texture_is_gold_inside_and_clear_outside() -> void:
	var img := VipMarker.texture().get_image()
	var half := VipMarker.SIZE / 2
	# Inside the band, above the navy band line: the gold fill.
	var fill := img.get_pixel(half, half + 4)
	assert_float(fill.a).is_equal_approx(1.0, 0.01)
	assert_float(fill.r).is_equal_approx(VipMarker.FILL.r, 0.02)
	assert_float(fill.g).is_equal_approx(VipMarker.FILL.g, 0.02)
	# A valley between two points is outside the crown.
	assert_float(img.get_pixel(half + 24, half - 20).a).is_equal(0.0)
	assert_float(img.get_pixel(1, 1).a).is_equal(0.0)


func test_marked_ids_reads_accepted_vips_with_a_target_only() -> void:
	assert_dict(VipMarker.marked_ids(null)).is_empty()
	var marked := VipMarker.marked_ids(_director)
	assert_dict(marked).contains_key_value(_run["first"], true)
	assert_int(marked.size()).is_equal(1)
