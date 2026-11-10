class_name TestBridgeBoardingOldSave
extends GdUnitTestSuite
## A version 31 passenger save is refused (PassengerSim.SAVE_VERSION 32, board
## 927ed9e0): from 32 a walk outside is measured in 3D and a docking plane's
## walker boards through the jet bridge, so a 31 save's apron_mm is ground
## distance along a ground walk. No migration before the first release
## (decision old-saves-are-not-supported-until-after-a-release-no-save-mi).
##
## The fixture is built fresh as a version 31 save would be written, never by
## cloning a current snapshot (anti_pattern an-old-save-migration-test-built-
## from-a-current-snapshot-hides-a-missing-migration).


func test_a_version_31_save_with_an_apron_walker_is_refused() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	var old := PassengerSnapshot.load(_save(31), grid)
	var current := PassengerSnapshot.load(_save(PassengerSim.SAVE_VERSION), grid)
	print(
		(
			"version 31: %s; version %d, same fixture: %s"
			% [
				old.get("error", "loaded"),
				PassengerSim.SAVE_VERSION,
				current.get("error", "loaded")
			]
		)
	)
	assert_int(PassengerSim.SAVE_VERSION).is_equal(32)
	assert_str(old.get("error", "")).is_equal("save_version must be 32")
	# The control: the version is what refuses it; at 32 the same fixture gets
	# past the version check.
	assert_str(str(current.get("error", ""))).not_contains("save_version")


## A passenger save of `version` holding one walker out on the apron, part way
## along a ground walk to the plane, written field by field.
func _save(version: int) -> Dictionary:
	var walker := {
		"id": 1,
		"flight_id": "F1",
		"stage": Passenger.Stage.APRON,
		"exit_object": 3,
		"apron": [[0.5, 0.22, 0.5], [0.5, 0.22, 0.0], [0.5, 0.2, -6.0]],
		"apron_mm": 2500,
	}
	return {
		"save_version": version,
		"tick": "100",
		"next_id": 2,
		"last_batch_seed": "0",
		"schedule": [],
		"passengers": [walker],
		"queues": {},
		"no_shows": {},
		"cafe": {},
		"made": 0,
		"missed": 0,
		"flight_results": {},
		"scheduled": [],
		"security": [],
		"toilet": {},
		"shop": {},
	}
