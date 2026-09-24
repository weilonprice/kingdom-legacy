extends Node2D
## Entry point: wires up the world, simulation, input controllers and UI.

var world: WorldMap
var citizens: CitizenManager
var raids: RaidDirector
var military: Military
var units: UnitController
var research: Research
var progression: Progression
var needs: Needs
var overlay: Overlay
var day_night: DayNight
var fire: FireSystem
var seasons: Seasons
var trade: Trade
var build: BuildController
var camera: CameraController
var hud: HUD
## How a load swaps in the saved game. The verify driver replaces this, since
## changing scenes would free it.
var reloader := func() -> void: get_tree().change_scene_to_file("res://scenes/main.tscn")

var _autosave_timer := 0.0


func _ready() -> void:
	randomize()
	Sound.enabled = false  # no noise while the map is built or a save applied
	var save: Dictionary = GameState.pending_load
	GameState.pending_load = {}
	GameState.reset()
	if not save.is_empty():
		GameState.difficulty = int(save.difficulty)

	Art.season = GameState.season
	world = WorldMap.new()
	world.width = int(save.get("size", GameState.MAP_SIZES[GameState.map_size].tiles)) if not save.is_empty() \
		else GameState.MAP_SIZES[GameState.map_size].tiles
	world.height = world.width
	add_child(world)
	world.generate(int(save.seed) if not save.is_empty() else _seed_from_args())
	print("Map seed: %d" % world.map_seed)

	citizens = CitizenManager.new()
	citizens.setup(world)
	add_child(citizens)

	raids = RaidDirector.new()
	raids.setup(world)
	add_child(raids)
	raids.place_lairs()

	day_night = DayNight.new()
	day_night.world = world
	add_child(day_night)

	seasons = Seasons.new()
	seasons.world = world
	add_child(seasons)
	day_night.day_started.connect(seasons.on_new_day)
	seasons.season_changed.connect(func(_s: String) -> void: world.growth_paused = seasons.is_winter())

	fire = FireSystem.new()
	fire.world = world
	add_child(fire)

	needs = Needs.new()
	needs.setup(world, citizens)
	needs.seasons = seasons
	add_child(needs)

	research = Research.new()
	research.setup(world)
	add_child(research)

	progression = Progression.new()
	progression.setup(world, raids, research)
	add_child(progression)
	raids.progression = progression

	trade = Trade.new()
	trade.world = world
	trade.raids = raids
	trade.progression = progression
	add_child(trade)

	military = Military.new()
	military.setup(world, citizens)
	military.progression = progression
	add_child(military)

	build = BuildController.new()
	build.world = world
	build.progression = progression
	add_child(build)

	overlay = Overlay.new()
	overlay.world = world
	add_child(overlay)

	# Added after the build controller so it sees input first.
	units = UnitController.new()
	units.setup(world, build, military)
	add_child(units)

	camera = CameraController.new()
	camera.bounds = Rect2(Vector2.ZERO, world.pixel_size())
	camera.position = world.tile_center(world.keep.entrance())
	add_child(camera)

	hud = HUD.new()
	hud.setup(build, world, citizens, raids, military, units, progression, research, needs, overlay, day_night)
	add_child(hud)

	world.keep_destroyed.connect(_on_defeat.bind("The Keep has fallen!"))
	citizens.all_villagers_lost.connect(_on_defeat.bind("Your people have abandoned the kingdom."))
	raids.final_siege_won.connect(_on_victory)
	raids.raid_ended.connect(func(_n: int) -> void: autosave())
	raids.warning_started.connect(func(_t: Vector2i) -> void:
		if Settings.get_value("game/pause_on_raid") and GameState.speed > 0:
			GameState.set_speed(0)
			GameState.notify("Paused: raiders sighted. Press Space to resume."))
	hud.set_save_actions(save_game, load_game)

	if not save.is_empty():
		SaveGame.apply(self, save)
	Sound.enabled = true
	if not save.is_empty():
		GameState.notify("Game loaded (saved %s)." % str(save.saved_at).replace("T", " "))


func _process(delta: float) -> void:
	Sound.listener = camera.position
	Sound.ambience_mode = "" if GameState.game_over else (
		"winter" if seasons.is_winter() and not world.is_night else ("night" if world.is_night else "day"))
	Music.set_mood(_music_mood())
	var every: float = Settings.get_value("game/autosave_minutes") * 60.0
	_autosave_timer += delta
	if every > 0.0 and _autosave_timer >= every:
		_autosave_timer = 0.0
		autosave()


## Raids and the Dragon's siege outrank the time of day and season.
func _music_mood() -> String:
	if GameState.game_over:
		return ""
	if raids.phase == RaidDirector.Phase.ACTIVE:
		return "siege" if raids.final_siege else "raid"
	if world.is_night:
		return "night"
	return "winter" if seasons.is_winter() else "day"


## Manual save (F5 or the game menu).
func save_game() -> void:
	var err := SaveGame.save(self, SaveGame.SLOT)
	GameState.notify("Game saved." if err == "" else "Not saved: " + err)


## Quiet save between raids; silently skipped during one (and when the
## player turned autosave off).
func autosave() -> void:
	if Settings.get_value("game/autosave_minutes") > 0 and SaveGame.save(self, SaveGame.AUTO) == "":
		print("Autosaved")


## Load a slot (F8 / game menu / title screen Continue).
func load_game(slot: String) -> void:
	var data := SaveGame.read(slot)
	if data.is_empty():
		GameState.notify("No saved game to load.")
		return
	GameState.pending_load = data
	GameState.reset()
	reloader.call()


## `godot --path . -- --seed=123` replays a specific map; otherwise the seed
## typed in the main menu, or random.
func _seed_from_args() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			return int(arg.get_slice("=", 1))
	if GameState.new_game_seed != 0:
		return GameState.new_game_seed
	return randi()


func _on_defeat(title: String) -> void:
	if GameState.game_over:
		return
	GameState.end_game()
	Sound.play("defeat")
	hud.show_defeat(title, "Raids survived: %d\nMap seed: %d" % [raids.raids_survived, world.map_seed])


func _on_victory() -> void:
	if GameState.game_over:
		return
	GameState.end_game()
	Sound.play("victory")
	hud.show_victory("Victory! The Dragon is slain.",
		"Your Kingdom stands. Raids survived: %d\nPopulation: %d\nMap seed: %d" % [
			raids.raids_survived, GameState.population, world.map_seed])
