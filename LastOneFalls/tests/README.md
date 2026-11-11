# Tests

## A. Automated (headless, no display needed)

Both tests print `PASS` / `FAIL` lines and exit with code `1` if anything failed.
Replace `godot` with the path to your Godot 4.7 binary. Run from the `LastOneFalls/` folder.

### 1. Single‑process smoke test (practice mode, menus, lobby, settings, profile)
```
godot --headless --path . res://tests/smoke_test.tscn
```
Expected: `[SMOKE] finished with 0 failure(s)`.

### 2. Real LAN multiplayer test (two processes, real ENet socket)
Terminal 1 (host):
```
godot --headless --path . res://tests/net_test.tscn -- host
```
Terminal 2 (client, within ~5 seconds):
```
godot --headless --path . res://tests/net_test.tscn -- join 127.0.0.1
```
To test across two computers on the same LAN, replace `127.0.0.1` with the host's IP.
Expected: `[NET:host] finished with 0 failure(s)` and `[NET:join] finished with 0 failure(s)`.

What the network test covers: host_game, join_game, lobby list snapshot sync, ready → `can_start`,
`start_match` RPC loading the arena on both peers, player spawning (2 players, correct authority),
host↔client position replication, host‑validated push delivered to the client, client fall →
host elimination → round end → ranks and points, `return_to_lobby`, clean session shutdown.

Status: Godot-headless tests were NOT executed in the latest review (no Godot binary available); see TEST_REPORT.md for exactly what was and was not run.

### 2b. Modes and maps (single process)
```
godot --headless --path . res://tests/modes_test.tscn
```
Loads the main scenes and starts Classic (5 maps), Team (2 maps) and Hide & Seek (2 houses). Expected: `[MODES] finished with 0 failure(s)`.

### 2c. Knockout mode (single process, real host logic)
```
godot --headless --path . res://tests/ko_test.tscn
```
Expected: `[KO] finished with 0 failure(s)` (takes about 1 minute). Covers mode selection (lobby config, clamping, bots without teams),
match initialisation, scoring, duplicate / stale report prevention, simultaneous and mutual knockouts, credit rules (self, expired,
departed attacker), spawn protection through the real `_server_arm` path, host-only registration, idempotent snapshot mirroring
(client side), tie-breaks, target-score and timer match completion, and the results screen.
**Status: written but NOT yet executed (no Godot binary was available when it was written).**

### 2d. Knockout source invariants (Python, runs without Godot)
```
python3 tests/test_knockout_invariants.py
```
47 source-level checks (authority, duplicate prevention, mode wiring, other modes untouched, UI/locale presence).

### 3. Host registration invariants (Python, source-level)

Run from the project root:
```
python3 tests/test_network_registration_invariants.py
```
This checks that the host revalidates the match lock at the registration RPC boundary,
ignores duplicate registrations, and retains sender, capacity, nickname, and color validation.
It is a static source check, not a live ENet multiplayer test.

## B. Manual two‑phone procedure (NOT performed by the authors — no devices were available)

1. Export the APK (see README §6) and install it on **two** Android phones.
2. Phone A: enable *Mobile hotspot*. Phone B: connect to that hotspot.
3. Phone A: open the game → PLAY → LAN MULTIPLAYER → note the IP under “Your IP” → HOST GAME.
4. Phone B: PLAY → LAN MULTIPLAYER → enter Phone A's IP → JOIN GAME.
   ✔ Phone A should show a toast “<name> joined” and both lobbies list 2 players with colours.
5. Phone B: tap READY. Phone A: START MATCH should become enabled; tap it.
   ✔ Both phones load the arena, show READY / SET / GO and the 1:30 timer in sync.
6. Move on both phones. ✔ Each phone sees the other character move, jump, and animate.
7. Walk next to the other player and press PUSH. ✔ The other player is knocked back on *their* screen.
8. Walk into a hammer. ✔ You are knocked away on your phone and the other phone sees the movement.
9. Step on an outer‑ring tile. ✔ It shakes and falls on **both** phones.
10. Let one player fall. ✔ Elimination message on both phones; the round ends; results list ranks/points.
11. Host: REMATCH → both load a new round. Host: BACK TO LOBBY → both return to the lobby with scores.
12. Client: LEAVE during a match. ✔ Host sees “left”, the remaining player wins.
13. Host: kill the app during a match. ✔ Client returns to the main menu with “The host left the game.”
14. Settings: change joystick size/opacity, camera distance and graphics preset mid‑match (pause → settings).
    ✔ Changes apply immediately and persist after restarting the app.

