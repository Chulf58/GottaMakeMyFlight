extends Node
## The demo audio floor autoload (decisions demo-audio-floor-d5-cozy-terminal-
## ambience-loop-light-tactil and demo-audio-pa-announcer-and-sound-jokes-
## e612caf3-procedural): ensures the Master, Ambience and SFX buses exist,
## loads and saves per-bus linear volumes and mute state in
## user://audio_settings.cfg (shielded during script/test runs just like
## HudFlagSetting, so tests never read or overwrite the player's config), loops
## cozy terminal ambience while a gameplay scene (BuildMode) is in the tree,
## plays tactile UI/build/cash/gameplay/joke SFX on a fixed child pool, and
## emits warm PA chimes paired with translated dry announcements via
## pa_announced with cooldowns and load/fast-forward suppression.

signal changed
signal pa_announced(text: String)

const DEFAULT_SETTINGS_PATH := "user://audio_settings.cfg"
const SECTION := "audio"
const BUS_MASTER := &"Master"
const BUS_AMBIENCE := &"Ambience"
const BUS_SFX := &"SFX"
const DEFAULT_MASTER := 0.8
const DEFAULT_AMBIENCE := 0.7
const DEFAULT_SFX := 0.8
const DEFAULT_MUTED := false
const MIN_LINEAR := 0.0001
const POOL_SIZE := 8
const PA_COOLDOWN_MS := 7500
const PA_PRIORITY_COOLDOWN_MS := 2500
const FINAL_CALL_POLL_TICKS := 10
const FINAL_CALL_LEAD_TICKS := 300
const STAR_MILESTONES: Array[float] = [3.0, 4.0, 5.0]

const AMBIENCE_PATH := "res://assets/audio/terminal_ambience.wav"
const SFX_PATHS := {
	&"ui_click": "res://assets/audio/ui_click.wav",
	&"build_place": "res://assets/audio/build_place.wav",
	&"build_remove": "res://assets/audio/build_remove.wav",
	&"build_refuse": "res://assets/audio/build_refuse.wav",
	&"cash_chime": "res://assets/audio/cash_chime.wav",
	&"security_beep": "res://assets/audio/security_beep.wav",
	&"pa_chime": "res://assets/audio/pa_chime.wav",
	&"pa_final_call": "res://assets/audio/pa_final_call.wav",
	&"close_call_save": "res://assets/audio/close_call_save.wav",
	&"joke_spill": "res://assets/audio/joke_spill.wav",
	&"joke_fault": "res://assets/audio/joke_fault.wav",
	&"joke_queue_horn": "res://assets/audio/joke_queue_horn.wav",
	&"star_up": "res://assets/audio/star_up.wav",
}
const SFX_COOLDOWN_MS := {
	&"ui_click": 25,
	&"build_place": 45,
	&"build_remove": 45,
	&"build_refuse": 80,
	&"cash_chime": 450,
	&"security_beep": 1400,
	&"pa_chime": 7000,
	&"pa_final_call": 7000,
	&"close_call_save": 4500,
	&"joke_spill": 4000,
	&"joke_fault": 4000,
	&"joke_queue_horn": 15000,
	&"star_up": 6000,
}

## Shielded settings path during -s / --script runs (anti-pattern 1639342a).
var protected_path := DEFAULT_SETTINGS_PATH
var settings_path := DEFAULT_SETTINGS_PATH
var master_volume := DEFAULT_MASTER
var ambience_volume := DEFAULT_AMBIENCE
var sfx_volume := DEFAULT_SFX
var muted := DEFAULT_MUTED
var save_count := 0

