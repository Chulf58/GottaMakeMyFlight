class_name ShellView
extends Node
## Draws the Toon terminal shell's cutaway (ShellCutaway) for the camera:
## dithers the roof group out as the camera zooms in and squashes the
## camera-side facade to a kerb. View only.
##
## The roof group gets its own material copies on the dissolve shaders, set as
## surface overrides on this shell's nodes, because toon_post_import.gd binds
## the same .tres materials to every imported asset. The surface and its
## outline get the same dissolve level. At level 1 the roof nodes are hidden;
## the roof is never removed for good, so this node owns their `visible`.
## The roof casts no shadow while it is fading or gone (level above 0): the
## dither would also run in the shadow pass and project a moire pattern of the
## shadow map onto the roof and the floor. So the roof's shadow leaves when the
## fade starts and comes back when the roof is whole again.
##
## Facade pieces are only moved: each one's transform is rebuilt from the base
## captured at setup, squashed in shell space. This node never writes a facade
## bay's `visible`, never frees or reparents one, and skips a piece that was
## freed, so a later permanent wall removal (hiding or freeing a bay) stays in
## force. Nothing else may move a facade piece while this node runs.
##
## Doorways: each Doorway_n empty (glTF extras: door, bay, outward, width)
## gets its door bay its own material copy with a hole box, and two jamb
## pieces from the interior kit under a DoorStubs node it adds to the shell.
## While a doorway is open (ShellCutaway.doorway_open) the hole is set, the
## jambs are shown, and the door and porch are hidden; doors and porches are
## never removed for good, so this node owns their `visible`.

const TOON := "res://shaders/toon.gdshader"
const OUTLINE := "res://shaders/toon_outline.gdshader"
const TOON_DISSOLVE := preload("res://shaders/toon_dissolve.gdshader")
const OUTLINE_DISSOLVE := preload("res://shaders/toon_outline_dissolve.gdshader")
const UNSHADED_DISSOLVE := preload("res://shaders/unshaded_dissolve.gdshader")
## The roof group. Poles are the canopy's struts and fade with it (user
## ruling 2026-10-26, "Dissolve with the canopy").
const ROOF_NODES: Array[String] = ["Upper", "Canopy", "Lights_Upper", "Poles"]
const JAMB_PIECE := "wall"
## Hole boxes per dissolve material; the hole_min and hole_max array size in
## dissolve.gdshaderinc must match. Eight, one per doorway: a turn from north
## to south passes a frame where both sides are cut exactly 0.5 and all eight
## doorways are open.
const HOLE_SLOTS := 8
## A hole box that holds no point.
const NO_HOLE_MIN := Vector3(1.0e9, 1.0e9, 1.0e9)
const NO_HOLE_MAX := Vector3(-1.0e9, -1.0e9, -1.0e9)
## Pieces that are not named after a side; they get the side of the outer
## face they sit nearest. Each must be there, numbered 1 to DOOR_COUNT.
const DOOR_PREFIXES: Array[String] = ["Door_", "Porch_"]
const DOOR_COUNT := 8

## The instanced tp_airport_shell.glb.
@export var shell: Node3D
## The camera rig whose distance and heading drive the cutaway. Without one
## the node holds whatever levels are set and only redraws on apply().
@export var camera: TycoonCamera
@export var roof_hide_below := 100.0
@export var roof_show_above := 120.0
@export var roof_fade_seconds := 0.4
@export var side_fade_seconds := 0.25
## The facade is cut only while the roof is gone (user ruling 2026-10-26,
## "Cut only when roof is gone"; see ShellCutaway's gate).
@export var cut_only_without_roof := true

var cutaway := ShellCutaway.new()
var roof_nodes: Array[MeshInstance3D] = []
## Indexed by ShellCutaway.Side: the pieces on that outer face.
var side_pieces: Array = [[], [], [], []]
## The facade group's bounds in shell space, for placing doors and porches.
var facade_box := AABB()
## One ShellView.Doorway per Doorway_n, in order.
var doorways: Array[Doorway] = []

## Shell-space base transform of each facade piece, captured at setup.
var _bases: Dictionary = {}
## The roof's dissolve materials, outline passes included.
var _roof_materials: Array[ShaderMaterial] = []
## Each roof node's own cast_shadow setting, restored when the roof is whole.
var _roof_shadows: Dictionary = {}
## Lot's own materials (surface and outline), whose holes drop the letter
## signs of open doorways' porches.
var _lot_materials: Array[ShaderMaterial] = []
var _ready_ok := false
var _drawn_roof := -1.0
var _drawn_cuts: Array = [-1.0, -1.0, -1.0, -1.0]
## Per side: 1 open, 0 shut, -1 not drawn yet.
var _drawn_open: Array = [-1, -1, -1, -1]


