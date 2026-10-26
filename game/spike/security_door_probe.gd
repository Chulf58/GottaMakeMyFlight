extends SceneTree
## Headless finding probe: a door wall in the security divider of the
## reference terminal. Reports, does not judge: whether generic routing
## crosses the divider, and whether passengers reach the gate without a
## scanner, with the scanners in place and with them removed.
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path game -s res://spike/security_door_probe.gd

const DOOR_CELL := Vector2i(12, ReferenceTerminal.DIVIDER_Y)
const PASSENGERS := 24
const END_TICK := 2100


func _initialize() -> void:
	var seed := randi()
	print("PROBE seed=", seed)
	_case("door_in_divider_with_scanners", false, seed)
	_case("door_in_divider_no_scanners", true, seed)
	quit(0)


func _case(label: String, remove_scanners: bool, seed: int) -> void:
	var world := PassengerTestWorld.reference_world(seed)
	var grid := world.grid
	var landside := Vector2i(12, 12)
	var airside := Vector2i(12, 5)
	var before := grid.find_path(landside, airside)
	var door := grid.apply(
		BuildEdit.place_wall(DOOR_CELL, BuildGrid.Side.NORTH, BuildGrid.WallKind.DOOR)
	)
	if remove_scanners:
		for id in ReferenceTerminal.object_ids(grid)["scanners"]:
			grid.apply(BuildEdit.remove_object(id))
	var after := grid.find_path(landside, airside)
	print(
		(
			"PROBE %s: door_placed=%s route_cells_before=%d route_cells_after=%d scanners=%d"
			% [label, door.ok, before.size(), after.size(), world.sim.layout.scanners.size()]
		)
	)
	world.sim.schedule_flight(PassengerTestWorld.FLIGHT, PASSENGERS)
	var through_door := {}
	var screened := {}
	var at_gate := {}
	var at_gate_uncleared := {}
	## Passenger.Stuck -> passengers that were ever stuck for it.
	var stuck_seen := {}
	while world.clock.tick < END_TICK:
		world.step()
		for id in world.sim.passenger_ids():
			var p := world.passenger(id)
			if p.stage == Passenger.Stage.SECURITY:
				screened[id] = true
			if p.stuck != Passenger.Stuck.NONE:
				if not stuck_seen.has(p.stuck):
					stuck_seen[p.stuck] = {}
				stuck_seen[p.stuck][id] = true
			if _crosses_door(p.path):
				through_door[id] = true
			var gate := p.stage >= Passenger.Stage.SITTING_DOWN
			if gate and p.stage != Passenger.Stage.MISSED:
				at_gate[id] = true
				if not p.cleared:
					at_gate_uncleared[id] = true
	var stuck := {}
	for reason in stuck_seen:
		stuck[Passenger.Stuck.keys()[reason]] = (stuck_seen[reason] as Dictionary).size()
	print(
		(
			"PROBE %s: spawned=%d path_through_door=%d screened=%d at_gate=%d"
			% [
				label,
				world.sim.passenger_ids().size(),
				through_door.size(),
				screened.size(),
				at_gate.size()
			]
		)
	)
	print(
		(
			"PROBE %s: at_gate_without_clearance=%d made=%d missed=%d ever_stuck=%s"
			% [
				label,
				at_gate_uncleared.size(),
				world.sim.made_count(),
				world.sim.missed_count(),
				stuck
			]
		)
	)
	world.free_all()


func _crosses_door(path: Array[Vector2i]) -> bool:
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		if a.x == DOOR_CELL.x and b.x == DOOR_CELL.x and mini(a.y, b.y) == DOOR_CELL.y - 1:
			return true
	return false
