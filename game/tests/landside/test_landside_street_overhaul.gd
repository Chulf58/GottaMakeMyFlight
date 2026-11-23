class_name TestLandsideStreetOverhaul
extends GdUnitTestSuite
## Contracts for the extended highway, tunnel portals, and forecourt/boulevard
## street dressing mounted by LandsidePlaces -> LandsideStreetDressing.

const STARTER := preload("res://landside/starter_landside.tres")
const PORTAL_SCENE := preload("res://assets/landside/landside_tunnel_portal.glb")
const ROAD_EXT_SCENE := preload("res://assets/landside/landside_road_ext.glb")
const CAR_HALF_WIDTH := 1.05
const TERMINAL_CLEAR_Z := -59.5
const BACKSTOP_LOCAL_X := 19.2
const CROSSWALK_XS := [-26.0, -17.0, -2.0, 16.0, 25.0]


func test_vehicle_endpoints_sit_inside_solid_tunnel_portals() -> void:
	var min_clear := LandsideStreetDressing.VEHICLE_HALF_LENGTH
	var east_in := STARTER.road_in[0]
	var west_out := STARTER.road_out[STARTER.road_out.size() - 1]

	# Spawn point (road_in[0]) sits cleanly past east portal mouth and before backstop.
	assert_float(east_in.x).is_greater_equal(LandsideStreetDressing.PORTAL_MOUTH_EAST_X + min_clear)
	assert_float(east_in.x + min_clear).is_less_equal(
		LandsideStreetDressing.PORTAL_MOUTH_EAST_X + BACKSTOP_LOCAL_X
	)
	assert_float(absf(east_in.z - LandsideStreetDressing.ROAD_CENTER_Z) + CAR_HALF_WIDTH).is_less(
		LandsideStreetDressing.PORTAL_BORE_HALF_Z
	)

	# Despawn point (road_out[-1]) sits cleanly past west portal mouth and before backstop.
	assert_float(west_out.x).is_less_equal(LandsideStreetDressing.PORTAL_MOUTH_WEST_X - min_clear)
	assert_float(west_out.x - min_clear).is_greater_equal(
		LandsideStreetDressing.PORTAL_MOUTH_WEST_X - BACKSTOP_LOCAL_X
	)
	assert_float(absf(west_out.z - LandsideStreetDressing.ROAD_CENTER_Z) + CAR_HALF_WIDTH).is_less(
		LandsideStreetDressing.PORTAL_BORE_HALF_Z
	)

	# Both car park exit lanes also terminate inside the east portal bore.
	for i in STARTER.lots.size():
		var lot_end := STARTER.lots[i].exit[STARTER.lots[i].exit.size() - 1]
		assert_float(lot_end.x).override_failure_message("lot %d exit" % i).is_greater_equal(
			LandsideStreetDressing.PORTAL_MOUTH_EAST_X + min_clear
		)
		(
			assert_float(absf(lot_end.z - LandsideStreetDressing.ROAD_CENTER_Z) + CAR_HALF_WIDTH)
			. is_less(LandsideStreetDressing.PORTAL_BORE_HALF_Z)
		)


func test_portal_and_road_extension_assets_have_valid_meshes() -> void:
	var portal := auto_free(PORTAL_SCENE.instantiate()) as Node3D
	var interior := portal.find_child("Portal_Interior", true, false) as MeshInstance3D
	var structure := portal.find_child("Portal_Structure", true, false) as MeshInstance3D
	var berm := portal.find_child("Portal_Berm", true, false) as MeshInstance3D
	assert_object(interior).is_not_null()
	assert_object(structure).is_not_null()
	assert_object(berm).is_not_null()

	var road_ext := auto_free(ROAD_EXT_SCENE.instantiate()) as Node3D
	var road_mesh := road_ext.find_child("Road_Ext", true, false) as MeshInstance3D
	var dashes_mesh := road_ext.find_child("Road_Ext_Dashes", true, false) as MeshInstance3D
	assert_object(road_mesh).is_not_null()
	assert_object(dashes_mesh).is_not_null()
	var aabb := road_mesh.get_aabb()
	assert_float(aabb.size.x).is_equal_approx(113.0, 0.05)
	assert_float(aabb.size.z).is_equal_approx(12.0, 0.05)


