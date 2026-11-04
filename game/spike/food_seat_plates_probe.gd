extends SceneTree
## Guests seated at the food-room pieces of the services kit (board 3405a04b):
## the restaurant table's chairs, the restaurant booth's benches and the bar
## counter's stools. Each seat is read from the piece's own Mount_SitRoot_*
## (the .glb is the authority), and a body is drawn there in sit_idle, stepped
## towards the table and up by PassengerLooks.seat_shift().
##
## --parts=sweep (windowed too: a headless run cannot bake a posed body, and
## says so with PROBE_INVALID): for every body at every piece, the body
## points inside the piece at the bare root (SEAT_BARE), at the cafe chair's
## step the game drew before (SEAT_CAFE; SEAT_CONTROL fails when no body
## reaches into the piece at either, as the check could then see nothing), at
## seat_shift() at each SIT_PHASES point (SEAT_FIT, which must be none), the
## gap from the body to the seat cushion (SEAT_PAN, a gap over FLOAT_M floats),
## and the least step towards the table that leaves no point inside
## (SEAT_SWEEP), for each lift.
## --parts=plates (windowed): per piece six orthographic views at true scale
## beside a 1 m cube with a male and a female guest seated, a side-on close-up
## of each guest, a three-quarter in-context view, a distance shot of all three
## pieces, and a contact sheet. Every plate proves each guest is in frame (its
## bounds projected inside the plate with a margin) and seen (sight lines land
## on it) before it is saved; a failure prints PROBE_INVALID and exits 1.
##
## Run (windowed, in the one windowed slot):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows
##     --rendering-driver vulkan --audio-driver Dummy --path <checkout>/game
##     -s res://spike/food_seat_plates_probe.gd -- --parts=sweep,plates
## Plates go to tools/blender/out/food-seats/.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/food-seats"
const MARGIN_PX := 8.0
## Piece -> [male guest's seat mount, female guest's seat mount].
const SEATS := {
	&"restaurant_table": ["Mount_SitRoot_BL", "Mount_SitRoot_FR"],
	&"restaurant_booth": ["Mount_SitRoot_BL", "Mount_SitRoot_FR"],
	&"bar_counter": ["Mount_SitRoot_L", "Mount_SitRoot_R"],
}
## The bodies on the plates: a male and the female body whose dress hangs
## lowest (female_01, the one that needs a lift on the cafe chair).
const MALE := 0
const FEMALE := 6
const VIEWS := {
	"front": Vector3(0, 0, 1),
	"back": Vector3(0, 0, -1),
	"left": Vector3(-1, 0, 0),
	"right": Vector3(1, 0, 0),
	"top": Vector3(0, 1, 0),
	"bottom": Vector3(0, -1, 0),
}
const SIX_M := 4.2
## Beside and behind the piece, so from no axis does it stand in front of a
## guest.
const CUBE_AT := Vector3(-1.6, 0.0, -1.9)
const SIT_PHASES: Array[float] = [0.0, 0.25, 0.5, 0.75]
## A body point this far behind every face of a piece part is inside it.
const OVERLAP_SLACK_M := 0.002
## A body whose lowest point is further than this over the cushion floats.
const FLOAT_M := 0.03
## Body points within this height band of the cushion top are what sits on it.
const PAN_TOP_RANGE := Vector2(0.45, 0.6)

var _failed := false
var _out := ""
var _cam := Camera3D.new()
var _stage := Node3D.new()


func _initialize() -> void:
	_out = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	return false


func _run() -> void:
	var parts := ["sweep"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--parts="):
			parts = Array(arg.get_slice("=", 1).split(","))
	print("PROBE out=", _out, " parts=", parts, " bodies=", PassengerLooks.BODIES.size())
	_studio()
	root.add_child(_cam)
	root.add_child(_stage)
	_cam.current = true
	if "sweep" in parts:
		for piece: StringName in SEATS:
			await _sweep(piece)
	if "plates" in parts:
		var sheet: Array[Image] = []
		for piece: StringName in SEATS:
			await _plates(piece, sheet)
		await _distance(sheet)
		_save(_sheet(sheet, 6, 300), "food_seats_contact_sheet.png")
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _studio() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.86, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)


