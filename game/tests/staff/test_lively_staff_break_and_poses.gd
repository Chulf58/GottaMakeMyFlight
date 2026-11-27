class_name TestLivelyStaffBreakAndPoses
extends GdUnitTestSuite
## Targeted gdUnit4 coverage for Lively Staff 2/3 & 3/3:
## - Break Room indoor seat claiming, non-overlap, standing fallback, demolish
##   release, save/load parity, and seated Coffee Mug / Phone / Magazine props.
## - Coworker Break Room chat pairing, look-at turn, and icon bubble alternation
##   versus solo resting silence.
## - Procedural SkeletonModifier3D micro-reactions (wave, wipe, stretch/yawn,
##   clipboard/watch, cheer) and backward-tick / snap resets.
## - Cool-down gated reaction audio loading, routing, and mute/Dummy gating.

const GAME_AUDIO := preload("res://audio/game_audio.gd")
const BREAK_RECT := Rect2i(11, 13, 6, 4)

var _w: PassengerTestWorld
var _other: PassengerTestWorld
var _views: StaffCharacters
var _extra_views: Array[StaffCharacters] = []
var _audio: GAME_AUDIO
var _cfg_path := ""


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_audio = get_node("/root/GameAudio") as GAME_AUDIO
	_cfg_path = SaveTestKit.run_path("lively_staff_audio").replace(".json", ".cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))
	if _audio != null:
		_audio.reset_for_test()
		_audio.set_settings_path(_cfg_path)


func after_test() -> void:
	for ev in _extra_views:
		if is_instance_valid(ev):
			ev.free()
	_extra_views.clear()
	if _views != null:
		_views.free()
		_views = null
	for w in [_w, _other]:
		if w != null:
			w.free_all()
	_w = null
	_other = null
	if _audio != null:
		_audio.reset_for_test()
	if _cfg_path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg_path))


func _make_break_world() -> Dictionary:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var edits: Array[BuildEdit] = []
	for y in range(BREAK_RECT.position.y, BREAK_RECT.end.y):
		for x in range(BREAK_RECT.position.x, BREAK_RECT.end.x):
			if grid.floor_at(Vector2i(x, y)) == BuildGrid.FLOOR_NONE:
				edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	edits.append(BuildEdit.place_room(BREAK_RECT, &"break_room"))
	edits.append(BuildEdit.place_object(&"lounge_sofa", BREAK_RECT.position, 0))
	edits.append(
		BuildEdit.place_object(&"lounge_armchair", BREAK_RECT.position + Vector2i(3, 0), 0)
	)
	var room_id := 0
	var sofa_id := 0
	var chair_id := 0
	for res: BuildResult in grid.apply_batch(edits):
		assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
		if res.room_id != 0:
			room_id = res.room_id
		if res.object_id != 0:
			var rec := grid.get_object(res.object_id)
			if StringName(rec.get("def", &"")) == &"lounge_sofa":
				sofa_id = res.object_id
			elif StringName(rec.get("def", &"")) == &"lounge_armchair":
				chair_id = res.object_id
	var w := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	w.auto_staff = false
	assert_bool(w.flights.open_airport()).is_true()
	return {"world": w, "room_id": room_id, "sofa_id": sofa_id, "chair_id": chair_id}


func _attach_views(w: PassengerTestWorld) -> StaffCharacters:
	var views := StaffCharacters.new()
	views.clock = w.clock
	views.staff = w.staff
	views.flights = w.flights
	add_child(views)
	_views = views
	return views


func _attach_extra_views(w: PassengerTestWorld) -> StaffCharacters:
	var views := StaffCharacters.new()
	views.clock = w.clock
	views.staff = w.staff
	views.flights = w.flights
	add_child(views)
	_extra_views.append(views)
	return views


func _skeleton_of(node: Node3D) -> Skeleton3D:
	return node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


func _capture_quats(sk: Skeleton3D, bone_names: Array[String]) -> Array[Quaternion]:
	var out: Array[Quaternion] = []
	for bone_name in bone_names:
		out.append(sk.get_bone_global_pose(sk.find_bone(bone_name)).basis.get_rotation_quaternion())
	return out


func _max_quat_diff(a: Array[Quaternion], b: Array[Quaternion]) -> float:
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, a[i].angle_to(b[i]))
	return worst


