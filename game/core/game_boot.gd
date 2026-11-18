class_name GameBoot
extends RefCounted
## How the title screen starts the game (decision title-menu-with-continue-new-
## airport-load-and-quit-autosave). The title sets load_path (a save for
## Continue or Load, "" for New Airport) and changes to main.tscn. SaveGame takes
## the path as main.tscn enters the tree and loads it once the whole scene is
## ready; with no path main.tscn is a new airport, as it always was. A refused
## boot load puts its message in `refusal` and goes back to the title, which
## shows it.

const MAIN_SCENE := "res://main/main.tscn"
const TITLE_SCENE := "res://main/title.tscn"

## The save main.tscn loads as it boots, or "" for a new airport.
static var load_path := ""
## Why the last boot load was refused, or "" when nothing is waiting to be shown.
static var refusal := ""
## True when the title's New Airport started this game. The HUD pieces that keep a
## saved on/off choice (HudFlagSetting.load_boot_flag) then open on their defaults;
## Continue and Load keep the remembered choice (decision a-new-airport-starts-
## with-the-hud-overlays-closed-overlay-an). Cleared by SaveGame once main.tscn
## finishes booting and on SaveGame.load_world(). A main.tscn run that did not
## come through the title leaves it false, as it always was.
static var new_airport := false


## Starts a new airport. `change` is SceneTree.change_scene_to_file or a stand-in.
static func start_new(change: Callable) -> Error:
	load_path = ""
	new_airport = true
	return change.call(MAIN_SCENE)


## Starts main.tscn on the save at `path`.
static func start_load(path: String, change: Callable) -> Error:
	load_path = path
	new_airport = false
	return change.call(MAIN_SCENE)


## The boot save, cleared so a later main.tscn starts new.
static func take_load_path() -> String:
	var path := load_path
	load_path = ""
	return path


## The refusal to show, cleared so it shows once.
static func take_refusal() -> String:
	var text := refusal
	refusal = ""
	return text


## Ends the New Airport boot flag once the HUD has read it or a save loads.
static func clear_new_airport() -> void:
	new_airport = false
