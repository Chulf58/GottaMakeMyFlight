class_name TestPseudolocale
extends GdUnitTestSuite
## The pseudolocalization profile (PseudoLocale): on, an untranslated string
## comes back bracketed and padded by about the expansion ratio, and {named}
## placeholders still format; off, it comes back unchanged. The server's flag and
## the project settings are put back after every case.

const SAMPLE := "Mood: {mood} of {max}"


func after_test() -> void:
	PseudoLocale.disable()


func test_it_is_off_in_the_shipped_settings() -> void:
	(
		assert_bool(
			ProjectSettings.get_setting(
				"internationalization/pseudolocalization/use_pseudolocalization"
			)
		)
		. is_false()
	)
	assert_bool(TranslationServer.pseudolocalization_enabled).is_false()
	assert_str(TranslationServer.translate(SAMPLE)).is_equal(SAMPLE)


func test_on_it_brackets_and_pads_a_string_by_the_ratio() -> void:
	PseudoLocale.enable(0.4)
	var shown := String(TranslationServer.translate(SAMPLE))
	assert_str(shown).starts_with("[").ends_with("]").contains(SAMPLE)
	var growth := float(shown.length() - SAMPLE.length()) / SAMPLE.length()
	assert_float(growth).is_between(0.35, 0.55)


func test_on_the_named_placeholders_still_format() -> void:
	PseudoLocale.enable()
	var shown := String(TranslationServer.translate(SAMPLE)).format({"mood": 80, "max": 100})
	assert_str(shown).contains("Mood: 80 of 100").not_contains("{")


func test_off_again_it_restores_the_string_and_the_settings() -> void:
	PseudoLocale.enable()
	PseudoLocale.disable()
	assert_str(TranslationServer.translate(SAMPLE)).is_equal(SAMPLE)
	(
		assert_float(
			ProjectSettings.get_setting("internationalization/pseudolocalization/expansion_ratio")
		)
		. is_equal(0.0)
	)
	(
		assert_bool(
			ProjectSettings.get_setting(
				"internationalization/pseudolocalization/replace_with_accents"
			)
		)
		. is_true()
	)
