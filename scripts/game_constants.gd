extends RefCounted
## Shared constants for LAST ONE FALLS!
## Loaded with: const GameConstants := preload("res://scripts/game_constants.gd")

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 8
const MIN_PLAYERS := 2
const ROUND_DURATION := 90.0
const PRACTICE_DURATION := 60.0
const FALL_Y := -12.0

## Game modes
const MODE_FFA := 0        # every player for themselves, last one standing
const MODE_TEAMS := 1      # team survival, last team standing
const MODE_HIDE := 2       # hide and seek in a house
const MODE_KNOCKOUT := 3   # respawning free-for-all: most validated knockouts when the timer ends
const MODE_TRAMPOLINE := 4 # giant bounce arena: respawn brawler, highest KO score wins
const MODE_COUNT := 5
const MAX_TOTAL := 12      # humans + bots in one match

## Teams (index -> colour preset index). In H&S team 0 hides and team 1 seeks.
const TEAM_COLOR_INDEX := [7, 4, 6, 0]     # Ocean Blue, Cherry Red, Lime Green, Sunny Yellow
const TEAM_KEYS := ["team_blue", "team_red", "team_green", "team_yellow"]
const HS_ROLE_NONE := 0
const HS_ROLE_HIDER := 1
const HS_ROLE_SEEKER := 2

## Hide and seek tuning
const HS_HIDE_TIME := 20.0         # seekers are blindfolded while the hiders run and hide
const HS_SEEK_TIME := 300.0        # 5 minutes of seeking
const HS_CATCH_RANGE := 2.6
const HS_CATCH_COOLDOWN := 1.3
const HS_HUG_TIME := 2.8           # hug + melt animation length

## Knockout mode tuning (all host-side)
const KO_DURATION := 120.0         # default Knockout match length (seconds)
const TRAMPOLINE_DURATION := 120.0 # timed bounce brawler match
const KO_TARGET_SCORE := 10        # first to this many knockouts wins immediately
const KO_RESPAWN_DELAY := 2.0      # a knocked-out player respawns after this long
const KO_SPAWN_PROTECT := 1.5      # host ignores hits on a freshly respawned player
const KO_FALL_GRACE := 1.0         # host ignores fall reports this long after a respawn (stale packets)
const KO_CREDIT_WINDOW := 5.0      # a hit / grab counts as the cause of a fall for this long

## Maps. kind 0 = floating arena, kind 1 = house (HIDE), kind 2 = trampoline arena.
const MAPS := [
	{"key": "map_cloud", "kind": 0, "size_key": "size_large"},
	{"key": "map_ring", "kind": 0, "size_key": "size_small"},
	{"key": "map_tiles", "kind": 0, "size_key": "size_large"},
	{"key": "map_islands", "kind": 0, "size_key": "size_medium"},
	{"key": "map_donut", "kind": 0, "size_key": "size_small"},
	{"key": "map_villa", "kind": 1, "size_key": "size_large"},
	{"key": "map_flat", "kind": 1, "size_key": "size_small"},
	{"key": "map_bounce_dome", "kind": 2, "size_key": "size_large"},
	{"key": "map_neon_springs", "kind": 2, "size_key": "size_large"},
	{"key": "map_candy_cloud", "kind": 2, "size_key": "size_large"},
	{"key": "map_sky_bounce", "kind": 2, "size_key": "size_large"},
	{"key": "map_pinball_bounce", "kind": 2, "size_key": "size_large"},
	{"key": "map_twister", "kind": 0, "size_key": "size_large"},
	{"key": "map_school", "kind": 1, "size_key": "size_large"},
	{"key": "map_warehouse", "kind": 1, "size_key": "size_large"},
	{"key": "map_museum", "kind": 1, "size_key": "size_large"},
	{"key": "map_family_flat", "kind": 1, "size_key": "size_large"},
	{"key": "map_plaza", "kind": 0, "size_key": "size_small"},
	{"key": "map_mini_tiles", "kind": 0, "size_key": "size_small"},
	{"key": "map_split_ring", "kind": 0, "size_key": "size_small"},
	{"key": "map_ice_rink", "kind": 0, "size_key": "size_small"},
	{"key": "map_conveyor_mill", "kind": 0, "size_key": "size_medium"},
	{"key": "map_wind_tunnel", "kind": 0, "size_key": "size_large"},
]

