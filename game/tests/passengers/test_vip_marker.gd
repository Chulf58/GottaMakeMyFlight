class_name TestVipMarker
extends GdUnitTestSuite
## The VIP crown over the passenger an accepted VIP incident marked (board
## 2348c245, VipMarker). Boots the real main scene, so PassengerViews reads the
## real IncidentDirector it is wired to. The incident is put into the director
## through from_snapshot(), the same door a load uses: the marking itself
## (IncidentMajors.spawned) is the incidents suite's subject, not this one's.
## The crown shows over the marked passenger only, goes when the incident is
## done, and after a load shows over the loaded VIP, not the one marked before
## the load (anti-pattern a-per-id-view-record-holding-a-sim-tick-must-start-
## over-on-l).

const SEED := 23_481_126
const PASSENGERS_WANTED := 3
const SEARCH_LIMIT := 12000

var _path := SaveTestKit.run_path("test_vip_marker")
var _main: Node
var _views: PassengerViews
var _sim: PassengerSim
var _director: IncidentDirector
var _run := {}


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_views = _main.get_node("PassengerViews")
	_sim = _main.get_node("PassengerSim")
	_director = _main.get_node("IncidentDirector")
	SaveTestKit.start_airport(_main)
	var ticks := 0
	while _views.active_count() < PASSENGERS_WANTED and ticks < SEARCH_LIMIT:
		SaveTestKit.step(_main)
		ticks += 1
	var ids := _drawn_ids()
	_run["drawn"] = ids.size()
	if ids.size() < 2:
		return
	var first: int = ids[0]
	var second: int = ids[1]
	_run["first"] = first
	_run["second"] = second
	_run["before_any"] = _crowned()
	# Marked: the crown shows on the next tick's sync.
	_run["set_first"] = _set_vip(first, IncidentCatalogue.ACCEPTED)
	SaveTestKit.step(_main)
	_run["marked"] = _crowned()
	_run["saved"] = SaveTestKit.save_game(_main).save_to_file(_path)
	# Done (the VIP made the flight): the crown goes on the next tick.
	_run["set_done"] = _set_vip(first, IncidentCatalogue.DONE)
	SaveTestKit.step(_main)
	_run["after_done"] = _crowned()
	# Another passenger marked, then the save with the first one marked loaded,
	# with no tick run after it (SaveTestKit.step leaves the clock paused).
	_run["set_second"] = _set_vip(second, IncidentCatalogue.ACCEPTED)
	SaveTestKit.step(_main)
	_run["before_load"] = _crowned()
	_run["loaded"] = SaveTestKit.save_game(_main).load_from_file(_path)
	_run["after_load"] = _crowned()


func after() -> void:
	if _main != null:
		_main.free()
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


## Puts one VIP incident marking `target` into the director in `state`, in
## place of any other, through the snapshot a load would give it.
func _set_vip(target: int, state: String) -> bool:
	var data := _director.to_snapshot()
	var p := _sim.get_passenger(target)
	var incident := {
		"id": data["next_id"],
		"kind": IncidentCatalogue.VIP,
		"roll_day": 1,
		"state": state,
		"fire_tick": 0,
		"cell": [-1, -1],
		"mess_id": 0,
		"place": "",
		"outcome": IncidentMajors.BONUS if state == IncidentCatalogue.DONE else "",
		"shown": false,
		"plan":
		{
			"flight": p.flight_id,
			"departs": 0,
			"bonus": IncidentTuning.VIP_BONUS_MONEY,
			"target": target,
			"good_mood": IncidentTuning.VIP_GOOD_MOOD,
			"miss_half_stars": IncidentTuning.VIP_MISS_HALF_STARS,
		},
	}
	data["incidents"] = [incident]
	data["next_id"] = int(data["next_id"]) + 1
	return _director.from_snapshot(data)


func _drawn_ids() -> Array[int]:
	var out: Array[int] = []
	for id in _sim.passenger_ids():
		if _views.node_for(id) != null:
			out.append(id)
	return out


## The drawn passengers whose crown is shown, as ids.
func _crowned() -> Array[int]:
	var out: Array[int] = []
	for id in _drawn_ids():
		var crown := _views.node_for(id).get_node(VipMarker.SPRITE) as Sprite3D
		if crown.visible:
			out.append(id)
	return out


