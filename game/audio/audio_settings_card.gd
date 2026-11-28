class_name AudioSettingsCard
extends PanelContainer
## Shared cozy cream/navy audio controls card for both GameMenu (Esc -> Settings)
## and TitleScreen (decisions demo-audio-floor-d5-cozy-terminal-ambience-loop-
## light-tactil and cozy-5-track-procedural-music-playlist-and-separate-music-
## ambience-sliders): Master, Music, Ambience and SFX 0..100% HSliders plus a
## Mute audio CheckButton, live-synced with /root/GameAudio. Dragging a slider
## previews dB live on AudioServer and writes ConfigFile once on drag_ended.

const GAME_AUDIO := preload("res://audio/game_audio.gd")
const AUDIO_NODE_PATH := ^"/root/GameAudio"
const LABEL_WIDTH := 128.0
const SLIDER_MIN_SIZE := Vector2(180.0, 28.0)
const VALUE_WIDTH := 64.0
const NAVY := Color(0.1, 0.13, 0.26, 1.0)
const TRACK_BG := Color(0.87, 0.85, 0.81, 1.0)
const FILL_TEAL := Color(0.25, 0.68, 0.68, 1.0)
const FILL_TEAL_HOVER := Color(0.4, 0.744, 0.744, 1.0)

var _audio: GAME_AUDIO
var _dragging := false
var _dirty_while_dragging := false
var _heading: Label
var _mute_switch: CheckButton
var _master_label: Label
var _music_label: Label
var _ambience_label: Label
var _sfx_label: Label
var _master_slider: HSlider
var _music_slider: HSlider
var _ambience_slider: HSlider
var _sfx_slider: HSlider
var _master_value: Label
var _music_value: Label
var _ambience_value: Label
var _sfx_value: Label


func _init() -> void:
	theme_type_variation = &"HudSubCard"
	var box := VBoxContainer.new()
	box.name = "Rows"
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_heading = Label.new()
	_heading.name = "Title"
	_heading.text = tr("Audio")
	_heading.theme_type_variation = &"HudLarge"
	box.add_child(_heading)
	_mute_switch = CheckButton.new()
	_mute_switch.name = "MuteAudio"
	_mute_switch.text = tr("Mute audio")
	_mute_switch.focus_mode = Control.FOCUS_NONE
	_mute_switch.toggled.connect(_on_mute_toggled)
	box.add_child(_mute_switch)
	var master_parts := _add_slider_row(box, "Master", tr("Master"), _on_master_changed)
	_master_slider = master_parts[0]
	_master_value = master_parts[1]
	_master_label = master_parts[2]
	var music_parts := _add_slider_row(box, "Music", tr("Music"), _on_music_changed)
	_music_slider = music_parts[0]
	_music_value = music_parts[1]
	_music_label = music_parts[2]
	var ambience_parts := _add_slider_row(box, "Ambience", tr("Ambience"), _on_ambience_changed)
	_ambience_slider = ambience_parts[0]
	_ambience_value = ambience_parts[1]
	_ambience_label = ambience_parts[2]
	var sfx_parts := _add_slider_row(box, "SFX", tr("SFX"), _on_sfx_changed)
	_sfx_slider = sfx_parts[0]
	_sfx_value = sfx_parts[1]
	_sfx_label = sfx_parts[2]


func _ready() -> void:
	_audio = get_node_or_null(AUDIO_NODE_PATH) as GAME_AUDIO
	if _audio != null and not _audio.changed.is_connected(sync_from_audio):
		_audio.changed.connect(sync_from_audio)
	sync_from_audio()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()


func _exit_tree() -> void:
	if _dragging and _dirty_while_dragging and is_instance_valid(_audio):
		_audio.save_settings()
	_dragging = false
	_dirty_while_dragging = false
	if is_instance_valid(_audio) and _audio.changed.is_connected(sync_from_audio):
		_audio.changed.disconnect(sync_from_audio)


func mute_switch() -> CheckButton:
	return _mute_switch


