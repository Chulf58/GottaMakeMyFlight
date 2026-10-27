extends RefCounted
## Shared checks for the windowed plates probes (miss_reasons, passenger and
## cafe): sight lines against the meshes the plate actually draws, and the HUD
## measured against a twin plate with the scene's canvas layers hidden. Load
## it with preload(); it has no class_name, so the spike adds nothing to the
## game's global class list.
##
## Sight lines: colliders() builds one static body per visible mesh of the
## given owners, in world space and in the pose drawn now (a skinned mesh is
## baked from its current skeleton pose). A body inside a subject node carries
## the subject's tag. sight_lines() classifies each line by its first hit.

## A line runs this far past its target point.
const PAST_M := 3.0
## A first hit this close before the target point is the target's own surface.
const SLACK_M := 0.05
## A person is shown only when at least this many of its nine lines land on it
## (a seated body leans back from the middle of its bounds, so most lines to it
## pass in front of the torso; two landings were the fewest seen on a guest in
## plain view).
const MIN_ON := 2


## One static body per visible mesh of `owners`, under a new holder added to
## `root`. `subjects` maps a Node3D to a tag: a mesh inside that node (or the
## node itself) gets meta "subject" = tag, and its world bounds are merged into
## the holder's meta "bounds" (tag -> AABB). A skinned mesh that cannot be
## baked is listed in the holder's meta "unbaked", so a caller can fail loudly.
static func colliders(root: Node, owners: Array[Node], subjects: Dictionary) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ProbeColliders"
	holder.set_meta("bounds", {})
	holder.set_meta("unbaked", [])
	root.add_child(holder)
	for owner_node in owners:
		var meshes := owner_node.find_children("*", "MeshInstance3D", true, false)
		if owner_node is MeshInstance3D:
			meshes.append(owner_node)
		for mi in meshes:
			var inst := mi as MeshInstance3D
			if not inst.is_visible_in_tree() or inst.mesh == null:
				continue
			var mesh: Mesh = inst.mesh
			if inst.skin != null:
				mesh = inst.bake_mesh_from_current_skeleton_pose()
				if mesh == null or mesh.get_faces().is_empty():
					(holder.get_meta("unbaked") as Array).append(str(inst.get_path()))
					continue
			var tag := _subject_tag(inst, subjects)
			var body := _add_body(holder, inst.name, mesh, [inst.global_transform])
			if body != null and tag != "":
				body.set_meta("subject", tag)
				_merge_bounds(holder, tag, inst.global_transform * mesh.get_aabb())
		for mmi in owner_node.find_children("*", "MultiMeshInstance3D", true, false):
			var multi := mmi as MultiMeshInstance3D
			if not multi.is_visible_in_tree() or multi.multimesh == null:
				continue
			var mm := multi.multimesh
			var at: Array[Transform3D] = []
			var count := mm.instance_count
			if mm.visible_instance_count >= 0:
				count = mm.visible_instance_count
			for i in count:
				at.append(multi.global_transform * mm.get_instance_transform(i))
			_add_body(holder, multi.name, mm.mesh, at)
	return holder


## Lines from `from` to each target, each run on PAST_M past it. A first hit on
## a body tagged `tag` lands on the subject; a first hit on anything else
## before the target is a blocker; a line that hits nothing, or first hits
## something past its target (it went through a gap in the subject), proves
## nothing either way. Returns {on_subject: Array[Vector3] of landing points,
## past: int, blockers: Array[String] of blocker mesh names}.
static func sight_lines(
	space: PhysicsDirectSpaceState3D, from: Vector3, targets: Array[Vector3], tag: String
) -> Dictionary:
	var on_subject: Array[Vector3] = []
	var past := 0
	var blockers: Array[String] = []
	for at in targets:
		var to := at + (at - from).normalized() * PAST_M
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
		if hit.is_empty():
			past += 1
		elif str((hit.collider as Node).get_meta("subject", "")) == tag:
			on_subject.append(hit.position)
		elif from.distance_to(hit.position) < from.distance_to(at) - SLACK_M:
			blockers.append(str((hit.collider as Node).get_meta("mesh", "")))
		else:
			past += 1
	return {"on_subject": on_subject, "past": past, "blockers": blockers}


