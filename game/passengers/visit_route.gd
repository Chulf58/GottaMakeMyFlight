class_name VisitRoute
extends RefCounted
## The walk a facility visit starts with, from wherever the passenger stands,
## shared by CafeSim and ToiletSim. A passenger partway along a step either
## finishes it and goes on from its far cell, or turns back, whichever is
## shorter.


## The shortest way from where `p` stands to `target`: {"path", "keep", "mm",
## "from"}. Partway along a step, the passenger either finishes it and goes on
## from its far cell, or turns back; "from" is the cell the path starts at
## (the step's far cell when turning back), "keep" the progress already made
## from it along the path's first step, and "mm" the walk still to do. Empty
## when there is no way.
static func plan(grid: BuildGrid, p: Passenger, target: Vector2i) -> Dictionary:
	var here := grid.find_path(p.at, target)
	var stay := {}
	if not here.is_empty():
		stay = {"path": here, "keep": 0, "from": p.at, "mm": Passenger.path_mm(here)}
	if not p.is_moving() or p.seg_mm == 0:
		return stay
	var next := p.path[p.path_index + 1]
	if not grid.can_route(p.at, next):
		return stay
	var step_mm := Passenger.segment_mm(p.at, next)
	var best := {}
	if not here.is_empty():
		var back := here.duplicate()
		back.push_front(next)
		var back_mm := p.seg_mm + Passenger.path_mm(here)
		best = {"path": back, "keep": step_mm - p.seg_mm, "from": next, "mm": back_mm}
	var ahead := grid.find_path(next, target)
	if not ahead.is_empty():
		var on_mm := step_mm - p.seg_mm + Passenger.path_mm(ahead)
		if best.is_empty() or on_mm <= int(best["mm"]):
			ahead.push_front(p.at)
			best = {"path": ahead, "keep": p.seg_mm, "from": p.at, "mm": on_mm}
	return best


## Puts `p` on a plan()'s walk.
static func start(p: Passenger, route: Dictionary) -> void:
	var path: Array[Vector2i] = []
	path.assign(route["path"])
	p.at = route["from"]
	p.set_path(path)
	p.seg_mm = route["keep"]
