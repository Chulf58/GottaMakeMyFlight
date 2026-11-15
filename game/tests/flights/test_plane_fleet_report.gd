class_name TestPlaneFleetReport
extends GdUnitTestSuite
## PlaneFleet reports a gate it cannot route once, and again when the gate
## comes back (taxiroutes-as-built, board item taxiroutes-residual-edge-cases-
## on-malformed-scenes): the entry goes when the gate leaves live_gates(), not
## only while the gate is live and routed.

const MESSAGE := "PlaneFleet: gate B has no taxi route; its planes are not drawn"


## A sim whose live flights are set directly: one-off flights are never
## pruned, so a gate could not otherwise lose its flight.
class HeldSim:
	extends FlightSim
	var held := {}

	func flight_ids() -> Array[String]:
		var ids: Array[String] = []
		ids.assign(held.keys())
		return ids

	func flight_gate(id: String) -> String:
		return held.get(id, "")


func test_the_report_fires_again_after_a_gate_loses_and_regains_its_flight() -> void:
	var airside := auto_free(TestStandLaneClearance.scene_airside()) as Airside
	add_child(airside)
	airside.get_node("RunwayExit").free()
	assert_bool(airside.rebuild()).is_false()
	var sim := auto_free(HeldSim.new()) as HeldSim
	var fleet := auto_free(PlaneFleet.new()) as PlaneFleet
	fleet.sim = sim
	fleet.airside = airside
	sim.held = {"F1": "B"}
	assert_error(func() -> void: fleet.update_views()).is_push_error(MESSAGE)
	# Reported once while the flight stays.
	assert_error(func() -> void: fleet.update_views()).is_success()
	sim.held = {}
	fleet.update_views()
	assert_dict(fleet._unroutable).is_empty()
	sim.held = {"F2": "B"}
	assert_error(func() -> void: fleet.update_views()).is_push_error(MESSAGE)
	assert_array(fleet.gates).is_empty()
