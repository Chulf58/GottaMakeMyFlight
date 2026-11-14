class_name TestNeedClusterHeads
extends GdUnitTestSuite
## A need-icon count badge never ends over a passenger's head (board 769f210d).
## The cluster_badge_heads plates found a badge on a seated gate row carrying
## the shift (0, 48) that NeedCluster.place() took at ring 48 (down comes
## before up 60 in its order) and kept while it fitted, so it sat on a head:
## heads were not among the obstacles. Here a badge is handed a kept shift
## onto a head, measured from the head bones, and the next draw must move it
## clear of every head.

const TOILET := NeedIcons.Need.TOILET
## The head rect a test measures from the head bone, independent of
## NeedIcons.head_top(): its top this far over the bone (the head top the
## need_icon_near_camera probe measured), a square this wide across the view.
const HEAD_UP_M := 0.12
const HEAD_WIDE_M := 0.3

var _world: PassengerTestWorld
var _views: PassengerViews
var _camera: Camera3D
## The views draw into a 1600 x 900 viewport, as a game window would; the
## headless root is 64 pixels high on output.
var _screen: SubViewport


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	NeedFacilityKit.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	_screen = SubViewport.new()
	_screen.size = Vector2i(1600, 900)
	add_child(_screen)
	_screen.add_child(_views)
	_camera = Camera3D.new()
	_screen.add_child(_camera)
	_camera.make_current()
	PassengerTestWorld.show_need(_views, NeedIcons.Need.TOILET)


func after_test() -> void:
	_screen.free()
	_world.free_all()


func test_a_badge_kept_shift_onto_a_head_moves_clear_of_every_head() -> void:
	var ids: Array[int] = []
	for i in 10:
		var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		ids.append(id)
		var p := _world.passenger(id)
		ToiletTestLayout.calm(p)
		p.toilet_need = ToiletSim.NEED_MAX
	_world.step()
	_views.draw()
	var centre := Vector3.ZERO
	for id in ids:
		centre += _views.node_for(id).global_position
	centre /= ids.size()
	_camera.global_position = centre + Vector3(0.0, 12.0, 9.0)
	_camera.look_at(centre + Vector3(0.0, NeedIcons.LIFT_M, 0.0))
	_views.draw()
	var badges := _views.need_badges()
	assert_int(badges.size()).is_equal(1)
	var cluster: int = badges[0]["id"]
	var first: Rect2 = badges[0]["rect"]
	var kept: Vector2 = _views.need_clusters._shifts[cluster]
	var wanted := Rect2(first.position - kept, first.size)
	var heads := _head_rects()
	print("badge %s shift %s, wanted %s, %d heads" % [first, kept, wanted, heads.size()])
	# The control: the shift handed over really lands the badge on a head.
	var onto := Vector2(NAN, NAN)
	for shift in NeedCluster._offsets():
		if (
			shift.x == 0.0
			and shift.y > 0.0
			and not _over(Rect2(wanted.position + shift, wanted.size), heads).is_empty()
		):
			onto = shift
			break
	print("a kept shift onto a head: %s" % onto)
	(
		assert_bool(is_nan(onto.x))
		. override_failure_message("no downward shift reaches a head")
		. is_false()
	)
	_views.need_clusters._shifts[cluster] = onto
	_views.draw()
	var placed: Rect2 = _views.need_badges()[0]["rect"]
	var hit := _over(placed, _head_rects())
	print("placed %s (shift %s), over heads %s" % [placed, placed.position - wanted.position, hit])
	assert_vector(placed.position).is_not_equal(wanted.position + onto)
	(
		assert_array(hit)
		. override_failure_message("the badge %s is over heads %s" % [placed, hit])
		. is_empty()
	)


## Passenger id -> its head's screen rect in output pixels, a square from
## HEAD_WIDE_M across, its top HEAD_UP_M over the head bone.
func _head_rects() -> Dictionary:
	var to_output := _views.get_viewport().get_stretch_transform().get_scale().y
	var out := {}
	for id in _world.sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null:
			continue
		var top_m := _head_bone(node) + Vector3(0.0, HEAD_UP_M, 0.0)
		var top := _camera.unproject_position(top_m) * to_output
		var side_m := top_m + _camera.global_basis.x * HEAD_WIDE_M
		var side := _camera.unproject_position(side_m).distance_to(top / to_output) * to_output
		out[id] = Rect2(top - Vector2(side / 2.0, 0.0), Vector2.ONE * side)
	return out


func _over(rect: Rect2, heads: Dictionary) -> Array:
	var out := []
	for id: int in heads:
		if rect.intersects(heads[id]):
			out.append(id)
	return out


func _head_bone(node: Node3D) -> Vector3:
	for skeleton in node.find_children("*", "Skeleton3D", true, false):
		var bones := skeleton as Skeleton3D
		for i in bones.get_bone_count():
			if bones.get_bone_name(i).to_lower().contains("head"):
				return bones.global_transform * bones.get_bone_global_pose(i).origin
	fail("no head bone on passenger %s" % node.name)
	return Vector3.ZERO
