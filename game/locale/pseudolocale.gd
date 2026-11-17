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

## What the live settings and the server's flag were before enable(); empty
## while the profile is off.
static var _saved := {}


## Turns the profile on and snapshots what it changes for disable(). A second
## call while the profile is already on does nothing, so the first snapshot
## (the real state) is never overwritten by the profile's own values.
static func enable(ratio := EXPANSION) -> void:
	if not _saved.is_empty():
		return
	_saved = {
		"use_pseudolocalization": ProjectSettings.get_setting(BASE + "use_pseudolocalization"),
		"expansion_ratio": ProjectSettings.get_setting(BASE + "expansion_ratio"),
		"replace_with_accents": ProjectSettings.get_setting(BASE + "replace_with_accents"),
		"server_enabled": TranslationServer.pseudolocalization_enabled,
	}
	ProjectSettings.set_setting(BASE + "use_pseudolocalization", true)
	ProjectSettings.set_setting(BASE + "expansion_ratio", ratio)
	ProjectSettings.set_setting(BASE + "replace_with_accents", false)
	TranslationServer.pseudolocalization_enabled = true
	TranslationServer.reload_pseudolocalization()


## Puts the settings and the server's flag back exactly as enable() found them.
## Does nothing when the profile is not on.
static func disable() -> void:
	if _saved.is_empty():
		return
	for key in ["use_pseudolocalization", "expansion_ratio", "replace_with_accents"]:
		ProjectSettings.set_setting(BASE + key, _saved[key])
	TranslationServer.pseudolocalization_enabled = _saved["server_enabled"]
	_saved = {}
	TranslationServer.reload_pseudolocalization()
