extends SceneTree
## Measures what the security forecast costs in test_cafe_deadline's no-visit
## scenario (TestCafeDeadline._scenario(false)): the stream of passengers who
## have just checked in, run to `--ticks=N` past the start (default: to the
## guest's doors closing), with the replays, replay steps and wall time the
## forecast took, and a checksum of every passenger's stage and outcome tick so
## two builds can be compared for the same play.
##
## godot --headless --audio-driver Dummy --path game
##   -s res://spike/forecast_cost_probe.gd -- --ticks=400

const CROWD_CELL := Vector2i(16, 12)
const CROWD_EVERY := 7
const CROWD_UNTIL := 700
const START := 200


func _initialize() -> void:
	var limit := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks="):
			limit = int(arg.substr(8))
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	world.run_to(START)
	var guest := _new_passenger(world)
	while guest.stage != Passenger.Stage.TO_SECURITY and world.clock.tick < START + 600:
		world.step()
	var end := world.flights.doors_close_tick(guest.flight_id) + 1
	if limit > 0:
		end = mini(end, START + limit)
	var replays := SecurityForecast.replays_played
	var steps := SecurityForecast.steps_played
	var from := Time.get_ticks_usec()
	while world.clock.tick < end:
		var crowding := world.clock.tick < START + CROWD_UNTIL
		if crowding and posmod(world.clock.tick, CROWD_EVERY) == 0:
			_checked_in(world)
		world.step()
	var usec := Time.get_ticks_usec() - from
	replays = SecurityForecast.replays_played - replays
	steps = SecurityForecast.steps_played - steps
	var sum := 0
	for p in world.sim._passengers:
		sum = (sum * 31 + p.id * 7 + int(p.stage) * 13 + p.outcome_tick) % 1000000007
	print(
		(
			"ticks %d..%d guest %s: %.1f s, replays %d, steps %d, %.4f ms/step, checksum %d"
			% [
				START,
				end,
				Passenger.Stage.keys()[guest.stage],
				usec / 1e6,
				replays,
				steps,
				usec / 1000.0 / maxi(steps, 1),
				sum,
			]
		)
	)
	world.free_all()
	quit(0)


func _checked_in(world: PassengerTestWorld) -> void:
	var p := _new_passenger(world)
	p.stage = Passenger.Stage.TO_SECURITY
	p.service_end = world.clock.tick
	p.at = CROWD_CELL
	p.clear_path()


func _new_passenger(world: PassengerTestWorld) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	return p
