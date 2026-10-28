class_name SaveTestKit
extends RefCounted
## Test support for whole-world saves on the real main scene: boot a seeded
## world, open its airport through the real hiring path, step it, and read a
## checksum of everything that decides what happens next.
##
## The checksum hashes every SaveGame part's to_snapshot(). Each of those only
## reads (PassengerSim's and StaffSim's included), so an unsaved control world
## can be checksummed on every tick and stay unsaved.

const MAIN := "res://main/main.tscn"


## A save file path for one test run, unique to this Godot process. Every
## Godot process on the machine shares the same user:// folder, so two suites
## running at once (two worktrees, a lane and the conductor) would otherwise
## see each other's files at a fixed path and fail a "file not there yet" check.
static func run_path(file_name: String) -> String:
	return "user://saves/%s_%d.json" % [file_name, OS.get_process_id()]


## A directory path for one test run, unique to this Godot process, for tests
## that write several files under a folder (the playtest log tests). The same
## reasoning as run_path: a fixed folder is shared by every process on the
## machine, so one process's cleanup deletes another's files mid-test.
static func run_dir(dir_name: String) -> String:
	return "user://%s_%d" % [dir_name, OS.get_process_id()]


## A main scene under `parent` whose sim RNG starts from `seed`, paused so
## only step() moves it. Seeded before it enters the tree, so the day-0 offers
## are drawn from the seed.
static func boot(parent: Node, seed: int) -> Node:
	var main: Node = load(MAIN).instantiate()
	var clock: SimClock = main.get_node("SimClock")
	clock.seed_rng(seed)
	clock.set_paused(true)
	parent.add_child(main)
	return main


## One tick, the way the game runs one.
static func step(main: Node) -> void:
	var clock: SimClock = main.get_node("SimClock")
	clock.set_paused(false)
	clock.advance(SimClock.STEP)
	clock.set_paused(true)


## Builds the starter terminal with the HUD button and hires one check-in
## agent and one security officer, who walk to their stations; the airport
## opens once they are on duty.
static func start_airport(main: Node) -> void:
	(main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var staff: StaffSim = main.get_node("Staff")
	staff.hire(StaffMember.Role.CHECKIN)
	staff.hire(StaffMember.Role.SECURITY)


static func save_game(main: Node) -> SaveGame:
	return main.get_node("SaveGame")


static func checksum(main: Node) -> String:
	var data := {}
	for part in save_game(main).parts():
		data[part.key] = part.save.call()
	return JSON.stringify(data, "", true, true).sha256_text()