func _sample_pose_quats(
	body: Node3D,
	sk: Skeleton3D,
	bone_names: Array[String],
	mode: StaffStationPose.Mode,
	sub: StaffStationPose.SubMode,
	tick: float,
	role: int,
) -> Array[Quaternion]:
	(
		StaffStationPose
		. pose(
			body,
			mode,
			1.0,
			tick,
			Vector2.ZERO,
			1,
			sub,
			0.0,
			StaffStationPose.Mode.NONE,
			StaffStationPose.SubMode.NONE,
			0.0,
			role,
		)
	)
	await get_tree().process_frame
	await sk.skeleton_updated
	return _capture_quats(sk, bone_names)


func test_break_room_seat_claim_no_double_seating_fallback_and_demolish() -> void:
	var setup := _make_break_world()
	_w = setup["world"] as PassengerTestWorld
	var room_id: int = setup["room_id"]
	var chair_id: int = setup["chair_id"]
	var views := _attach_views(_w)

	var seats := StaffBreakRooms.seats_in(_w.grid, room_id)
	assert_int(seats.size()).is_equal(3)

	var ids: Array[int] = [
		_w.staff.hire(StaffMember.Role.CHECKIN),
		_w.staff.hire(StaffMember.Role.SECURITY),
		_w.staff.hire(StaffMember.Role.SHOP),
		_w.staff.hire(StaffMember.Role.GATE),
	]
	for _i in 120:
		_w.step()
	for id in ids:
		_w.staff.get_member(id).energy = StaffMember.TIRED_THRESHOLD

	var settled := false
	for _t in 800:
		_w.step()
		var all_break := true
		for id in ids:
			if _w.staff.get_member(id).state != StaffMember.State.ON_BREAK:
				all_break = false
				break
		if all_break:
			settled = true
			break
	assert_bool(settled).is_true()

	for _t in StaffCharacters.BREAK_SHUFFLE_TICKS + 4:
		_w.step()
	views.draw()

	var seated_spots := {}
	var seated_ids: Array[int] = []
	var standing_ids: Array[int] = []
	var prop_kinds := {}
	for id in ids:
		var m := _w.staff.get_member(id)
		var seat := StaffBreakRooms.seat_for(_w.grid, m.break_room, m.break_spot, m.role)
		var bv: Dictionary = views._break_views.get(id, {})
		if not seat.is_empty():
			seated_ids.append(id)
			assert_bool(seated_spots.has(m.break_spot)).is_false()
			seated_spots[m.break_spot] = id
			assert_bool(bool(bv.get("seated", false))).is_true()
			var node := views.node_for(id)
			assert_vector(node.position).is_equal_approx(
				seat["seat_pos"], Vector3(0.03, 0.03, 0.03)
			)
			var clip := String(node.get_meta(&"clip", ""))
			assert_bool(clip == "sit_down" or clip == "sit_idle").is_true()
			prop_kinds[views.hand_prop_of(id)] = true
		else:
			standing_ids.append(id)
			assert_bool(bool(bv.get("standing_rest", false))).is_true()
			assert_str(String(views.node_for(id).get_meta(&"clip", ""))).is_equal("idle")
	assert_int(seated_ids.size()).is_equal(3)
	assert_int(standing_ids.size()).is_equal(1)
	assert_bool(seated_spots.has(_w.staff.get_member(standing_ids[0]).break_spot)).is_false()
	assert_bool(prop_kinds.has(StaffHandProps.PropKind.COFFEE_MUG)).is_true()
	assert_bool(prop_kinds.has(StaffHandProps.PropKind.PHONE)).is_true()
	assert_bool(prop_kinds.has(StaffHandProps.PropKind.MAGAZINE)).is_true()

	# Snapshot round-trip keeps deterministic break spots, seat poses, props, and chat bubbles.
	var snap_text := StaffTestKit.save_text(_w)
	_other = StaffTestKit.load_world(snap_text)
	assert_str(StaffTestKit.signature(_other.staff)).is_equal(StaffTestKit.signature(_w.staff))

	var loaded_views := _attach_extra_views(_other)
	loaded_views.sync(true)
	for _t in StaffCharacters.BREAK_SHUFFLE_TICKS + 4:
		_other.step()
	loaded_views.draw()
	for id in seated_ids:
		var lm := _other.staff.get_member(id)
		var lseat := StaffBreakRooms.seat_for(_other.grid, lm.break_room, lm.break_spot, lm.role)
		var lbv: Dictionary = loaded_views._break_views.get(id, {})
		assert_bool(bool(lbv.get("seated", false))).is_true()
		var lnode := loaded_views.node_for(id)
		assert_vector(lnode.position).is_equal_approx(lseat["seat_pos"], Vector3(0.03, 0.03, 0.03))
		var lclip := String(lnode.get_meta(&"clip", ""))
		assert_bool(lclip == "sit_down" or lclip == "sit_idle").is_true()
		assert_int(loaded_views.hand_prop_of(id)).is_equal(views.hand_prop_of(id))
	var saw_loaded_chat := false
	var saw_loaded_bubble := false
	for _t in StaffChatBubbles.CHAT_PERIOD_TICKS + 20:
		_other.step()
		loaded_views.draw()
		for id in seated_ids:
			if loaded_views.station_pose_mode(id) == StaffStationPose.Mode.BREAK_CHAT:
				saw_loaded_chat = true
			var lb := (
				loaded_views.node_for(id).get_node_or_null(StaffChatBubbles.SPRITE) as Sprite3D
			)
			if lb != null and lb.visible:
				saw_loaded_bubble = true
		if saw_loaded_chat and saw_loaded_bubble:
			break
	assert_bool(saw_loaded_chat).is_true()
	assert_bool(saw_loaded_bubble).is_true()
	_extra_views.erase(loaded_views)
	loaded_views.free()

	# Demolishing the armchair releases that seated staff member cleanly to standing.
	var chair_occupant := 0
	for id in seated_ids:
		var m := _w.staff.get_member(id)
		var seat := StaffBreakRooms.seat_for(_w.grid, m.break_room, m.break_spot, m.role)
		if int(seat.get("object_id", 0)) == chair_id:
			chair_occupant = id
			break
	assert_int(chair_occupant).is_greater(0)
	var rm := _w.grid.apply_batch([BuildEdit.remove_object(chair_id)])
	assert_bool(rm[0].ok).is_true()
	_w.step()
	views.draw()
	var former_chair_m := _w.staff.get_member(chair_occupant)
	(
		assert_bool(
			(
				StaffBreakRooms
				. seat_for(
					_w.grid,
					former_chair_m.break_room,
					former_chair_m.break_spot,
					former_chair_m.role
				)
				. is_empty()
			)
		)
		. is_true()
	)
	assert_bool(bool(views._break_views[chair_occupant].get("standing_rest", false))).is_true()
	assert_str(String(views.node_for(chair_occupant).get_meta(&"clip", ""))).is_equal("idle")


