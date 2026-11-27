class_name Bag
extends RefCounted
## One checked bag as plain data (decision baggage-bag-sim-design-route-field-
## belt-capacity-cutoff). BaggageSim owns and moves it.
##
## A bag on a belt owns one cell, `cell`. It came in along its committed edge
## from the cell `cell - from_step` (or, when `from_desk`, from its desk's
## outlet) and still has `remain_mm` to go to the centre of `cell`; at the
## centre (remain_mm 0) it picks its next edge from the route field. The edge
## must stay in place until then: a bag whose belt-to-belt edge goes stops.
## While remain_mm is more than half a cell its body is still on the cell it
## came from (physical_cell()), so that cell is taken too. An IN_ROOM bag
## keeps the belt end it reached in `cell`; an AT_DESK bag has no cell.
## `passenger` and `desk` are historical: the passenger may be retired and
## the desk demolished while the bag still exists.

enum State { AT_DESK, RIDING, BLOCKED, IN_ROOM, LOADED, MISSED }
enum Cause { NONE, LATE, NO_BELT, NO_ROUTE, LOST }

## Distance between two cell centres, in mm.
const CELL_MM := 1000
## Names of the causes in BaggageSim.results and in saves.
const CAUSE_NAMES: Array[String] = ["none", "late", "no_belt", "no_route", "lost"]
## Six readable suitcase colors shared from passenger arrival through cart loading.
const SUITCASE_COLORS: Array[Color] = [
	Color8(199, 48, 54),
	Color8(41, 71, 125),
	Color8(33, 128, 133),
	Color8(209, 158, 41),
	Color8(99, 143, 94),
	Color8(125, 61, 122),
]
const SUITCASE_COLOR_NAMES: Array[String] = ["crimson", "navy", "teal", "mustard", "sage", "plum"]

static var _suitcase_materials := {}

var id := 0
var passenger := 0
var flight := ""
var desk := 0
var color := 0
var state := State.AT_DESK
var cause := Cause.NONE
var cell := Vector2i.ZERO
var from_step := Vector2i.ZERO
var remain_mm := 0
## True while the bag rides the half cell from its desk's outlet: that edge
## needs no belt behind it, so a desk taken away never stops the bag.
var from_desk := false
## The tick it began waiting for its next cell: its check-in tick at a desk,
## the tick it reached a cell centre on a belt. Merges go to the earliest,
## then the lower id.
var wait_tick := 0
var created_tick := 0
## The last tick on which reaching a bag room still loads it.
var cutoff_tick := 0
var rest_tick := -1
var outcome_tick := -1
## Active BaggageShuttle id carrying this bag to the plane, or 0.
var shuttle_id := 0


func is_settled() -> bool:
	return state == State.LOADED or state == State.MISSED


func on_belt() -> bool:
	return state == State.RIDING or state == State.BLOCKED


## The cell the bag's body is on: the one it came from while it is in the
## first half of its edge, else its own cell.
func physical_cell() -> Vector2i:
	if remain_mm * 2 > CELL_MM:
		return cell - from_step
	return cell


static func color_for_passenger(passenger_id: int) -> int:
	var h := posmod(passenger_id * 747796405 + 2891336453, 2147483647)
	return posmod((h >> 16) ^ h, SUITCASE_COLORS.size())


static func suitcase_color(index: int) -> Color:
	return SUITCASE_COLORS[posmod(index, SUITCASE_COLORS.size())]


static func paint_suitcase(node: Node3D, color_index: int) -> void:
	if node == null:
		return
	var mesh_instance: MeshInstance3D = (
		(
			node as MeshInstance3D
			if node is MeshInstance3D
			else node.find_child("BaggageBag_Body", true, false)
		)
		as MeshInstance3D
	)
	if mesh_instance == null:
		return
	var mat := suitcase_material(mesh_instance, color_index)
	if mat != null:
		mesh_instance.set_surface_override_material(0, mat)


static func suitcase_material(mesh_instance: MeshInstance3D, color_index: int) -> Material:
	var idx := posmod(color_index, SUITCASE_COLORS.size())
	var base: Material = null
	if mesh_instance.has_meta(&"_base_bag_mat"):
		base = mesh_instance.get_meta(&"_base_bag_mat")
	if base == null:
		base = mesh_instance.get_active_material(0)
		if base == null:
			return null
		mesh_instance.set_meta(&"_base_bag_mat", base)
	if not (base is ShaderMaterial):
		return base
	var key := "%s:%d" % [str(base.get_rid()), idx]
	if _suitcase_materials.has(key):
		return _suitcase_materials[key]
	var shader_base := base as ShaderMaterial
	var made := shader_base.duplicate() as ShaderMaterial
	var tex := shader_base.get_shader_parameter("albedo_texture") as Texture2D
	if tex != null:
		var atlas: Image = tex.get_image()
		if atlas != null:
			if atlas.is_compressed():
				atlas.decompress()
			if atlas.get_format() != Image.FORMAT_RGBA8:
				atlas.convert(Image.FORMAT_RGBA8)
			var cell_w := maxi(1, int(atlas.get_width() / 32.0))
			var cell_h := maxi(1, int(atlas.get_height() / 16.0))
			atlas.fill_rect(Rect2i(31 * cell_w, 0, cell_w, cell_h), SUITCASE_COLORS[idx])
			atlas.generate_mipmaps()
			made.set_shader_parameter("albedo_texture", ImageTexture.create_from_image(atlas))
	_suitcase_materials[key] = made
	return made