var _ambience_player: AudioStreamPlayer
var _ambience_playing := false
var _pa_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_streams: Dictionary = {}
var _sfx_cursor := 0
var _last_sfx: StringName = &""
var _sfx_counts: Dictionary = {}
var _last_played_ms: Dictionary = {}
var _gameplay_nodes: Array[Node] = []
var _desk_open_ids: Dictionary = {}
var _desks_by_id: Dictionary = {}
var _clock: SimClock
var _flights: FlightSim
var _passengers: PassengerSim
var _incidents: IncidentDirector
var _rating: AirportRating
var _save_game: SaveGame
var _suppress_events := false
var _last_pa_ms := -1
var _last_final_call_check_tick := -FINAL_CALL_POLL_TICKS
var _prev_stage: Dictionary = {}
var _announced_boarding: Dictionary = {}
var _announced_final_call: Dictionary = {}
var _close_call_flights: Dictionary = {}
var _close_call_counts: Dictionary = {}
var _last_rating_stars := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()
	_setup_players()
	load_settings(settings_path)
	get_tree().node_added.connect(_on_node_added)
	_scan_existing(get_tree().root)


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


## Ensures Master, Ambience and SFX buses exist on AudioServer and send to Master.
func ensure_buses() -> void:
	_ensure_bus(BUS_AMBIENCE)
	_ensure_bus(BUS_SFX)


## Redirects persistence to `path` and loads from it immediately.
func set_settings_path(path: String) -> void:
	settings_path = path
	load_settings(path)


## Reads volumes and mute state from `path` (or defaults when missing/shielded).
func load_settings(path: String = settings_path) -> void:
	settings_path = path
	ensure_buses()
	master_volume = DEFAULT_MASTER
	ambience_volume = DEFAULT_AMBIENCE
	sfx_volume = DEFAULT_SFX
	muted = DEFAULT_MUTED
	if not _is_shielded(path):
		var cfg := ConfigFile.new()
		var err := cfg.load(path)
		if err == OK:
			master_volume = clampf(
				float(cfg.get_value(SECTION, "master_volume", DEFAULT_MASTER)), 0.0, 1.0
			)
			ambience_volume = clampf(
				float(cfg.get_value(SECTION, "ambience_volume", DEFAULT_AMBIENCE)), 0.0, 1.0
			)
			sfx_volume = clampf(float(cfg.get_value(SECTION, "sfx_volume", DEFAULT_SFX)), 0.0, 1.0)
			muted = bool(cfg.get_value(SECTION, "muted", DEFAULT_MUTED))
		elif err != ERR_FILE_NOT_FOUND:
			push_error("GameAudio: cannot read %s (error %d)" % [path, err])
	_apply_buses()
	changed.emit()


## Persists current volumes and mute state to `settings_path` unless shielded.
func save_settings() -> void:
	if _is_shielded(settings_path):
		return
	var cfg := ConfigFile.new()
	var err := cfg.load(settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_error("GameAudio: cannot read %s (error %d)" % [settings_path, err])
		return
	cfg.set_value(SECTION, "master_volume", master_volume)
	cfg.set_value(SECTION, "ambience_volume", ambience_volume)
	cfg.set_value(SECTION, "sfx_volume", sfx_volume)
	cfg.set_value(SECTION, "muted", muted)
	err = cfg.save(settings_path)
	if err != OK:
		push_error("GameAudio: cannot write %s (error %d)" % [settings_path, err])
		return
	save_count += 1


## Restores default buses, paths, counters, cooldowns and PA tracking for tests.
func reset_for_test() -> void:
	protected_path = DEFAULT_SETTINGS_PATH
	settings_path = DEFAULT_SETTINGS_PATH
	save_count = 0
	_last_sfx = &""
	_sfx_counts.clear()
	_last_played_ms.clear()
	_suppress_events = false
	_last_pa_ms = -1
	_last_final_call_check_tick = -FINAL_CALL_POLL_TICKS
	_prev_stage.clear()
	_announced_boarding.clear()
	_announced_final_call.clear()
	_close_call_flights.clear()
	_close_call_counts.clear()
	_last_rating_stars = -1.0
	for player in _sfx_players:
		player.stop()
	if _pa_player != null:
		_pa_player.stop()
	load_settings(DEFAULT_SETTINGS_PATH)
	_sync_ambience()


func set_master_volume(value: float, persist := true) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_buses()
	if persist:
		save_settings()
	changed.emit()


func set_ambience_volume(value: float, persist := true) -> void:
	ambience_volume = clampf(value, 0.0, 1.0)
	_apply_buses()
	if persist:
		save_settings()
	changed.emit()


func set_sfx_volume(value: float, persist := true) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_buses()
	if persist:
		save_settings()
	changed.emit()


func set_muted(value: bool) -> void:
	muted = value
	_apply_buses()
	save_settings()
	changed.emit()


func is_ambience_playing() -> bool:
	return _ambience_playing and _ambience_player != null and _ambience_player.playing


## Plays `sfx_id` on the SFX bus when off cooldown; returns true when triggered.
func play_sfx(sfx_id: StringName, ignore_cooldown := false) -> bool:
	if not _sfx_streams.has(sfx_id) or _sfx_players.is_empty():
		return false
	var now := Time.get_ticks_msec()
	var cooldown := int(SFX_COOLDOWN_MS.get(sfx_id, 0))
	if not ignore_cooldown and _last_played_ms.has(sfx_id):
		if now - int(_last_played_ms[sfx_id]) < cooldown:
			return false
	_last_played_ms[sfx_id] = now
	var player := _sfx_players[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_players.size()
	player.stream = _sfx_streams[sfx_id]
	player.play()
	_last_sfx = sfx_id
	_sfx_counts[sfx_id] = int(_sfx_counts.get(sfx_id, 0)) + 1
	return true


func last_sfx() -> StringName:
	return _last_sfx


func sfx_count(sfx_id: StringName) -> int:
	return int(_sfx_counts.get(sfx_id, 0))


func _is_shielded(path: String) -> bool:
	return path == protected_path and Hints.launched_by_script(OS.get_cmdline_args())


func _is_fast_forwarding() -> bool:
	return is_instance_valid(_clock) and _clock.is_fast_forwarding()


func _is_paused() -> bool:
	return is_instance_valid(_clock) and _clock.paused


func _can_announce_pa() -> bool:
	if muted or master_volume <= MIN_LINEAR or sfx_volume <= MIN_LINEAR:
		return false
	return not _is_fast_forwarding() and not _is_paused()


func _play_sim_sfx(sfx_id: StringName) -> bool:
	if _suppress_events or _is_fast_forwarding():
		return false
	return play_sfx(sfx_id)


func _announce_pa(chime_id: StringName, text: String, priority := false) -> bool:
	if text == "" or _suppress_events or not _can_announce_pa():
		return false
	var now := Time.get_ticks_msec()
	var cooldown := PA_PRIORITY_COOLDOWN_MS if priority else PA_COOLDOWN_MS
	if _last_pa_ms >= 0 and now - _last_pa_ms < cooldown:
		return false
	if chime_id != &"" and not _play_on_pa_player(chime_id, now):
		return false
	_last_pa_ms = now
	pa_announced.emit(text)
	return true


func _play_on_pa_player(chime_id: StringName, now: int) -> bool:
	if not _sfx_streams.has(chime_id) or _pa_player == null:
		return false
	var cooldown := int(SFX_COOLDOWN_MS.get(chime_id, 0))
	if _last_played_ms.has(chime_id) and now - int(_last_played_ms[chime_id]) < cooldown:
		return false
	_last_played_ms[chime_id] = now
	_pa_player.stream = _sfx_streams[chime_id]
	_pa_player.play()
	_last_sfx = chime_id
	_sfx_counts[chime_id] = int(_sfx_counts.get(chime_id, 0)) + 1
	return true


func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, String(bus_name))
	AudioServer.set_bus_send(idx, BUS_MASTER)


func _apply_buses() -> void:
	ensure_buses()
	_set_bus_level(BUS_MASTER, master_volume, muted or master_volume <= MIN_LINEAR)
	_set_bus_level(BUS_AMBIENCE, ambience_volume, ambience_volume <= MIN_LINEAR)
	_set_bus_level(BUS_SFX, sfx_volume, sfx_volume <= MIN_LINEAR)


func _set_bus_level(bus_name: StringName, linear: float, bus_muted: bool) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, bus_muted)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, MIN_LINEAR)))


