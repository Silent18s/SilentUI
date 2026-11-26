from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "examples" / "Showcase.client.luau").read_text(encoding="utf-8")
errors = []

calls = re.findall(r"\bNavigationSubTab:([A-Za-z_]\w*)\s*\(", source)
if calls != ["Section"]:
    errors.append(f"SubTab must only create a Section; got {calls}")
if source.count("Window:ConfigManager(") != 1:
    errors.append("ConfigManager must be created once")
for tab in ("Overview", "Controls", "Components", "Layout", "Feedback", "Settings", "Runtime", "Diagnostics"):
    if f'Title = "{tab}"' not in source:
        errors.append(f"Missing tab {tab}")
for api in ("BindEnabledWhen", "MultiDropdown", "ToggleKeybind", "ButtonKeybind", "SystemInfoGrid",
            "AssetGrid", "CardGrid", "CreateKeybindList", "CreateStateList", "CreateBubbleToggle",
            "ExportConfig", "ImportConfig", "CreateSnapshot", "RestoreSnapshot"):
    if api not in source:
        errors.append(f"Missing API coverage {api}")
if not source.startswith("--!strict"):
    errors.append("Showcase must start with --!strict")
if errors:
    print("SHOWCASE CONTRACTS: FAIL")
    print("\n".join(" - " + error for error in errors))
    sys.exit(1)
print("SHOWCASE CONTRACTS: PASS (SubTab, ConfigManager, eight tabs, public API coverage)")
