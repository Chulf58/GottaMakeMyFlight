class_name PseudoLocale
extends RefCounted
## The pseudolocalization profile for probes and tests (decision
## translation-format-po-gettext-files-with-tr-and-tr-n-for-all). It turns the
## TranslationServer's pseudolocalization on at run time and puts it back,
## because the shipped project settings keep it off.
##
## expansion_ratio is the share of each string added as padding: the server
## puts "_" x (length * ratio / 2) after the prefix and again before the suffix
## (core/string/translation_domain.cpp, _add_padding), so 0.4 grows a string by
## about 40%. What it shows is clipping and overflow: a "]" cut off, a card that
## wraps. It does not show routing: Godot auto-translates every Label, Button
## and tooltip text, so a literal that never went through tr() is bracketed too,
## and a string that did go through tr() is bracketed twice. Routing is the job
## of the guard test (test_translation_guard.gd). tr_n() results are never
## pseudolocalized, so plural lines show no brackets (measured on 4.7.2).
##
## Accents stay off: the server skips only %s/%d style placeholders, so with
## accents on it rewrites the letters inside {named} placeholders and
## String.format() then finds no key.

const EXPANSION := 0.4
const BASE := "internationalization/pseudolocalization/"

static var _saved := {}


## Turns the profile on; keeps the settings it changes so disable() restores them.
static func enable(ratio := EXPANSION) -> void:
	_saved = {
		"use_pseudolocalization": ProjectSettings.get_setting(BASE + "use_pseudolocalization"),
		"expansion_ratio": ProjectSettings.get_setting(BASE + "expansion_ratio"),
		"replace_with_accents": ProjectSettings.get_setting(BASE + "replace_with_accents"),
	}
	ProjectSettings.set_setting(BASE + "use_pseudolocalization", true)
	ProjectSettings.set_setting(BASE + "expansion_ratio", ratio)
	ProjectSettings.set_setting(BASE + "replace_with_accents", false)
	TranslationServer.pseudolocalization_enabled = true
	TranslationServer.reload_pseudolocalization()


## Puts every setting enable() changed back and turns the server's flag off.
static func disable() -> void:
	for key in _saved:
		ProjectSettings.set_setting(BASE + key, _saved[key])
	_saved = {}
	TranslationServer.pseudolocalization_enabled = false
	TranslationServer.reload_pseudolocalization()
