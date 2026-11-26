# Executor usage

SilentUI's normal source tree is modular and uses ModuleScript-relative imports. Executors execute a Luau chunk rather than mounting that ModuleScript tree, so use the generated single-file distribution.

## Recommended: one-file showcase

Paste this one line into a Delta-style executor editor:

\`\`\`lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Silent18s/SilentUI/main/dist/SilentUI-Showcase.lua"))()
\`\`\`

That raw file includes all 13 library modules and the showcase UI. It does not call \`require(script...)\`, access an executor filesystem, or rely on \`getgenv()\`.

## Load only the library

\`\`\`lua
local SilentUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Silent18s/SilentUI/main/dist/SilentUI.lua"))()

local Window = SilentUI:CreateWindow({
    Title = "My UI",
    Width = 720,
    Height = 520,
    Resizable = true,
    ToggleKey = Enum.KeyCode.RightControl,
})

local Tab = Window:Tab({ Title = "Main" })
local Section = Tab:Section("Options")

Section:Toggle({
    Title = "Example toggle",
    Flag = "Main_Example",
    Default = false,
})

Section:Button({
    Title = "Unload library",
    ButtonText = "Unload",
    Callback = function()
        SilentUI:Destroy()
    end,
})
\`\`\`

\`dist/SilentUI.lua\` returns a ready-to-use SilentUI instance (not a constructor class), so do not call \`.new()\` on its result.

## Separate showcase loader

The alternative script \`examples/ExecutorShowcase.lua\` downloads the standalone library distribution and builds the same eight-tab showcase. Execute it directly:

\`\`\`lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Silent18s/SilentUI/main/examples/ExecutorShowcase.lua"))()
\`\`\`

This route performs a second HTTP request from the script to fetch \`dist/SilentUI.lua\`; use the recommended one-file showcase if you prefer a single hosted file.

## Executor boundary

The examples use two executor-provided capabilities:

- \`game:HttpGet(url)\` to retrieve source from GitHub raw.
- \`loadstring(source)\` to compile and execute the downloaded Luau chunk.

These are not ordinary Roblox client APIs. Roblox's documented \`loadstring\` is restricted to server script contexts and disabled by default; an executor provides its own execution environment. Delta's public usage guides describe the HttpGet + loadstring workflow, but do not publish a stable, authoritative API contract for every executor build. Therefore this repository does not assume \`getgenv\`, \`gethui\`, \`readfile\`, \`writefile\`, clipboard or other executor APIs.

## Runtime assumptions

- Run from an attached client context where \`Players.LocalPlayer\` and \`PlayerGui\` exist.
- GitHub raw content must be reachable from the executor.
- The library's GUI uses Roblox client UI, input, camera and tween APIs.
- Configuration profiles use in-memory storage by default. Persistence is not assumed.
- To unload the playground, use **Diagnostics → Unload SilentUI**.
