class_name HudFlagSetting
extends RefCounted
## One saved choice of an optional HUD piece in the shared settings file
## (decision optional-hud-pieces-keep-their-on-off-setting-in-user-hud-se):
## a ConfigFile, section "hud", one key per piece. Most are on/off flags; the
## camera angle is a step number (decision camera-angle-is-a-player-setting-
## fixed-while-zooming). A missing file or key gives the default; an unreadable
## file or a failed write is reported with push_error, naming `who`, and the
## session carries on with the choice it has.

const PATH := "user://hud_settings.cfg"
const SECTION := "hud"


## The saved choice for `key`, `default` when nothing is saved yet.
static func load_flag(path: String, key: String, default: bool, who: String) -> bool:
	return bool(_load(path, key, default, who))


## The saved step number for `key`, `default` when nothing is saved yet.
static func load_int(path: String, key: String, default: int, who: String) -> int:
	return int(_load(path, key, default, who))


## Writes the choice next to any other settings already in the file.
static func save_flag(path: String, key: String, value: bool, who: String) -> void:
	_save(path, key, value, who)


## Writes the step number next to any other settings already in the file.
static func save_int(path: String, key: String, value: int, who: String) -> void:
	_save(path, key, value, who)


static func _load(path: String, key: String, default: Variant, who: String) -> Variant:
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err == ERR_FILE_NOT_FOUND:
		return default
	if err != OK:
		push_error("%s: cannot read %s (error %d)" % [who, path, err])
		return default
	return cfg.get_value(SECTION, key, default)


static func _save(path: String, key: String, value: Variant, who: String) -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_error("%s: cannot read %s (error %d)" % [who, path, err])
		return
	cfg.set_value(SECTION, key, value)
	err = cfg.save(path)
	if err != OK:
		push_error("%s: cannot write %s (error %d)" % [who, path, err])
