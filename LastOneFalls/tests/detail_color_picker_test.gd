extends Node3D
## Headless test for the "screws & gaps" (detail) colour picker.
## Opens the real customisation screen, picks detail colours and checks that the
## live 3D preview's recolor material actually receives the new colour.
##   godot --headless --path . res://tests/detail_color_picker_test.tscn

const CustomScene := preload("res://scenes/ui/customization_menu.tscn")
const GameConstants := preload("res://scripts/game_constants.gd")

var failures := 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("[DETAIL] PASS  " + label)
	else:
		failures += 1
		print("[DETAIL] FAIL  " + label)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# Isolated XDG_DATA_HOME keeps the real profile untouched.
	SaveManager.detail_color_index = 3            # grape, as if the player picked it
	SaveManager.save_profile()

	var menu = CustomScene.instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame

	check(int(menu._selected_detail) == 3, "the menu opens on the saved detail colour")
	check(menu._detail_grid != null and menu._detail_grid.get_node_or_null("Detail0") != null,
		"the picker shows the classic metal swatch plus every colour preset")
	check(menu._detail_grid.get_child_count() == GameConstants.detail_color_count(),
		"detail swatch count = colour presets + 1")

	var preview_detail = func() -> Variant:
		var mats: Array = menu._preview_char.get("_recolor_materials")
		return Color(mats[0].get_shader_parameter("detail_color")) if mats.size() > 0 else null

	check(preview_detail.call() == GameConstants.get_detail_color(3), "preview starts on the saved detail colour")

	menu._select_detail(-1)
	await get_tree().process_frame
	check(int(menu._selected_detail) == -1, "the metal swatch selects the classic metal")
	check(preview_detail.call() == GameConstants.DEFAULT_DETAIL_COLOR,
		"selecting metal updates the preview shader parameter")

	menu._select_detail(3)
	await get_tree().process_frame
	check(int(menu._selected_detail) == 3, "selecting a preset colour updates the selection")
	check(preview_detail.call() == GameConstants.get_detail_color(3),
		"the preview recolor material receives the new detail colour")

	# Body colour must be unaffected by the detail picker.
	var body_ok := true
	for mat in menu._preview_char.get("_recolor_materials"):
		if Color(mat.get_shader_parameter("body_color")) != GameConstants.get_color(int(menu._selected_color)):
			body_ok = false
	check(body_ok, "the body colour is untouched by the detail picker")

	menu._select_detail(8)      # locked reward colour must be rejected
	await get_tree().process_frame
	check(int(menu._selected_detail) == 3, "locked detail colours are rejected")

	menu._save()                # persists name + colours, then closes
	await get_tree().process_frame
	check(int(SaveManager.detail_color_index) == 3, "saving keeps the detail colour")
	SaveManager.load_profile()
	check(int(SaveManager.detail_color_index) == 3, "the detail colour survives a reload")
	SaveManager.reset_defaults()
	check(int(SaveManager.detail_color_index) == -1, "reset restores the classic metal")

	menu.queue_free()
	print("[DETAIL] finished with %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
