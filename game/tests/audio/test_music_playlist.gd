class_name TestMusicPlaylist
extends GdUnitTestSuite
## 5-track cozy procedural music playlist, shuffle-without-back-to-back-repeat,
## ambient breather timer between tracks, gentle fade-in, and independent Music
## vs Ambience AudioServer bus/slider isolation.

const GAME_AUDIO := preload("res://audio/game_audio.gd")

var _audio: GAME_AUDIO
var _cfg_path := ""


func before_test() -> void:
	_audio = get_node("/root/GameAudio") as GAME_AUDIO
	_cfg_path = SaveTestKit.run_path("music_playlist").replace(".json", ".cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))
	_audio.reset_for_test()
	_audio.set_settings_path(_cfg_path)


func after_test() -> void:
	if _audio != null:
		_audio.reset_for_test()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))


func test_five_music_tracks_and_ambience_bed_import_with_expected_lengths_and_loops() -> void:
	var paths := _audio.music_playlist_paths()
	assert_int(paths.size()).is_equal(5)
	for path: String in paths:
		var ogg := load(path) as AudioStreamOggVorbis
		assert_object(ogg).override_failure_message("Missing track %s" % path).is_not_null()
		assert_bool(ogg.loop).is_false()
		assert_float(ogg.get_length()).is_between(75.0, 100.0)

	var amb := load(GAME_AUDIO.AMBIENCE_PATH) as AudioStreamOggVorbis
	assert_object(amb).is_not_null()
	assert_bool(amb.loop).is_true()
	assert_float(amb.get_length()).is_between(18.0, 32.0)


func test_playlist_shuffles_without_repeats_and_uses_breather_pause() -> void:
	var paths := _audio.music_playlist_paths()
	var mode := BuildMode.new()
	add_child(mode)
	var music_player := _audio.get_node("MusicPlayer") as AudioStreamPlayer
	var breather := _audio.get_node("MusicBreatherTimer") as Timer
	assert_object(music_player).is_not_null()
	assert_object(breather).is_not_null()
	assert_str(String(music_player.bus)).is_equal("Music")
	assert_bool(_audio.is_music_playing()).is_true()
	assert_bool(_audio.is_ambience_playing()).is_true()
	var first_track := _audio.current_music_track()
	assert_bool(paths.has(first_track)).is_true()

	# Track finish enters ambient breather pause (4..8 s) while ambience continues.
	music_player.stop()
	music_player.finished.emit()
	assert_bool(_audio.is_in_music_breather()).is_true()
	assert_bool(_audio.is_ambience_playing()).is_true()
	assert_float(breather.wait_time).is_between(
		GAME_AUDIO.MUSIC_BREATHER_MIN_S, GAME_AUDIO.MUSIC_BREATHER_MAX_S
	)

	# Breather timeout starts a different track.
	breather.stop()
	breather.timeout.emit()
	assert_bool(_audio.is_in_music_breather()).is_false()
	assert_bool(_audio.is_music_playing()).is_true()
	var second_track := _audio.current_music_track()
	assert_str(second_track).is_not_equal(first_track)

	# 40 transitions never repeat back-to-back and visit all 5 tracks.
	var seen := {}
	seen[second_track] = true
	var prev := second_track
	for _i in 40:
		var nxt := _audio.next_music_track()
		assert_str(nxt).is_not_equal(prev)
		assert_bool(paths.has(nxt)).is_true()
		seen[nxt] = true
		prev = nxt
	assert_int(seen.size()).is_equal(5)

	mode.free()
	assert_bool(_audio.is_music_playing()).is_false()
	assert_bool(_audio.is_in_music_breather()).is_false()


func test_music_and_ambience_buses_and_sliders_are_independent() -> void:
	var music_idx := AudioServer.get_bus_index(&"Music")
	var amb_idx := AudioServer.get_bus_index(&"Ambience")
	assert_int(music_idx).is_greater(0)
	assert_int(amb_idx).is_greater(0)
	assert_int(music_idx).is_not_equal(amb_idx)

	_audio.set_music_volume(0.0, false)
	_audio.set_ambience_volume(0.75, false)
	assert_bool(AudioServer.is_bus_mute(music_idx)).is_true()
	assert_bool(AudioServer.is_bus_mute(amb_idx)).is_false()

	_audio.set_music_volume(0.65, false)
	_audio.set_ambience_volume(0.0, false)
	assert_bool(AudioServer.is_bus_mute(music_idx)).is_false()
	assert_bool(AudioServer.is_bus_mute(amb_idx)).is_true()
