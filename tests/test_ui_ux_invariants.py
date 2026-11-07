from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

checks = []
def check(name, condition):
    checks.append((name, bool(condition)))

ui = read("scripts/ui_kit.gd")
main = read("scripts/main_menu.gd")
settings = read("scripts/settings_menu.gd")
hud = read("scripts/gameplay_hud.gd")
lobby = read("scripts/lobby_manager.gd")
custom = read("scripts/customization_menu.gd")
results = read("scripts/results_screen.gd")

check("centered panels account for device safe-area insets", "safe_insets(viewport)" in ui and "available.x" in ui and "available.y" in ui)
check("HUD safe-area margins recalculate after viewport changes", "_apply_safe_margins(m, viewport, extra)" in ui and "var update := _apply_safe_margins.bind(m, viewport, extra)" in ui and "viewport.size_changed.connect(update)" in ui)
check("modal safe-area offsets and size recalculate after viewport changes", "_apply_centered_layout(c, child, viewport, max_size)" in ui and "viewport.size_changed.connect(update)" in ui)
check("modal sizing does not force oversized minimums on tiny viewports", "maxf(0.0, view_size.x - safe.x - safe.z - 28.0)" in ui and "maxf(0.0, view_size.y - safe.y - safe.w - 28.0)" in ui)
check("shared compact breakpoint exists", "static func is_compact" in ui)
check("settings sliders switch to stacked compact layout", "static func slider_row" in ui and "row.vertical = compact" in ui)
check("buttons expose pointer affordance and tooltip", "CURSOR_POINTING_HAND" in ui and "b.tooltip_text = text" in ui)
check("main menu switches layout on viewport resize", "size_changed.connect(_on_viewport_resized)" in main and "_menu_row.vertical = compact" in main)
check("main menu actions remain in a scrollable container", "_menu_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO" in main)
check("settings provide five category jump shortcuts", 'category_keys := [\"graphics\", \"audio\", \"voice\", \"controls\", \"gameplay\"]' in settings and "ensure_control_visible" in settings)
check("HUD keeps animated game mute visible and groups voice controls in quick panel", "top.add_child(_game_audio_button)" in hud and "_chan_button, _friends_audio_button]" in hud)
check("HUD audio controls are reparented only after initial creation", "top.add_child(_chan_button)" in hud and "top.remove_child(audio_control)" in hud)
check("microphone and mute remain independently reachable in the HUD", "top.add_child(_mic_button)" in hud and "top.add_child(_game_audio_button)" in hud)
check("lobby connection columns adapt to compact screens", "_connect_columns.vertical = compact" in lobby and "_connect_separator.custom_minimum_size" in lobby)
check("lobby settings and action rows adapt to compact screens", "_responsive_boxes.append(row1)" in lobby and "_responsive_boxes.append(actions)" in lobby)
check("customization preview layout supports compact stacking", "body.vertical = get_viewport().get_visible_rect().size.x < 900.0" in custom)
check("results screen uses compact typography and flexible width", "_is_compact" in results and "title.custom_minimum_size = Vector2(0, 0)" in results)
check("map picker card grid adapts to phone and tablet widths", "var responsive_columns := 1 if viewport_width < 760.0" in read("scripts/map_picker.gd"))
check("customization content can scroll when stacked on short screens", "var body_scroll := ScrollContainer.new()" in custom and "body_scroll.add_child(body)" in custom)

from invariant_test_utils import register_checks, run_checks

register_checks(globals(), checks)

if __name__ == "__main__":
    raise SystemExit(run_checks(checks))
