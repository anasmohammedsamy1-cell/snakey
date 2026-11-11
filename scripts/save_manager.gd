extends Node
## Autoload: SaveManager
## Simple, reliable local persistence of the player's profile (name, colour, stats).

signal profile_changed

const PROFILE_PATH := "user://profile.cfg"
const MAX_NAME_LENGTH := 14
const DEFAULT_NAME := "Player"
const DEFAULT_COLOR := 0
const DEFAULT_DETAIL := -1             # -1 = classic metal screws/gaps
const GameConstants := preload("res://scripts/game_constants.gd")
const BASE_COLOR_COUNT := 8
const MATCH_COLOR := 8
const WIN_COLOR := 9
const MATCH_COLOR_TARGET := 3
const AccessoriesLib := preload("res://scripts/accessories.gd")
const NAME_CHANGE_COST := 100          # coins for every name change after the first (free) one
const COINS_PER_MATCH := 10
const COINS_PER_WIN := 20
const COINS_PER_KO := 2
const MAX_COINS := 9999999

var player_name := DEFAULT_NAME
var color_index := DEFAULT_COLOR
var detail_color_index := DEFAULT_DETAIL
var matches_played := 0
var rounds_won := 0
var last_unlocked_colors: Array[int] = []
var coins := 0
var owned_hats: Array[String] = []
var equipped_hat := ""
var name_changes := 0                  # how many times the player has chosen a name (the first one is free)
var last_coins_earned := 0


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
	var saved_detail := int(cfg.get_value("profile", "detail", DEFAULT_DETAIL))
	detail_color_index = saved_detail if GameConstants.is_detail_color_valid(saved_detail) else DEFAULT_DETAIL
	last_unlocked_colors.clear()
	coins = clampi(int(cfg.get_value("wallet", "coins", 0)), 0, MAX_COINS)
	name_changes = maxi(0, int(cfg.get_value("wallet", "name_changes", 0)))
	owned_hats.clear()
	for h in str(cfg.get_value("wallet", "hats", "")).split(",", false):
		if AccessoriesLib.ids().has(h) and not owned_hats.has(h):
			owned_hats.append(h)
	var eq := str(cfg.get_value("wallet", "equipped", ""))
	equipped_hat = eq if owned_hats.has(eq) else ""


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "name", player_name)
	cfg.set_value("profile", "color", color_index)
	cfg.set_value("profile", "detail", detail_color_index)
	cfg.set_value("stats", "matches", matches_played)
	cfg.set_value("stats", "wins", rounds_won)
	cfg.set_value("wallet", "coins", coins)
	cfg.set_value("wallet", "name_changes", name_changes)
	cfg.set_value("wallet", "hats", ",".join(owned_hats))
	cfg.set_value("wallet", "equipped", equipped_hat)
	var err := cfg.save(PROFILE_PATH)
	if err != OK:
		push_warning("SaveManager: could not save profile (error %d)" % err)
	profile_changed.emit()


## Saves the colours. The name is only changed through change_name(), because a name change costs coins.
func set_profile(new_name: String, new_color: int, new_detail: int = DEFAULT_DETAIL) -> String:
	color_index = new_color if is_color_unlocked(new_color) else color_index
	detail_color_index = new_detail if GameConstants.is_detail_color_valid(new_detail) else detail_color_index
	var err := ""
	if sanitize_name(new_name) != player_name:
		err = change_name(new_name)
	save_profile()
	return err


## What the next name change costs (0 for the first one).
func name_change_cost() -> int:
	return 0 if name_changes == 0 else NAME_CHANGE_COST


## Returns "" on success, "need_coins" when the player cannot pay, "same_name" when nothing changes.
func change_name(new_name: String) -> String:
	var clean := sanitize_name(new_name)
	if clean == player_name:
		return "same_name"
	var cost := name_change_cost()
	if coins < cost:
		return "need_coins"
	coins -= cost
	name_changes += 1
	player_name = clean
	save_profile()
	return ""


## Colour and hat go back to the defaults. The name is NOT reset (that would be a free name change).
func reset_defaults() -> void:
	color_index = DEFAULT_COLOR
	detail_color_index = DEFAULT_DETAIL
	equipped_hat = ""
	save_profile()


func add_coins(amount: int) -> void:
	coins = clampi(coins + maxi(0, amount), 0, MAX_COINS)


## Returns "" on success, "owned", "invalid" or "need_coins".
func buy_hat(id: String) -> String:
	if id.is_empty() or not AccessoriesLib.ids().has(id):
		return "invalid"
	if owned_hats.has(id):
		return "owned"
	var price := AccessoriesLib.price_of(id)
	if coins < price:
		return "need_coins"
	coins -= price
	owned_hats.append(id)
	save_profile()
	return ""


func equip_hat(id: String) -> bool:
	if id.is_empty() or owned_hats.has(id):
		equipped_hat = id
		save_profile()
		return true
	return false


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


func record_match(won: bool, kos := 0) -> void:
	var had_match_color := is_color_unlocked(MATCH_COLOR)
	var had_win_color := is_color_unlocked(WIN_COLOR)
	matches_played += 1
	if won:
		rounds_won += 1
	last_coins_earned = COINS_PER_MATCH + (COINS_PER_WIN if won else 0) + COINS_PER_KO * maxi(0, kos)
	add_coins(last_coins_earned)
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
