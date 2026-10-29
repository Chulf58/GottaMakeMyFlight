extends RefCounted
## Close-up plates of one chosen carrier during the security visuals probe's
## crowd sweep, for a before/after of a carry-on fix: with --plate-id=N (and
## --plate-tag=T, --plate-cell=X,Y[/X,Y...]) passenger N is plated while it stands on
## one of those cells with every bag settled in hand, from up to SHOTS headings (round the
## body from its hand side, then the same higher) until WANTED are saved. A
## shot takes three sweep frames: aim; read the frame that drew (the image, the bounds
## projected through the camera and colliders of that same pose); after a
## physics step, sight lines to the bag. It is saved only when the bag's and
## body's bounds are inside the viewport by MARGIN_PX, the body is at least
## MIN_BODY_PX tall, a sight line lands on the bag and none is blocked; else
## the heading is rejected (printed) and the next tried. No saved shot by the
## end of the sweep (finish()) is a problem. Plates go to
## tools/blender/out/carry-roller-diagonal/. Load with preload(); no
## class_name.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/carry-roller-diagonal"
const MARGIN_PX := 8.0
const MIN_BODY_PX := 200.0
## Camera distance from the look-at point and its height over the floor (m).
const DISTANCE_M := 3.6
const HEIGHT_M := 2.4
## Headings tried (8 round the body, at HEIGHT_M then 1.2 m higher), and how
## many saved shots are enough.
const SHOTS := 16
const WANTED := 2

var problems: Array[String] = []
var saved: Array[String] = []
var _id := 0
var _tag := "plate"
var _cells: Array[Vector2i] = []
var _shot := 0
## 0 idle, 1 aimed (the next frame draws the shot), 2 read (colliders up).
var _phase := 0
var _cam: Camera3D
var _was: Camera3D
var _holder: Node3D
var _image: Image
var _line := ""
var _in_frame := false
var _targets: Array[Vector3] = []


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--plate-id="):
			_id = int(arg.get_slice("=", 1))
		elif arg.begins_with("--plate-tag="):
			_tag = arg.get_slice("=", 1)
		elif arg.begins_with("--plate-cell="):
			for spot in arg.get_slice("=", 1).split("/"):
				var xy := spot.split(",")
				_cells.append(Vector2i(int(xy[0]), int(xy[1])))


## Called before each sweep frame is drawn.
func step(views: PassengerViews, sim: PassengerSim) -> void:
	if _id == 0 or _shot >= SHOTS or saved.size() >= WANTED:
		return
	match _phase:
		1:
			_read(views)
		2:
			_judge(views)
		_:
			_aim(views, sim)


## At the end of the sweep: a requested plate with no saved shot is a problem;
## a shot still in flight is dropped.
func finish() -> void:
	_drop()
	if _id != 0 and saved.is_empty():
		problems.append("plate id=%d at %s: no shot saved" % [_id, _cells])


func _aim(views: PassengerViews, sim: PassengerSim) -> void:
	var p := sim.get_passenger(_id)
	var body := views.node_for(_id)
	if p == null or body == null or p.at not in _cells or p.carry_on == 0:
		return
	var props := views.carry_on_props()
	var bags: Array[Node3D] = props.props_of(_id)["bags"]
	var homes := SecurityLooks.bag_homes(sim, p)
	if bags.size() != p.carry_on or homes.size() != bags.size():
		return
	for i in bags.size():
		if homes[i] != SecurityLooks.Home.HAND or props.transfer_progress(_id, i) < 1.0:
			return
	var hand := SecurityLooks.hand_of(sim, p, 0)
	var turn := Basis(Vector3.UP, body.rotation.y)
	var side := turn * (Vector3.LEFT if hand == 0 else Vector3.RIGHT)
	var behind := turn * Vector3.FORWARD
	var look_at := body.global_position + behind * 0.45 + Vector3.UP * 0.45
	var away := Basis(Vector3.UP, (_shot % 8) * PI / 4.0) * side
	var up := HEIGHT_M + 1.2 * floorf(_shot / 8.0)
	_was = views.get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.fov = 40.0
	views.get_tree().root.add_child(_cam)
	_cam.global_position = look_at + away * DISTANCE_M + Vector3.UP * (up - 0.45)
	_cam.look_at(look_at, Vector3.UP)
	_cam.make_current()
	_phase = 1