func _setup_players() -> void:
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "AmbiencePlayer"
	_ambience_player.bus = BUS_AMBIENCE
	var ambience := load(AMBIENCE_PATH) as AudioStreamWAV
	if ambience != null:
		var looped := ambience.duplicate() as AudioStreamWAV
		looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
		looped.loop_begin = 0
		if looped.loop_end <= 0:
			looped.loop_end = int(round(looped.get_length() * float(looped.mix_rate)))
		_ambience_player.stream = looped
	add_child(_ambience_player)
	for id: StringName in SFX_PATHS:
		var stream := load(SFX_PATHS[id]) as AudioStream
		if stream != null:
			_sfx_streams[id] = stream
	_pa_player = AudioStreamPlayer.new()
	_pa_player.name = "PAPlayer"
	_pa_player.bus = BUS_SFX
	add_child(_pa_player)
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer%d" % i
		player.bus = BUS_SFX
		add_child(player)
		_sfx_players.append(player)


func _scan_existing(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_scan_existing(child)


func _on_node_added(node: Node) -> void:
	if node == self or is_ancestor_of(node):
		return
	if node is BaseButton:
		var btn := node as BaseButton
		if not btn.pressed.is_connected(_on_button_pressed):
			btn.pressed.connect(_on_button_pressed)
		return
	if node is BuildMode:
		_when_ready(node, _bind_build_mode.bind(node))
	elif node is Finances:
		_when_ready(node, _bind_finances.bind(node))
	elif node is FlightSim:
		_when_ready(node, _bind_flight_sim.bind(node))
	elif node is OfferDesk:
		_when_ready(node, _bind_offer_desk.bind(node))
	elif node is SimClock:
		_when_ready(node, _bind_clock.bind(node))
	elif node is PassengerSim:
		_when_ready(node, _bind_passenger_sim.bind(node))
	elif node is IncidentDirector:
		_when_ready(node, _bind_incident_director.bind(node))
	elif node is AirportRating:
		_when_ready(node, _bind_airport_rating.bind(node))
	elif node is AlertStack:
		_when_ready(node, _bind_alert_stack.bind(node))
	elif node is SaveGame:
		_when_ready(node, _bind_save_game.bind(node))


func _when_ready(node: Node, callback: Callable) -> void:
	if node.is_node_ready():
		callback.call()
	elif not node.ready.is_connected(callback):
		node.ready.connect(callback, CONNECT_ONE_SHOT)


func _bind_build_mode(mode: BuildMode) -> void:
	if not is_instance_valid(mode) or not mode.is_inside_tree():
		return
	if not _gameplay_nodes.has(mode):
		_gameplay_nodes.append(mode)
		var on_exit := _on_gameplay_exited.bind(mode)
		if not mode.tree_exiting.is_connected(on_exit):
			mode.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)
		_sync_ambience()
	if mode.grid == null:
		return
	if not mode.grid.edit_applied.is_connected(_on_edit_applied):
		mode.grid.edit_applied.connect(_on_edit_applied)
	if not mode.grid.edit_refused.is_connected(_on_edit_refused):
		mode.grid.edit_refused.connect(_on_edit_refused)


func _on_gameplay_exited(mode: Node) -> void:
	_gameplay_nodes.erase(mode)
	_sync_ambience()


func _sync_ambience() -> void:
	for i in range(_gameplay_nodes.size() - 1, -1, -1):
		if not is_instance_valid(_gameplay_nodes[i]) or not _gameplay_nodes[i].is_inside_tree():
			_gameplay_nodes.remove_at(i)
	var should_play := not _gameplay_nodes.is_empty()
	if _ambience_player == null:
		_ambience_playing = false
		return
	if should_play and not _ambience_player.playing:
		_ambience_player.play()
		_ambience_playing = true
	elif not should_play and _ambience_player.playing:
		_ambience_player.stop()
		_ambience_playing = false
	else:
		_ambience_playing = should_play and _ambience_player.playing


func _bind_finances(finances: Finances) -> void:
	if not is_instance_valid(finances) or finances.wallet == null:
		return
	if not finances.wallet.transaction.is_connected(_on_wallet_transaction):
		finances.wallet.transaction.connect(_on_wallet_transaction)


