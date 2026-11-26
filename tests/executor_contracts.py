from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []

library = ROOT / "dist" / "SilentUI.lua"
combined = ROOT / "dist" / "SilentUI-Showcase.lua"
executor = ROOT / "examples" / "ExecutorShowcase.lua"
studio = ROOT / "examples" / "Showcase.client.luau"

for path in (library, combined, executor, studio):
    if not path.is_file():
        errors.append(f"Missing distribution/example: {path.relative_to(ROOT)}")

if library.exists():
    source = library.read_text(encoding="utf-8")
    if not source.startswith("--!strict"):
        errors.append("Standalone bundle must start with --!strict")
    if "require(script." in source or "script.Parent" in source:
        errors.append("Standalone bundle contains ModuleScript-relative imports")
    if source.count("-- ===== Module:") != 13:
        errors.append("Standalone bundle must contain all 13 modules")
    if not source.rstrip().endswith("return __SUI_Library"):
        errors.append("Standalone bundle must return its initialized library instance")
    for alias in (
        "__SUI_Core_Janitor", "__SUI_Core_Signal", "__SUI_Core_InstancePool",
        "__SUI_Core_ConfigStore", "__SUI_Core_IconRegistry", "__SUI_Core_Localization",
        "__SUI_Core_ThemeManager", "__SUI_UI_Controls", "__SUI_UI_AdvancedControls",
        "__SUI_UI_Section", "__SUI_UI_Tab", "__SUI_UI_Window", "__SUI_Library",
    ):
        if alias not in source:
            errors.append(f"Missing bundled module alias: {alias}")

if combined.exists():
    source = combined.read_text(encoding="utf-8")
    if "require(script." in source or "script.Destroying" in source:
        errors.append("All-in-one executor showcase must not depend on a ModuleScript or LocalScript lifecycle")
    if "local Library = __SUI_Library" not in source:
        errors.append("All-in-one showcase does not bind the returned library instance")
    for tab in ("Overview", "Controls", "Components", "Layout", "Feedback", "Settings", "Runtime", "Diagnostics"):
        if f'Title = "{tab}"' not in source:
            errors.append(f"All-in-one showcase is missing tab {tab}")
    if 'Title = "Unload SilentUI"' not in source:
        errors.append("All-in-one showcase must provide an unload control")

if executor.exists():
    source = executor.read_text(encoding="utf-8")
    if not source.startswith("--!strict"):
        errors.append("Executor loader must start with --!strict")
    if "game:HttpGet(LibraryURL)" not in source or "loadstring" not in source:
        errors.append("Executor loader must use HttpGet and loadstring")
    if "require(ReplicatedStorage" in source or "script.Destroying" in source:
        errors.append("Executor loader must not depend on a Studio ModuleScript")
    if "LibraryModule.new" in source:
        errors.append("Executor loader must consume the returned library instance directly")
if studio.exists():
    source = studio.read_text(encoding="utf-8")
    if "LibraryModule.new" in source:
        errors.append("Studio showcase must not call .new() on the returned library instance")

if errors:
    print("EXECUTOR CONTRACTS: FAIL")
    for error in errors:
        print(" -", error)
    sys.exit(1)

print("EXECUTOR CONTRACTS: PASS (single-file bundle, 13 modules, executor loader, eight-tab showcase, Studio instance API)")
