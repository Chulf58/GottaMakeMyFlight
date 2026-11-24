extends Node
## Optional GodotSteam bridge autoload (Stage 3 Slice S3-P4b, decision c5664a34).
##
## Safe zero-error no-op when GodotSteam is absent (dev, headless, gdUnit4,
## non-Steam builds). Uses Engine.has_singleton("Steam") at runtime and never
## hard-references a missing Steam global class so GDScript compiles cleanly
## without the GDExtension installed.
##
## Steam Auto-Cloud Path Contract (configured in Steamworks Partner portal; no
## custom ISteamRemoteStorage file sync code needed):
##   - Saves directory:
##       user://saves/ (AUTO_CLOUD_SAVE_DIR)
##       Windows: %APPDATA%/Godot/app_userdata/Gotta Make My Flight/saves/
##       Linux:   ~/.local/share/godot/app_userdata/Gotta Make My Flight/saves/
##       macOS:   ~/Library/Application Support/Godot/app_userdata/Gotta Make My Flight/saves/
##   - Achievement profile:
##       user://achievements.json (ACHIEVEMENTS_PATH)
##       Windows: %APPDATA%/Godot/app_userdata/Gotta Make My Flight/achievements.json
##       Linux:   ~/.local/share/godot/app_userdata/Gotta Make My Flight/achievements.json
##       macOS:   ~/Library/Application Support/Godot/app_userdata/Gotta Make My Flight/
##                achievements.json

const AUTO_CLOUD_SAVE_DIR := "user://saves"
const ACHIEVEMENTS_PATH := "user://achievements.json"

var _mock_steam: Object
var _real_steam_ready := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Hints.launched_by_script(OS.get_cmdline_args()):
		return
	_try_init_real_steam()


func _process(_delta: float) -> void:
	if _mock_steam != null:
		return
	if not _real_steam_ready or not Engine.has_singleton("Steam"):
		return
	var steam := Engine.get_singleton("Steam")
	if steam != null and steam.has_method("run_callbacks"):
		steam.call("run_callbacks")


## Injects or clears a mock Steam object for headless tests.
func set_mock_steam(mock: Object) -> void:
	_mock_steam = mock


## True when a live Steam backend (or test mock) is active and running.
func is_steam_available() -> bool:
	var backend := _steam_backend()
	if backend == null:
		return false
	if _mock_steam != null:
		if backend.has_method("isSteamRunning"):
			return bool(backend.call("isSteamRunning"))
		return true
	if not _real_steam_ready:
		return false
	if backend.has_method("isSteamRunning"):
		return bool(backend.call("isSteamRunning"))
	return true


## True when Steam Cloud is enabled for both the account and this app.
func is_cloud_enabled() -> bool:
	if not is_steam_available():
		return false
	var backend := _steam_backend()
	if backend == null:
		return false
	if (
		backend.has_method("isCloudEnabledForAccount")
		and backend.has_method("isCloudEnabledForApp")
	):
		return (
			bool(backend.call("isCloudEnabledForAccount"))
			and bool(backend.call("isCloudEnabledForApp"))
		)
	if backend.has_method("isCloudEnabled"):
		return bool(backend.call("isCloudEnabled"))
	return false


## Pushes achievement `api_id` to Steam via setAchievement + storeStats when
## available; returns false silently with zero errors when unavailable.
func unlock_achievement(api_id: String) -> bool:
	if api_id.strip_edges() == "" or not is_steam_available():
		return false
	var backend := _steam_backend()
	if (
		backend == null
		or not backend.has_method("setAchievement")
		or not backend.has_method("storeStats")
	):
		return false
	var set_result: Variant = backend.call("setAchievement", api_id)
	if typeof(set_result) == TYPE_BOOL and not bool(set_result):
		return false
	var store_result: Variant = backend.call("storeStats")
	return typeof(store_result) != TYPE_BOOL or bool(store_result)


func _steam_backend() -> Object:
	if _mock_steam != null and is_instance_valid(_mock_steam):
		return _mock_steam
	if Engine.has_singleton("Steam"):
		return Engine.get_singleton("Steam")
	return null


func _try_init_real_steam() -> void:
	if not Engine.has_singleton("Steam"):
		return
	var steam := Engine.get_singleton("Steam")
	if steam == null:
		return
	if steam.has_method("steamInitEx"):
		var init_res: Variant = steam.call("steamInitEx", false)
		if typeof(init_res) == TYPE_DICTIONARY:
			_real_steam_ready = int((init_res as Dictionary).get("status", -1)) == 0
			return
	if steam.has_method("steamInit"):
		var ok: Variant = steam.call("steamInit")
		_real_steam_ready = bool(ok) if typeof(ok) == TYPE_BOOL else true