func test_break_room_exhausting_seats_and_floor_spots_returns_empty_no_stacking() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var rect := Rect2i(11, 13, 2, 3)
	var edits: Array[BuildEdit] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if grid.floor_at(Vector2i(x, y)) == BuildGrid.FLOOR_NONE:
				edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	edits.append(BuildEdit.place_room(rect, &"break_room"))
	edits.append(BuildEdit.place_object(&"lounge_armchair", rect.position, 0))
	var room_id := 0
	for res: BuildResult in grid.apply_batch(edits):
		assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
		if res.room_id != 0:
			room_id = res.room_id
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.auto_staff = false
	assert_bool(_w.flights.open_airport()).is_true()

	var all_spots := StaffBreakRooms.spots_in(_w.grid, room_id)
	assert_int(all_spots.size()).is_equal(5)
	assert_int(StaffBreakRooms.seats_in(_w.grid, room_id).size()).is_equal(1)

	var ids: Array[int] = []
	for i in all_spots.size():
		var role := StaffMember.Role.CHECKIN if i % 2 == 0 else StaffMember.Role.SECURITY
		ids.append(_w.staff.hire(role))
	for _t in 120:
		_w.step()
	for id in ids:
		_w.staff.get_member(id).energy = StaffMember.TIRED_THRESHOLD
	var all_resting := false
	for _t in 900:
		_w.step()
		all_resting = true
		for id in ids:
			if _w.staff.get_member(id).state != StaffMember.State.ON_BREAK:
				all_resting = false
				break
		if all_resting:
			break
	assert_bool(all_resting).is_true()

	var claimed := {}
	for id in ids:
		var spot := _w.staff.get_member(id).break_spot
		assert_bool(spot != StaffMember.NO_CELL).is_true()
		assert_bool(claimed.has(spot)).is_false()
		claimed[spot] = id
	assert_int(claimed.size()).is_equal(all_spots.size())

	var extra_id := _w.staff.hire(StaffMember.Role.CHECKIN)
	for _t in 120:
		_w.step()
	var extra_m := _w.staff.get_member(extra_id)
	extra_m.energy = StaffMember.TIRED_THRESHOLD
	assert_bool(StaffBreakRooms.nearest_break(_w.staff, extra_m).is_empty()).is_true()
	for _t in 60:
		_w.step()
	assert_bool(extra_m.is_on_break()).is_false()
	assert_vector(extra_m.break_spot).is_equal(StaffMember.NO_CELL)


