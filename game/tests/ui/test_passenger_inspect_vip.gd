class_name TestPassengerInspectVip
extends MajorTestBase
## The VIP's inspect card (board 884174ce, decision daily-incidents-small-ones-
## just-happen-with-a-card-and-a-cau): the passenger an accepted VIP incident
## marked says so, "VIP for today's 15:15 flight" from the incident's plan; any
## other passenger's card carries no such line.

var _views: PassengerViews
var _camera: TycoonCamera
var _hud: PassengerHud
var _inspect: PassengerInspect
var _settings := ""


func before_test() -> void:
	super.before_test()
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	_views.incidents = _director
	add_child(_views)
	_camera = TycoonCamera.new()
	var eye := Camera3D.new()
	eye.name = "Camera3D"
	_camera.add_child(eye)
	add_child(_camera)
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.views = _views
	_hud.camera = _camera
	_settings = SaveTestKit.run_path("passenger_inspect_vip_board")
	_hud.departures_settings_path = _settings
	add_child(_hud)
	_inspect = _hud.find_child("PassengerInspect", true, false) as PassengerInspect


func after_test() -> void:
	_hud.free()
	_camera.free()
	_views.free()
	DirAccess.remove_absolute(_settings)
	super.after_test()


## Selects a new passenger and refreshes the card; returns the passenger's id.
func _select_new() -> int:
	var id := _world.sim.spawn_now(VIP_FLIGHT)
	_world.step()
	_views.selected_id = id
	_hud.refresh()
	assert_bool(_inspect.visible).is_true()
	return id


func test_the_marked_passengers_card_says_they_are_the_vip() -> void:
	var departs := GameCalendar.tick_at(0, 15 * 60 + 15)
	var vip := _world.sim.spawn_now(VIP_FLIGHT)
	_accepted_vip(VIP_FLIGHT, {"target": vip, "departs": departs})
	_world.step()
	_views.selected_id = vip
	_hud.refresh()
	print(_inspect.vip_text())
	assert_bool(_inspect.visible).is_true()
	assert_str(_inspect.vip_text()).is_equal("VIP for today's 15:15 flight")


func test_another_passengers_card_carries_no_vip_line() -> void:
	var vip := _world.sim.spawn_now(VIP_FLIGHT)
	_accepted_vip(VIP_FLIGHT, {"target": vip})
	var other := _select_new()
	assert_int(other).is_not_equal(vip)
	assert_str(_inspect.vip_text()).is_equal("")


func test_the_line_goes_when_the_incident_ends() -> void:
	var vip := _world.sim.spawn_now(VIP_FLIGHT)
	var id := _accepted_vip(VIP_FLIGHT, {"target": vip})
	_world.step()
	_views.selected_id = vip
	_hud.refresh()
	assert_str(_inspect.vip_text()).is_not_equal("")
	var data := _director.to_snapshot()
	for saved: Dictionary in data["incidents"]:
		if saved["id"] == id:
			saved["state"] = IncidentCatalogue.DONE
	assert_bool(_director.from_snapshot(data)).is_true()
	_hud.refresh()
	assert_str(_inspect.vip_text()).is_equal("")