func _ready() -> void:
	cutaway.roof_hide_below = roof_hide_below
	cutaway.roof_show_above = roof_show_above
	cutaway.roof_fade_seconds = roof_fade_seconds
	cutaway.side_fade_seconds = side_fade_seconds
	cutaway.cut_only_without_roof = cut_only_without_roof
	_ready_ok = setup()
	if _ready_ok and camera != null:
		# The camera rig sits earlier in the tree, so its _ready() has already
		# applied its home distance and yaw.
		cutaway.snap(camera.distance, _toward_eye())
	apply()
	set_process(_ready_ok and camera != null)


func _process(delta: float) -> void:
	cutaway.step(camera.distance, _toward_eye(), delta)
	apply()


## Whether setup found the roof and the four facade sides.
func is_ready() -> bool:
	return _ready_ok


## Finds the roof group and the facade pieces, gives the roof its own
## dissolve materials and captures each facade piece's base transform.
## Fails loudly (push_error, false) when a piece is missing or unknown.
func setup() -> bool:
	var problem := "no shell" if shell == null else cutaway.tuning_error()
	if problem == "":
		problem = _find_roof()
	var facade: Node3D = null
	if problem == "":
		facade = shell.find_child("Facade", true, false) as Node3D
		problem = "the shell has no Facade" if facade == null else ""
	if problem != "":
		push_error("ShellView: " + problem)
		return false
	var first := true
	for mi in facade.find_children("*", "MeshInstance3D", true, false):
		var box := _shell_box(mi as MeshInstance3D)
		facade_box = box if first else facade_box.merge(box)
		first = false
	if not _collect_pieces():
		return false
	for mi in roof_nodes:
		if not _give_dissolve_materials(mi):
			return false
	problem = _give_lot_material()
	if problem == "":
		problem = _find_doorways()
	if problem != "":
		push_error("ShellView: " + problem)
		return false
	return true


## Draws the current levels: the roof's dissolve and visibility, and each
## side's squash. Writes only what changed since the last call.
func apply() -> void:
	if not _ready_ok:
		return
	var roof: float = cutaway.roof_level
	if roof != _drawn_roof:
		for mat in _roof_materials:
			mat.set_shader_parameter("dissolve", roof)
		for mi in roof_nodes:
			if is_instance_valid(mi):
				mi.visible = roof < 1.0
				mi.cast_shadow = (
					_roof_shadows[mi]
					if roof == 0.0
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				)
		_drawn_roof = roof
	var to_world := shell.global_transform
	for side in 4:
		var amount := cutaway.cut(side)
		if amount == _drawn_cuts[side]:
			continue
		_drawn_cuts[side] = amount
		var squash := ShellCutaway.stub_transform(amount)
		for piece in side_pieces[side]:
			if is_instance_valid(piece):
				(piece as Node3D).global_transform = to_world * squash * _bases[piece]
	var changed := false
	for side in 4:
		var open := 1 if cutaway.doorway_open(side) else 0
		if open != _drawn_open[side]:
			_drawn_open[side] = open
			changed = true
			for doorway in doorways:
				if doorway.side == side:
					doorway.draw_open(open == 1)
	if changed:
		var signs: Array[AABB] = []
		for doorway in doorways:
			if _drawn_open[doorway.side] == 1:
				signs.append(doorway.sign_hole)
		if signs.size() > HOLE_SLOTS:
			push_error("ShellView: %d porch signs open, only %d holes" % [signs.size(), HOLE_SLOTS])
		for mat in _lot_materials:
			set_holes(mat, signs)


## Sets a dissolve material's hole boxes (world space) to `boxes`: hole_count
## says how many are used, and the unused slots are empty boxes as well.
## Boxes past HOLE_SLOTS are left out.
static func set_holes(mat: ShaderMaterial, boxes: Array[AABB]) -> void:
	mat.set_shader_parameter("hole_count", mini(boxes.size(), HOLE_SLOTS))
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	for i in HOLE_SLOTS:
		lo.append(boxes[i].position if i < boxes.size() else NO_HOLE_MIN)
		hi.append(boxes[i].end if i < boxes.size() else NO_HOLE_MAX)
	mat.set_shader_parameter("hole_min", lo)
	mat.set_shader_parameter("hole_max", hi)


