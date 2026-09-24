extends Node
## Player settings (autoload "Settings"), saved in user://settings.cfg and
## applied as soon as they change. Keys are "section/name":
##   audio/Master, audio/SFX, audio/Ambience, audio/Music   0..1
##   display/fullscreen, display/vsync                      bool
##   display/ui_scale                                       0.75..2.0
##   game/hints, game/edge_scroll, game/pause_on_raid       bool
##   game/autosave_minutes                                  0 (off), 2, 5, 10
##   game/pan_speed                                         camera speed multiplier
## Tools call use_file() first so they never read or change the player's file.

signal changed(key: String)

const DEFAULT_FILE := "user://settings.cfg"
const DEFAULTS := {
	"audio/Master": 0.8, "audio/SFX": 0.8, "audio/Ambience": 0.6, "audio/Music": 0.5,
	"display/fullscreen": false, "display/vsync": true, "display/ui_scale": 1.0,
	"game/hints": true, "game/autosave_minutes": 5, "game/pan_speed": 1.0,
	"game/edge_scroll": false, "game/pause_on_raid": false,
}
const UI_SCALES := [0.75, 1.0, 1.25, 1.5, 2.0]
const AUTOSAVE_CHOICES := [0, 2, 5, 10]
const PAN_SPEEDS := {"Slow": 0.6, "Normal": 1.0, "Fast": 1.6}

var path := DEFAULT_FILE
var values := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_file()


## Switch to another settings file (tests and tools). `fresh` starts it from
## the defaults instead of whatever an earlier run left there.
func use_file(p_path: String, fresh := true) -> void:
	path = p_path
	if fresh:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	load_file()


func load_file() -> void:
	values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		for key: String in DEFAULTS:
			var parts := key.split("/")
			values[key] = type_convert(cfg.get_value(parts[0], parts[1], DEFAULTS[key]), typeof(DEFAULTS[key]))
	for key: String in values:
		_apply(key)


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	value = type_convert(value, typeof(DEFAULTS[key]))
	if values.get(key) == value:
		return
	values[key] = value
	_apply(key)
	var cfg := ConfigFile.new()
	cfg.load(path)
	var parts := key.split("/")
	cfg.set_value(parts[0], parts[1], value)
	cfg.save(path)
	changed.emit(key)


func toggle_fullscreen() -> void:
	set_value("display/fullscreen", not get_value("display/fullscreen"))


func _apply(key: String) -> void:
	var value: Variant = values[key]
	if key.begins_with("audio/"):
		Sound.set_volume(key.get_slice("/", 1), value)
		return
	match key:
		"game/hints":
			GameState.hints_enabled = value
		"display/ui_scale":
			get_window().content_scale_factor = value
	# The window itself: leave it alone headless (tests size it themselves).
	if DisplayServer.get_name() == "headless":
		return
	match key:
		"display/fullscreen":
			var want := DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED
			if DisplayServer.window_get_mode() != want:
				DisplayServer.window_set_mode(want)
		"display/vsync":
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
