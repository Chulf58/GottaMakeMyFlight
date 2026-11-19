extends Node
## The demo audio floor autoload (decision demo-audio-floor-d5-cozy-terminal-
## ambience-loop-light-tactil): ensures the Master, Ambience and SFX buses exist,
## loads and saves per-bus linear volumes and mute state in
## user://audio_settings.cfg (shielded during script/test runs just like
## HudFlagSetting, so tests never read or overwrite the player's config), loops
## cozy terminal ambience while a gameplay scene (BuildMode) is in the tree, and
## plays light tactile UI, build and cash SFX on a fixed child pool with zero
## orphan nodes.

signal changed

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
const POOL_SIZE := 6

const AMBIENCE_PATH := "res://assets/audio/terminal_ambience.wav"
const SFX_PATHS := {
	&"ui_click": "res://assets/audio/ui_click.wav",
	&"build_place": "res://assets/audio/build_place.wav",
	&"build_remove": "res://assets/audio/build_remove.wav",
	&"build_refuse": "res://assets/audio/build_refuse.wav",
	&"cash_chime": "res://assets/audio/cash_chime.wav",
}
const SFX_COOLDOWN_MS := {
	&"ui_click": 25,
	&"build_place": 45,
	&"build_remove": 45,
	&"build_refuse": 80,
	&"cash_chime": 450,
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
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_streams: Dictionary = {}
var _sfx_cursor := 0
var _last_sfx: StringName = &""
var _sfx_counts: Dictionary = {}
var _last_played_ms: Dictionary = {}
var _gameplay_nodes: Array[Node] = []
var _desk_open_ids: Dictionary = {}


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


## Restores default buses, paths, counters and playback state for test teardown.
func reset_for_test() -> void:
	protected_path = DEFAULT_SETTINGS_PATH
	settings_path = DEFAULT_SETTINGS_PATH
	save_count = 0
	_last_sfx = &""
	_sfx_counts.clear()
	_last_played_ms.clear()
	for player in _sfx_players:
		player.stop()
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


func _bind_flight_sim(flights: FlightSim) -> void:
	if not is_instance_valid(flights):
		return
	if not flights.state_changed.is_connected(_on_flight_state):
		flights.state_changed.connect(_on_flight_state)


func _bind_offer_desk(desk: OfferDesk) -> void:
	if not is_instance_valid(desk) or desk.board == null:
		return
	var id := desk.get_instance_id()
	_desk_open_ids[id] = _open_offer_ids(desk.board)
	var on_changed := _on_board_changed.bind(desk)
	if not desk.board.changed.is_connected(on_changed):
		desk.board.changed.connect(on_changed)
	var on_exit := _on_desk_exited.bind(id)
	if not desk.tree_exiting.is_connected(on_exit):
		desk.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)


func _on_desk_exited(desk_id: int) -> void:
	_desk_open_ids.erase(desk_id)


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


func _on_flight_state(_flight_id: String, new_state: int) -> void:
	if new_state == FlightSim.State.DEPARTED:
		play_sfx(&"cash_chime")


## Lump-sum rewards only (never per-passenger FEES, SHOP or PARKING ticks).
func _on_wallet_transaction(amount: int, category: int, _claimed: Dictionary, _tick: int) -> void:
	if amount <= 0:
		return
	var lump_rewards := [
		Wallet.Category.GRANT,
		Wallet.Category.SIGNING_BONUS,
		Wallet.Category.INCIDENT,
	]
	if lump_rewards.has(category):
		play_sfx(&"cash_chime")
