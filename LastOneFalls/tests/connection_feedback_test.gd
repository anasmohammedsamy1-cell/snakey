extends Node
var failures := 0
var failed_count := 0
var disconnected_count := 0
func _ready() -> void:
	call_deferred("run_test")
func check(ok: bool, label: String) -> void:
	if ok:
		print("[FEEDBACK] PASS ", label)
	else:
		failures += 1
		print("[FEEDBACK] FAIL ", label)
func on_failure(_reason: String) -> void:
	failed_count += 1
func on_disconnected() -> void:
	disconnected_count += 1
func run_test() -> void:
	var previous_language: Variant = SettingsManager.settings["language"]
	SettingsManager.settings["language"] = "ar"
	NetworkManager.connection_failed.connect(on_failure)
	NetworkManager.host_disconnected.connect(on_disconnected)
	var lobby = load("res://scenes/lobby.tscn").instantiate()
	add_child(lobby)
	await get_tree().process_frame
	lobby._ip_edit.text = "127.0.0.1"
	lobby._port_edit.text = "24660"
	lobby._on_join_pressed()
	check(NetworkManager.is_busy(), "manual join enters busy state")
	# Simulate transport reporting a lost host during handshake; this checks
	# UI/state behavior, not a real two-device radio disconnect.
	NetworkManager._on_server_disconnected()
	check(failed_count == 1 and disconnected_count == 0, "handshake disconnect is join failure, not match disconnect")
	check(lobby._connect_panel.visible and not lobby._lobby_panel.visible, "failure remains on join screen")
	check(lobby._error_label.text == GameManager.t("join_host_left"), "join error visible in client language")
	NetworkManager._on_server_disconnected()
	check(failed_count == 1 and disconnected_count == 0, "stale disconnect ignored")
	lobby._on_join_pressed()
	check(NetworkManager.is_busy(), "retry can start")
	NetworkManager.leave()
	await get_tree().create_timer(7.5).timeout
	check(failed_count == 1 and not NetworkManager.online, "cancelled attempt timeout does not report a false failure")
	lobby.queue_free()
	NetworkManager.connection_failed.disconnect(on_failure)
	NetworkManager.host_disconnected.disconnect(on_disconnected)
	SettingsManager.settings["language"] = previous_language
	print("[FEEDBACK] finished with %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
