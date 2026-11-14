extends "res://spike/passenger_looks_plates_probe.gd"
## Windowed plates and seat sweeps for the added passenger bodies (board
## 3fcd8e5a: male 04 and 05 and female 06, 09 and 12), built on the passenger
## looks plates probe:
## - crowd: its crowd of passengers in spawn order (--seed=N);
## - seated: the bodies on their own gate seat rows in groups of three (the base
##   probe shoots the first twelve only), with SEAT_OVERLAP checks and, with
##   --sweep, the least step out of the row per body;
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
		# The base probe seats three bodies per group; a remainder is named, never
		# passed silently.
		for group in PassengerLooks.BODIES.size() / 3:
			await _seated(group, close)
		for body in range(PassengerLooks.BODIES.size() / 3 * 3, PassengerLooks.BODIES.size()):
			print("SEATED_NOT_SHOT %s (not in a group of three)" % PassengerLooks.BODIES[body])
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
