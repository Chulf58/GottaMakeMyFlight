extends SceneTree
## Windowed plate probe for Runway R4 (board c6564501): the airside moved 28 m
## north, with the runway at z -338, the taxi lane at z -284 and its ends at
## x +-124 (decision runway-and-taxi-technical-design-movement-plan-analytic-
## bookings-planned-pauses).
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/runway_r4_plates_probe.gd
##
## Boots main.tscn as the game does (starter shell, one stand), moves the stand
## to the north row with Airside.set_stand() so its paving follows, and adds two
## model 07 planes, the largest: one parked door-aligned on a north-row stand
## (wall z -210) and one on the lane centreline in front of it, so the plates
## show the large tail's clearance from the lane traffic. Plates: one top-down
## of the whole airside, one top-down close-up of the north-row stand and the
## lane, and the play camera at each angle step looking north from the north
## edge of its bounds at full zoom-out. Before each plate, every subject (the
## runway's middle, both lane ends, the stand, the two planes) is projected
## and must fall inside the viewport, and no collider may sit between the camera
## and it; otherwise PROBE_INVALID is printed and the probe exits 1. The HUD is
## hidden. Plates go to tools/blender/out/runway_r4/. Prints the world seed.

const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/runway_r4"
const LARGE_MODEL := "tp_plane_07a"
const MARGIN_PX := 8.0

var _out_dir := ""
var _failed := false
var _main: Node


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var seed_value := randi()
	seed(seed_value)
	print("PROBE out_dir=%s seed=%d" % [_out_dir, seed_value])
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await _frames(30)
	# The HUD panels would cover the runway and lane in every plate.
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var airside := _main.get_node("Airside") as Airside
	var at := func(waypoint: StringName) -> Vector3: return airside.graph.position_of(waypoint)
	var north := StandPlacement.make(1, 0.5, -210.0)
	var stand_point := StandPlacement.stand_point(north)
	# The stand and its paving follow to the north row, under the parked plane.
	if not airside.set_stand(north):
		_invalid("set_stand(%s) failed" % [north])
	var shift := PlaneClasses.stand_offset(LARGE_MODEL)
	var parked := _plane(stand_point + shift, 0.0)
	var on_lane := _plane(Vector3(stand_point.x + 60.0, 0.0, StandPlacement.TAXI_LANE_Z), -PI / 2.0)
	var tail_z := stand_point.z + shift.z - float(PlaneModels.PLANES[LARGE_MODEL]["tail"])
	var band := StandPlacement.TAXI_LANE_Z + float(PlaneModels.PLANES[LARGE_MODEL]["half_span"])
	print(
		(
			"large north-row tail z %.2f, large lane band edge z %.2f, clearance %.2f m"
			% [tail_z, band, tail_z - band]
		)
	)
	await _frames(10)
	var stand_now: Vector3 = at.call(&"Stand")
	print("Stand waypoint at %s, north-row stand point %s" % [stand_now, stand_point])
	if stand_now.distance_to(stand_point) > 0.01:
		_invalid("the stand moved off the north row to %s" % stand_now)
	var subjects := {
		"runway middle": Vector3(0.0, 0.0, StandPlacement.RUNWAY_Z),
		"TaxiEast": at.call(&"TaxiEast"),
		"TaxiWest": at.call(&"TaxiWest"),
		"RunwayExit": at.call(&"RunwayExit"),
		"RunwayEntry": at.call(&"RunwayEntry"),
		"north-row stand": at.call(&"Stand"),
		"parked large": parked.global_position + Vector3(0.0, 4.0, 0.0),
		"large on lane": on_lane.global_position + Vector3(0.0, 4.0, 0.0),
	}
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 330.0
	top.far = 2000.0
	root.add_child(top)
	top.global_transform = Transform3D(
		Basis.from_euler(Vector3(-PI / 2.0, 0.0, 0.0)), Vector3(0.0, 600.0, -215.0)
	)
	top.make_current()
	await _plate(top, subjects, "r4_top_whole_airside.png")
	top.size = 120.0
	top.global_position = Vector3(20.0, 600.0, -262.0)
	var close := {}
	for key in ["parked large", "large on lane"]:
		close[key] = subjects[key]
	close["lane at the stand"] = Vector3(stand_point.x, 0.0, StandPlacement.TAXI_LANE_Z)
	await _plate(top, close, "r4_top_north_stand_and_lane.png")
	top.queue_free()
	var rig := _main.get_node("TycoonCamera") as TycoonCamera
	var cam := rig.get_node("Camera3D") as Camera3D
	cam.make_current()
	var far_view := {}
	for key in ["runway middle", "TaxiEast", "TaxiWest", "parked large", "large on lane"]:
		far_view[key] = subjects[key]
	for step in TycoonCamera.AngleStep.values():
		rig.set_angle_step(step)
		rig.position = Vector3(0.0, 0.0, -rig.bounds_half_extent)
		rig.yaw = 0.0
		rig.distance = rig.max_distance
		rig.zoom(1.0)
		await _frames(90)
		await _plate(cam, far_view, "r4_play_camera_angle_%d.png" % step)
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _plane(position: Vector3, yaw: float) -> Node3D:
	var model := (
		(load(PlaneModels.PLANES[LARGE_MODEL]["path"]) as PackedScene).instantiate() as Node3D
	)
	_main.add_child(model)
	model.global_transform = Transform3D(Basis(Vector3.UP, yaw), position)
	return model


func _plate(cam: Camera3D, subjects: Dictionary, name: String) -> void:
	await _frames(5)
	var size := root.get_visible_rect().size
	var space := root.world_3d.direct_space_state
	for key: String in subjects:
		var point: Vector3 = subjects[key]
		var screen := cam.unproject_position(point)
		var inside := (
			not cam.is_position_behind(point)
			and screen.x > MARGIN_PX
			and screen.y > MARGIN_PX
			and screen.x < size.x - MARGIN_PX
			and screen.y < size.y - MARGIN_PX
		)
		var query := PhysicsRayQueryParameters3D.create(
			cam.global_position, point + (point - cam.global_position).normalized() * 3.0
		)
		var hit := space.intersect_ray(query)
		# Hidden when a collider sits between the camera and the subject, more
		# than 2 m in front of it. The ground and paving have no colliders, so
		# no hit means nothing solid is in the way.
		var to_point := cam.global_position.distance_to(point)
		var to_hit := INF if hit.is_empty() else cam.global_position.distance_to(hit["position"])
		var hidden := to_hit < to_point - 2.0
		print(
			(
				"%s: %s at %s screen %s inside=%s, %.1f m from the camera, first hit %.1f m"
				% [name, key, point, screen, inside, to_point, to_hit]
			)
		)
		if not inside:
			_invalid("%s: %s is out of frame" % [name, key])
		elif hidden:
			_invalid("%s: %s is hidden (hit %.1f m before it)" % [name, key, to_point - to_hit])
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join(name)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw
