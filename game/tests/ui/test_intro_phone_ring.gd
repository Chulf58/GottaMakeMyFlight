class_name TestIntroPhoneRing
extends GdUnitTestSuite
## Regression tests for ruling phone-ring-sfx-and-new-airport-intro-ring-
## procedural-phone-r (board ccf99062):
## - PassengerHud.open_intro() opens a brief bottom-centre ringing-phone cue
##   and plays phone_ring via GameAudio before IntroDialogue appears (intro() is
##   null on frame 0), keeping the clock and camera gated throughout.
## - Answering via click, Space or the auto-answer timer transitions cleanly
##   into IntroDialogue under the same clock hold.
## - Dismissing or loading a save while ringing cancels cleanly without leaks or
##   asking the new-game incident question.
## - UnlockGuide opening call plays phone_ring and shows PhoneRingCue cleanly.

var _port: SubViewport
var _world: PassengerTestWorld
var _hud: PassengerHud
var _shown_before: bool


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_shown_before = IntroDialogue.shown_this_session
	IntroDialogue.shown_this_session = false
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_method(&"reset_for_test"):
		audio.reset_for_test()
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.alert_settings_path = SaveTestKit.run_path("intro_ring_alerts")
	_hud.departures_settings_path = SaveTestKit.run_path("intro_ring_dep")
	_port.add_child(_hud)


func after_test() -> void:
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_method(&"reset_for_test"):
		audio.reset_for_test()
	DirAccess.remove_absolute(_hud.alert_settings_path)
	DirAccess.remove_absolute(_hud.departures_settings_path)
	_port.free()
	_world.free_all()
	IntroDialogue.shown_this_session = _shown_before


func _ring_cue() -> IntroDialogue.PhoneRingCue:
	return _hud.find_child("PhoneRingCue", true, false) as IntroDialogue.PhoneRingCue


func test_open_intro_starts_ring_beat_before_dialogue_and_click_answers() -> void:
	var cam := TycoonCamera.new()
	var eye := Camera3D.new()
	eye.name = "Camera3D"
	cam.add_child(eye)
	_port.add_child(cam)
	_hud.camera = cam
	assert_bool(_world.clock.paused).is_false()
	assert_bool(_hud.open_intro()).is_true()

	# Frame 0: ringing icon visible bottom-centre, SFX triggered, IntroDialogue not yet open.
	assert_object(_hud.intro()).is_null()
	var cue := _ring_cue()
	assert_object(cue).is_not_null()
	assert_bool(cue.is_ringing()).is_true()
	assert_bool(cue.is_visible_in_tree()).is_true()
	assert_object(cue.phone_icon().texture).is_not_null()
	var rect := cue.get_global_rect()
	assert_float(rect.get_center().x).is_equal_approx(640.0, 2.0)
	assert_float(rect.end.y).is_less_equal(720.0 - BuildMenu.MARGIN - BuildMenu.BAR_H)
	assert_bool(_world.clock.paused).is_true()
	assert_int(_world.clock.holds.count()).is_equal(1)
	assert_bool(cam.is_processing()).is_false()
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_method(&"sfx_count"):
		assert_int(audio.sfx_count(&"phone_ring")).is_equal(1)

	# Answering via button press transitions into IntroDialogue under the same clock hold.
	cue.answer_button().pressed.emit()
	assert_bool(cue.is_ringing()).is_false()
	assert_object(_hud.intro()).is_not_null()
	assert_bool(_world.clock.paused).is_true()
	assert_int(_world.clock.holds.count()).is_equal(1)
	assert_bool(cam.is_processing()).is_false()

	_hud.dismiss_intro()
	assert_object(_hud.intro()).is_null()
	assert_bool(_world.clock.paused).is_false()
	assert_int(_world.clock.holds.count()).is_equal(0)
	assert_bool(cam.is_processing()).is_true()


func test_space_answers_ringing_phone_without_closing_or_unpausing() -> void:
	assert_bool(_hud.open_intro()).is_true()
	assert_object(_hud.intro()).is_null()
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	_port.push_input(key)
	assert_object(_hud.intro()).is_not_null()
	assert_bool(_world.clock.paused).is_true()
	_hud.dismiss_intro()
	assert_bool(_world.clock.paused).is_false()


func test_ring_timer_auto_answers_into_intro_dialogue() -> void:
	assert_bool(_hud.open_intro()).is_true()
	assert_object(_hud.intro()).is_null()
	await get_tree().create_timer(IntroDialogue.PhoneRingCue.RING_DURATION_S + 0.15).timeout
	assert_object(_hud.intro()).is_not_null()
	assert_bool(_world.clock.paused).is_true()
	assert_int(_world.clock.holds.count()).is_equal(1)
	_hud.dismiss_intro()
	assert_bool(_world.clock.paused).is_false()
	assert_int(_world.clock.holds.count()).is_equal(0)