func test_the_world_was_set_up() -> void:
	assert_int(_run["drawn"]).is_greater_equal(2)
	assert_bool(_run["set_first"]).is_true()
	assert_bool(_run["set_done"]).is_true()
	assert_bool(_run["set_second"]).is_true()
	assert_bool(_run["saved"]).is_true()
	assert_bool(_run["loaded"]).is_true()


func test_no_crown_shows_before_any_vip() -> void:
	assert_array(_run["before_any"]).is_empty()


func test_the_crown_shows_over_the_marked_passenger_only() -> void:
	assert_array(_run["marked"]).contains_exactly([_run["first"]])


func test_the_crown_goes_when_the_vip_incident_is_done() -> void:
	assert_array(_run["after_done"]).is_empty()


func test_a_load_shows_the_crown_over_the_loaded_vip_only() -> void:
	# Control: before the load the crown was over the second passenger.
	assert_array(_run["before_load"]).contains_exactly([_run["second"]])
	assert_bool(_main.get_node("SimClock").paused).is_true()
	assert_array(_run["after_load"]).contains_exactly([_run["first"]])


func test_the_marked_view_wears_the_crown_texture() -> void:
	var node := _views.node_for(_run["first"])
	var crown := node.get_node(VipMarker.SPRITE) as Sprite3D
	assert_bool(node.get_meta(&"vip", false)).is_true()
	assert_object(crown.texture).is_same(VipMarker.texture())


func test_layout_puts_the_crown_over_the_head_at_crown_px() -> void:
	var node := _layout_node(20.0)
	var crown := _lay_out(node)
	assert_bool(crown.visible).is_true()
	# Where the icon row would stand: the head gap over the head (decision
	# need-icons-and-wish-bubbles-sit-a-fixed-screen-gap-above-the).
	var head := _head_lift(node)
	assert_float(head).is_greater(NeedIcons.HEAD_GAP_PX)
	assert_vector(crown.position).is_equal(NeedIcons.head_centre(node))
	var above := head * VipMarker.SIZE / VipMarker.CROWN_PX
	assert_float(crown.offset.y).is_equal_approx(VipMarker.SIZE / 2.0 + above, 0.001)
	var pixel := VipMarker.CROWN_PX * _unit() / VipMarker.SIZE
	assert_float(crown.pixel_size).is_equal_approx(pixel, pixel * 0.001)
	node.free()


func test_layout_lifts_the_crown_over_a_need_icon_row() -> void:
	var node := _layout_node(20.0)
	(node.get_node(NeedIcons.SPRITES[0]) as Sprite3D).visible = true
	var crown := _lay_out(node)
	var row := _head_lift(node) + NeedIcons.ICON_PX + NeedIcons.GAP_PX
	var lift := row * VipMarker.SIZE / VipMarker.CROWN_PX
	assert_float(crown.offset.y).is_equal_approx(VipMarker.SIZE / 2.0 + lift, 0.001)
	node.free()


func test_layout_lifts_the_crown_over_a_wish_bubble() -> void:
	var node := _layout_node(20.0)
	(node.get_node(NeedIcons.SPRITES[0]) as Sprite3D).visible = true
	(node.get_node(WishIconView.SPRITE) as Sprite3D).visible = true
	var crown := _lay_out(node)
	var row := _head_lift(node) + WishIconView.WISH_PX + NeedIcons.GAP_PX
	var lift := row * VipMarker.SIZE / VipMarker.CROWN_PX
	assert_float(crown.offset.y).is_equal_approx(VipMarker.SIZE / 2.0 + lift, 0.001)
	node.free()


func test_layout_puts_the_crown_on_top_of_a_speech_bubble_and_its_row() -> void:
	var node := _layout_node(20.0)
	(node.get_node(NeedIcons.SPRITES[0]) as Sprite3D).visible = true
	var bubble := node.get_node("Bubble") as Label3D
	bubble.text = "I'm late!"
	var crown := _lay_out(node)
	var row_only := (NeedIcons.ICON_PX + NeedIcons.GAP_PX) * VipMarker.SIZE / VipMarker.CROWN_PX
	assert_vector(crown.position).is_equal(bubble.position)
	assert_float(crown.offset.y).is_greater(VipMarker.SIZE / 2.0 + row_only)
	node.free()


func test_layout_hides_an_unmarked_crown_and_one_near_the_lens() -> void:
	var node := _layout_node(20.0)
	VipMarker.mark(node, false)
	assert_bool(_lay_out(node).visible).is_false()
	node.free()
	var near := _layout_node(NeedIcons.NEAR_HIDDEN_M - 1.0)
	assert_bool(_lay_out(near).visible).is_false()
	near.free()