## Rubber arm / dash tuning. The punch / grab strength depends on how long the button was held
## (charge 0 = quick tap = weak and short, charge 1 = held = long arm and strong).
## The host recomputes range, force and cooldown from the charge, clients cannot choose them.
const PUNCH_RANGE_MIN := 2.1
const PUNCH_RANGE := 5.2           # range at full charge
const GRAB_RANGE_MIN := 3.2
const GRAB_RANGE := 6.8
const PUNCH_FORCE_MIN := 8.0
const PUNCH_FORCE := 28.0
const PUNCH_LIFT_MIN := 2.5
const PUNCH_LIFT := 6.5
const PUNCH_COOLDOWN_MIN := 0.275
const PUNCH_COOLDOWN := 0.675
const GRAB_COOLDOWN_MIN := 0.6
const GRAB_COOLDOWN := 0.9
const SERVER_CD_FACTOR := 0.7      # host cooldown is a bit shorter (network lag tolerance)
const CHARGE_TIME := 0.85          # seconds to reach a full charge
const ARM_LENIENCE := 0.55         # small host-only allowance for replication delay
const ARM_TARGET_RADIUS := 0.4     # match the player capsule's horizontal radius
const ARM_VERTICAL_REACH := 1.65   # avoid hits through players at very different heights
const GRAB_PULL_SPEED := 16.0      # hook speed; must beat a sprinting victim
const GRAB_PULL_CONTROL := 0.15    # victim's own running is mostly suppressed while hooked
const GRAB_PULL_MAX_TIME := 1.3    # time allowed to pull the victim next to you
const GRAB_HOLD_DISTANCE := 1.9    # pulled in closer than this -> victim is lifted
const GRAB_HANG_TIME := 3.0        # lift (0.375 s) + carry + throw window; was 2.0 s (too short to show the full lift->carry->throw animation)

## Grab / throw animation timing (seconds). All are 2x faster than the original
## 0.55 s reach, 0.75 s lift, 0.34 s wind-up + 0.28 s release and 0.55 s follow-through.
## Shared by ContenderAnimator (visuals) and RoundManager (host release timing).
const GRAB_REACH_TIME := 0.275
const GRAB_LIFT_TIME := 0.375
const THROW_PREP_TIME := 0.17
const THROW_TOTAL_TIME := 0.31
const THROW_FOLLOW_TIME := 0.275
const GRAB_CARRY_SPEED := 0.65     # holder walks slower while carrying
const GRAB_DROP_PUSH := 3.5
const GRAB_ESCAPE_PRESSES := 5
const GRAB_ESCAPE_WINDOW := 2.0
const GRAB_ESCAPE_MIN_INTERVAL := 0.03
const DASH_SPEED := 19.0
const DASH_TIME := 0.2
const DASH_COOLDOWN := 2.2
const ARM_MODE_PUNCH := 0
const ARM_MODE_GRAB := 1

## Physics layers
const LAYER_WORLD := 1
const LAYER_PLAYERS := 2

## Original colour presets (name + colour). Index is what gets replicated over the network.
const COLOR_PRESETS := [
	{"name_key": "color_sunny", "color": Color(1.0, 0.85, 0.12)},
	{"name_key": "color_bubblegum", "color": Color(1.0, 0.42, 0.72)},
	{"name_key": "color_cyan", "color": Color(0.2, 0.85, 0.95)},
	{"name_key": "color_grape", "color": Color(0.62, 0.36, 0.95)},
	{"name_key": "color_cherry", "color": Color(0.95, 0.27, 0.27)},
	{"name_key": "color_tangerine", "color": Color(1.0, 0.56, 0.16)},
	{"name_key": "color_lime", "color": Color(0.45, 0.9, 0.3)},
	{"name_key": "color_ocean", "color": Color(0.27, 0.47, 1.0)},
	{"name_key": "color_mint", "color": Color(0.1, 0.87, 0.65)},
	{"name_key": "color_gold", "color": Color(0.95, 0.68, 0.13)},
]

const ARENA_PALETTE := [
	Color(1.0, 0.85, 0.12),
	Color(1.0, 0.42, 0.72),
	Color(0.2, 0.85, 0.95),
	Color(0.62, 0.36, 0.95),
	Color(1.0, 0.56, 0.16),
	Color(0.45, 0.9, 0.3),
]


## Detail colour (screws, gaps and seams of the metal body). Index -1 keeps the
## classic metal look; the customisation picker offers it plus every colour preset.
const DEFAULT_DETAIL_COLOR := Color(0.72, 0.75, 0.8)

static func detail_color_count() -> int:
	return color_count() + 1


static func get_detail_color(index: int) -> Color:
	return DEFAULT_DETAIL_COLOR if index < 0 else get_color(index)


static func is_detail_color_valid(index: int) -> bool:
	return index == -1 or (index >= 0 and index < color_count())


static func get_color(index: int) -> Color:
	var i := posmod(index, COLOR_PRESETS.size())
	return COLOR_PRESETS[i]["color"]


static func get_color_name(index: int) -> String:
	var i := posmod(index, COLOR_PRESETS.size())
	if COLOR_PRESETS[i].has("name_key"):
		var gm := Engine.get_main_loop()
		if gm:
			var tree := gm as SceneTree
			if tree and tree.root and tree.root.has_node("GameManager"):
				var g := tree.root.get_node("GameManager")
				if g.has_method("t"):
					return str(g.call("t", str(COLOR_PRESETS[i]["name_key"])))
		return str(COLOR_PRESETS[i]["name_key"])
	return COLOR_PRESETS[i]["name"]


