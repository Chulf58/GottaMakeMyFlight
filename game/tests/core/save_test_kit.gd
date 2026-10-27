class_name SaveTestKit
extends RefCounted
## Test support for whole-world saves on the real main scene: boot a seeded
## world, open its airport through the real hiring path, step it, and read a
## checksum of everything that decides what happens next.
##
## The checksum only reads. It hashes every SaveGame part's to_snapshot()
## except the staff, whose to_snapshot() reconciles first, so the staff are
## read member by member instead (StaffTestKit.signature). An unsaved control
## world can therefore be checksummed on every tick and stay unsaved.

const MAIN := "res://main/main.tscn"


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
		if part.key != "staff":
			data[part.key] = part.save.call()
	var staff: StaffSim = main.get_node("Staff")
	data["staff"] = [staff.member_ids(), StaffTestKit.signature(staff)]
	return JSON.stringify(data, "", true, true).sha256_text()