func test_the_crown_texture_is_gold_inside_and_clear_outside() -> void:
	var img := VipMarker.texture().get_image()
	var half := VipMarker.SIZE / 2
	# Inside the band, above the navy band line: the gold fill.
	var fill := img.get_pixel(half, half + 4)
	assert_float(fill.a).is_equal_approx(1.0, 0.01)
	assert_float(fill.r).is_equal_approx(VipMarker.FILL.r, 0.02)
	assert_float(fill.g).is_equal_approx(VipMarker.FILL.g, 0.02)
	# A valley between two points is outside the crown.
	assert_float(img.get_pixel(half + 24, half - 20).a).is_equal(0.0)
	assert_float(img.get_pixel(1, 1).a).is_equal(0.0)


func test_marked_ids_reads_accepted_vips_with_a_target_only() -> void:
	var into := {99: true}
	VipMarker.marked_ids(null, into)
	assert_dict(into).is_empty()
	var director := IncidentDirector.new()
	(
		director
		. _incidents
		. assign(
			[
				_record(IncidentCatalogue.VIP, IncidentCatalogue.ACCEPTED, 7),
				_record(IncidentCatalogue.VIP, IncidentCatalogue.ACCEPTED, 0),
				_record(IncidentCatalogue.VIP, IncidentCatalogue.DONE, 8),
				_record(IncidentCatalogue.VIP, IncidentCatalogue.OFFERED, 9),
				_record(IncidentCatalogue.FAVOUR, IncidentCatalogue.ACCEPTED, 10),
			]
		)
	)
	# A reused dictionary loses what it held: a stale id goes.
	into[99] = true
	VipMarker.marked_ids(director, into)
	assert_array(into.keys()).contains_exactly([7])
	# The director's query matches the filter over copied incidents it replaced.
	var query := {}
	director.vip_targets(query)
	assert_dict(query).is_equal(_copied_targets(director))
	director.free()


## The marked ids read the old way, from the deep copies incidents() returns:
## the reference the director's vip_targets() must match.
func _copied_targets(director: IncidentDirector) -> Dictionary:
	var out := {}
	for incident in director.incidents():
		var vip: bool = incident["kind"] == IncidentCatalogue.VIP
		var accepted: bool = incident["state"] == IncidentCatalogue.ACCEPTED
		var target: int = incident["plan"].get("target", 0)
		if vip and accepted and target != 0:
			out[target] = true
	return out


## A bare incident record of `kind` in `state` whose plan targets `target`.
func _record(kind: String, state: String, target: int) -> Dictionary:
	return {"kind": kind, "state": state, "plan": {"target": target}}


## A passenger-like node with the sprites PassengerViews gives one, marked as a
## VIP and placed `distance` metres in front of the game camera, every icon and
## the bubble hidden.
func _layout_node(distance: float) -> Node3D:
	var camera := _views.get_viewport().get_camera_3d()
	var node := Node3D.new()
	var bubble := Label3D.new()
	bubble.name = "Bubble"
	bubble.font_size = 56
	bubble.outline_size = 14
	bubble.pixel_size = 0.006
	bubble.position = Vector3(0.0, PassengerViews.BUBBLE_HEIGHT, 0.0)
	node.add_child(bubble)
	for sprite_name in NeedIcons.SPRITES:
		node.add_child(NeedIcons.make_sprite(sprite_name))
	node.add_child(WishIconView.make_sprite())
	node.add_child(VipMarker.make_sprite())
	_main.add_child(node)
	node.global_position = camera.global_position - camera.global_basis.z * distance
	VipMarker.mark(node, true)
	return node


func _unit() -> float:
	return NeedIcons.unit_of(_views.get_viewport(), _views.get_viewport().get_camera_3d())


## The screen lift NeedIcons.row_anchor() gives the node's row over its head.
func _head_lift(node: Node3D) -> float:
	var camera := _views.get_viewport().get_camera_3d()
	return NeedIcons.row_anchor(node, node.get_node("Bubble") as Label3D, camera, _unit())[1]


func _lay_out(node: Node3D) -> Sprite3D:
	var camera := _views.get_viewport().get_camera_3d()
	VipMarker.layout(node, node.get_node("Bubble") as Label3D, camera, _unit())
	return node.get_node(VipMarker.SPRITE) as Sprite3D