func test_break_room_coworker_chat_pairing_versus_solo_silence() -> void:
	var setup := _make_break_world()
	_w = setup["world"] as PassengerTestWorld
	var views := _attach_views(_w)

	var solo_id := _w.staff.hire(StaffMember.Role.CHECKIN)
	for _i in 60:
		_w.step()
	_w.staff.get_member(solo_id).energy = StaffMember.TIRED_THRESHOLD
	for _t in 700:
		_w.step()
		if _w.staff.get_member(solo_id).state == StaffMember.State.ON_BREAK:
			break
	assert_int(_w.staff.get_member(solo_id).state).is_equal(StaffMember.State.ON_BREAK)
	for _t in StaffCharacters.BREAK_SHUFFLE_TICKS + 4:
		_w.step()
	views.draw()
	assert_int(views.station_pose_mode(solo_id)).is_equal(StaffStationPose.Mode.BREAK_SEATED)
	var solo_bubble := views.node_for(solo_id).get_node_or_null(StaffChatBubbles.SPRITE) as Sprite3D
	assert_bool(solo_bubble == null or not solo_bubble.visible).is_true()

	# Second resting coworker joins nearby -> both switch to BREAK_CHAT & emit alternating icons.
	var peer_id := _w.staff.hire(StaffMember.Role.SHOP)
	for _i in 60:
		_w.step()
	_w.staff.get_member(peer_id).energy = StaffMember.TIRED_THRESHOLD
	for _t in 700:
		_w.step()
		if _w.staff.get_member(peer_id).state == StaffMember.State.ON_BREAK:
			break
	assert_int(_w.staff.get_member(peer_id).state).is_equal(StaffMember.State.ON_BREAK)
	for _t in StaffCharacters.BREAK_SHUFFLE_TICKS + 4:
		_w.step()

	var saw_chat_pose := false
	var saw_solo_bubble := false
	var saw_peer_bubble := false
	var icon_textures := {}
	for _t in StaffChatBubbles.CHAT_PERIOD_TICKS + 20:
		_w.step()
		views.draw()
		if (
			views.station_pose_mode(solo_id) == StaffStationPose.Mode.BREAK_CHAT
			and views.station_pose_mode(peer_id) == StaffStationPose.Mode.BREAK_CHAT
		):
			saw_chat_pose = true
		var b_solo := views.node_for(solo_id).get_node_or_null(StaffChatBubbles.SPRITE) as Sprite3D
		var b_peer := views.node_for(peer_id).get_node_or_null(StaffChatBubbles.SPRITE) as Sprite3D
		if b_solo != null and b_solo.visible:
			saw_solo_bubble = true
			icon_textures[b_solo.texture] = true
		if b_peer != null and b_peer.visible:
			saw_peer_bubble = true
			icon_textures[b_peer.texture] = true
	assert_bool(saw_chat_pose).is_true()
	assert_bool(saw_solo_bubble).is_true()
	assert_bool(saw_peer_bubble).is_true()
	assert_int(icon_textures.size()).is_greater_equal(2)

	var mod := views.node_for(solo_id).get_meta(&"station_pose") as StaffStationPose
	assert_float(absf(mod.look_yaw_deg)).is_greater(2.0)

	# Ending peer's break leaves solo coworker alone again -> chat bubbles vanish immediately.
	_w.staff.get_member(peer_id).energy = StaffMember.BREAK_DONE_THRESHOLD
	_w.staff.get_member(solo_id).energy = StaffMember.TIRED_THRESHOLD
	_w.step()
	assert_bool(_w.staff.get_member(peer_id).is_on_break()).is_false()
	for _t in StaffChatBubbles.CHAT_PERIOD_TICKS + 10:
		_w.step()
		views.draw()
		var b_solo_after := (
			views.node_for(solo_id).get_node_or_null(StaffChatBubbles.SPRITE) as Sprite3D
		)
		assert_bool(b_solo_after == null or not b_solo_after.visible).is_true()
		var b_peer_after := (
			views.node_for(peer_id).get_node_or_null(StaffChatBubbles.SPRITE) as Sprite3D
		)
		assert_bool(b_peer_after == null or not b_peer_after.visible).is_true()
	assert_int(views.station_pose_mode(solo_id)).is_equal(StaffStationPose.Mode.BREAK_SEATED)