static func color_count() -> int:
	return COLOR_PRESETS.size()


static func arm_range(mode: int, charge: float) -> float:
	var c := clampf(charge, 0.0, 1.0)
	if mode == ARM_MODE_GRAB:
		return lerpf(GRAB_RANGE_MIN, GRAB_RANGE, c)
	return lerpf(PUNCH_RANGE_MIN, PUNCH_RANGE, c)


## Combat distance uses the player physics roots on the ground plane, never the
## animated Visuals/limb transforms. The Z component is part of the ground plane.
static func combat_ground_distance(a: Node3D, b: Node3D) -> float:
	var delta := b.global_position - a.global_position
	return Vector2(delta.x, delta.z).length()


static func punch_force(charge: float) -> float:
	return lerpf(PUNCH_FORCE_MIN, PUNCH_FORCE, clampf(charge, 0.0, 1.0))


static func punch_lift(charge: float) -> float:
	return lerpf(PUNCH_LIFT_MIN, PUNCH_LIFT, clampf(charge, 0.0, 1.0))


static func arm_cooldown(mode: int, charge: float) -> float:
	var c := clampf(charge, 0.0, 1.0)
	if mode == ARM_MODE_GRAB:
		return lerpf(GRAB_COOLDOWN_MIN, GRAB_COOLDOWN, c)
	return lerpf(PUNCH_COOLDOWN_MIN, PUNCH_COOLDOWN, c)


static func arm_server_cooldown(mode: int, charge: float) -> float:
	return arm_cooldown(mode, charge) * SERVER_CD_FACTOR


static func team_color_index(team: int) -> int:
	return int(TEAM_COLOR_INDEX[posmod(team, TEAM_COLOR_INDEX.size())])


static func team_color(team: int) -> Color:
	return get_color(team_color_index(team))


## Map ids that can be used with a game mode.
static func maps_for_mode(mode: int) -> Array:
	var want := 2 if mode == MODE_TRAMPOLINE else (1 if mode == MODE_HIDE else 0)
	var out: Array = []
	for i in MAPS.size():
		if int(MAPS[i]["kind"]) == want:
			out.append(i)
	return out


## Default match length for a mode.
static func default_round_time(mode: int) -> float:
	if mode == MODE_HIDE:
		return HS_SEEK_TIME
	if mode == MODE_KNOCKOUT:
		return KO_DURATION
	if mode == MODE_TRAMPOLINE:
		return TRAMPOLINE_DURATION
	return ROUND_DURATION


## True for the modes that split players into teams (Team Brawl, Hide and Seek).
static func uses_teams(mode: int) -> bool:
	return mode == MODE_TEAMS or mode == MODE_HIDE


## Knockout ranking order: more knockouts, then fewer falls, then the player who reached
## their final knockout count first (host time in ms, -1 = never scored), then id (display order only).
static func ko_last_key(e: Dictionary) -> int:
	var t := int(e.get("last_ms", -1))
	return 2147483647 if t < 0 else t


static func ko_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["kos"]) != int(b["kos"]):
		return int(a["kos"]) > int(b["kos"])
	if int(a["falls"]) != int(b["falls"]):
		return int(a["falls"]) < int(b["falls"])
	if ko_last_key(a) != ko_last_key(b):
		return ko_last_key(a) < ko_last_key(b)
	return int(a["id"]) < int(b["id"])


## Two entries share a place only when every tie-break is identical.
static func ko_same_place(a: Dictionary, b: Dictionary) -> bool:
	return int(a["kos"]) == int(b["kos"]) and int(a["falls"]) == int(b["falls"]) and ko_last_key(a) == ko_last_key(b)


## entries: [{id, kos, falls, last_ms}] -> same entries sorted best first, each with a "rank" (1 = best, ties share).
static func ko_rank_entries(entries: Array) -> Array:
	var sorted_entries: Array = entries.duplicate()
	sorted_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return ko_before(a, b))
	var out: Array = []
	for i in sorted_entries.size():
		var e: Dictionary = sorted_entries[i].duplicate()
		if i == 0:
			e["rank"] = 1
		elif ko_same_place(sorted_entries[i - 1], sorted_entries[i]):
			e["rank"] = int(out[i - 1]["rank"])
		else:
			e["rank"] = i + 1
		out.append(e)
	return out


## Match points for the lobby total: 3 / 2 / 1 for the first three places. Nobody scores for 0 knockouts.
static func ko_points(rank: int, kos: int) -> int:
	if kos <= 0:
		return 0
	return maxi(0, 4 - rank)
