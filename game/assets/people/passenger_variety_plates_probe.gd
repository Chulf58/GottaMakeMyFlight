extends "res://spike/passenger_looks_plates_probe.gd"
## Windowed plates and seat sweeps for the added passenger bodies (board
## 3fcd8e5a: male 04 and 05 and female 06, 09 and 12), built on the passenger
## looks plates probe:
## - crowd: its crowd of passengers in spawn order (--seed=N);
## - seated: every body on its own gate seat row in groups of three, the last
##   group short when the count is not a multiple of three (_seated() here; the
##   base probe's needs full groups), with SEAT_OVERLAP checks and, with
##   --sweep, the least step out of the row per body; a body no saved plate
##   shows is PROBE_INVALID;
## - cafe: every body on the cafe_table chair (CAFE_SWEEP with --sweep);
## - carry: each added body standing in its idle with a roller parked beside
##   it as a queue stand (RollerPark.queue_park) and with a backpack worn from
##   its Spine_03 bone (CarryWorn.worn_back), each beside a 1 m cube.
## Every plate proves its subjects are in frame and seen before it is saved
## (the base probe's _proven); a failure prints PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --path <checkout>/game \
##     -s res://assets/people/passenger_variety_plates_probe.gd \
##     -- --parts=seated,cafe,carry [--sweep] [--seed=N]
## The crowd and seated plates go where the base probe puts them; the carry
## plates and the sheets to tools/blender/out/passenger_variety_20261114/.

const VARIETY_REL := "res://../tools/blender/out/passenger_variety_20261114"
const ADDED: Array[String] = [
	"tcp_male_character_04",
	"tcp_male_character_05",
	"tcp_female_character_06",
	"tcp_female_character_09",
	"tcp_female_character_12",
]

## Body indices a saved seated plate shows.
var _seated_shot := {}


func _run() -> void:
	var seed := 777
	var parts := ["seated", "cafe", "carry"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.get_slice("=", 1))
		if arg.begins_with("--parts="):
			parts = Array(arg.get_slice("=", 1).split(","))
	print("VARIETY seed=", seed, " parts=", parts, " bodies=", PassengerLooks.BODIES.size())
	_studio()
	root.add_child(_cam)
	root.add_child(_stage)
	_cam.current = true
	if "crowd" in parts:
		await _crowd(seed)
	if "seated" in parts:
		var close: Array[Image] = []
		for group in ceili(PassengerLooks.BODIES.size() / 3.0):
			await _seated(group, close)
		for body in PassengerLooks.BODIES.size():
			if not _seated_shot.has(body):
				_invalid("%s: no seated plate shows it" % PassengerLooks.BODIES[body])
		print("SEATED_SHOT %d of %d" % [_seated_shot.size(), PassengerLooks.BODIES.size()])
		_save(_sheet(close, 9, 240), "seated_close_sheet.png", VARIETY_REL)
	if "cafe" in parts:
		var cafe: Array[Image] = []
		await _cafe(cafe)
		_save(_sheet(cafe, 6, 240), "cafe_close_sheet.png", VARIETY_REL)
	if "carry" in parts:
		var tiles: Array[Image] = []
		for stem in ADDED:
			var body := PassengerLooks.BODIES.find(stem)
			if body < 0:
				_invalid("%s is not a passenger body" % stem)
				continue
			await _carry(body, SecurityLooks.Kind.ROLLER, tiles)
			await _carry(body, SecurityLooks.Kind.BACKPACK, tiles)
		_save(_sheet(tiles, 4, 400), "carry_sheet.png", VARIETY_REL)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