func _bind_clock(clock: SimClock) -> void:
	if not is_instance_valid(clock) or not clock.is_inside_tree():
		return
	if (
		is_instance_valid(_clock)
		and _clock != clock
		and _clock.ticked.is_connected(_on_clock_ticked)
	):
		_clock.ticked.disconnect(_on_clock_ticked)
	_clock = clock
	_last_final_call_check_tick = -FINAL_CALL_POLL_TICKS
	if not clock.ticked.is_connected(_on_clock_ticked):
		clock.ticked.connect(_on_clock_ticked)
	var on_exit := _on_clock_exited.bind(clock)
	if not clock.tree_exiting.is_connected(on_exit):
		clock.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)


func _on_clock_exited(clock: SimClock) -> void:
	if is_instance_valid(clock) and clock.ticked.is_connected(_on_clock_ticked):
		clock.ticked.disconnect(_on_clock_ticked)
	if _clock == clock:
		_clock = null
		_last_final_call_check_tick = -FINAL_CALL_POLL_TICKS


func _bind_flight_sim(flights: FlightSim) -> void:
	if not is_instance_valid(flights) or not flights.is_inside_tree():
		return
	_flights = flights
	_seed_flights(flights)
	var on_state := _on_flight_state.bind(flights)
	if not flights.state_changed.is_connected(on_state):
		flights.state_changed.connect(on_state)
	var on_loaded := _on_snapshot_loaded.bind(flights)
	if not flights.snapshot_loaded.is_connected(on_loaded):
		flights.snapshot_loaded.connect(on_loaded)
	var on_exit := _on_flight_sim_exited.bind(flights)
	if not flights.tree_exiting.is_connected(on_exit):
		flights.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)


func _on_flight_sim_exited(flights: FlightSim) -> void:
	if is_instance_valid(flights):
		var on_state := _on_flight_state.bind(flights)
		if flights.state_changed.is_connected(on_state):
			flights.state_changed.disconnect(on_state)
		var on_loaded := _on_snapshot_loaded.bind(flights)
		if flights.snapshot_loaded.is_connected(on_loaded):
			flights.snapshot_loaded.disconnect(on_loaded)
	if _flights == flights:
		_flights = null
		_announced_boarding.clear()
		_announced_final_call.clear()


func _bind_passenger_sim(sim: PassengerSim) -> void:
	if not is_instance_valid(sim) or not sim.is_inside_tree():
		return
	_passengers = sim
	_seed_passengers(sim)
	var on_stage := _on_passenger_stage_changed.bind(sim)
	if not sim.stage_changed.is_connected(on_stage):
		sim.stage_changed.connect(on_stage)
	var on_outcome := _on_passenger_outcome.bind(sim)
	if not sim.outcome.is_connected(on_outcome):
		sim.outcome.connect(on_outcome)
	var on_exit := _on_passenger_sim_exited.bind(sim)
	if not sim.tree_exiting.is_connected(on_exit):
		sim.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)


func _on_passenger_sim_exited(sim: PassengerSim) -> void:
	if is_instance_valid(sim):
		var on_stage := _on_passenger_stage_changed.bind(sim)
		if sim.stage_changed.is_connected(on_stage):
			sim.stage_changed.disconnect(on_stage)
		var on_outcome := _on_passenger_outcome.bind(sim)
		if sim.outcome.is_connected(on_outcome):
			sim.outcome.disconnect(on_outcome)
	if _passengers == sim:
		_passengers = null
		_prev_stage.clear()
		_close_call_flights.clear()
		_close_call_counts.clear()


func _bind_incident_director(director: IncidentDirector) -> void:
	if not is_instance_valid(director) or not director.is_inside_tree():
		return
	_incidents = director
	if not director.started.is_connected(_on_incident_started):
		director.started.connect(_on_incident_started)
	if not director.major_presented.is_connected(_on_incident_major_presented):
		director.major_presented.connect(_on_incident_major_presented)
	if not director.restored.is_connected(_on_incidents_restored):
		director.restored.connect(_on_incidents_restored)
	var on_exit := _on_incident_director_exited.bind(director)
	if not director.tree_exiting.is_connected(on_exit):
		director.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)


