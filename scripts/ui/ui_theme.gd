class_name UiTheme
extends RefCounted
## The HUD's look: the PixelLab pixel font and wooden panel (when present),
## warm button styles and text colours. Missing assets fall back to Godot's
## defaults for that piece.

const FONT := "res://assets/ui/kingdom_pixel.ttf"
const PANEL := "res://assets/ui/panel.png"
## Pixels of the panel image kept unstretched at each edge (9-slice).
const PANEL_MARGIN := 7
const ICON := "res://assets/ui/icon_%s.png"

const TEXT := Color(0.97, 0.92, 0.80)
const TEXT_MUTED := Color(0.78, 0.70, 0.55)
const WOOD := Color(0.27, 0.18, 0.11, 0.92)
const WOOD_LIGHT := Color(0.40, 0.27, 0.16, 0.95)
const GOLD := Color(0.85, 0.68, 0.30)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func icon(name: String) -> Texture2D:
	return Art.texture(ICON % name)


static func _build() -> Theme:
	var theme := Theme.new()
	if ResourceLoader.exists(FONT):
		var f: FontFile = load(FONT)
		# The pixel font covers letters, digits and basic punctuation; symbols
		# like ⚔ ☀ ✔ come from Godot's default font.
		f.fallbacks = [ThemeDB.fallback_font]
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		theme.default_font = f
		theme.default_font_size = 16
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", GOLD.lightened(0.3))
	theme.set_color("font_disabled_color", "Button", TEXT_MUTED.darkened(0.3))

	var panel: StyleBox = _panel_style()
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)

	theme.set_stylebox("normal", "Button", _flat(WOOD, GOLD.darkened(0.4)))
	theme.set_stylebox("hover", "Button", _flat(WOOD_LIGHT, GOLD))
	theme.set_stylebox("pressed", "Button", _flat(WOOD_LIGHT.darkened(0.2), GOLD.lightened(0.2)))
	theme.set_stylebox("disabled", "Button", _flat(Color(WOOD, 0.6), Color(GOLD, 0.25)))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	# Check boxes are just the tick and the text, highlighted on hover.
	for state in ["normal", "pressed", "hover_pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	theme.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	theme.set_color("font_hover_color", "CheckBox", GOLD.lightened(0.3))
	theme.set_color("font_hover_pressed_color", "CheckBox", GOLD.lightened(0.3))
	theme.set_color("font_pressed_color", "CheckBox", TEXT)
	theme.set_stylebox("panel", "TooltipPanel", _flat(Color(0.12, 0.08, 0.05, 0.96), GOLD))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	return theme


static func _panel_style() -> StyleBox:
	var tex := Art.texture(PANEL)
	if tex != null:
		var box := StyleBoxTexture.new()
		box.texture = tex
		box.set_texture_margin_all(PANEL_MARGIN)
		box.set_content_margin_all(10)
		return box
	return _flat(Color(0.16, 0.11, 0.07, 0.9), GOLD.darkened(0.3))


static func _flat(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.set_content_margin_all(5)
	box.content_margin_left = 8
	box.content_margin_right = 8
	return box