## The aimed frame has drawn and nothing has moved since: its image, the
## bounds through the camera, and colliders of this pose.
func _read(views: PassengerViews) -> void:
	var name := "%s_h%d_a%03d_id%d" % [_tag, floori(_shot / 8.0), (_shot % 8) * 45, _id]
	var body := views.node_for(_id)
	var bags: Array[Node3D] = views.carry_on_props().props_of(_id)["bags"]
	if body == null or bags.is_empty():
		_fail(name, "the subject left")
		return
	_image = views.get_viewport().get_texture().get_image()
	var size := views.get_viewport().get_visible_rect().size
	var corners: Array[Vector3] = []
	for mi: MeshInstance3D in bags[0].find_children("*", "MeshInstance3D", true, false):
		var box := mi.global_transform * mi.get_aabb()
		for k in 8:
			corners.append(box.get_endpoint(k))
	var centre := Vector3.ZERO
	for at in corners:
		centre += at
	centre /= corners.size()
	_targets = [centre]
	for k in range(0, corners.size(), 3):
		_targets.append(centre.lerp(corners[k], 0.5))
	corners.append(body.global_position)
	corners.append(body.global_position + Vector3.UP * 1.7)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for at in corners:
		var px := _cam.unproject_position(at)
		lo = lo.min(px)
		hi = hi.max(px)
	var feet := _cam.unproject_position(body.global_position)
	var tall := absf(feet.y - _cam.unproject_position(corners[-1]).y)
	_in_frame = (
		lo.x >= MARGIN_PX
		and lo.y >= MARGIN_PX
		and hi.x <= size.x - MARGIN_PX
		and hi.y <= size.y - MARGIN_PX
		and tall >= MIN_BODY_PX
	)
	_line = (
		"PLATE %s bbox_px=(%.0f,%.0f)-(%.0f,%.0f) viewport=%s body_px=%.0f"
		% [name, lo.x, lo.y, hi.x, hi.y, size, tall]
	)
	var owners: Array[Node] = [views.get_tree().root]
	# The carrier and its bag are the subject: a line may land on either.
	_holder = PlateSight.colliders(views.get_tree().root, owners, {bags[0]: "bag", body: "bag"})
	_phase = 2


## After a physics step: sight lines to the bag, then the verdict.
func _judge(views: PassengerViews) -> void:
	var name := "%s_h%d_a%03d_id%d" % [_tag, floori(_shot / 8.0), (_shot % 8) * 45, _id]
	var space := views.get_viewport().world_3d.direct_space_state
	var lines := PlateSight.sight_lines(space, _cam.global_position, _targets, "bag")
	var landed: int = (lines["on_subject"] as Array).size()
	var unbaked: Array = _holder.get_meta("unbaked")
	print(
		(
			"%s sight_on=%d of %d blocked=%s unbaked=%d"
			% [_line, landed, _targets.size(), lines["blockers"], unbaked.size()]
		)
	)
	if not _in_frame or landed == 0 or not (lines["blockers"] as Array).is_empty():
		_fail(name, "not in frame, too small or hidden")
		return
	if not unbaked.is_empty():
		_fail(name, "meshes not baked for the sight lines: %s" % [unbaked])
		return
	var dir := ProjectSettings.globalize_path(OUT_REL)
	var path := dir.path_join(name + ".png")
	var made := DirAccess.make_dir_recursive_absolute(dir)
	var wrote := _image.save_png(path) if made == OK else made
	if wrote != OK:
		problems.append("plate %s not written (error %d)" % [path, wrote])
		print("PROBE_INVALID plate %s not written (error %d)" % [path, wrote])
	else:
		saved.append(path)
		print("PLATE saved ", path)
	_drop()
	_shot += 1


func _fail(name: String, why: String) -> void:
	print("PLATE rejected %s: %s" % [name, why])
	_drop()
	_shot += 1


func _drop() -> void:
	if _holder != null:
		_holder.queue_free()
		_holder = null
	if _cam != null:
		_cam.queue_free()
		_cam = null
		if _was != null:
			_was.make_current()
	_phase = 0
