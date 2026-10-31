extends SceneTree
## Headless cost check for BirdFlock with 500 people on the map: the old
## per-frame path (every frame: collect every person, every perched group
## checks every point, every AnimationPlayer speed set) against the real
## BirdFlock._process at 3x (a scatter check after every sim tick, here every
## frame; the reach box first,
## player speed set on change only). People are 500 Node3D at fixed places
## (450 inside the terminal, 50 outdoors), read the way threats_now() reads
## passenger nodes; LandsideViews and PassengerViews are not in this scene.
##   Godot --headless --path game --audio-driver Dummy --fixed-fps 60
##     -s res://spike/bird_flock_cost_probe.gd

const PEOPLE := 500
const INDOORS := 450
const FRAMES := 1200
const DT := 1.0 / 60.0


## The real flock, with threats_now() reading the probe's people through the
## same reach-box filter and buffer the game uses for passenger nodes.
class CostFlock:
	extends BirdFlock
	var people: Array[Node3D] = []
	var checks := 0

	func threats_now() -> PackedVector3Array:
		_threats.resize(0)
		var reach := BirdPerches.reach()
		for node in people:
			if not node.is_visible_in_tree():
				continue
			var at := node.global_position
			if reach.has_point(Vector2(at.x, at.z)):
				_threats.append(at)
		for g in groups:
			if g["target"] < 0:
				checks += _threats.size()
		return _threats


var _flock: CostFlock
var _people: Array[Node3D] = []
var _clock: SimClock


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	print("PROBE seed=42 people=", PEOPLE, " frames=", FRAMES)
	var holder := Node3D.new()
	root.add_child(holder)
	for i in PEOPLE:
		var n := Node3D.new()
		if i < INDOORS:
			n.position = Vector3(rng.randf_range(-30, 30), 0.3, rng.randf_range(-92, -66))
		else:
			n.position = Vector3(rng.randf_range(-40, 40), 0.2, rng.randf_range(-58, -20))
		holder.add_child(n)
		_people.append(n)
	var clock := SimClock.new()
	_clock = clock
	clock.set_process(false)
	root.add_child(clock)
	_flock = CostFlock.new()
	_flock.clock = clock
	_flock.people = _people
	_flock.rng.seed = 42
	root.add_child(_flock)
	_flock.rebuild()


func _old_frame() -> int:
	var pts := PackedVector3Array()
	for n in _people:
		if n.is_visible_in_tree():
			pts.append(n.global_position)
	var checks := 0
	for g in _flock.groups:
		if g["target"] < 0:
			checks += pts.size()
		for b in g["birds"]:
			(b["player"] as AnimationPlayer).speed_scale = 1.0
	_flock.step(DT, pts)
	return checks


func _process(_delta: float) -> bool:
	_flock.set_process(false)
	var old_checks := 0
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		old_checks += _old_frame()
	var old_us := Time.get_ticks_usec() - t0
	_flock.rebuild()
	_flock.checks = 0
	# 3x: a sim tick every frame at 60 fps, so a scatter check every frame,
	# the most often the per-tick scan runs.
	_clock.set_speed(3)
	t0 = Time.get_ticks_usec()
	for i in FRAMES:
		_clock.advance(DT)
		_flock._process(DT)
	var new_us := Time.get_ticks_usec() - t0
	print(
		"COST old_us_per_frame=",
		snappedf(float(old_us) / FRAMES, 0.1),
		" old_checks_per_frame=",
		snappedf(float(old_checks) / FRAMES, 0.1),
		" new_us_per_frame=",
		snappedf(float(new_us) / FRAMES, 0.1),
		" new_checks_per_frame=",
		snappedf(float(_flock.checks) / FRAMES, 0.1),
		" groups=",
		_flock.groups.size()
	)
	for n in _people:
		n.get_parent().remove_child(n)
		n.free()
	_flock.free()
	return true
