class_name TestPassengerLooks
extends GdUnitTestSuite
## Passenger looks (PassengerLooks): the body, clothing tint and bag colour come
## from the variant and the id alone, neighbours in spawn order differ, a tint
## recolours the clothes and nothing else, and PassengerViews draws each
## passenger with its own body and tint.


func test_a_body_stays_within_its_variant_and_every_body_is_drawn() -> void:
	var seen := {}
	for variant in 2:
		for id in range(1, 61):
			var body := PassengerLooks.body_of(id, variant)
			assert_int(PassengerLooks.variant_of(body)).is_equal(variant)
			seen[body] = true
	print("bodies seen: %s" % [seen.keys()])
	assert_int(seen.size()).is_equal(PassengerLooks.BODIES.size())


## The roster (decision passenger-looks-add-the-unused-toon-city-people-bodies-
## and-b): 19 bodies, 9 male then 10 female, male 10 and female 02 among them
## (board a1c067fc), each with its own scene and both walk and run speeds.
func test_the_roster_holds_19_bodies_with_male_10_and_female_02() -> void:
	print("roster: %d bodies, %d male" % [PassengerLooks.BODIES.size(), PassengerLooks.PER_VARIANT])
	assert_int(PassengerLooks.BODIES.size()).is_equal(19)
	assert_int(PassengerLooks.PER_VARIANT).is_equal(9)
	assert_int(PassengerLooks.SCENES.size()).is_equal(PassengerLooks.BODIES.size())
	assert_int(PassengerLooks.CLIP_WALK_MPS.size()).is_equal(PassengerLooks.BODIES.size())
	assert_int(PassengerLooks.CLIP_RUN_MPS.size()).is_equal(PassengerLooks.BODIES.size())
	for added: Array in [["tcp_male_character_10", 0], ["tcp_female_character_02", 1]]:
		var b := PassengerLooks.BODIES.find(added[0])
		assert_int(b).override_failure_message(added[0]).is_greater_equal(0)
		assert_int(PassengerLooks.variant_of(b)).is_equal(added[1])
		assert_str(PassengerLooks.SCENES[b].resource_path).contains(added[0])
	for b in PassengerLooks.BODIES.size():
		var stem := PassengerLooks.BODIES[b]
		assert_bool(stem.contains("_male_") == (PassengerLooks.variant_of(b) == 0)).is_true()
		assert_str(PassengerLooks.SCENES[b].resource_path).contains(stem)


## Every body has a seat shift (game/spike/passenger_looks_plates_probe.gd
## measures it against the seat row), never backward or down, and lifted at
## most 2 cm: more would show the body floating over the pan.
func test_every_body_has_a_seat_shift_forward_and_at_most_a_small_lift() -> void:
	assert_int(PassengerLooks.SEAT_SHIFT_M.size()).is_equal(PassengerLooks.BODIES.size())
	for shift in PassengerLooks.SEAT_SHIFT_M:
		assert_float(shift.x).is_greater(0.0)
		assert_float(shift.y).is_between(0.0, 0.02)


## Every body has a cafe seat shift (the plates probe's --parts=cafe measures
## it against the cafe_table), towards the table and never up by more than
## 2 cm: more would show the body floating over the pan.
func test_every_body_has_a_cafe_seat_shift_towards_the_table_and_a_small_lift() -> void:
	assert_int(PassengerLooks.CAFE_SEAT_SHIFT_M.size()).is_equal(PassengerLooks.BODIES.size())
	for shift in PassengerLooks.CAFE_SEAT_SHIFT_M:
		assert_float(shift.x).is_greater(0.0)
		assert_float(shift.y).is_between(0.0, 0.02)


