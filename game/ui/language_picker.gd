class_name LanguagePicker
extends HBoxContainer

const LOCALE_SETTINGS := preload("res://locale/locale_settings.gd")
const LABEL_WIDTH := 128.0
const OPTION_MIN_WIDTH := 168.0

var _show_label := true
var _label: Label
var _option: OptionButton
var _codes := PackedStringArray()


func _init(show_label := true) -> void:
	_show_label = show_label
	add_theme_constant_override("separation", 10)
	if _show_label:
		_label = Label.new()
		_label.name = "Label"
		_label.text = tr("Language")
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_label)
	_option = OptionButton.new()
	_option.name = "Option"
	_option.focus_mode = Control.FOCUS_NONE
	_option.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_option.get_popup().auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_option.custom_minimum_size = Vector2(OPTION_MIN_WIDTH, 0.0)
	_codes = LOCALE_SETTINGS.codes()
	for code in _codes:
		_option.add_item(LOCALE_SETTINGS.display_name(code))
	_option.item_selected.connect(_on_item_selected)
	add_child(_option)


func _ready() -> void:
	var settings := _settings()
	if settings != null and not settings.locale_changed.is_connected(_on_locale_changed):
		settings.locale_changed.connect(_on_locale_changed)
	_retranslate()


func _exit_tree() -> void:
	var settings := _settings()
	if is_instance_valid(settings) and settings.locale_changed.is_connected(_on_locale_changed):
		settings.locale_changed.disconnect(_on_locale_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()


func option_button() -> OptionButton:
	return _option


func label() -> Label:
	return _label


func selected_code() -> String:
	var idx := _option.selected
	if idx < 0 or idx >= _codes.size():
		return LOCALE_SETTINGS.DEFAULT_LOCALE
	return _codes[idx]


func select_code(code: String) -> bool:
	var settings := _settings()
	if settings != null:
		return settings.select_locale(code)
	return false


func set_label_min_width(width: float) -> void:
	if _label != null:
		_label.custom_minimum_size = Vector2(width, 0.0)


func _settings() -> LOCALE_SETTINGS:
	return get_node_or_null(^"/root/LocaleSettings") as LOCALE_SETTINGS


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _codes.size():
		return
	select_code(_codes[index])


func _on_locale_changed(code: String) -> void:
	_sync_selection(code)


func _sync_selection(code: String) -> void:
	var idx := _codes.find(code)
	if idx >= 0 and _option.selected != idx:
		_option.select(idx)


func _retranslate() -> void:
	if _label != null:
		_label.text = tr("Language")
	var settings := _settings()
	if settings != null:
		_sync_selection(settings.current_locale())
