class_name StandEnvelope
extends RefCounted
## The ground a plane of each class needs at a stand (decision runway-and-taxi-
## technical-design-movement-plan-analytic-bookings-planned-pauses, section 3,
## building user rulings a-gate-has-no-size-planes-use-any-stand-they-fit-
## neighbours-share-apron-space and three-runway-sizes-unlock-three-plane-
## classes). Pure: nothing here changes the grid.
##
## A class's envelope has StandPlacement.swept_rects()' two parts, sized for the
## class (PlaneClasses): the SWING square, which holds the parked plane, the
## pushback and the turn, radius() either side of the stand point and from
## radius() north of the pushback's end to NOSE_M south of the stand point; and
## the WAY north from the pushback's end to the taxi lane, half_span() either
## side. The medium envelope is the one StandPlacement has always used (model
## 05's), so medium stands are unchanged.
##
## A gate has no size: max_class() is the largest class whose envelope is clear
## of everything built, the site's obstacles and the lane band. Neighbouring
## gates may share their medium and large envelopes, and only the small swing
## squares of two gates may never meet (GateDesks), which puts their exits at
## least spacing_cells(SMALL) apart. Building into a gate's unused larger space
## is allowed and lowers its max_class; GateDesks refuses building under the
## envelope of the largest class booked at a gate (GATE_ROUTE).
##
## Not guaranteed: the envelope is the class radius about the stand point. A
## model door-aligned on the stand (PlaneClasses.stand_offset) and turned about
## the stand point, as FlightPose turns it today, can reach past it (the small
## plane's corner is about 15.5 m from the stand point).

## Why a class does not fit at a stand (blocked_part()).
enum Part { CLEAR, SWING, WAY, LANE }

## The swing square's margin past the class radius: the 0.2 m by which
## StandPlacement.SWING_RADIUS_M (20.6 m) has always exceeded model 05's own
## swing radius (20.4 m), kept for every class. Small exits then need 19 m
## between them, medium 42 m and large 66 m.
const SWING_CLEARANCE_M := 0.2
## Largest first, the order max_class() tries.
const LARGEST_FIRST: Array[String] = [PlaneClasses.LARGE, PlaneClasses.MEDIUM, PlaneClasses.SMALL]


## The swing square's half width: the class's swing radius plus
## SWING_CLEARANCE_M.
static func radius(plane_class: String) -> float:
	return PlaneClasses.swing_radius(plane_class) + SWING_CLEARANCE_M


## The way north's half width: the class's widest half span, rounded up to
## 0.1 m (14.2 m for medium, StandPlacement.HALF_SPAN_M).
static func half_span(plane_class: String) -> float:
	var widest := 0.0
	for model: String in PlaneClasses.CLASSES[plane_class]["models"]:
		widest = maxf(widest, PlaneModels.PLANES[model]["half_span"])
	return ceilf(widest * 10.0 - 0.0001) / 10.0


## Whole cells two stands' exits need between them so their swing squares for
## `plane_class` do not meet.
static func spacing_cells(plane_class: String) -> int:
	return ceili(2.0 * radius(plane_class))


## The envelope of `plane_class` at `stand` as world xz rectangles (x, z): the
## swing square, then the way north. With `north_of`, only what lies north of
## that z, as StandPlacement.swept_rects() cuts it.
static func rects(stand: Dictionary, plane_class: String, north_of := INF) -> Array[Rect2]:
	var at := StandPlacement.stand_point(stand)
	var back := StandPlacement.pushback_end(stand)
	var swing := radius(plane_class)
	var span := half_span(plane_class)
	var swing_south := at.z + StandPlacement.NOSE_M
	var swing_north := back.z - swing
	var parts: Array[Rect2] = [
		Rect2(at.x - swing, swing_north, 2.0 * swing, swing_south - swing_north),
		Rect2(
			at.x - span, StandPlacement.TAXI_LANE_Z, 2.0 * span, back.z - StandPlacement.TAXI_LANE_Z
		),
	]
	var out: Array[Rect2] = []
	for rect in parts:
		var south := minf(rect.end.y, north_of)
		if south > rect.position.y:
			out.append(
				Rect2(rect.position.x, rect.position.y, rect.size.x, south - rect.position.y)
			)
	return out


## The in-bounds grid cells the envelope of `plane_class` at `stand` covers, as
## a set (cell -> true).
static func cells(grid: BuildGrid, stand: Dictionary, plane_class: String) -> Dictionary:
	return StandPlacement.cells_under(grid, rects(stand, plane_class))


## The south edge of the band a plane on the taxi lane sweeps: the lane's
## centreline plus the widest half span of any class.
static func lane_band_south() -> float:
	var widest := 0.0
	for plane_class in PlaneClasses.ORDER:
		widest = maxf(widest, half_span(plane_class))
	return StandPlacement.TAXI_LANE_Z + widest


## Whether every model of `plane_class` parked door-aligned at `stand`
## (PlaneClasses.stand_offset) keeps its tail south of lane_band_south().
static func clears_lane(stand: Dictionary, plane_class: String) -> bool:
	var at := StandPlacement.stand_point(stand)
	for model: String in PlaneClasses.CLASSES[plane_class]["models"]:
		var tail: float = (
			at.z + PlaneClasses.stand_offset(model).z - PlaneModels.PLANES[model]["tail"]
		)
		if tail < lane_band_south():
			return false
	return true


## Which part of the envelope of `plane_class` at `stand` is blocked on `grid`
## (with `site`'s obstacles; null for none): SWING or WAY when something built
## stands under it (the swing first), LANE when the parked plane would reach the
## lane band, else CLEAR.
static func blocked_part(
	grid: BuildGrid, site: SiteDefinition, stand: Dictionary, plane_class: String
) -> Part:
	var parts := rects(stand, plane_class)
	for i in parts.size():
		var one: Array[Rect2] = [parts[i]]
		for cell: Vector2i in StandPlacement.cells_under(grid, one):
			if not StandPlacement.apron_clear(grid, site, cell):
				return Part.SWING if i == 0 else Part.WAY
	if not clears_lane(stand, plane_class):
		return Part.LANE
	return Part.CLEAR


## The largest plane class whose envelope at `stand` is clear on `grid`, or ""
## when not even a small plane's is.
static func max_class(grid: BuildGrid, site: SiteDefinition, stand: Dictionary) -> String:
	for plane_class in LARGEST_FIRST:
		if blocked_part(grid, site, stand, plane_class) == Part.CLEAR:
			return plane_class
	return ""


## The larger of two classes ("" is smaller than every class).
static func larger(a: String, b: String) -> String:
	return a if PlaneClasses.ORDER.find(a) >= PlaneClasses.ORDER.find(b) else b


## The cells `edit` builds on: a wall's two sides, an object's footprint, a
## room's rectangle, else its one cell.
static func edit_cells(edit: BuildEdit) -> Array[Vector2i]:
	var out: Array[Vector2i] = [edit.cell]
	match edit.kind:
		BuildEdit.Kind.PLACE_WALL:
			out.append(edit.cell + BuildGrid.SIDE_STEP[edit.side])
		BuildEdit.Kind.PLACE_OBJECT:
			var def := BuildCatalog.get_def(edit.def_id)
			if def != null:
				out = def.footprint(edit.cell, edit.facing)
		BuildEdit.Kind.PLACE_ROOM, BuildEdit.Kind.RESIZE_ROOM:
			for y in edit.room_size.y:
				for x in edit.room_size.x:
					out.append(edit.cell + Vector2i(x, y))
	return out