## The services kit's food pieces (board 3405a04b, updated in VF6 for tall bar
## stools) take their own seat step (game/spike/food_seat_plates_probe.gd
## measures it): one per body, never backward or down, at most 3 cm towards the
## table, up to 2 cm lift at dining tables/booths, and BAR_SEAT_LIFT_M + [0, 0.02]
## on the 0.68 m bar_counter stools. The cafe table keeps CAFE_SEAT_SHIFT_M.
func test_the_food_pieces_take_their_own_small_seat_step() -> void:
	var pieces := [&"restaurant_table", &"restaurant_booth", &"bar_counter"]
	assert_array(PassengerLooks.PIECE_SEAT_SHIFT_M.keys()).contains_exactly_in_any_order(pieces)
	for piece: StringName in pieces:
		var min_lift := PassengerLooks.BAR_SEAT_LIFT_M if piece == &"bar_counter" else 0.0
		var max_lift := min_lift + 0.02
		for body in PassengerLooks.BODIES.size():
			var shift := PassengerLooks.seat_shift(piece, body)
			assert_float(shift.x).override_failure_message(str(piece)).is_between(0.0, 0.03)
			assert_float(shift.y).override_failure_message(str(piece)).is_between(
				min_lift - 1e-5, max_lift + 1e-5
			)
			assert_vector(shift).is_equal(PassengerLooks.PIECE_SEAT_SHIFT_M[piece][body])
	for body in PassengerLooks.BODIES.size():
		assert_vector(PassengerLooks.seat_shift(&"cafe_table", body)).is_equal(
			PassengerLooks.CAFE_SEAT_SHIFT_M[body]
		)


func test_the_look_is_the_same_for_the_same_id() -> void:
	for id in [1, 7, 42, 1000]:
		assert_int(PassengerLooks.body_of(id, 1)).is_equal(PassengerLooks.body_of(id, 1))
		assert_int(PassengerLooks.tint_of(id)).is_equal(PassengerLooks.tint_of(id))
		assert_int(PassengerLooks.bag_of(id)).is_equal(PassengerLooks.bag_of(id))


## Within a block of ids every body, tint and bag colour comes once, so no two
## passengers spawned in one block look alike; across a block edge the pair
## of neighbours may share one of them but rarely all three.
func test_neighbours_in_spawn_order_differ() -> void:
	var same_look := 0
	for block in 50:
		var bodies := {}
		var tints := {}
		var bags := {}
		for k in PassengerLooks.LOOK_BLOCK:
			var id := block * PassengerLooks.LOOK_BLOCK + k
			bodies[PassengerLooks.body_of(id, 0)] = true
			tints[PassengerLooks.tint_of(id)] = true
			bags[PassengerLooks.bag_of(id)] = true
		assert_int(bodies.size()).is_equal(PassengerLooks.LOOK_BLOCK)
		assert_int(tints.size()).is_equal(PassengerLooks.LOOK_BLOCK)
		assert_int(bags.size()).is_equal(PassengerLooks.BAG_TINTS.size())
	for id in range(1, 301):
		if (
			PassengerLooks.body_of(id, 0) == PassengerLooks.body_of(id + 1, 0)
			and PassengerLooks.tint_of(id) == PassengerLooks.tint_of(id + 1)
		):
			same_look += 1
	print("neighbour pairs with the same body and tint in 300: %d" % same_look)
	assert_int(same_look).is_less(5)


func test_cloth_split_follows_the_clothes_mark() -> void:
	var index := PackedInt32Array([0, 1, 2, 3, 4, 5, 0, 2, 5])
	var colors := PackedColorArray(
		[Color.BLACK, Color.BLACK, Color.BLACK, Color.WHITE, Color.WHITE, Color.WHITE]
	)
	var parts := PassengerLooks.cloth_split(index, colors)
	assert_array(Array(parts[0])).is_equal([0, 1, 2, 0, 2, 5])
	assert_array(Array(parts[1])).is_equal([3, 4, 5])


## A tint sets the hue and saturation outright, keeps the shading (value
## order) and lifts black off the floor; tint 0 changes nothing.
func test_a_tint_sets_its_colour_and_keeps_the_shading() -> void:
	var red := Color.from_hsv(0.0, 0.8, 0.6)
	assert_that(PassengerLooks.tinted(red, -1.0, 0.0)).is_equal(red)
	var grey := PassengerLooks.tinted(Color(0.5, 0.5, 0.5), 0.59, 0.56)
	var dark := PassengerLooks.tinted(Color(0.1, 0.1, 0.1), 0.59, 0.56)
	var black := PassengerLooks.tinted(Color.BLACK, 0.59, 0.56)
	print("grey -> %s, dark -> %s, black -> %s" % [grey, dark, black])
	assert_float(grey.h).is_equal_approx(0.59, 0.01)
	assert_float(grey.s).is_equal_approx(0.56, 0.01)
	assert_float(dark.v).is_less(grey.v)
	assert_float(black.v).is_equal_approx(PassengerLooks.VALUE_FLOOR, 0.01)
	assert_float(black.s).is_equal_approx(0.56, 0.01)
	# A red swatch in a blue tint is blue: the hue is set, not turned.
	assert_float(PassengerLooks.tinted(red, 0.59, 0.56).h).is_equal_approx(0.59, 0.01)