func _on_incident_director_exited(director: IncidentDirector) -> void:
	if is_instance_valid(director):
		if director.started.is_connected(_on_incident_started):
			director.started.disconnect(_on_incident_started)
		if director.major_presented.is_connected(_on_incident_major_presented):
			director.major_presented.disconnect(_on_incident_major_presented)
		if director.restored.is_connected(_on_incidents_restored):
			director.restored.disconnect(_on_incidents_restored)
	if _incidents == director:
		_incidents = null


func _bind_airport_rating(rating: AirportRating) -> void:
	if not is_instance_valid(rating) or not rating.is_inside_tree():
		return
	_rating = rating
	_last_rating_stars = rating.stars() if rating.has_data() else -1.0
	var on_changed := _on_rating_changed.bind(rating)
	if not rating.changed.is_connected(on_changed):
		rating.changed.connect(on_changed)
	var on_exit := _on_airport_rating_exited.bind(rating)
	if not rating.tree_exiting.is_connected(on_exit):
		rating.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)


func _on_airport_rating_exited(rating: AirportRating) -> void:
	if is_instance_valid(rating):
		var on_changed := _on_rating_changed.bind(rating)
		if rating.changed.is_connected(on_changed):
			rating.changed.disconnect(on_changed)
	if _rating == rating:
		_rating = null
		_last_rating_stars = -1.0


func _bind_alert_stack(stack: AlertStack) -> void:
	if not is_instance_valid(stack) or not stack.is_inside_tree():
		return
	if not stack.alert_raised.is_connected(_on_alert_raised):
		stack.alert_raised.connect(_on_alert_raised)
	var on_exit := _on_alert_stack_exited.bind(stack)
	if not stack.tree_exiting.is_connected(on_exit):
		stack.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)


func _on_alert_stack_exited(stack: AlertStack) -> void:
	if is_instance_valid(stack) and stack.alert_raised.is_connected(_on_alert_raised):
		stack.alert_raised.disconnect(_on_alert_raised)


func _bind_save_game(save_game: SaveGame) -> void:
	if not is_instance_valid(save_game) or not save_game.is_inside_tree():
		return
	_save_game = save_game
	if not save_game.loaded.is_connected(_on_save_loaded):
		save_game.loaded.connect(_on_save_loaded)
	var on_exit := _on_save_game_exited.bind(save_game)
	if not save_game.tree_exiting.is_connected(on_exit):
		save_game.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)


func _on_save_game_exited(save_game: SaveGame) -> void:
	if is_instance_valid(save_game) and save_game.loaded.is_connected(_on_save_loaded):
		save_game.loaded.disconnect(_on_save_loaded)
	if _save_game == save_game:
		_save_game = null


func _bind_offer_desk(desk: OfferDesk) -> void:
	if not is_instance_valid(desk) or desk.board == null:
		return
	var id := desk.get_instance_id()
	_desk_open_ids[id] = _open_offer_ids(desk.board)
	_desks_by_id[id] = desk
	var on_changed := _on_board_changed.bind(desk)
	if not desk.board.changed.is_connected(on_changed):
		desk.board.changed.connect(on_changed)
	var on_exit := _on_desk_exited.bind(id)
	if not desk.tree_exiting.is_connected(on_exit):
		desk.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)


func _on_desk_exited(desk_id: int) -> void:
	_desk_open_ids.erase(desk_id)
	_desks_by_id.erase(desk_id)


func _open_offer_ids(board: OfferBoard) -> Array[String]:
	var ids: Array[String] = []
	for offer in board.open_offers():
		ids.append(String(offer["id"]))
	return ids


func _on_board_changed(desk: OfferDesk) -> void:
	if not is_instance_valid(desk) or desk.board == null:
		return
	var id := desk.get_instance_id()
	var before: Array = _desk_open_ids.get(id, [])
	var now := _open_offer_ids(desk.board)
	_desk_open_ids[id] = now
	if _suppress_events:
		return
	for offer_id: String in before:
		if not now.has(offer_id):
			var rec := desk.board.offer_of(offer_id)
			if rec.get("status", "") == OfferBoard.ACCEPTED:
				play_sfx(&"cash_chime")
				return


