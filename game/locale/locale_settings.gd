extends Node

signal locale_changed(code: String)

const DEFAULT_LOCALE := "en"
const DEFAULT_SETTINGS_PATH := "user://locale.cfg"
const SECTION := "locale"
const KEY := "code"

const BASE_FONT_PATH := "res://ui/fonts/Nunito-Variable.ttf"
const SC_FONT_PATH := "res://ui/fonts/NotoSansSC-Bold.otf"
const JP_FONT_PATH := "res://ui/fonts/NotoSansJP-Bold.otf"
const KR_FONT_PATH := "res://ui/fonts/NotoSansKR-Bold.otf"

const LOCALES := {
	"en": "English",
	"zh_CN": "简体中文",
	"ja": "日本語",
	"ko": "한국어",
	"de": "Deutsch",
	"fr": "Français",
	"es": "Español",
	"pt_BR": "Português (Brasil)",
	"ru": "Русский",
	"pl": "Polski",
}

var protected_path := DEFAULT_SETTINGS_PATH
var settings_path := DEFAULT_SETTINGS_PATH
var _current := DEFAULT_LOCALE


func _init() -> void:
	load_available_translations()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_available_translations()
	if Hints.launched_by_script(OS.get_cmdline_args()):
		apply_locale(DEFAULT_LOCALE, false)
		return
	var saved := load_from_path(settings_path)
	apply_locale(resolve_startup_locale(saved, OS.get_locale()), false)


static func load_available_translations() -> void:
	var loaded := TranslationServer.get_loaded_locales()
	for code: String in LOCALES:
		if code == DEFAULT_LOCALE or loaded.has(code):
			continue
		var path := "res://locale/%s.po" % code
		if not ResourceLoader.exists(path):
			continue
		var tr_res := ResourceLoader.load(path) as Translation
		if tr_res != null:
			TranslationServer.add_translation(tr_res)


static func codes() -> PackedStringArray:
	return PackedStringArray(LOCALES.keys())


static func available_locales() -> PackedStringArray:
	var out := PackedStringArray()
	for code: String in LOCALES:
		if is_available(code):
			out.append(code)
	return out


static func is_supported(code: String) -> bool:
	return LOCALES.has(code)


static func is_available(code: String) -> bool:
	if code == DEFAULT_LOCALE:
		return true
	if not LOCALES.has(code):
		return false
	return TranslationServer.get_loaded_locales().has(code)


static func resolve_startup_locale(saved: String, os_locale: String) -> String:
	if saved != "" and is_available(saved):
		return saved
	var os_code := normalize_os_locale(os_locale)
	if is_available(os_code):
		return os_code
	return DEFAULT_LOCALE


static func display_name(code: String) -> String:
	return str(LOCALES.get(code, ""))


static func normalize_os_locale(raw: String) -> String:
	var clean := raw.strip_edges()
	if clean == "":
		return DEFAULT_LOCALE
	var std := TranslationServer.standardize_locale(clean)
	var parts := std.replace("-", "_").split("_", false)
	if parts.is_empty():
		return DEFAULT_LOCALE
	var lang := parts[0].to_lower()
	if lang == "zh":
		return _normalize_chinese(parts.slice(1))
	match lang:
		"pt":
			return "pt_BR"
		"es", "ja", "ko", "de", "fr", "ru", "pl", "en":
			return lang
	return DEFAULT_LOCALE


static func _normalize_chinese(subtags: PackedStringArray) -> String:
	for tag in subtags:
		if tag.to_lower() == "hant":
			return DEFAULT_LOCALE
	for tag in subtags:
		if tag.to_lower() == "hans":
			return "zh_CN"
	for tag in subtags:
		var region := tag.to_upper()
		if region == "TW" or region == "HK" or region == "MO":
			return DEFAULT_LOCALE
	return "zh_CN"


static func save_to_path(path: String, code: String) -> bool:
	if not is_supported(code):
		return false
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_error("LocaleSettings: cannot read %s (error %d)" % [path, err])
		return false
	cfg.set_value(SECTION, KEY, code)
	err = cfg.save(path)
	if err != OK:
		push_error("LocaleSettings: cannot write %s (error %d)" % [path, err])
		return false
	return true


static func load_from_path(path: String) -> String:
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err == ERR_FILE_NOT_FOUND:
		return ""
	if err != OK:
		push_error("LocaleSettings: cannot read %s (error %d)" % [path, err])
		return ""
	var code := str(cfg.get_value(SECTION, KEY, ""))
	if code != "" and not is_supported(code):
		push_error("LocaleSettings: unsupported locale '%s' in %s" % [code, path])
		return ""
	return code


func apply_locale(code: String, persist := false) -> bool:
	if not is_supported(code):
		return false
	if not is_available(code):
		apply_locale(DEFAULT_LOCALE, persist)
		return false
	_apply_font_fallbacks(code)
	_current = code
	TranslationServer.set_locale(code)
	if persist and not _is_shielded():
		save_to_path(settings_path, code)
	locale_changed.emit(code)
	return true


func select_locale(code: String) -> bool:
	return apply_locale(code, true)


func current_locale() -> String:
	var active := TranslationServer.get_locale()
	if is_available(active):
		return active
	return _current


func _is_shielded() -> bool:
	return settings_path == protected_path and Hints.launched_by_script(OS.get_cmdline_args())


static func _apply_font_fallbacks(code: String) -> void:
	var base_font := load(BASE_FONT_PATH) as FontFile
	if base_font == null:
		push_error("LocaleSettings: missing base font %s" % BASE_FONT_PATH)
		return
	var sc := load(SC_FONT_PATH) as Font
	var jp := load(JP_FONT_PATH) as Font
	var kr := load(KR_FONT_PATH) as Font
	var ordered: Array[Font] = []
	match code:
		"ja":
			ordered = [jp, sc, kr]
		"ko":
			ordered = [kr, jp, sc]
		_:
			ordered = [sc, jp, kr]
	base_font.fallbacks = ordered
