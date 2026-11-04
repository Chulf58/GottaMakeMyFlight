class_name NeedIconsToggle
extends Node
## The on/off choice for the need icons over passengers (decision passenger-
## need-icons-toggle-key-n-on-by-default): the N key shows and hides every
## icon, the choice is kept in the HUD settings file under "need_icons"
## (HudFlagSetting, decision optional-hud-pieces-keep-their-on-off-setting-in-
## user-hud-se) and On is the default. While on, the zoomed-out hide
## (NeedIcons.shown_at) and the near-camera fade (NeedIcons.near_alpha) still
## apply. PassengerViews owns one and reads is_shown() when it lays the icons
## out. N is free of the build tool keys 1 to 0, R, Z, B, M, H, Escape, the
## speed keys, the camera keys (WASD, Q, E, Home) and the save keys (F5, F8).

## The input action for the toggle key, bound to N in project.godot.
const ACTION := &"toggle_need_icons"
const SETTING_KEY := "need_icons"
const WHO := "NeedIconsToggle"

## Where the on/off choice is kept; tests point it at a per-process file.
var settings_path := HudFlagSetting.PATH

var _shown := true


func _ready() -> void:
	name = "NeedIconsToggle"
	_shown = HudFlagSetting.load_flag(settings_path, SETTING_KEY, true, WHO)


## True while the need icons may show.
func is_shown() -> bool:
	return _shown


## Shows or hides the need icons and keeps the choice.
func set_shown(value: bool) -> void:
	if value == _shown:
		return
	_shown = value
	HudFlagSetting.save_flag(settings_path, SETTING_KEY, _shown, WHO)


## N toggles; a held key's repeats and modified presses are left alone.
func _shortcut_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or not event.is_action_pressed(ACTION):
		return
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed or key.shift_pressed:
		return
	if not key.echo:
		set_shown(not _shown)
	get_viewport().set_input_as_handled()
