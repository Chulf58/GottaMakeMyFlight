class_name TestBirdScatterAudio
extends GdUnitTestSuite
## Procedural bird_scatter cue: Ambience bus routing, volume/mute respect,
## >= 4.5 s cooldown gating, and fast-forward / pause suppression.

const GAME_AUDIO := preload("res://audio/game_audio.gd")

var _audio: GAME_AUDIO
var _cfg_path := ""


func before_test() -> void:
	_audio = get_node("/root/GameAudio") as GAME_AUDIO
	_cfg_path = SaveTestKit.run_path("bird_scatter_audio").replace(".json", ".cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))
	_audio.reset_for_test()
	_audio.set_settings_path(_cfg_path)


func after_test() -> void:
	if _audio != null:
		_audio.reset_for_test()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))


func test_bird_scatter_routes_to_ambience_bus_and_gates_cooldown_and_suppression() -> void:
	var stream := _audio._sfx_streams.get(&"bird_scatter") as AudioStreamWAV
	assert_object(stream).is_not_null()
	assert_float(stream.get_length()).is_between(0.25, 0.50)

	var bird_player := _audio.get_node_or_null("BirdScatterPlayer") as AudioStreamPlayer
	assert_object(bird_player).is_not_null()
	assert_str(String(bird_player.bus)).is_equal("Ambience")
	assert_int(GAME_AUDIO.SFX_COOLDOWN_MS[&"bird_scatter"]).is_greater_equal(4500)

	var fake_now := [20000]
	_audio._clock_ms = func() -> int: return fake_now[0]
	assert_bool(_audio.play_bird_scatter()).is_true()
	assert_int(_audio.sfx_count(&"bird_scatter")).is_equal(1)
	assert_str(String(_audio.last_sfx())).is_equal("bird_scatter")

	fake_now[0] = 22000
	assert_bool(_audio.play_bird_scatter()).is_false()
	assert_int(_audio.sfx_count(&"bird_scatter")).is_equal(1)

	var amb_idx := AudioServer.get_bus_index(&"Ambience")
	_audio.set_ambience_volume(0.0, false)
	assert_bool(AudioServer.is_bus_mute(amb_idx)).is_true()
	_audio.set_ambience_volume(0.7, false)
	assert_bool(AudioServer.is_bus_mute(amb_idx)).is_false()
	_audio.set_muted(true)
	assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master"))).is_true()
	_audio.set_muted(false)

	fake_now[0] = 26000
	var clock := SimClock.new()
	clock.set_paused(false)
	clock.fast_forward_source = func() -> int: return 500
	clock.advance(SimClock.STEP)
	add_child(clock)
	assert_bool(_audio.play_bird_scatter()).is_false()
	clock.fast_forward_source = Callable()
	clock.fast_forward_until = -1
	clock.set_paused(true)
	assert_bool(_audio.play_bird_scatter()).is_false()
	clock.set_paused(false)
	assert_bool(_audio.play_bird_scatter()).is_true()
	assert_int(_audio.sfx_count(&"bird_scatter")).is_equal(2)
	clock.free()
