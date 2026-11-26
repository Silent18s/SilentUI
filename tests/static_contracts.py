from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "src" / "SilentUI"
FILES = [
    "init.luau",
    "Core/ConfigStore.luau",
    "Core/IconRegistry.luau",
    "Core/InstancePool.luau",
    "Core/Janitor.luau",
    "Core/Localization.luau",
    "Core/Signal.luau",
    "Core/ThemeManager.luau",
    "UI/AdvancedControls.luau",
    "UI/Controls.luau",
    "UI/Section.luau",
    "UI/Tab.luau",
    "UI/Window.luau",
]
errors = []
for relative in FILES:
    path = SOURCE / relative
    if not path.is_file():
        errors.append(f"Missing source: {relative}")
        continue
    source = path.read_text(encoding="utf-8")
    if not source.startswith("--!strict"):
        errors.append(f"Missing strict mode: {relative}")
    if source.count("{") != source.count("}"):
        errors.append(f"Brace count mismatch: {relative}")
    if source.count("(") != source.count(")"):
        errors.append(f"Parenthesis count mismatch: {relative}")
try:
    project = json.loads((ROOT / "default.project.json").read_text(encoding="utf-8"))
    tree = project["tree"]
    if tree["ReplicatedStorage"]["SilentUI"]["$path"] != "src/SilentUI":
        errors.append("Invalid Rojo library mapping")
    if tree["StarterPlayer"]["StarterPlayerScripts"]["SilentUIShowcase"]["$path"] != "examples/Showcase.client.luau":
        errors.append("Invalid Rojo showcase mapping")
except Exception as exc:
    errors.append(f"Invalid Rojo JSON: {exc}")
if errors:
    print("STATIC CONTRACTS: FAIL")
    print("\n".join(" - " + error for error in errors))
    sys.exit(1)
print(f"STATIC CONTRACTS: PASS ({len(FILES)} strict library modules and Rojo mappings)")
