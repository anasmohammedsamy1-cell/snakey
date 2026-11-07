from pathlib import Path
import json
import struct

from invariant_test_utils import register_checks, run_checks

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


visuals = read("scripts/character/contender_visuals.gd")
pose = read("scripts/character/contender_pose_rig.gd")
ragdoll = read("scripts/character/contender_ragdoll.gd")
controller = read("scripts/player_controller.gd")
round_manager = read("scripts/round_manager.gd")
custom = read("scripts/customization_menu.gd")
player_scene = read("scenes/player.tscn")

with (ROOT / "NewAssets/Model/contender.glb").open("rb") as model_file:
    _, version, _ = struct.unpack("<4sII", model_file.read(12))
    json_length, _ = struct.unpack("<II", model_file.read(8))
    model = json.loads(model_file.read(json_length))
joint_names = {model["nodes"][index].get("name") for index in model["skins"][0]["joints"]}

checks = []


def check(name, condition):
    checks.append((name, bool(condition)))


check("active player scene uses the imported contender visual", "contender_visuals.gd" in player_scene)
check("visual grab state is declared and synchronized by the player controller",
      "var grabbing_id := 0" in visuals and "var grab_phase := 0" in visuals
      and "visuals.set_grab_state(holding, phase)" in controller)
check("throw input is only enabled after the grab reaches its carrying phase",
      "if grabbing_id != 0 and grab_phase == 0:" in controller
      and "var carrying := grabbing_id != 0 and grab_phase == 1" in controller)
check("imported skin contains real left and right hand chains",
      version == 2 and {"Arm_L", "Hand_L", "Arm_R", "Hand_R"} <= joint_names)
check("grab/punch aims existing skeleton bones without a replacement fist",
      ("set_bone_pose_rotation(arm_id," in pose or "_aim_offset(" in pose)
      and "_arm_chain(" in pose
      and "arm_fist" not in visuals and "RubberArm" not in visuals and "replacement hand" not in visuals.lower())
check("held character follows the selected real hand transform",
      "get_grab_hold_position()" in controller or "get_grab_hand_transform()" in controller
      and ("visuals.get_grab_hold_position()" in controller or "get_grab_hand_transform().origin" in controller))
check("failed grab retracts while confirmed grab keeps its real-hand target",
      "not _arm_confirmed and _arm_hold_t > ARM_HOLD_UNCONFIRMED" in visuals
      and "pose_rig.set_reach_target(_arm_world_goal, _arm_side)" in visuals)
check("throw wind-up delays release and applies impulse after the timer",
      "THROW_RELEASE_DELAY := 0.30" in round_manager
      and 'held["throw_time"] = THROW_RELEASE_DELAY' in round_manager
      and 'if float(g["throw_time"]) <= 0.0:' in round_manager
      and round_manager.index('if float(g["throw_time"]) <= 0.0:')
      < round_manager.index('_release_grab(int(aid))', round_manager.index('if float(g["throw_time"]) <= 0.0:')))
check("throw impulse includes carrier momentum",
      "throw_impulse += a.velocity * 0.35" in round_manager)
check("body recoloring preserves atlas shading and is instance-local",
      "ShaderMaterial.new()" in visuals and "set_surface_override_material(i, recolor)" in visuals
      and "recolor_strength" in visuals and ("body_color.rgb" in visuals or "body_color" in visuals)
      and ("shade" in visuals or "luminance" in visuals) and "neutral" in visuals)
check("customization panel and swatches use compact dimensions",
      "Vector2(760, 540)" in custom and "52.0)" in custom)
check("active ragdoll uses stronger, damped motors and tighter head limits",
      '"Head":' in ragdoll and 'JOINT_LIMITS' in ragdoll
      and '"Head":' in ragdoll.split('BODY_ANGULAR_DAMP')[1] if 'BODY_ANGULAR_DAMP' in ragdoll else False
      and 'PARAM_ANGULAR_DAMPING' in ragdoll and 'MOTOR_FORCE' in ragdoll and 'MOTOR_GAIN' in ragdoll)

register_checks(globals(), checks)

if __name__ == "__main__":
    raise SystemExit(run_checks(checks))