func test_dismiss_and_save_load_while_ringing_clean_up_without_asking_incidents() -> void:
	var save := SaveGame.new()
	_port.add_child(save)
	var menu := GameMenu.new()
	menu.name = "GameMenu"
	menu.clock = _world.clock
	_port.add_child(menu)
	_hud.save_game = save
	_hud._game_menu = menu

	# Dismiss while ringing releases hold and does not open ask_incidents.
	assert_bool(_hud.open_intro()).is_true()
	assert_object(_ring_cue()).is_not_null()
	_hud.dismiss_intro()
	assert_object(_hud.intro()).is_null()
	assert_bool(menu.is_question_open()).is_false()
	assert_bool(_world.clock.paused).is_false()
	assert_int(_world.clock.holds.count()).is_equal(0)

	# Save load while ringing cleans up cue, layer and hold cleanly.
	IntroDialogue.shown_this_session = false
	await await_idle_frame()
	assert_bool(_hud.open_intro()).is_true()
	assert_bool(_world.clock.paused).is_true()
	_world.clock.holds.clear()
	_world.clock.set_paused(true)
	_hud._on_save_loaded(true)
	await await_idle_frame()
	assert_object(_ring_cue()).is_null()
	assert_object(_hud.intro()).is_null()
	assert_int(_hud._camera_gates).is_equal(0)
	assert_int(_world.clock.holds.count()).is_equal(0)


func test_unlock_guide_opening_call_rings_audio_and_shows_icon() -> void:
	var rating: AirportRating = auto_free(AirportRating.new())
	var unlocks := BuildUnlocks.new()
	unlocks.rating = rating
	unlocks.passengers = _world.sim
	unlocks.manual = true
	_port.add_child(unlocks)
	var gate := AirportGate.new()
	gate.flights = _world.flights
	gate.staff = _world.staff
	_port.add_child(gate)
	var guide := UnlockGuide.new()
	guide.mode = UnlockGuide.Mode.PROFILE
	guide.unlocks = unlocks
	guide.clock = _world.clock
	guide.gate = gate
	guide.flights = _world.flights
	_port.add_child(guide)
	assert_bool(gate.open()).is_true()
	assert_bool(guide.is_open()).is_true()
	var cue := guide.ring_cue()
	assert_object(cue).is_not_null()
	assert_bool(cue.is_ringing()).is_true()
	assert_bool(cue.is_visible_in_tree()).is_true()
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_method(&"sfx_count"):
		assert_int(audio.sfx_count(&"phone_ring")).is_equal(1)
	guide.dismiss()
	assert_bool(cue.is_ringing()).is_false()


func test_boot_load_skips_intro_ring_without_latching_session() -> void:
	assert_bool(IntroDialogue.should_show(false, true, false, true)).is_false()
	assert_bool(IntroDialogue.should_show(false, true, false, false)).is_true()

	var save_path := SaveTestKit.run_path("boot_load_no_ring")
	var alerts_path := SaveTestKit.run_path("boot_load_alerts")
	var dep_path := SaveTestKit.run_path("boot_load_dep")
	var source := SaveTestKit.boot(self, 19_112_027)
	assert_bool(SaveTestKit.save_game(source).save_to_file(save_path)).is_true()
	source.free()

	var audio := get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_method(&"reset_for_test"):
		audio.reset_for_test()

	var prev_scene := get_tree().current_scene
	var prev_load := GameBoot.load_path
	var host := Node.new()
	get_tree().root.add_child(host)
	get_tree().current_scene = host
	GameBoot.start_load(save_path, func(_scene: String) -> Error: return OK)
	var main := (load(GameBoot.MAIN_SCENE) as PackedScene).instantiate()
	var hud := main.get_node("PassengerHud") as PassengerHud
	hud.alert_settings_path = alerts_path
	hud.departures_settings_path = dep_path
	(main.get_node("SimClock") as SimClock).seed_rng(19_112_027)
	host.add_child(main)
	await await_idle_frame()
	await await_idle_frame()

	assert_bool(hud._in_current_scene()).is_true()
	assert_object(hud.find_child("PhoneRingCue", true, false)).is_null()
	assert_object(hud.intro()).is_null()
	assert_bool(IntroDialogue.shown_this_session).is_false()
	if audio != null and audio.has_method(&"sfx_count"):
		assert_int(audio.sfx_count(&"phone_ring")).is_equal(0)

	get_tree().current_scene = prev_scene
	GameBoot.load_path = prev_load
	host.free()
	for path in [save_path, save_path + ".tmp", alerts_path, dep_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
