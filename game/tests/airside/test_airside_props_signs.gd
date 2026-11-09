class_name TestAirsidePropsSigns
extends GdUnitTestSuite
## The taxi signs (board 4c08b8e5, Runway R11): one at each turn-off where a
## taxiway leaves the runway, beside its leg and off the paving, facing the
## runway, with the leg's letter, the lane's letter and the arrow the way the
## route turns onto the lane. The turn-offs come from the Airside's own taxi
## routes after a real rebuild; the test names them from main.tscn's links.

const Kit := preload("res://tests/airside/airside_props_kit.gd")
## The two stubs main.tscn links the runway to the lane with, east first, and
## the side a plane leaving the runway there turns to onto the lane.
const STUBS := [
	{"runway": "RunwayExit", "lane": "TaxiEast", "loc": "B", "arrow": "R"},
	{"runway": "RunwayEntry", "lane": "TaxiWest", "loc": "C", "arrow": "L"},
]

var _airside: Airside


func before() -> void:
	_airside = Kit.airside_from_main()
	add_child(_airside)
	var gates := {
		"A": StandPlacement.make(1, 20.0, -230.0), "B": StandPlacement.make(2, 60.0, -230.0)
	}
	assert_bool(_airside.set_gate_stands(gates)).is_true()


func after() -> void:
	_airside.free()


func test_a_sign_stands_at_each_turn_off_from_the_runway() -> void:
	for link in ["RunwayExit>TaxiEast", "TaxiWest>RunwayEntry"]:
		assert_bool(_airside.links.has(link)).is_true()
	var props := _airside.props
	var south := Airside.runway_south()
	assert_int(props.turn_off_list.size()).is_equal(STUBS.size())
	assert_int(props.signs.size()).is_equal(STUBS.size())
	for i in STUBS.size():
		var stub: Dictionary = STUBS[i]
		var stub_x := _airside.graph.position_of(StringName(stub["runway"])).x
		var turn: Dictionary = props.turn_off_list[i]
		var sign := props.signs[i]
		var front := sign.global_basis.z.normalized()
		var on_paving := TaxiPaving.paved(
			_airside.paving.shown, _airside.paving.pads, sign.global_position
		)
		print(
			(
				"%s: turn-off at %s, sign at %s facing %s, letters %s/%s arrow %s, on paving %s"
				% [
					stub["runway"],
					turn["at"],
					sign.global_position,
					front,
					turn["loc"],
					turn["dir"],
					turn["arrow"],
					on_paving
				]
			)
		)
		assert_float(turn["at"].x).is_equal_approx(stub_x, 0.01)
		assert_float(turn["at"].z).is_equal_approx(south, 0.01)
		assert_float(sign.global_position.z).is_between(south + 1.0, south + 12.0)
		assert_float(absf(sign.global_position.x - stub_x)).is_greater(TaxiPaving.WIDTH_M / 2.0)
		assert_bool(on_paving).is_false()
		# Its front faces the runway, north.
		assert_float(front.z).is_less(-0.99)
		assert_str(turn["loc"]).is_equal(stub["loc"])
		assert_str(turn["dir"]).is_equal(AirsideProps.LANE_LETTER)
		assert_str(turn["arrow"]).is_equal(stub["arrow"])
		assert_array(_shown_glyphs(sign)).contains_exactly_in_any_order(
			[
				"Glyph_Loc_" + stub["loc"],
				"Glyph_Dir_" + AirsideProps.LANE_LETTER,
				"Glyph_Arrow_" + stub["arrow"]
			]
		)


func test_sign_scale_sizes_every_sign() -> void:
	var props := _airside.props
	props.sign_scale = 2.5
	for sign in props.signs:
		assert_vector(sign.scale).is_equal_approx(Vector3.ONE * 2.5, Vector3.ONE * 0.001)
	props.sign_scale = 1.0
	assert_int(props.signs.size()).is_greater(0)


func test_the_signs_follow_a_rebuild_without_doubling() -> void:
	var before_count := _airside.props.signs.size()
	assert_int(before_count).is_equal(STUBS.size())
	var routes_before := _airside.taxi_routes()
	assert_bool(_airside.set_gate_stands({"A": StandPlacement.make(1, 20.0, -230.0)})).is_true()
	# The routes changed, so the signs were laid out again.
	assert_bool(_airside.taxi_routes() == routes_before).is_false()
	await get_tree().process_frame
	var live := _airside.props.find_children("TaxiSign_*", "Node3D", false, false)
	assert_int(live.size()).is_equal(STUBS.size())
	assert_int(_airside.props.signs.size()).is_equal(STUBS.size())


func _shown_glyphs(sign: Node) -> Array[String]:
	var out: Array[String] = []
	for node in sign.find_children("Glyph_*", "Node3D", true, false):
		if not String(node.name).ends_with("_Mesh") and (node as Node3D).visible:
			out.append(String(node.name))
	return out