func _clear() -> void:
	for child in _stage.get_children():
		child.free()


## The piece `id` at `at`, with meta "piece" for the part names.
func _piece(id: StringName, at: Vector3) -> Node3D:
	var node := InteriorKit.instantiate(InteriorKit.object_piece(id))
	node.set_meta(&"piece", id)
	_stage.add_child(node)
	node.position = at
	return node


## The seat mount's frame in the piece's frame.
func _mount(piece: Node3D, mount_name: String) -> Transform3D:
	var node := piece.find_child(mount_name, true, false) as Node3D
	if node == null:
		_invalid("%s has no %s" % [piece.get_meta(&"piece"), mount_name])
		return Transform3D()
	var xf := node.transform
	var parent := node.get_parent()
	while parent != piece:
		xf = (parent as Node3D).transform * xf
		parent = parent.get_parent()
	return xf


## A body seated in sit_idle at `mount` of `piece`, stepped `shift` (towards
## the table, up) from the bare root.
func _guest(body: int, piece: Node3D, mount: String, shift: Vector2) -> Node3D:
	var xf := piece.global_transform * _mount(piece, mount)
	var facing := xf.basis.z.normalized()
	var node := PassengerLooks.SCENES[body].instantiate() as Node3D
	_stage.add_child(node)
	PassengerLooks.paint_body(node, body, 0)
	node.set_meta(&"body", body)
	node.set_meta(&"root", xf.origin)
	node.set_meta(&"facing", facing)
	node.position = xf.origin + facing * shift.x + Vector3.UP * shift.y
	node.rotation.y = atan2(facing.x, facing.z)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	player.play("sit_idle")
	player.seek(0.0, true)
	player.speed_scale = 0.0
	return node


func _place(node: Node3D, shift: Vector2) -> void:
	var root_at: Vector3 = node.get_meta(&"root")
	var facing: Vector3 = node.get_meta(&"facing")
	node.position = root_at + facing * shift.x + Vector3.UP * shift.y


func _seek_all(people: Array[Node3D], phase: float) -> void:
	for node in people:
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		player.seek(phase * player.current_animation_length, true)
	for i in 2:
		await process_frame


# --------------------------------------------------------------- sweep


