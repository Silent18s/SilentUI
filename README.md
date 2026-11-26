# SilentUI

Professional, standalone Roblox UI library written in Luau.

## Use in a Delta-style executor

The quickest option is the complete single-file playground. Paste this into the executor editor and execute:

\`\`\`lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Silent18s/SilentUI/main/dist/SilentUI-Showcase.lua"))()
\`\`\`

It contains the bundled library and the full eight-tab UI showcase. It does not need a ModuleScript hierarchy or Rojo.

Standalone distribution:

\`\`\`lua
local SilentUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Silent18s/SilentUI/main/dist/SilentUI.lua"))()
local Window = SilentUI:CreateWindow({ Title = "My Interface" })
local Tab = Window:Tab({ Title = "General" })
local Section = Tab:Section("Options")
Section:Toggle({ Title = "Enabled", Flag = "General_Enabled", Default = false })
\`\`\`

The executor distribution requires an executor that exposes both \`game:HttpGet()\` and \`loadstring()\`. These are executor-specific capabilities, not standard Roblox client APIs. Exact availability can vary between executor versions.

## Repository layout

- \`src/SilentUI/\` — original modular library source (\`Core\`, \`UI\`, \`init.luau\`).
- \`dist/SilentUI.lua\` — bundled single-file distribution; returns a SilentUI instance.
- \`dist/SilentUI-Showcase.lua\` — single-file library + complete showcase.
- \`examples/ExecutorShowcase.lua\` — executor loader that downloads \`dist/SilentUI.lua\` and creates the showcase.
- \`examples/Showcase.client.luau\` — Studio LocalScript example using the ModuleScript project.
- \`default.project.json\` — optional Rojo mapping for Studio.
- \`docs/\` — architecture, API, executor, feature and test documentation.
- \`tests/\` — static contract checks and a manual Studio smoke test.

## Use with Roblox Studio

1. Install Rojo and the Roblox Studio plugin.
2. Run \`rojo serve\` from the repository root.
3. Connect Studio to the Rojo server.
4. The project maps the library to \`ReplicatedStorage.SilentUI\` and the demo to \`StarterPlayerScripts.SilentUIShowcase\`.
5. Start Play and press **RightControl** to toggle the showcase.

The Studio module returns a ready-to-use SilentUI instance:

\`\`\`lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SilentUI = require(ReplicatedStorage:WaitForChild("SilentUI"))
local Window = SilentUI:CreateWindow({ Title = "My Interface" })
\`\`\`

## Verification

Run:

\`\`\`bash
python tests/static_contracts.py
python tests/showcase_contracts.py
python tests/executor_contracts.py
\`\`\`

These checks validate static source/API contracts; they are not a Luau compiler, executor runtime test, or memory benchmark. Complete \`tests/StudioSmokeTest.client.luau\` and \`docs/TEST_CHECKLIST.md\` in Roblox Studio.

## Scope

SilentUI is a UI library. The repository does not include game-specific features, executor filesystem helpers, clipboard helpers, authentication, or loaders beyond the documented raw-GitHub distribution entry points. The default config adapter is in-memory; a host application may inject a permitted storage adapter.
