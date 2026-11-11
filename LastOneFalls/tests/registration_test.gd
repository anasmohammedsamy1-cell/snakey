extends Node
## Three real ENet processes: host capacity 2, accepted client, rejected client.
const PORT := 24631
var role := ""
var failures := 0
var success_count := 0
var fail_count := 0
var kick_count := 0
var failure_reason := ""
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "host"
	call_deferred("run_test")
func check(ok: bool, label: String) -> void:
	if ok:
		print("[REGISTER:%s] PASS %s" % [role, label])
	else:
		failures += 1
		print("[REGISTER:%s] FAIL %s" % [role, label])
func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
func wait_for(fn: Callable, seconds: float) -> bool:
	for i in int(seconds * 10):
		if fn.call():
			return true
		await wait(0.1)
	return fn.call()
func on_success() -> void:
	success_count += 1
	check(NetworkManager.players.has(multiplayer.get_unique_id()), "success only after own authoritative registration")
func on_failure(reason: String) -> void:
	fail_count += 1
	failure_reason = reason
func on_kick(_reason: String) -> void:
	kick_count += 1
func run_test() -> void:
	SettingsManager.settings["language"] = "ar" if role == "extra" else "en"
	NetworkManager.connection_succeeded.connect(on_success)
	NetworkManager.connection_failed.connect(on_failure)
	NetworkManager.kicked.connect(on_kick)
	if role == "host":
		check(NetworkManager.host_game(PORT, "Capacity Test", 2) == "", "host created")
		var full := await wait_for(func() -> bool: return NetworkManager.players.size() == 2, 8.0)
		check(full, "first client registered")
		await wait(7.0)
		check(NetworkManager.players.size() == 2, "rejected join did not enter player list")
	elif role == "holder":
		await wait(1.0)
		check(NetworkManager.join_game("127.0.0.1", PORT) == "", "join started")
		var joined := await wait_for(func() -> bool: return success_count > 0, 8.0)
		check(joined and success_count == 1 and fail_count == 0, "first client accepted exactly once")
		await wait(7.0)
	else:
		await wait(3.0)
		check(NetworkManager.join_game("127.0.0.1", PORT) == "", "join started")
		var failed := await wait_for(func() -> bool: return fail_count > 0 or success_count > 0 or kick_count > 0, 8.0)
		check(failed and fail_count == 1 and success_count == 0 and kick_count == 0, "full room fails without premature success or in-match kick")
		check(failure_reason == GameManager.t("lobby_full"), "full-room explanation localized for client despite English host")
		check(not NetworkManager.online and not NetworkManager.is_busy(), "failed join cleaned up")
	NetworkManager.leave()
	print("[REGISTER:%s] finished with %d failure(s)" % [role, failures])
	get_tree().quit(1 if failures else 0)