## SEAT_BARE, SEAT_CAFE, SEAT_FIT, SEAT_PAN and SEAT_SWEEP for every body at
## the male guest's seat of `id` (the seats of a piece are mirror images).
func _sweep(id: StringName) -> void:
	_clear()
	var people: Array[Node3D] = []
	var pieces: Array[Node3D] = []
	for body in PassengerLooks.BODIES.size():
		var piece := _piece(id, Vector3(body * 4.0, 0, 0))
		pieces.append(piece)
		people.append(_guest(body, piece, SEATS[id][0], PassengerLooks.seat_shift(id, body)))
	var islands: Array = []
	for piece in pieces:
		islands.append(_islands(piece))
	var cafe_hits := 0
	var control_hits := 0
	for phase in SIT_PHASES:
		await _seek_all(people, phase)
		for k in people.size():
			var hits := _overlap(people[k], islands[k])
			print(
				"SEAT_FIT %s %s phase=%.2f points=%d %s" % [id, _stem(k), phase, _sum(hits), hits]
			)
			if _sum(hits) > 0:
				_invalid("%s %s: body points inside the piece" % [id, _stem(k)])
	await _seek_all(people, 0.0)
	for k in people.size():
		var pan := _pan_gap(people[k], islands[k])
		print("SEAT_PAN %s %s gap=%.3f" % [id, _stem(k), pan])
		if pan > FLOAT_M:
			_invalid("%s %s floats %.3f m over the cushion" % [id, _stem(k), pan])
		var fit := PassengerLooks.seat_shift(id, k)
		_place(people[k], Vector2.ZERO)
		var bare := _overlap(people[k], islands[k])
		print("SEAT_BARE %s %s points=%d %s" % [id, _stem(k), _sum(bare), bare])
		_place(people[k], PassengerLooks.CAFE_SEAT_SHIFT_M[k])
		var cafe := _overlap(people[k], islands[k])
		cafe_hits += _sum(cafe)
		control_hits += _sum(bare) + _sum(cafe)
		print("SEAT_CAFE %s %s points=%d %s" % [id, _stem(k), _sum(cafe), cafe])
		for dyi in 3:
			var found := -1.0
			for step in 41:
				_place(people[k], Vector2(step * 0.005, dyi * 0.01))
				if _overlap(people[k], islands[k]).is_empty():
					found = step * 0.005
					break
			print("SEAT_SWEEP %s %s dy=%.2f min_ahead=%.3f" % [id, _stem(k), dyi * 0.01, found])
		_place(people[k], fit)
	# The control: at the bare root or at the cafe chair's step some body
	# reaches into the piece, or the check could not see an overlap.
	print("SEAT_CONTROL %s cafe_points=%d bare_or_cafe_points=%d" % [id, cafe_hits, control_hits])
	if control_hits == 0:
		_invalid("control: no body reaches into %s at the bare root or the cafe step" % id)


func _stem(body: int) -> String:
	return PassengerLooks.BODIES[body].replace("tcp_", "").replace("_character", "")


func _sum(hits: Dictionary) -> int:
	var total := 0
	for key: String in hits:
		total += hits[key]
	return total


## The posed body's points in world space.
func _points(person: Node3D) -> PackedVector3Array:
	var mi := PassengerLooks.body_mesh(person)
	var baked := mi.bake_mesh_from_current_skeleton_pose()
	var out := PackedVector3Array()
	if baked == null:
		# A headless run has no skinning; nothing measured is not a pass.
		_invalid("%s: the posed body could not be baked" % person.name)
		return out
	for s in baked.get_surface_count():
		for v: Vector3 in baked.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			out.append(mi.global_transform * v)
	return out


## Body points inside the piece, counted by part.
func _overlap(person: Node3D, islands: Array) -> Dictionary:
	var counts := {}
	for p in _points(person):
		var part := _inside(islands, p)
		if part != "":
			counts[part] = counts.get(part, 0) + 1
	return counts


## The least outward distance of a body point from a cushion island: 0 or
## less when the body rests on (or in) the cushion.
func _pan_gap(person: Node3D, islands: Array) -> float:
	var gap := INF
	var points := _points(person)
	for island: Dictionary in islands:
		if island["part"] != "cushion":
			continue
		for p in points:
			var out := -INF
			for plane: Array in island["planes"]:
				out = maxf(out, (p - (plane[0] as Vector3)).dot(plane[1]))
			gap = minf(gap, out)
	return gap