func test_landside_places_mounts_dressing_clear_of_protected_footprints() -> void:
	var sim: LandsideSim = auto_free(LandsideSim.new())
	sim.use_definition(STARTER)
	sim.wallet = Wallet.new()
	var places := auto_free(LandsidePlaces.new()) as LandsidePlaces
	places.landside = sim
	add_child(places)
	places.refresh()

	var dressing := places.street_dressing()
	assert_object(dressing).is_not_null()
	assert_bool(dressing.is_inside_tree()).is_true()

	var specs := LandsideStreetDressing.prop_specs()
	assert_int(specs.size()).is_greater(40)

	var berths := _all_berth_xs()
	var bad: Array[String] = []
	for i in specs.size():
		var s: Dictionary = specs[i]
		var name_s: String = s["name"]
		var pos: Vector3 = s["pos"]
		var half_p: Vector2 = s["half"]
		assert_object(dressing.find_child(name_s, true, false)).is_not_null()

		# 1. Terminal buildable zone protection: stay south of z = -59.5 everywhere.
		if pos.z - half_p.y <= TERMINAL_CLEAR_Z:
			bad.append(
				"%s touches z<=%.1f (min_z=%.2f)" % [name_s, TERMINAL_CLEAR_Z, pos.z - half_p.y]
			)

		# 2. Curb bays & drop-off doorways unobstructed along forecourt sidewalk.
		if pos.z < -52.0 and absf(pos.x) <= 43.0:
			for bx in berths:
				if absf(pos.x - bx) < 1.8:
					bad.append("%s blocks berth x=%.2f" % [name_s, bx])
			for cx in CROSSWALK_XS:
				if absf(pos.x - cx) < 1.2 + half_p.x * 0.5:
					bad.append("%s blocks crosswalk x=%.1f" % [name_s, cx])

		# 3. Lot 1 & Lot 2 footprints + vehicle aprons kept clear.
		if _in_rect(pos, half_p, 19.7, 43.7, -40.0, -5.5):
			bad.append("%s overlaps lot_1" % name_s)
		if _in_rect(pos, half_p, -12.0, 12.0, -40.0, 18.0):
			bad.append("%s overlaps lot_2" % name_s)
		# Lot 2 south sidewalk access/exit corridor x in [-3.5, 8.5] stays open.
		if pos.z >= -41.5 and pos.z <= -39.5 and pos.x + half_p.x > -3.5 and pos.x - half_p.x < 8.5:
			bad.append("%s blocks lot_2 sidewalk apron" % name_s)

		# 4. BirdPerches patches + clearance kept open.
		for j in BirdPerches.SPOTS.size():
			var spot := BirdPerches.SPOTS[j]
			var half := BirdPerches.HALVES[j]
			if (
				absf(pos.x - spot.x) < half.x + half_p.x + 0.5
				and absf(pos.z - spot.z) < half.y + half_p.y + 0.5
			):
				bad.append("%s overlaps BirdPerch %d at %s" % [name_s, j, spot])

		# 5. Props do not collide with one another.
		for j in range(i + 1, specs.size()):
			var o: Dictionary = specs[j]
			var opos: Vector3 = o["pos"]
			var ohalf: Vector2 = o["half"]
			if (
				absf(pos.x - opos.x) < half_p.x + ohalf.x - 0.05
				and absf(pos.z - opos.z) < half_p.y + ohalf.y - 0.05
			):
				bad.append("%s collides with %s" % [name_s, o["name"]])

	assert_array(bad).is_empty()


func _all_berth_xs() -> Array[float]:
	var xs: Array[float] = []
	for p in STARTER.curb.berths:
		xs.append(p.x)
	for bay: LandsideCurbSpot in STARTER.curb_spots:
		for p in bay.berths:
			xs.append(p.x)
	return xs


func _in_rect(pos: Vector3, half: Vector2, x0: float, x1: float, z0: float, z1: float) -> bool:
	return (
		pos.x + half.x > x0 and pos.x - half.x < x1 and pos.z + half.y > z0 and pos.z - half.y < z1
	)