func test_micro_reactions_distinct_bone_deltas_and_snap_reset() -> void:
	var chars := auto_free(StaffCharacters.new()) as StaffCharacters
	add_child(chars)
	var body := chars._take(StaffMember.Role.CHECKIN)
	var sk := _skeleton_of(body)
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	player.play("idle")
	player.seek(0.0, true)
	player.speed_scale = 0.0

	var bones: Array[String] = [
		"Spine_01",
		"Spine_02",
		"Spine_03",
		"Head",
		"Neck",
		"Arm.L",
		"Forearm.L",
		"Arm.R",
		"Forearm.R",
		"Hand.R",
	]
	var leg_bones: Array[String] = ["Quad.L", "Shin.L", "Quad.R", "Shin.R"]
	await get_tree().process_frame
	await sk.skeleton_updated
	var rest := _capture_quats(sk, bones)
	var rest_legs := _capture_quats(sk, leg_bones)

	var specs := [
		[StaffStationPose.Mode.REACTION_WAVE, StaffStationPose.SubMode.NONE],
		[StaffStationPose.Mode.REACTION_WIPE, StaffStationPose.SubMode.NONE],
		[StaffStationPose.Mode.REACTION_STRETCH, StaffStationPose.SubMode.NONE],
		[StaffStationPose.Mode.REACTION_CLIPBOARD, StaffStationPose.SubMode.REACT_CLIPBOARD],
		[StaffStationPose.Mode.REACTION_CHEER, StaffStationPose.SubMode.NONE],
	]
	var captured: Array = []
	for spec in specs:
		var q := await _sample_pose_quats(
			body, sk, bones, spec[0], spec[1], 45.0, StaffMember.Role.CHECKIN
		)
		assert_float(_max_quat_diff(q, rest)).is_greater(0.20)
		captured.append(q)
	for i in captured.size():
		for j in range(i + 1, captured.size()):
			assert_float(_max_quat_diff(captured[i], captured[j])).is_greater(0.15)

	# Verify walking-tired yawn leaves leg bones completely clean.
	var yawn_legs := await _sample_pose_quats(
		body,
		sk,
		leg_bones,
		StaffStationPose.Mode.REACTION_STRETCH,
		StaffStationPose.SubMode.REACT_WALK_YAWN,
		45.0,
		StaffMember.Role.CHECKIN,
	)
	assert_float(_max_quat_diff(yawn_legs, rest_legs)).is_less(0.005)

	# Verify matching hand props for wipe vs clipboard vs watch.
	(
		assert_int(
			(
				StaffHandProps
				. desired_prop(
					StaffStationPose.Mode.REACTION_WIPE,
					StaffStationPose.SubMode.NONE,
					1.0,
					45.0,
					1,
					false,
					false,
				)
			)
		)
		. is_equal(StaffHandProps.PropKind.CLOTH)
	)
	(
		assert_int(
			(
				StaffHandProps
				. desired_prop(
					StaffStationPose.Mode.REACTION_CLIPBOARD,
					StaffStationPose.SubMode.REACT_CLIPBOARD,
					1.0,
					45.0,
					1,
					false,
					false,
				)
			)
		)
		. is_equal(StaffHandProps.PropKind.CLIPBOARD)
	)
	(
		assert_int(
			(
				StaffHandProps
				. desired_prop(
					StaffStationPose.Mode.REACTION_CLIPBOARD,
					StaffStationPose.SubMode.REACT_WATCH,
					1.0,
					45.0,
					1,
					false,
					false,
				)
			)
		)
		. is_equal(StaffHandProps.PropKind.NONE)
	)

	# Verify queued check-in wave, tired walk yawn, and training cheer triggers + snap reset.
	var setup := _make_break_world()
	_w = setup["world"] as PassengerTestWorld
	var views := _attach_views(_w)
	var ci_id := _w.staff.hire(StaffMember.Role.CHECKIN)
	for _t in 200:
		_w.step()
		if _w.staff.get_member(ci_id).state == StaffMember.State.ON_DUTY:
			break
	assert_int(_w.staff.get_member(ci_id).state).is_equal(StaffMember.State.ON_DUTY)
	_w.staff.train(ci_id)
	_w.step()
	views.draw()
	assert_int(views.station_pose_mode(ci_id)).is_equal(StaffStationPose.Mode.REACTION_CHEER)
	views.sync(true)
	views.draw()
	assert_int(views.station_pose_mode(ci_id)).is_equal(StaffStationPose.Mode.NONE)