Record phone models, Android versions and observed frame rates when reporting results.


## C. LAN layer tests (added with automatic room discovery)

```
godot --headless --path . res://tests/lan_test.tscn
```
Single process, no devices needed. Covers: IPv4 validation (valid / invalid), Arabic-Indic / Persian / full-width digit
normalisation, port parsing, discovery protocol validation (query / join request / advertisement / malformed),
expiry of stale rooms, host start / fallback port / duplicate-server refusal, client connection failure and duplicate
connection refusal, discovery + join probe over loopback, cleanup after leave().
Two-process variant with discovery instead of a typed IP:
```
godot --headless --path . res://tests/net_test.tscn -- host
godot --headless --path . res://tests/net_test.tscn -- join discover
```

## D. Arena event regression checks (Python, no Godot required)

Run from the project root:
```sh
python3 tests/test_arena_event_invariants.py
```
This checks source-level invariants for host-local TILE TREMOR triggering, the reliable tile RPC path,
crumble-tile eligibility, Arabic/English announcements, and adaptive event pacing. It does not prove
that Godot parses the project or that multiplayer replication works at runtime.

### 4. Authoritative match-start invariants (Python, source-level)

Run from the project root:
```
python3 tests/test_match_start_invariants.py
```
This checks that fresh match starts are host-only, online-only, reject an already active match, and enforce `can_start()`; it also verifies that rematches use the shared launch path without the lobby readiness gate. This is a static source check, not a Godot runtime test.


### 5. Active-match mutation-lock invariants (Python, source-level)

Run from the project root:
```sh
python3 tests/test_match_mutation_lock_invariants.py
```
This checks that both local APIs and host-side client RPC handlers reject ready-state and profile mutations while a match is active. It is a static source check, not a live ENet test.


### 6. Lobby mutation boundary and registration resynchronization (Python, source-level)

Run from the project root:
```sh
python3 tests/test_match_mutation_lock_invariants.py
python3 tests/test_registration_resync_invariants.py
```
These checks cover host-only lobby configuration/team mutations during active matches and idempotent
registration recovery: a repeated registration request receives the current authoritative player/config
snapshots without resetting the existing player's state. They do not replace a live ENet test.

### 7. Responsive UI / UX invariants (Python, source-level)

Run from the project root:
```sh
python3 tests/test_ui_ux_invariants.py
```
This verifies that shared centered panels respect safe-area insets, the main menu and lobby have compact-layout breakpoints, settings include category shortcuts and compact sliders, map cards reflow by available width, and gameplay voice/audio controls are grouped without removing the dedicated microphone control. This is a source-level structural check; it does not replace rendering and touch testing on physical phones.


## E. Unified source-level test discovery

All Python invariant modules are now import-safe and expose each source invariant as an individual pytest test. Run the full source-level suite from the project root:

```sh
python3 -m pytest -q tests
```

The same files remain directly executable for a readable PASS/FAIL report, for example:

```sh
python3 tests/test_ui_ux_invariants.py
```

These tests inspect source-level contracts only. They do not replace Godot parser, scene, rendering, touch, Android export, or live multiplayer tests.


## F. Cheap toon look + outline test (headless, no display needed)

Covers the character toon shading (`RECOLOR_SHADER`'s `light()`) and the inverted-hull
outline attached as `next_pass` on the recolor material. Compiles both shaders and checks
the preset gating, the shared outline material and that `set_color()` still drives
`body_color`.

```
godot --headless --path . res://tests/toon_outline_test.tscn
```

Expected: `[TOON] finished with 0 failure(s)` and a clean exit code (`0`). The source-level
half of the same contract (switchable `TOON_ENABLED` constant, `light()` band math,
`cull_front` vertex push) runs without Godot:

```
python3 tests/test_toon_look_invariants.py
```


### 4. Audio engineering invariants (Python, source-level)

Run from the project root:
```sh
python3 -m pytest -q tests
```
The audio checks verify independent bus settings, voice-aware music ducking, game-only mute isolation, generated-audio headroom, comfort limits, priority-aware sound-pool behavior, duplicate-trigger protection, movement-footstep routing, and English/Arabic labels. These are source checks; use Godot and physical devices for actual listening and mixer validation.