func _on_button_pressed() -> void:
	play_sfx(&"ui_click")


func _on_edit_applied(edit: BuildEdit, _result: BuildResult) -> void:
	if edit == null or edit.kind == BuildEdit.Kind.RESHAPE_BELT:
		return
	var removals := [
		BuildEdit.Kind.REMOVE_FLOOR,
		BuildEdit.Kind.REMOVE_WALL,
		BuildEdit.Kind.REMOVE_OBJECT,
		BuildEdit.Kind.REMOVE_ROOM,
	]
	if removals.has(edit.kind):
		play_sfx(&"build_remove")
	else:
		play_sfx(&"build_place")


func _on_edit_refused(_edit: BuildEdit, _result: BuildResult) -> void:
	play_sfx(&"build_refuse")


func _on_clock_ticked(tick: int) -> void:
	if not is_instance_valid(_flights):
		return
	if (
		tick >= _last_final_call_check_tick
		and tick - _last_final_call_check_tick < FINAL_CALL_POLL_TICKS
	):
		return
	_last_final_call_check_tick = tick
	if _suppress_events or not _can_announce_pa():
		return
	for flight_id in _flights.flight_ids():
		if _flights.state_of(flight_id) != FlightSim.State.BOARDING:
			continue
		if _announced_final_call.has(flight_id):
			continue
		var window := _flights.boarding_window(flight_id)
		if window.y >= 0 and window.y - tick <= FINAL_CALL_LEAD_TICKS:
			_announced_final_call[flight_id] = true
			_announce_pa(&"pa_final_call", PaWords.final_call(_flights, flight_id), true)


func _on_flight_state(flight_id: String, new_state: int, flights: FlightSim) -> void:
	if _suppress_events or _is_fast_forwarding():
		return
	if new_state == FlightSim.State.DEPARTED:
		play_sfx(&"cash_chime")
	elif new_state == FlightSim.State.BOARDING:
		if not _announced_boarding.has(flight_id):
			_announced_boarding[flight_id] = true
			_announce_pa(&"pa_chime", PaWords.boarding(flights, flight_id), false)


func _on_snapshot_loaded(flights: FlightSim) -> void:
	_suppress_events = true
	_seed_flights(flights)
	_seed_state()
	call_deferred("_end_suppress")


func _on_incidents_restored() -> void:
	_suppress_events = true
	_seed_state()
	call_deferred("_end_suppress")


func _on_save_loaded(_ok: bool) -> void:
	_end_suppress()


func _end_suppress() -> void:
	_seed_state()
	_suppress_events = false


func _seed_state() -> void:
	if is_instance_valid(_flights):
		_seed_flights(_flights)
	if is_instance_valid(_passengers):
		_seed_passengers(_passengers)
	if is_instance_valid(_rating):
		_last_rating_stars = _rating.stars() if _rating.has_data() else -1.0
	for desk_id: int in _desks_by_id.keys():
		var desk := _desks_by_id[desk_id] as OfferDesk
		if is_instance_valid(desk) and desk.board != null:
			_desk_open_ids[desk_id] = _open_offer_ids(desk.board)
	_last_final_call_check_tick = (
		_clock.tick if is_instance_valid(_clock) else -FINAL_CALL_POLL_TICKS
	)


func _seed_flights(flights: FlightSim) -> void:
	_announced_boarding.clear()
	_announced_final_call.clear()
	for flight_id in flights.flight_ids():
		var state := flights.state_of(flight_id)
		if state >= FlightSim.State.BOARDING:
			_announced_boarding[flight_id] = true
		if state > FlightSim.State.BOARDING:
			_announced_final_call[flight_id] = true
		elif state == FlightSim.State.BOARDING:
			var window := flights.boarding_window(flight_id)
			if window.y >= 0 and window.y - flights.tick <= FINAL_CALL_LEAD_TICKS:
				_announced_final_call[flight_id] = true