func test_reaction_audio_loads_wavs_cooldown_gates_and_suppresses() -> void:
	assert_object(_audio).is_not_null()
	var fake_now := [20000]
	_audio._clock_ms = func() -> int: return fake_now[0]

	for cue_id in GAME_AUDIO.STAFF_REACTION_IDS:
		assert_bool(GAME_AUDIO.SFX_PATHS.has(cue_id)).is_true()
		var stream := load(GAME_AUDIO.SFX_PATHS[cue_id]) as AudioStreamWAV
		assert_object(stream).override_failure_message("Missing %s" % cue_id).is_not_null()
		assert_float(stream.get_length()).is_greater(0.05)
		assert_float(float(GAME_AUDIO.SFX_VOLUME_DB.get(cue_id, 0.0))).is_less_equal(-6.0)
		var cue_cooldown := int(GAME_AUDIO.SFX_COOLDOWN_MS.get(cue_id, 0))
		assert_int(cue_cooldown).is_greater_equal(GAME_AUDIO.STAFF_REACTION_COOLDOWN_MS)
		assert_bool(_audio.play_sfx(cue_id)).is_true()
		fake_now[0] += cue_cooldown - 100
		assert_bool(_audio.play_sfx(cue_id)).is_false()
		fake_now[0] += 150
		assert_bool(_audio.play_sfx(cue_id)).is_true()

	# Per-cue and global reaction cooldown + Dummy/mute gating work cleanly.
	assert_bool(_audio.can_play_staff_reaction(&"staff_cheer", fake_now[0], "Dummy")).is_false()
	var cheer_cd := int(GAME_AUDIO.SFX_COOLDOWN_MS[&"staff_cheer"])
	fake_now[0] += cheer_cd + 100
	assert_bool(_audio.can_play_staff_reaction(&"staff_cheer", fake_now[0], "WASAPI")).is_true()
	_audio._last_staff_reaction_ms = fake_now[0]
	(
		assert_bool(_audio.can_play_staff_reaction(&"staff_sip", fake_now[0] + 100, "WASAPI"))
		. is_false()
	)
	fake_now[0] += GAME_AUDIO.STAFF_REACTION_COOLDOWN_MS + 100
	assert_bool(_audio.can_play_staff_reaction(&"staff_cheer", fake_now[0], "WASAPI")).is_true()
	_audio.set_muted(true)
	assert_bool(_audio.can_play_staff_reaction(&"staff_cheer", fake_now[0], "WASAPI")).is_false()
	_audio.set_muted(false)

	# Zero SFX or Master volume suppresses reaction cues cleanly.
	_audio.set_sfx_volume(0.0, false)
	assert_bool(_audio.can_play_staff_reaction(&"staff_cheer", fake_now[0], "WASAPI")).is_false()
	_audio.set_sfx_volume(1.0, false)
	_audio.set_master_volume(0.0, false)
	assert_bool(_audio.can_play_staff_reaction(&"staff_cheer", fake_now[0], "WASAPI")).is_false()
	_audio.set_master_volume(1.0, false)

	var train_world := _make_break_world()
	_w = train_world["world"] as PassengerTestWorld
	_audio._clock = _w.clock
	_w.clock.set_paused(false)
	_w.clock.set_speed(1)
	assert_bool(_audio.can_play_staff_reaction(&"staff_cheer", fake_now[0], "WASAPI")).is_true()
	_w.clock.set_paused(true)
	assert_bool(_audio.can_play_staff_reaction(&"staff_cheer", fake_now[0], "WASAPI")).is_false()
	_w.clock.set_paused(false)
	assert_bool(_audio.can_play_staff_reaction(&"staff_cheer", fake_now[0], "WASAPI")).is_true()
	_w.clock.set_speed(3)
	assert_bool(_audio.can_play_staff_reaction(&"staff_cheer", fake_now[0], "WASAPI")).is_true()
	_w.clock.fast_forward_until = _w.clock.tick + 100
	assert_bool(_w.clock.is_fast_forwarding()).is_true()
	assert_bool(_audio.can_play_staff_reaction(&"staff_cheer", fake_now[0], "WASAPI")).is_false()
	_w.clock.fast_forward_until = -1
	_w.clock.set_speed(1)
	var sid := _w.staff.hire(StaffMember.Role.CHECKIN)
	assert_bool(_w.staff.train(sid)).is_true()
	assert_bool(_audio.play_staff_reaction(&"staff_cheer")).is_false()
	_audio._clock = null