## Body `body` standing in its idle at the origin facing +z with a bag of
## `kind`: a roller parked on its right as a queue stand, shot from the front
## quarter, or a backpack on its back, shot side-on so a gap shows.
func _carry(body: int, kind: SecurityLooks.Kind, tiles: Array[Image]) -> void:
	_clear()
	var person := _person(body, 0, Vector3.ZERO, 0.0, 0.0)
	var roller := kind == SecurityLooks.Kind.ROLLER
	# Clear of the line from the camera to the body and its bag.
	var cube := _cube(Vector3(1.0, 0, -0.8) if roller else Vector3(0, 0, -1.3))
	for i in 3:
		await process_frame
	var bag := InteriorKit.instantiate(SecurityLooks.KIND_PIECES[kind])
	_stage.add_child(bag)
	var view := Vector3(1.4, 0.9, 2.6)
	if roller:
		bag.global_transform = RollerPark.queue_park(person.global_transform, 0, 1.0, body)
	else:
		var skeleton := person.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var bone := skeleton.find_bone(CarryOnProps.SPINE_BONE)
		var spine := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		bag.global_transform = CarryWorn.worn_back(spine, person.rotation.y, 1.0, body)
		view = Vector3(3.0, 0.4, 0.0)
	PassengerLooks.paint_bags([{"node": bag}], 2)
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 35.0
	var centre := (cube.position + Vector3(0, 0.4, 0)) * 0.5 + Vector3(0, 0.6, 0)
	_cam.global_position = centre + view.normalized() * 4.2
	_cam.look_at(centre)
	var label := (
		"carry_%s_%s"
		% [PassengerLooks.BODIES[body].trim_prefix("tcp_"), "roller" if roller else "backpack"]
	)
	var subjects := {person: label, bag: label + "_bag", cube: "cube"}
	print("CARRY %s bag=%s" % [label, bag.global_transform.origin])
	var ok: bool = await _proven(label, subjects, false)
	var img: Image = await _grab(false)
	if ok:
		_save(img, label + ".png", VARIETY_REL)
		tiles.append(img)


## The base probe's _seated() (the bodies of `group`, group * 3 onwards, each in
## sit_idle on the middle chair of its own gate seat row, placed as PassengerSim
## and GateChairs place a seated passenger, shot side-on, SEAT_GAP printed,
## _overlaps() checked, close-ups appended to `close`), with the last group as
## short as the body count leaves it.
func _seated(group: int, close: Array[Image]) -> void:
	_clear()
	var chairs := Node3D.new()
	_stage.add_child(chairs)
	var subjects := {}
	var people: Array[Node3D] = []
	for k in mini(3, PassengerLooks.BODIES.size() - group * 3):
		var body := group * 3 + k
		var row := InteriorKit.instantiate(&"seat_row")
		chairs.add_child(row)
		row.position = Vector3(0, 0, k * 2.6)
		# The row's origin is its footprint's centre, the middle cell's centre.
		var shift := PassengerLooks.SEAT_SHIFT_M[body]
		var at := (
			row.position
			+ Vector3(GateChairs.CHAIR_OFFSET_M[1], shift.y, PassengerSim.SIT_FORWARD_M + shift.x)
		)
		var node := _person(body, 0, at, 0.0, 0.0, "sit_idle")
		subjects[node] = PassengerLooks.BODIES[body]
		people.append(node)
		# The chair is part of what the plate shows of the person sitting on it.
		subjects[row] = subjects[node]
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.size = 8.0
	var centre := Vector3(0, 0.8, 2.6)
	_cam.global_position = centre + Vector3(12, 0, 0)
	_cam.look_at(centre)
	for i in 3:
		await process_frame
	var owners: Array[Node] = [chairs]
	var holder := PlateSight.colliders(root, owners, {})
	await physics_frame
	await physics_frame
	var space := _cam.get_world_3d().direct_space_state
	for node in people:
		var skel := node.find_child("Skeleton3D", true, false) as Skeleton3D
		var hips := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Hips")).origin
		var down := PhysicsRayQueryParameters3D.create(
			Vector3(hips.x, 1.2, hips.z), Vector3(hips.x, 0.0, hips.z)
		)
		var hit := space.intersect_ray(down)
		var mi := PassengerLooks.body_mesh(node)
		var baked := mi.bake_mesh_from_current_skeleton_pose()
		var low := INF
		for s in baked.get_surface_count():
			for v: Vector3 in baked.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var w := mi.global_transform * v
				if Vector2(w.x - hips.x, w.z - hips.z).length() < SEAT_PROBE_M:
					low = minf(low, w.y)
		var pan: float = hit["position"].y if not hit.is_empty() else NAN
		print(
			(
				"SEAT_GAP %s hips=%s pan_top=%.3f body_low=%.3f gap_m=%.3f"
				% [subjects[node], hips, pan, low, low - pan]
			)
		)
		if hit.is_empty():
			_invalid("%s: no seat pan under the hips" % subjects[node])
	holder.free()
	await _overlaps(group, people, chairs, subjects)
	var ok: bool = await _proven("seated_%d" % group, subjects, false)
	var img: Image = await _grab(false)
	if ok:
		_save(img, "seated_%d.png" % group, VARIETY_REL)
		for k in people.size():
			_seated_shot[group * 3 + k] = true
	await _close_ups(people, chairs, subjects, close)
