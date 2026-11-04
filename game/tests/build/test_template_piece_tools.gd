class_name TestTemplatePieceTools
extends GdUnitTestSuite
## Every piece a room template can keep is held to a build tool, so a template
## cannot paste a piece the Build menu would still refuse. The Belt tool places
## through a special path with no catalog object, which let `baggage_belt` slip
## past the lock (board 240ca2ec, Sol re-check).

## Pieces a template may keep that no tool gates. None today; list one here
## with the reason when a piece is legitimately free.
const UNGATED: Array[StringName] = []


func test_every_piece_a_template_can_keep_maps_to_a_build_tool() -> void:
	var unmapped: Array[String] = []
	var checked := 0
	for def_id in BuildCatalog.ids():
		if not RoomTemplate.keeps_piece(def_id) or UNGATED.has(def_id):
			continue
		checked += 1
		var kept := BeltShaper.BELT if BuildCatalog.is_belt(def_id) else def_id
		if BuildUnlocks.tool_for_object(kept) == BuildMode.Tool.NONE:
			unmapped.append(String(kept))
	print("template pieces checked: %d, unmapped: %s" % [checked, unmapped])
	assert_int(checked).is_greater(0)
	assert_array(unmapped).is_empty()


func test_the_belt_pieces_are_held_to_the_belt_tool() -> void:
	for belt_id in BuildCatalog.BELT_IDS:
		assert_int(BuildUnlocks.tool_for_object(belt_id)).is_equal(BuildMode.Tool.BELT)