## The piece's convex islands in world space: [{"part", "planes"}], each plane
## a [point, outward normal] pair.
func _islands(piece: Node3D) -> Array:
	var out := []
	for mi: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		var faces := mi.mesh.get_faces()
		var tris := faces.size() / 3
		var parent := {}
		for t in tris:
			var a := _root_of(parent, _weld(faces[t * 3]))
			for c in [1, 2]:
				var b := _root_of(parent, _weld(faces[t * 3 + c]))
				if a != b:
					parent[b] = a
		var groups := {}
		for t in tris:
			var r := _root_of(parent, _weld(faces[t * 3]))
			if not groups.has(r):
				groups[r] = []
			(groups[r] as Array).append(t)
		for r: Vector3i in groups:
			var pts := PackedVector3Array()
			for t: int in groups[r]:
				for c in 3:
					pts.append(mi.global_transform * faces[t * 3 + c])
			var box := AABB(pts[0], Vector3.ZERO)
			for p in pts:
				box = box.expand(p)
			var centre := box.get_center()
			var planes := []
			for i in range(0, pts.size(), 3):
				var n := (pts[i + 1] - pts[i]).cross(pts[i + 2] - pts[i])
				if n.length() < 1e-9:
					continue
				n = n.normalized()
				if n.dot(centre - pts[i]) > 0.0:
					n = -n
				planes.append([pts[i], n])
			# Parts that share vertices weld into one island (the booth's base and
			# back panel); the hull of such an island covers the gap
			# between its parts, so it is tested by ray parity instead.
			var convex := true
			for plane: Array in planes:
				for p in pts:
					if (p - (plane[0] as Vector3)).dot(plane[1]) > 1e-3:
						convex = false
						break
				if not convex:
					break
			var part := _part(box, piece)
			if not convex:
				var local := piece.global_transform.affine_inverse() * box
				print(
					(
						"ISLAND_NONCONVEX %s %s tris=%d local=%s"
						% [piece.get_meta(&"piece"), part, pts.size() / 3, local]
					)
				)
			out.append({"part": part, "planes": planes, "convex": convex, "tris": pts, "box": box})
	return out


## True when `p` is inside the closed triangle soup `tris`: a vertical ray up
## from just beside `p` crosses it an odd number of times.
func _inside_by_parity(tris: PackedVector3Array, p: Vector3) -> bool:
	var o := p + Vector3(1.3e-4, 0.0, 0.7e-4)
	var crossings := 0
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var det := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
		if absf(det) < 1e-12:
			continue
		var u := ((o.x - a.x) * (c.z - a.z) - (c.x - a.x) * (o.z - a.z)) / det
		var v := ((b.x - a.x) * (o.z - a.z) - (o.x - a.x) * (b.z - a.z)) / det
		if u < 0.0 or v < 0.0 or u + v > 1.0:
			continue
		if a.y + u * (b.y - a.y) + v * (c.y - a.y) > o.y:
			crossings += 1
	return crossings % 2 == 1


func _weld(p: Vector3) -> Vector3i:
	return Vector3i((p * 1000.0).round())


func _root_of(parent: Dictionary, k: Vector3i) -> Vector3i:
	while parent.has(k):
		k = parent[k]
	return k


## A piece part named by its bounds in the piece's frame
## (tools/blender/interior/build_services_kit.py): the dining table in the
## middle row (|z| < 0.4), the bar counter in the back row (z < -0.15); a seat
## part with its top at cushion height is a "cushion".
func _part(box: AABB, piece: Node3D) -> String:
	var local := piece.global_transform.affine_inverse() * box
	var c := local.get_center()
	if piece.get_meta(&"piece") == &"bar_counter":
		if c.z < -0.15:
			return "counter"
	elif absf(c.z) < 0.4:
		return "table"
	var top := local.end.y
	if top > PAN_TOP_RANGE.x and top < PAN_TOP_RANGE.y and local.size.y < 0.2:
		return "cushion"
	return "seat"


func _inside(islands: Array, p: Vector3) -> String:
	for island: Dictionary in islands:
		if not island["convex"]:
			var box: AABB = island["box"]
			if box.has_point(p) and _inside_by_parity(island["tris"], p):
				return island["part"]
			continue
		var ok := true
		for plane: Array in island["planes"]:
			if (p - (plane[0] as Vector3)).dot(plane[1]) > -OVERLAP_SLACK_M:
				ok = false
				break
		if ok:
			return island["part"]
	return ""


# --------------------------------------------------------------- plates


