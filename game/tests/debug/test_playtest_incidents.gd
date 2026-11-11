class_name TestPlaytestIncidents
extends GdUnitTestSuite
## The playtest switch for incidents: --playtest-incidents turns a scene's
## incidents on (a playtest runs no new-game dialog, so they start off), and
## --playtest-incidents=<kind> also forces every roll to that kind. The hook
## being off keeps force_incidents() from touching anything.

const HOOK := preload("res://debug/playtest_hook.gd")


func test_the_incidents_argument_is_read_bare_or_with_a_kind() -> void:
	assert_object(HOOK.incidents_arg(PackedStringArray())).is_null()
	assert_object(HOOK.incidents_arg(PackedStringArray(["--playtest"]))).is_null()
	assert_str(HOOK.incidents_arg(PackedStringArray(["--playtest-incidents"]))).is_equal("")
	assert_str(HOOK.incidents_arg(PackedStringArray(["--playtest-incidents=spill"]))).is_equal(
		"spill"
	)
	var recorded := HOOK.recorded_args(PackedStringArray(["--playtest-incidents=spill", "x"]))
	assert_array(recorded).is_equal(["--playtest-incidents=spill"])


func test_forcing_turns_incidents_on_with_the_kind_and_refuses_an_unknown_one() -> void:
	var director := auto_free(IncidentDirector.new()) as IncidentDirector
	assert_bool(director.is_enabled()).is_false()
	assert_bool(HOOK.force_on(director, "spill")).is_true()
	assert_bool(director.is_enabled()).is_true()
	assert_str(director.forced_kind).is_equal("spill")
	var other := auto_free(IncidentDirector.new()) as IncidentDirector
	assert_bool(HOOK.force_on(other, "volcano")).is_false()
	assert_bool(other.is_enabled()).is_false()


func test_force_incidents_does_nothing_while_the_hook_is_off() -> void:
	var hook := auto_free(HOOK.new()) as Node
	hook.configure(false)
	assert_bool(hook.force_incidents("spill")).is_false()
