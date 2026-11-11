class_name IncidentPanelKit
extends RefCounted
## The world the major incident panel's tests share: a clock, a
## MajorTestDirector, a bare SaveGame and the panel, in a 1920x1080 SubViewport,
## with the dialogs the panel queues behind and what a load does to the clock.

var port: SubViewport
var clock: SimClock
var director: MajorTestDirector
var save: SaveGame
var panel: IncidentPanel
## A node standing in for the Offers sheet, which takes the turn too.
var sheet: Node
var sheet_turns := 0


## Builds the world under `host`, which frees `port` when the test ends.
func build(host: Node) -> void:
	sheet_turns = 0
	port = SubViewport.new()
	port.size = Vector2i(1920, 1080)
	host.add_child(port)
	clock = SimClock.new()
	port.add_child(clock)
	director = MajorTestDirector.new()
	port.add_child(director)
	save = SaveGame.new()
	port.add_child(save)
	panel = IncidentPanel.new()
	panel.director = director
	panel.clock = clock
	panel.save_game = save
	panel.copy_for = MajorTestDirector.copy
	port.add_child(panel)
	sheet = Node.new()
	port.add_child(sheet)


func announce() -> int:
	var id := director.add_scheduled()
	director.present(id, false)
	return id


func offer() -> int:
	var id := director.add_scheduled()
	director.present(id, true)
	return id


func state_of(id: int) -> String:
	for incident in director.incidents():
		if incident["id"] == id:
			return incident["state"]
	return ""


func is_shown(id: int) -> bool:
	for incident in director.incidents():
		if incident["id"] == id:
			return incident["shown"]
	return false


## The offers sheet's way of taking the turn (OfferPanel: yields to the player).
func sheet_takes_the_turn() -> int:
	return clock.holds.take_turn(sheet, func() -> void: sheet_turns += 1, true)


## An unlock dialog asking for its turn.
func unlock_dialog() -> UnlockGuide:
	var guide := UnlockGuide.new()
	guide.clock = clock
	port.add_child(guide)
	guide.open_dialog([2])
	return guide


## What SaveGame.load_world() leaves before it emits loaded: the world's clock
## is installed (every hold dropped) and waits at 1x for the player.
func load_happens() -> void:
	clock.holds.clear()
	clock.set_paused(true)
	clock.set_speed(1)
	save.loaded.emit(true)