## The piece at the origin with the male and the female guest, a 1 m cube
## beside it: six orthographic views, a side-on close-up of each guest and a
## three-quarter view.
func _plates(id: StringName, sheet: Array[Image]) -> void:
	_clear()
	var piece := _piece(id, Vector3.ZERO)
	var guests := {}
	for k in 2:
		var body := MALE if k == 0 else FEMALE
		var node := _guest(body, piece, SEATS[id][k], PassengerLooks.seat_shift(id, body))
		guests[node] = "%s_%s" % [id, _stem(body)]
	var cube := _cube(CUBE_AT)
	for i in 3:
		await process_frame
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = SIX_M
	var centre := Vector3(-0.6, 0.8, -0.5)
	for view: String in VIEWS:
		var dir: Vector3 = VIEWS[view]
		_cam.global_position = centre + dir * 12.0
		var up := Vector3.FORWARD if absf(dir.y) > 0.5 else Vector3.UP
		_cam.look_at(centre, up)
		var subjects := guests.duplicate()
		subjects[cube] = "cube"
		# From some sides the booth's back panel or the bar counter hides a seated
		# guest by design; there the piece counts as the guest's for its sight
		# lines (the guest must still be in frame). The close-ups and the
		# in-context view prove each guest seen on its own.
		await _shoot("%s_six_%s" % [id, view], subjects, sheet, piece)
	# Side-on close-ups: across the guest's facing, so the hips on the cushion
	# and the back against the chair back show. At the booth the bench's end
	# panel stands on that side, so the view looks down over it from the open
	# end, three-quarter from the front, about 50 degrees up.
	_cam.size = 1.8
	cube.visible = false
	for node: Node3D in guests:
		var facing: Vector3 = node.get_meta(&"facing")
		var across := facing.cross(Vector3.UP).normalized()
		var at: Vector3 = node.get_meta(&"root") + Vector3(0, 0.75, 0)
		var dir := across
		if id == &"restaurant_booth":
			at = node.get_meta(&"root") + Vector3(0, 0.7, 0)
			_cam.size = 2.3
			dir = (across * 0.8 + facing * 0.4 + Vector3.UP * 1.1).normalized()
		for other: Node3D in guests:
			other.visible = other == node
		_cam.global_position = at + dir * 10.0
		_cam.look_at(at, Vector3.UP)
		await _shoot("%s_close" % guests[node], {node: guests[node]}, sheet)
	for other: Node3D in guests:
		other.visible = true
	cube.visible = true
	# Three-quarter perspective from high on the open side (+X), as the player
	# looks down into a furnished room; the cube stands on the far side.
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 40.0
	_cam.global_position = Vector3(4.2, 4.2, 1.2)
	_cam.look_at(Vector3(-0.3, 0.6, -0.2), Vector3.UP)
	await _shoot("%s_context" % id, guests, sheet)


## The three pieces side by side with their guests, from the game's distance.
func _distance(sheet: Array[Image]) -> void:
	_clear()
	var guests := {}
	var x := -3.0
	for id: StringName in SEATS:
		var piece := _piece(id, Vector3(x, 0, 0))
		for k in 2:
			var body := MALE if k == 0 else FEMALE
			var node := _guest(body, piece, SEATS[id][k], PassengerLooks.seat_shift(id, body))
			guests[node] = "%s_%s" % [id, _stem(body)]
		x += 3.0
	guests[_cube(Vector3(0, 0, 3.0))] = "cube"
	for i in 3:
		await process_frame
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 40.0
	_cam.global_position = Vector3(0, 9.0, 9.5)
	_cam.look_at(Vector3(0, 0.5, 0.5), Vector3.UP)
	await _shoot("distance", guests, sheet)


func _cube(at: Vector3) -> Node3D:
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.45, 0.2)
	cube.material_override = mat
	cube.position = at + Vector3(0, 0.5, 0)
	_stage.add_child(cube)
	return cube


