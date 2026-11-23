class_name TestUnlockGuideCameraGate
extends GdUnitTestSuite
## PassengerHud holds the camera still while a dialog is open and counts the
## opens (dialog_changed(true)) against the closes. A guide dialog swapped in
## place for a queued first must stay one open and one close, or one gate stays
## and the camera is dead for the rest of the game. The guide and the panel are
## wired to the real HUD's gate as the HUD wires them in the main scene.

var _world: PassengerTestWorld
var _hud: PassengerHud
var _camera: TycoonCamera
var _host: Node
var _clock: SimClock
var _director: MajorTestDirector
var _unlocks: BuildUnlocks
var _guide: UnlockGuide
var _panel: IncidentPanel
var _save: SaveGame


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_world.flights.open_airport()
	_clock = _world.clock
	_host = Node.new()
	add_child(_host)
	_camera = TycoonCamera.new()
	var eye := Camera3D.new()
	eye.name = "Camera3D"
	_camera.add_child(eye)
	_host.add_child(_camera)
	_hud = PassengerHud.new()
	_hud.clock = _clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.camera = _camera
	_hud.alert_settings_path = SaveTestKit.run_path("guide_gate_alerts")
	_hud.departures_settings_path = SaveTestKit.run_path("guide_gate_departures")
	_host.add_child(_hud)
	_director = MajorTestDirector.new()
	_host.add_child(_director)
	_unlocks = BuildUnlocks.new()
	_unlocks.rating = auto_free(AirportRating.new())
	_unlocks.passengers = _world.sim
	_unlocks.manual = true
	_host.add_child(_unlocks)
	_save = SaveGame.new()
	_host.add_child(_save)
	_guide = UnlockGuide.new()
	_guide.mode = UnlockGuide.Mode.PROFILE
	_guide.unlocks = _unlocks
	_guide.clock = _clock
	_guide.director = _director
	_guide.save_game = _save
	_guide.dialog_changed.connect(_hud._gate_camera)
	_host.add_child(_guide)
	_panel = IncidentPanel.new()
	_panel.director = _director
	_panel.clock = _clock
	_panel.copy_for = MajorTestDirector.copy
	_panel.dialog_changed.connect(_hud._gate_camera)
	_host.add_child(_panel)


func after_test() -> void:
	DirAccess.remove_absolute(_hud.alert_settings_path)
	DirAccess.remove_absolute(_hud.departures_settings_path)
	_host.free()
	_world.free_all()


## A tier dialog is open when a major comes, so the first replaces it in place.
func _swap_in_the_first() -> void:
	_guide.open_dialog([2])
	_guide.answer_ring()
	assert_bool(_director.present(_director.add_scheduled(), false)).is_true()
	_guide.dismiss()
	assert_bool(_guide.is_open()).is_true()


func test_the_camera_gate_is_back_to_zero_after_a_swap_and_the_notice() -> void:
	_swap_in_the_first()
	assert_int(_hud._camera_gates).is_equal(1)
	assert_bool(_camera.is_processing()).is_false()
	_guide.dismiss()
	assert_bool(_panel.is_open()).is_true()
	assert_int(_hud._camera_gates).is_equal(1)
	_panel.dialog().dismiss()
	assert_int(_hud._camera_gates).is_equal(0)
	assert_bool(_camera.is_processing()).is_true()


func test_the_camera_gate_is_back_to_zero_after_a_load_with_the_swapped_dialog_open() -> void:
	_swap_in_the_first()
	assert_int(_hud._camera_gates).is_equal(1)
	# What SaveGame.load_world() leaves before it emits loaded.
	_clock.holds.clear()
	_clock.set_paused(true)
	_clock.set_speed(1)
	_save.loaded.emit(true)
	assert_bool(_guide.is_open()).is_false()
	assert_int(_hud._camera_gates).is_equal(0)
	assert_bool(_camera.is_processing()).is_true()


func test_the_camera_gate_is_back_to_zero_after_a_load_while_ringing() -> void:
	_guide.open_dialog([2])
	assert_bool(_guide.is_ringing()).is_true()
	assert_int(_hud._camera_gates).is_equal(1)
	assert_bool(_camera.is_processing()).is_false()
	_clock.holds.clear()
	_clock.set_paused(true)
	_clock.set_speed(1)
	_save.loaded.emit(true)
	assert_bool(_guide.is_open()).is_false()
	assert_bool(_guide.is_ringing()).is_false()
	assert_int(_hud._camera_gates).is_equal(0)
	assert_bool(_camera.is_processing()).is_true()