## Gives Lot its own hole material (for the porch signs). Returns what is
## wrong, or "".
func _give_lot_material() -> String:
	var lot := shell.find_child("Lot", true, false) as MeshInstance3D
	if lot == null or lot.mesh.get_surface_count() != 1:
		return "the shell has no one-surface Lot"
	var lot_mat := _toon_copy(lot.mesh.surface_get_material(0))
	if lot_mat == null:
		return "Lot is not toon"
	lot.set_surface_override_material(0, lot_mat)
	_lot_materials.append(lot_mat)
	if lot_mat.next_pass != null:
		_lot_materials.append(lot_mat.next_pass as ShaderMaterial)
	var no_boxes: Array[AABB] = []
	for mat in _lot_materials:
		set_holes(mat, no_boxes)
	return ""


## Reads every Doorway_n: its door, porch, door bay, outward direction and
## width. Gives the bay its own hole material and makes the hidden jambs.
## Returns what is missing, or "".
func _find_doorways() -> String:
	var stubs := Node3D.new()
	stubs.name = "DoorStubs"
	shell.add_child(stubs)
	var to_shell := shell.global_transform.affine_inverse()
	for n in range(1, DOOR_COUNT + 1):
		var marker := shell.find_child("Doorway_%d" % n, true, false) as Node3D
		if marker == null or not marker.has_meta("extras"):
			return "the shell has no Doorway_%d with extras" % n
		var extras: Dictionary = marker.get_meta("extras")
		var doorway := Doorway.new()
		doorway.door = shell.find_child(str(extras.get("door", "")), true, false) as Node3D
		doorway.porch = shell.find_child("Porch_%d" % n, true, false) as Node3D
		doorway.bay = shell.find_child(str(extras.get("bay", "")), true, false) as MeshInstance3D
		if doorway.door == null or doorway.porch == null or doorway.bay == null:
			return "Doorway_%d: door, porch or bay %s not found" % [n, extras]
		doorway.side = ShellCutaway.side_of_name(String(doorway.bay.name))
		var out: Array = extras.get("outward", [])
		var width := float(extras.get("width", 0.0))
		if doorway.side == -1 or out.size() != 3 or width <= 0.0:
			return "Doorway_%d: bad extras %s" % [n, extras]
		var outward := Vector3(out[0], out[1], out[2])
		var centre := to_shell * marker.global_position
		doorway.centre_world = marker.global_position
		doorway.hole = shell.global_transform * ShellCutaway.hole_box(centre, outward, width)
		var porch_box := _shell_box(doorway.porch as MeshInstance3D)
		doorway.sign_hole = shell.global_transform * ShellCutaway.sign_box(porch_box)
		for i in doorway.bay.mesh.get_surface_count():
			var made := _toon_copy(doorway.bay.mesh.surface_get_material(i))
			if made == null:
				return "Doorway_%d: bay %s is not toon" % [n, doorway.bay.name]
			doorway.bay.set_surface_override_material(i, made)
			doorway.materials.append(made)
			if made.next_pass != null:
				doorway.materials.append(made.next_pass as ShaderMaterial)
		for at in ShellCutaway.jamb_transforms(centre, outward, width):
			var jamb := InteriorKit.instantiate(JAMB_PIECE)
			jamb.name = "Jamb_%d_%d" % [n, doorway.jambs.size()]
			jamb.transform = at
			jamb.visible = false
			stubs.add_child(jamb)
			doorway.jambs.append(jamb)
		doorway.draw_open(false)
		doorways.append(doorway)
	return ""


## Collects the roof nodes and their own shadow settings; returns what is
## missing, or "".
func _find_roof() -> String:
	for node_name in ROOF_NODES:
		var mi := shell.find_child(node_name, true, false) as MeshInstance3D
		if mi == null:
			return "the shell has no %s" % node_name
		roof_nodes.append(mi)
		_roof_shadows[mi] = mi.cast_shadow
	return ""


func _toward_eye() -> Vector3:
	return shell.global_basis.inverse() * camera.global_basis.z


func _shell_box(mi: MeshInstance3D) -> AABB:
	return shell.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()


## Every Facade_* and Lights_<side>_* piece must name its side, and every
## Door_n and Porch_n must be there; anything else (Upper, Lot, Road, ...) is
## left alone.
func _collect_pieces() -> bool:
	var to_shell := shell.global_transform.affine_inverse()
	var doors := {}
	for mi in shell.find_children("*", "MeshInstance3D", true, false):
		var piece := mi as MeshInstance3D
		var piece_name := String(piece.name)
		var side := ShellCutaway.side_of_name(piece_name)
		if side == -1 and _door_number(piece_name) > 0:
			side = ShellCutaway.side_of_box(_shell_box(piece), facade_box)
			doors[piece_name] = true
		if side == -1:
			var sided := piece_name.begins_with("Facade_") or piece_name.begins_with("Lights_")
			if sided and not piece_name in ROOF_NODES:
				push_error("ShellView: cannot tell the side of %s" % piece_name)
				return false
			continue
		side_pieces[side].append(piece)
		_bases[piece] = to_shell * piece.global_transform
	for prefix in DOOR_PREFIXES:
		for n in range(1, DOOR_COUNT + 1):
			if not doors.has("%s%d" % [prefix, n]):
				push_error("ShellView: the shell has no %s%d" % [prefix, n])
				return false
	return true


