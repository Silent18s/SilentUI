# SilentUI

Professional, standalone Roblox UI library written in Luau.

## Repository layout
- \`src/SilentUI/\` — ModuleScript source (\`Core\`, \`UI\`, \`init.luau\`).
- \`examples/Basic.client.luau\` — minimal LocalScript example.
- \`examples/Showcase.client.luau\` — complete interactive UI playground.
- \`docs/\` — architecture, API, feature inventory, and test guidance.
- \`tests/\` — static contract checks and a manual Studio smoke test.

## Install with Rojo
1. Install Rojo and the Roblox Studio plugin.
2. Run \`rojo serve\` from the repository root.
3. Connect Studio to the Rojo server.
4. The project maps the library to \`ReplicatedStorage.SilentUI\` and the demo to \`StarterPlayerScripts.SilentUIShowcase\`.
5. Start Play. Press **RightControl** to toggle the window.

## Minimal usage
\`\`\`lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SilentUI = require(ReplicatedStorage:WaitForChild("SilentUI"))
local Window = SilentUI:CreateWindow({ Title = "My Interface", Width = 640, Height = 460 })
local Tab = Window:Tab({ Title = "General" })
local Section = Tab:Section("Options")
Section:Toggle({ Title = "Enabled", Flag = "General_Enabled", Default = false })
Section:Button({
    Title = "Notify",
    ButtonText = "Show",
    Callback = function()
        Window:Notify({ Title = "SilentUI", Content = "Button activated." })
    end,
})
\`\`\`

## Showcase
Run \`examples/Showcase.client.luau\` to explore eight pages: Overview, Controls, Components, Layout, Feedback, Settings, Runtime, and Diagnostics. It is UI-only and does not modify game state.

## Verification
Run both static contracts directly:

\`\`\`bash
python tests/static_contracts.py
python tests/showcase_contracts.py
\`\`\`

These checks are not a Luau compiler or runtime test. Complete \`tests/StudioSmokeTest.client.luau\` and \`docs/TEST_CHECKLIST.md\` in Roblox Studio before production.

## Scope
SilentUI has no game-specific scripts, external service integrations, executor APIs, loaders, or authentication systems. Its default config adapter is in-memory; the host may inject a permitted storage adapter.