## Cozy, not neon: no tinted colour is stronger (saturation times value) than
## 0.53, white goes pastel, and a gradient's step is never larger than its
## source's (no bands).
func test_tints_stay_cozy_and_smooth() -> void:
	var most := 0.0
	var worst_step := 0.0
	for tint in range(1, PassengerLooks.TINTS.size()):
		var family := PassengerLooks.TINTS[tint]
		for pair in [Vector2(family.x, family.y), Vector2(family.z, family.w)]:
			var last := PassengerLooks.tinted(Color.BLACK, pair.x, pair.y)
			for k in range(1, 101):
				var c := PassengerLooks.tinted(Color.from_hsv(0.3, 0.2, k / 100.0), pair.x, pair.y)
				most = maxf(most, c.s * c.v)
				var step := Vector3(c.r - last.r, c.g - last.g, c.b - last.b).length()
				worst_step = maxf(worst_step, step)
				last = c
		var white := PassengerLooks.tinted(Color.WHITE, family.x, family.y)
		assert_float(white.s).is_less_equal(family.y * (1.0 - PassengerLooks.BRIGHT_DIM) + 0.01)
	print("strongest tinted colour %.3f, largest step per 0.01 value %.4f" % [most, worst_step])
	assert_float(most).is_less_equal(0.53)
	assert_float(most).is_greater(0.4)
	assert_float(worst_step).is_less(0.03)


## The tints are different colour families: every two light hues are at least
## 0.05 of the wheel apart, and there are at least eight besides the vendor's.
func test_tints_are_different_colour_families() -> void:
	assert_int(PassengerLooks.TINTS.size()).is_greater_equal(9)
	var closest := 1.0
	for a in range(1, PassengerLooks.TINTS.size()):
		for b in range(a + 1, PassengerLooks.TINTS.size()):
			var d := absf(PassengerLooks.TINTS[a].x - PassengerLooks.TINTS[b].x)
			closest = minf(closest, minf(d, 1.0 - d))
	print("closest two light hues: %.3f" % closest)
	assert_float(closest).is_greater_equal(0.05)


## A dark swatch cell takes the tint's second colour, a light one its first.
func test_dark_cells_take_the_second_colour() -> void:
	var atlas := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	atlas.fill_rect(Rect2i(0, 0, 32, 64), Color(0.9, 0.9, 0.9))
	atlas.fill_rect(Rect2i(32, 0, 32, 64), Color(0.15, 0.15, 0.15))
	var texels := PackedInt32Array([10 * 64 + 5, 10 * 64 + 40])
	var dark := PassengerLooks.dark_cells(atlas, texels)
	assert_bool(dark[0]).is_false()
	assert_bool(dark[1]).is_true()
	var out := PassengerLooks.tint_image(atlas, texels, 1)
	var family := PassengerLooks.TINTS[1]
	print("light %s dark %s" % [out.get_pixel(5, 10), out.get_pixel(40, 10)])
	assert_float(out.get_pixel(5, 10).h).is_equal_approx(family.x, 0.02)
	assert_float(out.get_pixel(40, 10).h).is_equal_approx(family.z, 0.02)
	assert_that(out.get_pixel(6, 20)).is_equal(atlas.get_pixel(6, 20))