## Proves, grabs and saves one plate; a failed proof saves nothing.
## With `piece`, the piece's meshes count as each guest's for its sight lines.
func _shoot(name: String, subjects: Dictionary, sheet: Array[Image], piece: Node3D = null) -> void:
	var ok: bool = await _proven(name, subjects, piece)
	var img: Image = await _grab()
	sheet.append(img)
	if ok:
		_save(img, name + ".png")


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var local := mi.get_aabb()
		if mi.skin != null:
			local = mi.bake_mesh_from_current_skeleton_pose().get_aabb()
		var b := mi.global_transform * local
		box = b if first else box.merge(b)
		first = false
	if node is MeshInstance3D:
		box = node.global_transform * (node as MeshInstance3D).get_aabb()
	return box


## The square crop of the window, after the scene settled.
func _grab() -> Image:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var side := mini(img.get_width(), img.get_height())
	var x := (img.get_width() - side) / 2
	var y := (img.get_height() - side) / 2
	return img.get_region(Rect2i(x, y, side, side))


## Every subject in the square crop with a margin (all eight bounds corners)
## and seen: of nine sight lines from the camera to the middle of its bounds,
## at least PlateSight.MIN_ON land on it first (a seated guest is partly behind
## its table or chair from most sides, so a blocked line alone does not fail).
func _proven(label: String, subjects: Dictionary, piece: Node3D) -> bool:
	var size := root.get_visible_rect().size
	var side := minf(size.x, size.y)
	var frame := Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side)).grow(-MARGIN_PX)
	var owners: Array[Node] = [_stage]
	var ok := true
	var basis := _cam.global_transform.basis
	for node: Node3D in subjects:
		var tag: String = subjects[node]
		var tags := {node: tag}
		if piece != null and tag != "cube":
			tags[piece] = tag
		var holder := PlateSight.colliders(root, owners, tags)
		if not (holder.get_meta(&"unbaked", []) as Array).is_empty():
			_invalid("%s: unbaked meshes %s" % [label, holder.get_meta(&"unbaked")])
		await physics_frame
		await physics_frame
		var space := _cam.get_world_3d().direct_space_state
		var box := _bounds(node)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for k in 8:
			var px := _cam.unproject_position(box.get_endpoint(k))
			lo = lo.min(px)
			hi = hi.max(px)
		var inside := frame.has_point(lo) and frame.has_point(hi)
		var span := absf(box.size.dot(basis.x))
		var tall := absf(box.size.dot(basis.y))
		var on := 0
		var blocked: Array[String] = []
		for i in 3:
			for j in 3:
				var at := (
					box.get_center()
					+ basis.x * (0.2 * (i - 1) * span)
					+ basis.y * (0.2 * (j - 1) * tall)
				)
				var from := _cam.global_position
				if _cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
					from = at + basis.z * 20.0
				var one: Array[Vector3] = [at]
				var lines := PlateSight.sight_lines(space, from, one, tag)
				on += (lines["on_subject"] as Array).size()
				blocked.append_array(lines["blockers"])
		print(
			(
				"PROOF %s %s px=%s..%s frame=%s in_frame=%s sight_on=%d of 9 blockers=%d"
				% [label, tag, lo.round(), hi.round(), frame, inside, on, blocked.size()]
			)
		)
		if not inside or on < PlateSight.MIN_ON:
			_invalid("%s: %s not in frame or not seen" % [label, tag])
			ok = false
		holder.free()
	return ok


func _save(img: Image, name: String) -> void:
	var path := _out.path_join(name)
	img.save_png(path)
	print("PLATE ", path, " size=", img.get_size())


func _sheet(images: Array[Image], cols: int, tile: int) -> Image:
	var rows := ceili(images.size() / float(cols))
	var out := Image.create(cols * tile, rows * tile, false, Image.FORMAT_RGBA8)
	out.fill(Color(1, 1, 1))
	for i in images.size():
		var img := images[i].duplicate() as Image
		img.convert(Image.FORMAT_RGBA8)
		img.resize(tile, tile, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(
			img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(i % cols, i / cols) * tile
		)
	return out