## Whether a person (a passenger's drawn body, bounds `box` from colliders(),
## bodies tagged `tag`) is shown in the plate `img` taken from `cam`: nine
## sight lines to a 3 x 3 grid on the plane through the body that faces the
## camera (middle 60% of its width; 50%, 70% and 90% of its height, the upper
## body: a table or a counter in front of the legs is normal and does not hide
## the person). Shown when at least MIN_ON lines land on the body, no line is
## blocked in front of it, every landing point is inside `frame` (layout
## pixels), no landing point differs from the HUD-less
## twin `bare`, and the body is at least `min_px` layout pixels tall. Returns
## {ok, on, past, blockers, in_frame, hud_px, height_px, px}.
static func person_shown(
	cam: Camera3D, box: AABB, tag: String, frame: Rect2, img: Image, bare: Image, min_px: float
) -> Dictionary:
	if box.size == Vector3.ZERO:
		return {"ok": false, "on": 0, "past": 0, "blockers": ["no drawn mesh"]}
	var per_screen := cam.get_viewport().get_visible_rect().size.y / float(img.get_height())
	var centre := box.get_center()
	var base := Vector3(centre.x, box.position.y, centre.z)
	var tall := box.size.y
	var height_px := cam.unproject_position(base).distance_to(
		cam.unproject_position(base + Vector3(0.0, tall, 0.0))
	)
	var right := (cam.global_transform.basis.x * Vector3(1, 0, 1)).normalized()
	var wide := minf(box.size.x, box.size.z)
	var targets: Array[Vector3] = []
	for i in 3:
		for j in 3:
			targets.append(
				base + right * (0.3 * (i - 1)) * wide + Vector3(0.0, (0.5 + 0.2 * j) * tall, 0.0)
			)
	var space := cam.get_world_3d().direct_space_state
	var lines := sight_lines(space, cam.global_position, targets, tag)
	var on: Array[Vector3] = lines["on_subject"]
	var in_frame := not cam.is_position_behind(centre)
	var hud_px := 0
	for at in on:
		var px := cam.unproject_position(at)
		in_frame = in_frame and frame.has_point(px)
		var rect := Rect2(px - Vector2.ONE * 3.0, Vector2.ONE * 6.0)
		hud_px += differing(img, bare, to_screen(rect, per_screen, img.get_size()), 1)
	var blockers: Array[String] = lines["blockers"]
	return {
		"ok":
		(
			on.size() >= MIN_ON
			and blockers.is_empty()
			and in_frame
			and hud_px == 0
			and height_px >= min_px
		),
		"on": on.size(),
		"past": lines["past"],
		"blockers": blockers,
		"in_frame": in_frame,
		"hud_px": hud_px,
		"height_px": height_px,
		"px": cam.unproject_position(centre).round(),
	}


## The viewport as an RGBA8 image, after `frames` frames.
static func grab(tree: SceneTree, frames := 2) -> Image:
	for i in frames:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := tree.root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


## The same plate with every visible CanvasLayer under `scene` hidden, then the
## layers shown again. Returns {image, layers: int}.
static func hud_twin(tree: SceneTree, scene: Node) -> Dictionary:
	var layers: Array[CanvasLayer] = []
	for node in scene.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer.visible:
			layer.visible = false
			layers.append(layer)
	var bare := await grab(tree)
	for layer in layers:
		layer.visible = true
	for i in 2:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	return {"image": bare, "layers": layers.size()}


## Pixels inside `rect` (every `step`th one) that differ between two plates.
static func differing(a: Image, b: Image, rect: Rect2i, step: int) -> int:
	var count := 0
	for y in range(rect.position.y, rect.end.y, step):
		for x in range(rect.position.x, rect.end.x, step):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.03:
				count += 1
	return count


## The bounding box of the pixels inside `rect` that differ between two plates,
## or an empty Rect2i when none do.
static func differing_box(a: Image, b: Image, rect: Rect2i) -> Rect2i:
	var lo := Vector2i(rect.end)
	var hi := Vector2i(rect.position) - Vector2i.ONE
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.03:
				lo = lo.min(Vector2i(x, y))
				hi = hi.max(Vector2i(x, y))
	if hi.x < lo.x:
		return Rect2i()
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## A layout-pixel rect in plate (screen) pixels, rounded outward and clipped
## to the plate.
static func to_screen(rect: Rect2, per_screen: float, plate: Vector2i) -> Rect2i:
	var lo := Vector2i((rect.position / per_screen).floor())
	var hi := Vector2i((rect.end / per_screen).ceil())
	return Rect2i(lo, hi - lo).intersection(Rect2i(Vector2i.ZERO, plate))


static func _subject_tag(inst: Node, subjects: Dictionary) -> String:
	for node in subjects:
		if not is_instance_valid(node):
			continue
		if node == inst or (node as Node).is_ancestor_of(inst):
			return str(subjects[node])
	return ""


static func _merge_bounds(holder: Node3D, tag: String, box: AABB) -> void:
	var bounds: Dictionary = holder.get_meta("bounds")
	bounds[tag] = (bounds[tag] as AABB).merge(box) if bounds.has(tag) else box


static func _add_body(holder: Node3D, label: String, mesh: Mesh, transforms: Array) -> StaticBody3D:
	if mesh == null:
		return null
	var local_faces := mesh.get_faces()
	if local_faces.is_empty() or transforms.is_empty():
		return null
	var faces := PackedVector3Array()
	for at: Transform3D in transforms:
		for p in local_faces:
			faces.append(at * p)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	var body := StaticBody3D.new()
	body.set_meta("mesh", label)
	body.add_child(shape_node)
	holder.add_child(body)
	return body