## Every body carries the clothes' mark, and a tinted body draws the clothes on
## a recoloured atlas and everything else on the shared one: a texel under a
## clothes triangle changed, a texel under a face (skin) triangle did not.
func test_a_tint_recolours_the_clothes_and_keeps_the_skin() -> void:
	for body in PassengerLooks.BODIES.size():
		var plain := PassengerLooks.plain_mesh(body)
		var split := PassengerLooks.split_mesh(body, 1)
		assert_int(split.get_surface_count()).is_equal(2)
		var whole: int = (plain.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		var other: int = (split.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		var cloth: int = (split.surface_get_arrays(1)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		print(
			(
				"%s: triangles %d = other %d + clothes %d"
				% [PassengerLooks.BODIES[body], whole / 3, other / 3, cloth / 3]
			)
		)
		assert_int(cloth).is_greater(0)
		assert_int(other).is_greater(0)
		assert_int(other + cloth).is_equal(whole)
		assert_object(split.surface_get_material(0)).is_same(plain.surface_get_material(0))
	var shared := PassengerLooks.plain_mesh(0).surface_get_material(0) as ShaderMaterial
	var base: Texture2D = shared.get_shader_parameter("albedo_texture")
	var tinted: Texture2D = PassengerLooks.material(1).get_shader_parameter("albedo_texture")
	assert_object(tinted).is_not_same(base)
	var before := base.get_image()
	before.decompress()
	var after := tinted.get_image()
	var arrays := PassengerLooks.plain_mesh(0).surface_get_arrays(0)
	var parts := PassengerLooks.cloth_split(arrays[Mesh.ARRAY_INDEX], arrays[Mesh.ARRAY_COLOR])
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var size := Vector2(before.get_width(), before.get_height())
	var changed := 0
	for t in range(0, (parts[1] as PackedInt32Array).size(), 3):
		var at := Vector2i(uvs[parts[1][t]] * size)
		if not before.get_pixelv(at).is_equal_approx(after.get_pixelv(at)):
			changed += 1
	var kept := 0
	var cloth_texels := PassengerLooks.cloth_texels(before.get_width(), before.get_height())
	var clothes := {}
	for t in cloth_texels:
		clothes[t] = true
	for t in range(0, (parts[0] as PackedInt32Array).size(), 3):
		var at := Vector2i(uvs[parts[0][t]] * size)
		if not clothes.has(at.y * before.get_width() + at.x):
			kept += int(before.get_pixelv(at).is_equal_approx(after.get_pixelv(at)))
	print(
		(
			"male_01 tint 1: clothes corners changed %d, other corners off the clothes kept %d"
			% [changed, kept]
		)
	)
	assert_int(changed).is_greater(0)
	assert_int(kept).is_greater(0)


func test_views_draw_each_passenger_with_its_body_and_tint() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(5, 1), 0)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(30, 40))
	var views := PassengerTestWorld.views()
	views.clock = world.clock
	views.sim = world.sim
	add_child(views)
	var tinted := 0
	for n in 12:
		world.sim.spawn_now(PassengerTestWorld.FLIGHT, n % 2)
	world.step()
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		var node := views.node_for(id)
		var body := PassengerLooks.body_of(id, p.variant)
		var tint := PassengerLooks.tint_of(id)
		assert_int(node.get_meta(&"body")).is_equal(body)
		var drawn := PassengerLooks.body_mesh(node).mesh
		var want := (
			PassengerLooks.plain_mesh(body) if tint == 0 else PassengerLooks.split_mesh(body, tint)
		)
		assert_object(drawn).is_same(want)
		tinted += int(tint != 0)
	print("passengers drawn %d, tinted %d" % [world.sim.passenger_ids().size(), tinted])
	assert_int(tinted).is_greater(0)
	views.free()
	world.free_all()


func test_bags_take_their_passengers_colour() -> void:
	var bag := InteriorKit.instantiate(SecurityLooks.KIND_PIECES[SecurityLooks.Kind.CASE])
	add_child(bag)
	var id := 1
	while PassengerLooks.bag_of(id) == 0:
		id += 1
	PassengerLooks.paint_bags([{"node": bag}], id)
	var bodies := bag.find_children("*_Body", "MeshInstance3D", true, false)
	assert_int(bodies.size()).is_greater(0)
	var mi := bodies[0] as MeshInstance3D
	var colour: Color = (mi.material_override as ShaderMaterial).get_shader_parameter("albedo_tint")
	assert_that(colour).is_equal(PassengerLooks.BAG_TINTS[PassengerLooks.bag_of(id)])
	var plain_id := 1
	while PassengerLooks.bag_of(plain_id) != 0:
		plain_id += 1
	PassengerLooks.paint_bags([{"node": bag}], plain_id)
	assert_object(mi.material_override).is_null()
	bag.free()
