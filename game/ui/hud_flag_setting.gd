class_name HudFlagSetting
extends RefCounted
## One on/off choice of an optional HUD piece in the shared settings file
## (decision optional-hud-pieces-keep-their-on-off-setting-in-user-hud-se):
## a ConfigFile, section "hud", one key per piece. A missing file or key gives
## the default; an unreadable file or a failed write is reported with
## push_error, naming `who`, and the session carries on with the choice it has.

const PATH := "user://hud_settings.cfg"
const SECTION := "hud"


## The saved choice for `key`, `default` when nothing is saved yet.
static func load_flag(path: String, key: String, default: bool, who: String) -> bool:
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err == ERR_FILE_NOT_FOUND:
		return default
	if err != OK:
		push_error("%s: cannot read %s (error %d)" % [who, path, err])
		return default
	return bool(cfg.get_value(SECTION, key, default))


## Writes the choice next to any other settings already in the file.
static func save_flag(path: String, key: String, value: bool, who: String) -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_error("%s: cannot read %s (error %d)" % [who, path, err])
		return
	cfg.set_value(SECTION, key, value)
	err = cfg.save(path)
	if err != OK:
		push_error("%s: cannot write %s (error %d)" % [who, path, err])
