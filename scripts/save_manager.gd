extends Node
## Autoload: SaveManager
## Simple, reliable local persistence of the player's profile (name, colour, stats).

signal profile_changed

const PROFILE_PATH := "user://profile.cfg"
const MAX_NAME_LENGTH := 14
const DEFAULT_NAME := "Player"
const DEFAULT_COLOR := 0
const GameConstants := preload("res://scripts/game_constants.gd")
const BASE_COLOR_COUNT := 8
const MATCH_COLOR := 8
const WIN_COLOR := 9
const MATCH_COLOR_TARGET := 3

var player_name := DEFAULT_NAME
var color_index := DEFAULT_COLOR
var matches_played := 0
var rounds_won := 0
var last_unlocked_colors: Array[int] = []


func _ready() -> void:
	load_profile()


func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) != OK:
		player_name = "%s%02d" % [DEFAULT_NAME, randi() % 100]
		color_index = randi() % 8
		save_profile()
		return
	player_name = sanitize_name(str(cfg.get_value("profile", "name", DEFAULT_NAME)))
	matches_played = maxi(0, int(cfg.get_value("stats", "matches", 0)))
	rounds_won = maxi(0, int(cfg.get_value("stats", "wins", 0)))
	var saved_color := int(cfg.get_value("profile", "color", DEFAULT_COLOR))
	color_index = saved_color if is_color_unlocked(saved_color) else DEFAULT_COLOR
	last_unlocked_colors.clear()


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "name", player_name)
	cfg.set_value("profile", "color", color_index)
	cfg.set_value("stats", "matches", matches_played)
	cfg.set_value("stats", "wins", rounds_won)
	var err := cfg.save(PROFILE_PATH)
	if err != OK:
		push_warning("SaveManager: could not save profile (error %d)" % err)
	profile_changed.emit()


func set_profile(new_name: String, new_color: int) -> void:
	player_name = sanitize_name(new_name)
	color_index = new_color if is_color_unlocked(new_color) else color_index
	save_profile()


func reset_defaults() -> void:
	player_name = DEFAULT_NAME
	color_index = DEFAULT_COLOR
	save_profile()


## Unlocks are derived from existing persistent statistics, including older profiles.
## Practice and tutorial do not call record_match.
func is_color_unlocked(index: int) -> bool:
	if index < 0 or index >= GameConstants.color_count():
		return false
	if index < BASE_COLOR_COUNT:
		return true
	if index == MATCH_COLOR:
		return matches_played >= MATCH_COLOR_TARGET
	if index == WIN_COLOR:
		return rounds_won >= 1
	return false


func record_match(won: bool) -> void:
	var had_match_color := is_color_unlocked(MATCH_COLOR)
	var had_win_color := is_color_unlocked(WIN_COLOR)
	matches_played += 1
	if won:
		rounds_won += 1
	last_unlocked_colors.clear()
	if not had_match_color and is_color_unlocked(MATCH_COLOR):
		last_unlocked_colors.append(MATCH_COLOR)
	if not had_win_color and is_color_unlocked(WIN_COLOR):
		last_unlocked_colors.append(WIN_COLOR)
	save_profile()


## Never crash on empty / huge / multi-line names.
func sanitize_name(raw: String) -> String:
	var n := raw.strip_edges()
	n = n.replace("\n", " ").replace("\t", " ").replace("\r", "")
	if n.length() > MAX_NAME_LENGTH:
		n = n.substr(0, MAX_NAME_LENGTH)
	if n.is_empty():
		n = DEFAULT_NAME
	return n