func _seed_passengers(sim: PassengerSim) -> void:
	_prev_stage.clear()
	_close_call_flights.clear()
	_close_call_counts.clear()
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if p != null:
			_prev_stage[id] = p.stage
	for flight_id: String in sim.flight_results.keys():
		var cc := int(sim.flight_results[flight_id].get("close_calls", 0))
		_close_call_counts[flight_id] = cc
		if cc > 0:
			_close_call_flights[flight_id] = true


func _on_passenger_stage_changed(id: int, stage: Passenger.Stage, _sim: PassengerSim) -> void:
	var prev: int = _prev_stage.get(id, -1)
	_prev_stage[id] = stage
	if prev == Passenger.Stage.SECURITY and stage == Passenger.Stage.TO_GATE:
		_play_sim_sfx(&"security_beep")


func _on_passenger_outcome(id: int, made: bool, sim: PassengerSim) -> void:
	_prev_stage.erase(id)
	if not made or _suppress_events or _is_fast_forwarding() or not is_instance_valid(sim):
		return
	var p := sim.get_passenger(id)
	if p == null or p.flight_id == "":
		return
	var res: Dictionary = sim.flight_results.get(p.flight_id, {})
	var cc := int(res.get("close_calls", 0))
	var prev_cc := int(_close_call_counts.get(p.flight_id, 0))
	_close_call_counts[p.flight_id] = cc
	var doors_close := _flights.doors_close_tick(p.flight_id) if is_instance_valid(_flights) else -1
	var within_ticks := (
		p.outcome_tick >= 0
		and doors_close >= 0
		and doors_close - p.outcome_tick <= PassengerLifecycle.CLOSE_CALL_TICKS
	)
	if (cc > prev_cc or within_ticks) and not _close_call_flights.has(p.flight_id):
		_close_call_flights[p.flight_id] = true
		play_sfx(&"close_call_save")
		_announce_pa(&"", PaWords.close_call(_flights, p.flight_id), false)


func _on_incident_started(incident: Dictionary) -> void:
	if _suppress_events or _is_fast_forwarding():
		return
	var kind := String(incident.get("kind", ""))
	if kind == IncidentCatalogue.SPILL:
		play_sfx(&"joke_spill")
		_announce_pa(&"", PaWords.spill(), true)
	elif kind == IncidentCatalogue.FAULT:
		play_sfx(&"joke_fault")
		_announce_pa(&"", PaWords.fault(), true)


func _on_incident_major_presented(incident: Dictionary) -> void:
	if _suppress_events or _is_fast_forwarding():
		return
	var kind := String(incident.get("kind", ""))
	if kind == IncidentCatalogue.RUSH:
		_announce_pa(&"pa_chime", PaWords.rush(), true)


func _on_rating_changed(rating: AirportRating) -> void:
	if not is_instance_valid(rating) or not rating.has_data():
		_last_rating_stars = -1.0
		return
	var current := rating.stars()
	var prev := _last_rating_stars
	_last_rating_stars = current
	if _suppress_events or _is_fast_forwarding() or prev < 0.0:
		return
	var crossed := false
	for milestone in STAR_MILESTONES:
		if prev < milestone and current >= milestone:
			crossed = true
	if crossed:
		play_sfx(&"star_up")
		_announce_pa(&"", PaWords.star_milestone("%.1f" % current), true)


func _on_alert_raised(key: StringName) -> void:
	if _suppress_events or _is_fast_forwarding():
		return
	if key == AlertSources.QUEUE_CHECKIN:
		play_sfx(&"joke_queue_horn")
		_announce_pa(&"", PaWords.queue_checkin(), false)
	elif key == AlertSources.QUEUE_SECURITY:
		play_sfx(&"joke_queue_horn")
		_announce_pa(&"", PaWords.queue_security(), false)


## Lump-sum rewards only (never per-passenger FEES, SHOP or PARKING ticks).
func _on_wallet_transaction(amount: int, category: int, _claimed: Dictionary, _tick: int) -> void:
	if amount <= 0 or _suppress_events or _is_fast_forwarding():
		return
	var lump_rewards := [
		Wallet.Category.GRANT,
		Wallet.Category.SIGNING_BONUS,
		Wallet.Category.INCIDENT,
	]
	if lump_rewards.has(category):
		play_sfx(&"cash_chime")