## n for a Door_n or Porch_n name, else 0.
func _door_number(piece_name: String) -> int:
	for prefix in DOOR_PREFIXES:
		var rest := piece_name.trim_prefix(prefix)
		if piece_name.begins_with(prefix) and rest.is_valid_int():
			return rest.to_int()
	return 0


## Surface overrides on this node only; the imported mesh and its shared
## materials are left alone.
func _give_dissolve_materials(mi: MeshInstance3D) -> bool:
	for i in mi.mesh.get_surface_count():
		var source := mi.mesh.surface_get_material(i)
		var made := _dissolve_copy(source)
		if made == null:
			push_error(
				(
					"ShellView: %s surface %d has material %s with no dissolve copy"
					% [mi.name, i, source.resource_path if source else "null"]
				)
			)
			return false
		mi.set_surface_override_material(i, made)
	return true


## A dissolve copy of a roof material, kept in _roof_materials: the toon
## surface (with its outline pass) or the unshaded light panels. Null for
## anything else.
func _dissolve_copy(source: Material) -> ShaderMaterial:
	var toon := _toon_copy(source)
	if toon != null:
		_roof_materials.append(toon)
		if toon.next_pass != null:
			_roof_materials.append(toon.next_pass as ShaderMaterial)
		return toon
	if source is StandardMaterial3D:
		var standard := source as StandardMaterial3D
		var plain := (
			standard.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
			and standard.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			and not standard.vertex_color_use_as_albedo
		)
		if not plain:
			return null
		var made := ShaderMaterial.new()
		made.shader = UNSHADED_DISSOLVE
		made.render_priority = standard.render_priority
		made.set_shader_parameter("albedo_texture", standard.albedo_texture)
		made.set_shader_parameter("albedo_color", standard.albedo_color)
		_roof_materials.append(made)
		return made
	return null


## A copy of a toon material, and of its outline pass, on the dissolve
## shaders. Null when `source` is not the toon surface with a toon outline.
func _toon_copy(source: Material) -> ShaderMaterial:
	if not (source is ShaderMaterial and (source as ShaderMaterial).shader.resource_path == TOON):
		return null
	var made := _copy_shader_material(source as ShaderMaterial, TOON_DISSOLVE)
	var outline := source.next_pass as ShaderMaterial
	if outline != null:
		if outline.shader.resource_path != OUTLINE:
			return null
		made.next_pass = _copy_shader_material(outline, OUTLINE_DISSOLVE)
	return made


## A new material on `shader` holding every parameter value `source` has set;
## unset ones keep the shared defaults both shaders declare alike.
func _copy_shader_material(source: ShaderMaterial, shader: Shader) -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = shader
	made.render_priority = source.render_priority
	for uniform in source.shader.get_shader_uniform_list():
		var key: String = uniform["name"]
		var value: Variant = source.get_shader_parameter(key)
		if value != null:
			made.set_shader_parameter(key, value)
	return made


## One Doorway_n of the shell and what ShellView draws for it.
class Doorway:
	extends RefCounted
	var side := -1
	var door: Node3D
	var porch: Node3D
	var bay: MeshInstance3D
	## The bay's own materials, outline passes included, that carry the hole.
	var materials: Array[ShaderMaterial] = []
	var jambs: Array[Node3D] = []
	## The hole over the opening, in world space.
	var hole := AABB()
	## The hole over the porch's letter sign in Lot, in world space.
	var sign_hole := AABB()
	var centre_world := Vector3.ZERO

	## Opens or shuts the doorway: door and porch hidden, jambs shown and the
	## bay's lintel dropped while open. Freed nodes are skipped.
	func draw_open(open: bool) -> void:
		for node in [door, porch]:
			if is_instance_valid(node):
				(node as Node3D).visible = not open
		for jamb in jambs:
			if is_instance_valid(jamb):
				jamb.visible = open
		if not is_instance_valid(bay):
			return
		var boxes: Array[AABB] = []
		if open:
			boxes.append(hole)
		for mat in materials:
			ShellView.set_holes(mat, boxes)
