class_name TestCaptionFont
extends GdUnitTestSuite
## Every in-world Label3D caption draws in the HUD theme's Nunito (board item
## L2; decision hud-theme-file-game-ui-hud-theme-tres-nunito-font-set-on-eac):
## CaptionFont.font() is the theme's own FontVariation, each caption-making path
## sets it, and the layout code measures captions in the same font.

const THEME := preload("res://ui/hud_theme.tres")
## Game code only: tests, spikes, probes and vendored addons may make Label3Ds
## in other fonts on purpose (the look-pass probe draws the default font).
const SKIP_DIRS := ["res://addons", "res://tests", "res://spike", "res://.godot"]


func test_the_caption_font_is_the_hud_themes_own_nunito() -> void:
	var font := CaptionFont.font()
	print("caption font: %s, base %s" % [font, (font as FontVariation).base_font.resource_path])
	assert_object(font).is_same(THEME.default_font)
	assert_object(font).is_instanceof(FontVariation)
	assert_str((font as FontVariation).base_font.resource_path).is_equal(
		"res://ui/fonts/Nunito-Variable.ttf"
	)
	assert_object(font).is_not_same(ThemeDB.fallback_font)


func test_apply_sets_the_font_on_a_label() -> void:
	var label := auto_free(Label3D.new()) as Label3D
	assert_object(label.font).is_null()
	assert_object(CaptionFont.apply(label)).is_same(label)
	assert_object(label.font).is_same(CaptionFont.font())


func test_the_apron_status_label_is_in_the_caption_font() -> void:
	var stand := ApronStand.new()
	add_child(stand)
	var label := stand.get_node("Status") as Label3D
	assert_object(label.font).is_same(CaptionFont.font())
	stand.free()


func test_the_land_price_label_is_in_the_caption_font() -> void:
	var tool := LandTool.new()
	assert_object(tool.price_label().font).is_same(CaptionFont.font())
	tool.free()


func test_the_gate_caption_is_in_the_caption_font() -> void:
	var view := GateLinksView.new()
	var caption := view._make_caption("Probe", VERTICAL_ALIGNMENT_BOTTOM, 0.0)
	assert_object(caption.font).is_same(CaptionFont.font())
	caption.free()
	view.free()


func test_a_cafe_pop_is_in_the_caption_font() -> void:
	var pops := CafePops.new()
	var label := pops._take()
	assert_object(label.font).is_same(CaptionFont.font())
	label.free()
	pops.free()


func test_a_need_badge_count_is_in_the_caption_font() -> void:
	var badge := NeedCluster.make_badge()
	assert_object((badge.get_node(NeedCluster.COUNT) as Label3D).font).is_same(CaptionFont.font())
	badge.free()


## The gate caption and room label rectangles are measured in the font the
## captions draw with.
func test_caption_layout_measures_in_the_caption_font() -> void:
	var text := "Gate A\nup to large planes"
	var font := CaptionFont.font()
	var width := 0.0
	for line in text.split("\n"):
		width = maxf(
			width,
			font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, MissMarkers.CAPTION_FONT).x
		)
	var size := GateLinksView.caption_size(text)
	print("gate caption size %s, widest line in Nunito %.1f" % [size, width])
	assert_float(size.x).is_equal_approx(width + 2.0 * MissMarkers.CAPTION_OUTLINE, 0.01)
	var room := RoomLabelLayout.label_rect(Vector2.ZERO, "Cafe\nReady", 40, 4, 1.0)
	var measured := font.get_multiline_string_size(
		"Cafe\nReady", HORIZONTAL_ALIGNMENT_CENTER, -1, 40
	)
	print("room label rect %s, Nunito text %s" % [room, measured])
	assert_float(room.size.x).is_equal_approx(measured.x + 8.0, 0.01)
	assert_float(room.size.y).is_equal_approx(measured.y + 8.0, 0.01)


## The Label3D.new() sites in `source` whose label is never given a font: a
## site is fonted when it is wrapped in CaptionFont.apply(), or when the name it
## is assigned to reaches CaptionFont.apply(name) or `name.font =`. An unnamed,
## unwrapped site is listed as "?".
static func unfonted_labels(source: String) -> Array[String]:
	var made := RegEx.create_from_string(
		"(?:(\\w+)\\s*:?=\\s*)?(CaptionFont\\.apply\\(\\s*)?Label3D\\.new\\(\\)"
	)
	var missing: Array[String] = []
	for found in made.search_all(source):
		if found.get_string(2) != "":
			continue
		var name := found.get_string(1)
		if name == "":
			missing.append("?")
			continue
		var applied := RegEx.create_from_string(
			"CaptionFont\\.apply\\(\\s*" + name + "\\s*\\)|\\b" + name + "\\.font\\s*="
		)
		if applied.search(source) == null:
			missing.append(name)
	return missing


static func _game_scripts(dir: String, out: Array[String]) -> void:
	if dir in SKIP_DIRS:
		return
	for sub in DirAccess.get_directories_at(dir):
		_game_scripts(dir.path_join(sub), out)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd") and not file.ends_with("_probe.gd"):
			out.append(dir.path_join(file))


## Every game script that makes a Label3D gives it a font, so no caption falls
## back to the engine default.
func test_every_label3d_the_game_makes_gets_a_font() -> void:
	var scripts: Array[String] = []
	_game_scripts("res://", scripts)
	var sites := 0
	var makers: Array[String] = []
	var missing: Array[String] = []
	var made := RegEx.create_from_string("Label3D\\.new\\(\\)")
	for path in scripts:
		var source := FileAccess.get_file_as_string(path)
		var count := made.search_all(source).size()
		if count == 0:
			continue
		sites += count
		makers.append(path.get_file())
		for name in unfonted_labels(source):
			missing.append("%s: %s" % [path, name])
	print("scripts %d, Label3D.new() sites %d in %s" % [scripts.size(), sites, makers])
	print("unfonted: %s" % [missing])
	assert_int(scripts.size()).is_greater(100)
	assert_int(sites).is_greater_equal(8)
	assert_array(missing).is_empty()


## Control: the scan flags a label that is made and never given a font, so it
## cannot pass by accident.
func test_the_scan_flags_a_label_with_no_font() -> void:
	var bare := 'var caption := Label3D.new()\ncaption.text = tr("Gate")\n'
	assert_array(unfonted_labels(bare)).is_equal(["caption"] as Array[String])
	assert_array(unfonted_labels(bare + "CaptionFont.apply(caption)\n")).is_empty()
	assert_array(unfonted_labels(bare + "caption.font = f\n")).is_empty()
	assert_array(unfonted_labels("var _price := Label3D.new()\n_price.font_size = 3\n")).has_size(1)
	assert_array(unfonted_labels("var _price := CaptionFont.apply(Label3D.new())\n")).is_empty()
	assert_array(unfonted_labels("add_child(Label3D.new())\n")).is_equal(["?"] as Array[String])
