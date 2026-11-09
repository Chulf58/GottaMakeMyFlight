class_name TestPassengerViewsFileClip
extends GdUnitTestSuite
## The walk clip of a walker held in a boarding file plays at the pace the
## walker is walked, also on the tick it turns a corner (board 03454587, item
## 5). A held walker's pace is read off the sim, not off the drawn step: the
## drawn step across a 90 degree corner is a chord, 0.71 of the way walked, so
## the clip played at about 71% speed for that one tick.

const FILE_CELL := Vector2i(19, 6)
const FILE_WALKERS := 5
const MAX_TICKS := 400
## The most the clip's speed may differ from the speed for the pace walked.
const SPEED_EPS := 0.001
## A walker whose drawn step is under this share of the way walked on a tick
## has turned a corner on it.
const CORNER_SHARE := 0.95

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
	if _world != null:
		_world.free_all()
	_views = null
	_world = null


## The speed a walk clip plays at for `mm` walked in a tick (PassengerLooks).
func _clip_speed(id: int, mm: int) -> float:
	var body: int = _views.node_for(id).get_meta(&"body")
	return mm * SimClock.TICK_RATE / 1000.0 / PassengerLooks.CLIP_WALK_MPS[body]


## The odometer of `p` while it has a body drawn, else -1: a walker drawn new
## on a tick has no step drawn on it, so its clip starts there at idle.
func _drawn_odometer(p: Passenger) -> int:
	return p.odometer_mm if _views.node_for(p.id) != null else -1


## Boarding opens with FILE_WALKERS walkers on one cell, so the later ones wait
## in their file; the views draw them.
func _filed_walkers() -> Array[Passenger]:
	_world = TestBoardingFiles.boarding_world()
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_world.run_to(TestBoardingFiles.BOARDING + 5)
	var walkers: Array[Passenger] = []
	for i in FILE_WALKERS:
		var p := TestBoardingFiles.walker(_world, FILE_CELL)
		p.carry_on = 1
		walkers.append(p)
	return walkers


## Stepped tick by tick with the views drawn, every tick a held walker walks:
## {"ticks": walking ticks, "corners": those on a corner (the drawn step under
## CORNER_SHARE of the way walked), "straight": the others, "worst": the worst
## gap between the clip speed and the speed for the way walked, "worst_at":
## where}.
func _run() -> Dictionary:
	var walkers := _filed_walkers()
	var out := {"ticks": 0, "corners": 0, "straight": 0, "worst": 0.0, "worst_at": ""}
	var odo := {}
	for tick in MAX_TICKS:
		for p in walkers:
			odo[p.id] = _drawn_odometer(p)
		_world.step()
		for p in walkers:
			if not _world.sim.files.holds(p.id) or odo[p.id] < 0:
				continue
			var walked: int = p.odometer_mm - odo[p.id]
			if walked <= 0:
				continue
			var chord: float = (
				(_views.tick_position(p.id, true) - _views.tick_position(p.id, false)).length()
				* 1000.0
			)
			if chord >= walked * CORNER_SHARE:
				out["straight"] += 1
			else:
				out["corners"] += 1
			out["ticks"] += 1
			var node := _views.node_for(p.id)
			var gap := absf(float(node.get_meta(&"base_speed")) - _clip_speed(p.id, walked))
			if gap > out["worst"]:
				out["worst"] = gap
				out["worst_at"] = (
					"walker %d tick %d walked %d mm chord %.0f mm clip %.3f want %.3f"
					% [
						p.id,
						_world.clock.tick,
						walked,
						chord,
						node.get_meta(&"base_speed"),
						_clip_speed(p.id, walked)
					]
				)
	return out


func test_a_walker_held_in_its_file_plays_its_walk_clip_at_the_pace_it_walks() -> void:
	var out := _run()
	print("file clip: %s" % [out])
	# The control: the run walked both straight and round corners.
	assert_int(out["corners"]).is_greater(0)
	assert_int(out["straight"]).is_greater(0)
	assert_float(out["worst"]).is_less(SPEED_EPS)


## A load starts the views over (snap()): the way a walker walked is read from
## the odometer of the sync before, and a load can bring any odometer. One held
## walker that walks, its odometer put 5 m on and loaded, plays no walk clip
## on the loaded tick rather than a clip at 50 times the pace.
func test_a_load_does_not_read_the_way_walked_from_before_it() -> void:
	var walkers := _filed_walkers()
	var walking: Passenger = null
	for tick in MAX_TICKS:
		var odo := {}
		for p in walkers:
			odo[p.id] = _drawn_odometer(p)
		_world.step()
		for p in walkers:
			if (
				walking == null
				and _world.sim.files.holds(p.id)
				and odo[p.id] >= 0
				and p.odometer_mm > odo[p.id]
			):
				walking = p
		if walking != null:
			break
	assert_object(walking).is_not_null()
	var node := _views.node_for(walking.id)
	assert_float(node.get_meta(&"base_speed")).is_greater(0.5)
	walking.odometer_mm += 5000
	_views.snap()
	assert_str(node.get_meta(&"clip")).is_equal("idle")
	assert_float(node.get_meta(&"base_speed")).is_equal(1.0)