func master_slider() -> HSlider:
	return _master_slider


func music_slider() -> HSlider:
	return _music_slider


func ambience_slider() -> HSlider:
	return _ambience_slider


func sfx_slider() -> HSlider:
	return _sfx_slider


func sync_from_audio() -> void:
	if _audio == null and is_inside_tree():
		_audio = get_node_or_null(AUDIO_NODE_PATH) as GAME_AUDIO
	if _audio == null:
		return
	_mute_switch.set_pressed_no_signal(_audio.muted)
	_set_slider(_master_slider, _master_value, _audio.master_volume)
	_set_slider(_music_slider, _music_value, _audio.music_volume)
	_set_slider(_ambience_slider, _ambience_value, _audio.ambience_volume)
	_set_slider(_sfx_slider, _sfx_value, _audio.sfx_volume)


func _set_slider(slider: HSlider, value_label: Label, linear: float) -> void:
	var pct := int(round(clampf(linear, 0.0, 1.0) * 100.0))
	slider.set_value_no_signal(float(pct))
	value_label.text = tr("{percent}%").format({"percent": pct})


func _add_slider_row(parent: Control, row_id: String, caption: String, handler: Callable) -> Array:
	var row := HBoxContainer.new()
	row.name = row_id + "Row"
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label := Label.new()
	label.name = "Label"
	label.text = caption
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = row_id + "Slider"
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = SLIDER_MIN_SIZE
	_style_slider(slider)
	slider.drag_started.connect(_on_drag_started)
	slider.drag_ended.connect(_on_drag_ended)
	slider.value_changed.connect(handler)
	row.add_child(slider)
	var value_label := Label.new()
	value_label.name = "Value"
	value_label.custom_minimum_size = Vector2(VALUE_WIDTH, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return [slider, value_label, label]


func _retranslate() -> void:
	if _heading != null:
		_heading.text = tr("Audio")
	if _mute_switch != null:
		_mute_switch.text = tr("Mute audio")
	if _master_label != null:
		_master_label.text = tr("Master")
	if _music_label != null:
		_music_label.text = tr("Music")
	if _ambience_label != null:
		_ambience_label.text = tr("Ambience")
	if _sfx_label != null:
		_sfx_label.text = tr("SFX")
	sync_from_audio()


func _style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = TRACK_BG
	track.border_color = NAVY
	track.set_border_width_all(2)
	track.set_corner_radius_all(6)
	track.content_margin_top = 6.0
	track.content_margin_bottom = 6.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = FILL_TEAL
	fill.border_color = NAVY
	fill.set_border_width_all(2)
	fill.set_corner_radius_all(6)
	var fill_hover := fill.duplicate() as StyleBoxFlat
	fill_hover.bg_color = FILL_TEAL_HOVER
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_hover)


func _on_drag_started() -> void:
	_dragging = true
	_dirty_while_dragging = false


func _on_drag_ended(changed_on_drag: bool) -> void:
	var should_save := changed_on_drag or _dirty_while_dragging
	_dragging = false
	_dirty_while_dragging = false
	if should_save and _audio != null:
		_audio.save_settings()


func _on_mute_toggled(on: bool) -> void:
	if _audio != null:
		_audio.set_muted(on)


func _on_master_changed(value: float) -> void:
	if _audio == null:
		return
	if _dragging:
		_dirty_while_dragging = true
	_audio.set_master_volume(value / 100.0, not _dragging)


func _on_music_changed(value: float) -> void:
	if _audio == null:
		return
	if _dragging:
		_dirty_while_dragging = true
	_audio.set_music_volume(value / 100.0, not _dragging)


func _on_ambience_changed(value: float) -> void:
	if _audio == null:
		return
	if _dragging:
		_dirty_while_dragging = true
	_audio.set_ambience_volume(value / 100.0, not _dragging)


func _on_sfx_changed(value: float) -> void:
	if _audio == null:
		return
	if _dragging:
		_dirty_while_dragging = true
	_audio.set_sfx_volume(value / 100.0, not _dragging)
