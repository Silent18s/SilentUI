--!strict
-- SilentUI executor showcase loader.
-- Target: Delta-style executors exposing game:HttpGet and loadstring.
-- These are executor-specific capabilities, not standard Roblox client APIs.

local LibraryURL = "https://raw.githubusercontent.com/Silent18s/SilentUI/main/dist/SilentUI.lua"
local httpOk, librarySource = pcall(function()
    return game:HttpGet(LibraryURL)
end)
assert(httpOk and type(librarySource) == "string" and #librarySource > 0,
    "SilentUI: HTTP fetch failed. Verify executor HttpGet access and GitHub connectivity.")

local compile = loadstring
assert(type(compile) == "function",
    "SilentUI: this executor does not expose loadstring.")
local compiled, compileError = compile(librarySource, "@SilentUI")
assert(type(compiled) == "function",
    "SilentUI: bundled library compilation failed: " .. tostring(compileError))
local libraryOk, Library = pcall(compiled)
assert(libraryOk and type(Library) == "table",
    "SilentUI: library initialization failed: " .. tostring(Library))

Library:SetTheme("Dark", false)
Library:SetLanguage("en")


Library:RegisterLocale("en", { welcome = "All showcase systems are ready." })
Library:RegisterLocale("es", { welcome = "Todos los sistemas están listos." })

local Window = Library:CreateWindow({
    Title = "SilentUI",
    Subtitle = "Complete Library Showcase",
    Author = "SilentUI",
    Width = 920,
    Height = 640,
    MinWidth = 320,
    MinHeight = 360,
    Resizable = true,
    ToggleKey = Enum.KeyCode.RightControl,
    FloatingButtonText = "UI",
    SearchEnabled = true,
})

local function Notify(title: string, content: string)
    Window:Notify({ Title = title, Content = content, Duration = 4 })
end

Window:OnOpen(function() print("[SilentUI] Showcase opened") end)
Window:OnClose(function() print("[SilentUI] Showcase closed") end)
Window:OnDestroy(function() print("[SilentUI] Showcase destroyed") end)

-- 01 / Overview
local Overview = Window:Tab({ Title = "Overview" })
local Welcome = Overview:Section("Welcome")
Welcome:GradientCard({
    Title = "SilentUI",
    Heading = "A complete Roblox UI toolkit",
    Content = "Explore navigation, controls, data components, feedback, themes, profiles, localization, and runtime widgets.",
    ButtonText = "Show notification",
    Callback = function() Notify("SilentUI", Library:Translate("welcome")) end,
})
Welcome:Paragraph({
    Title = "About this playground",
    Content = "Every control is interactive. This showcase changes only its own UI state and local configuration; it does not modify character, inventory, currency, or game systems.",
})
Welcome:Tag({ Title = "Status", Text = "READY" })
Welcome:Stats({
    Title = "Library summary",
    Items = {
        { Title = "Runtime", Value = "Roblox / Luau" },
        { Title = "Input", Value = "Touch / Mouse / Keyboard" },
        { Title = "Dependencies", Value = "None" },
        { Title = "Scope", Value = "UI only" },
    },
})
Welcome:InfoGrid({
    Title = "Environment",
    Items = {
        { Label = "Library", Value = "SilentUI" },
        { Label = "Demo", Value = "Showcase" },
        { Label = "Storage", Value = "Memory adapter" },
        { Label = "Toggle", Value = "RightControl" },
    },
})
Welcome:LineText({ Title = "Build", Label = "Playground", Value = "Interactive" })
Welcome:Button({
    Title = "Open welcome dialog",
    ButtonText = "Open dialog",
    Callback = function()
        Window:Dialog({
            Title = "Welcome to SilentUI",
            Content = "This is a standalone UI library playground.",
            Buttons = {
                { Title = "Close", Variant = "Secondary" },
                { Title = "Continue", Variant = "Primary", Callback = function()
                    Notify("Dialog", "Primary action activated.")
                end },
            },
        })
    end,
})

-- 02 / Controls
local Controls = Window:Tab({ Title = "Controls" })
local State = Controls:Section("State and numeric controls")
local Master = State:Toggle({
    Title = "Enable dependent options",
    Flag = "Demo_Master",
    Default = true,
    Callback = function(value: boolean, info: any)
        print("[SilentUI] Master:", value, info.Source)
    end,
})
local Dependent = State:Slider({
    Title = "Dependent slider",
    Flag = "Demo_Dependent",
    Min = 0, Max = 100, Step = 5, Default = 50,
})
State:BindEnabledWhen(Master, function(value: any): boolean
    return value == true
end, { Dependent })
State:Slider({
    Title = "Volume",
    Flag = "Demo_Volume",
    Min = 0, Max = 100, Step = 1, Default = 70,
    Callback = function(value: number) print("[SilentUI] Volume:", value) end,
})
State:Stepper({ Title = "Quantity", Flag = "Demo_Quantity", Min = 0, Max = 25, Step = 1, Default = 4 })
local Progress = State:Progress({ Title = "Progress display", Min = 0, Max = 100, Default = 35 })
State:Button({
    Title = "Advance progress",
    ButtonText = "Set to 85%",
    Callback = function() Progress:Set(85, false) end,
})

local Inputs = Controls:Section("Selection and text input")
Inputs:Dropdown({
    Title = "Single selection",
    Flag = "Demo_Dropdown",
    Options = { "Default", "Compact", "Comfortable", "Custom" },
    Default = "Default",
    Callback = function(value: string) print("[SilentUI] Selected:", value) end,
})
Inputs:MultiDropdown({
    Title = "Multiple selection",
    Flag = "Demo_Multi",
    Options = { "Audio", "Visual", "Gameplay", "Accessibility", "Interface" },
    Default = { "Visual", "Interface" },
})
Inputs:Segmented({ Title = "Segmented control", Options = { "Low", "Medium", "High" }, Default = "Medium" })
Inputs:Textbox({
    Title = "Textbox", Flag = "Demo_Textbox", Placeholder = "Write something...", Default = "SilentUI",
    Callback = function(value: string) print("[SilentUI] Text:", value) end,
})
Inputs:Input({ Title = "Input alias", Placeholder = "Input control", Default = "Input" })
Inputs:ColorPicker({
    Title = "Accent color",
    Default = Color3.fromRGB(88, 150, 255),
    Callback = function(color: Color3) Library:SetAccent(color, true) end,
})
Inputs:Keybind({
    Title = "Press keybind", Flag = "Demo_Keybind", Default = Enum.KeyCode.G, Mode = "Press",
    Callback = function(keyName: string, info: any)
        Notify("Keybind", keyName .. " / " .. tostring(info.Action))
    end,
})
Inputs:ToggleKeybind({ Title = "Toggle + keybind", Flag = "Demo_ToggleKey", KeybindFlag = "Demo_Toggle", Default = false, Key = Enum.KeyCode.H })
Inputs:ButtonKeybind({
    Title = "Button + keybind", Key = Enum.KeyCode.J, ButtonText = "Run action",
    Callback = function() Notify("Composite", "Button/keybind action executed.") end,
})
Inputs:Button({ Title = "Lock dependent slider", ButtonText = "Lock", Callback = function() Dependent:Lock() end })
Inputs:Button({ Title = "Unlock dependent slider", ButtonText = "Unlock", Callback = function() Dependent:Unlock() end })
Inputs:Label({ Title = "Control methods", Text = "Get / Set / OnChanged / SetVisible / Lock / Unlock / Destroy" })

-- 03 / Components
local Components = Window:Tab({ Title = "Components" })
local Data = Components:Section("Data and presentation")
Data:Table({
    Title = "Table component",
    Columns = { "Control", "Category", "Status" },
    Rows = {
        { "Toggle", "Input", "Ready" },
        { "Slider", "Input", "Ready" },
        { "Dropdown", "Input", "Ready" },
        { "Card", "Display", "Ready" },
    },
})
local Console = Data:Console({ Title = "Console component", InitialText = "SilentUI console ready" })
Data:Changelog({
    Title = "Changelog",
    Entries = {
        { Version = "0.3.0", Title = "Showcase", Content = "Complete UI playground." },
        { Version = "0.2.0", Title = "Components", Content = "Component gallery." },
    },
})
Data:Card({
    Title = "Card component", Content = "A content card with an optional action.",
    ButtonText = "Card action", Callback = function() Notify("Card", "Card callback executed.") end,
})
Data:Tag({ Title = "Connection", Text = "ONLINE" })
Data:Stats({
    Title = "Sample statistics",
    Items = { { Title = "FPS", Value = "60" }, { Title = "Ping", Value = "35 ms" }, { Title = "Mode", Value = "Demo" } },
})

local Collections = Components:Section("Grids and media")
Collections:AssetGrid({
    Title = "Asset grid",
    Items = { { Title = "Asset A", Value = "asset-a" }, { Title = "Asset B", Value = "asset-b" }, { Title = "Asset C", Value = "asset-c" } },
    Default = "asset-a",
})
Collections:CardGrid({
    Title = "Card grid",
    Items = { { Title = "Layout A", Value = "layout-a" }, { Title = "Layout B", Value = "layout-b" }, { Title = "Layout C", Value = "layout-c" } },
    Default = "layout-b",
})
Collections:InfoGrid({
    Title = "Info grid",
    Items = { { Label = "Library", Value = "SilentUI" }, { Label = "Runtime", Value = "Roblox" }, { Label = "Language", Value = "Luau" } },
})
Collections:SystemInfoGrid({
    Title = "System info",
    Items = { { Label = "Platform", Value = "Roblox client" }, { Label = "Input", Value = "Touch / Mouse / Keyboard" } },
})
Collections:Image({ Title = "Image", Image = "", Caption = "Set a permitted image asset ID to preview." })
Collections:Video({ Title = "Video", Video = "", AutoPlay = false })
Collections:Code({ Title = "Code", Code = "local Window = Library:CreateWindow({ Title = 'Hello' })" })
Collections:LoadoutGroup({
    Title = "Loadout group",
    Slots = { { Slot = "Primary", Value = "Empty" }, { Slot = "Secondary", Value = "Empty" }, { Slot = "Utility", Value = "Empty" } },
})
Collections:StateList({
    Title = "State list",
    States = { { Title = "UI", Status = "Ready" }, { Title = "Config", Status = "Memory" } },
})
Collections:Rating({ Title = "Rating", Max = 5, Default = 4 })

-- 04 / Layout
local Layout = Window:Tab({ Title = "Layout" })
local Composition = Layout:Section("Groups and columns")
local Group = Composition:Group({ Title = "Nested group" })
Group:Toggle({ Title = "Group toggle", Flag = "Demo_Group", Default = true })
Group:Slider({ Title = "Group slider", Min = 0, Max = 10, Default = 5 })
local Columns = Composition:MultiSection({ Titles = { "Left column", "Right column" } })
Columns[1]:Label({ Title = "Column A", Text = "First section" })
Columns[1]:Button({ Title = "Left action", ButtonText = "Activate", Callback = function() Notify("Layout", "Left column.") end })
Columns[2]:Label({ Title = "Column B", Text = "Second section" })
Columns[2]:Button({ Title = "Right action", ButtonText = "Activate", Callback = function() Notify("Layout", "Right column.") end })
local NavigationSubTab = Layout:SubTab({ Title = "Subtab example" })
local SubTabSection = NavigationSubTab:Section("Subtab content")
SubTabSection:Paragraph({ Title = "Subtab", Content = "Subtabs expose Section(), and sections expose the regular control API." })
SubTabSection:Toggle({ Title = "Subtab toggle", Flag = "Demo_Subtab", Default = false })
Layout:AddControls({
    { Type = "Label", Title = "Declarative label", Text = "Created from a definition table." },
    { Type = "Toggle", Title = "Declarative toggle", Flag = "Demo_Declarative", Default = true },
    { Type = "Button", Title = "Declarative button", ButtonText = "Activate", Callback = function()
        Notify("Declarative", "Button activated.")
    end },
})

-- 05 / Feedback
local Feedback = Window:Tab({ Title = "Feedback" })
local Notices = Feedback:Section("Notifications")
Notices:Button({ Title = "Standard notification", ButtonText = "Notify", Callback = function() Notify("Notification", "SilentUI notification created.") end })
Notices:Button({
    Title = "Long notification", ButtonText = "Show",
    Callback = function()
        Window:Notify({ Title = "Long notification", Content = "This message exercises wrapping and transient cleanup at different viewport sizes.", Duration = 6 })
    end,
})
local Dialogs = Feedback:Section("Dialogs and prompts")
Dialogs:Button({
    Title = "Two-action dialog", ButtonText = "Open",
    Callback = function()
        Window:Dialog({
            Title = "Dialog example", Content = "Dialogs can contain multiple actions.",
            Buttons = {
                { Title = "Cancel", Variant = "Secondary" },
                { Title = "Continue", Variant = "Primary", Callback = function() Notify("Dialog", "Continue selected.") end },
            },
        })
    end,
})
Dialogs:Button({
    Title = "Confirmation dialog", ButtonText = "Confirm",
    Callback = function()
        Window:Confirm({
            Title = "Confirm action", Content = "A non-destructive demonstration.",
            ConfirmText = "Confirm", Callback = function() Notify("Confirmed", "Callback executed.") end,
        })
    end,
})
Dialogs:Button({
    Title = "Text prompt", ButtonText = "Open prompt",
    Callback = function()
        Window:Prompt({
            Title = "Prompt example", Content = "Enter a sample value.",
            InputPlaceholder = "Your text...", Default = "SilentUI",
            Callback = function(value: string) Notify("Prompt submitted", value) end,
        })
    end,
})

-- 06 / Settings
local Settings = Window:Tab({ Title = "Settings" })
local Appearance = Settings:Section("Appearance and themes")
Appearance:Dropdown({
    Title = "Theme preset", Options = Library:GetThemes(), Default = "Dark",
    Callback = function(themeName: string) Library:SetTheme(themeName, true) end,
})
Appearance:ColorPicker({ Title = "Accent color", Default = Color3.fromRGB(88, 150, 255), Callback = function(color: Color3) Library:SetAccent(color, true) end })
Appearance:Slider({ Title = "Interface scale", Min = 0.75, Max = 1.25, Step = 0.05, Default = 1, Callback = function(value: number) Window:SetUIScale(value) end })
Appearance:Slider({ Title = "Interface transparency", Min = 0, Max = 0.5, Step = 0.05, Default = 0, Callback = function(value: number) Window:SetInterfaceTransparency(value) end })
Appearance:Toggle({ Title = "Acrylic-style surface", Default = false, Callback = function(enabled: boolean) Window:SetAcrylicEnabled(enabled) end })
Appearance:Toggle({ Title = "Blur effect", Default = false, Callback = function(enabled: boolean) Window:SetBlurEnabled(enabled) end })
Appearance:Button({ Title = "Toggle fullscreen", ButtonText = "Toggle", Callback = function() Window:ToggleFullscreen() end })

local Profiles = Settings:Section("Configuration profiles")
Profiles:Button({ Title = "Save profile", ButtonText = "Save Showcase", Callback = function()
    local ok, err = Window:SaveConfig("Showcase")
    Notify(ok and "Profile saved" or "Save failed", tostring(err or "Showcase"))
end })
Profiles:Button({ Title = "Load profile", ButtonText = "Load Showcase", Callback = function()
    local ok, err = Window:LoadConfig("Showcase")
    Notify(ok and "Profile loaded" or "Load failed", tostring(err or "Showcase"))
end })
Profiles:Button({ Title = "Export / import JSON", ButtonText = "Round-trip", Callback = function()
    local saved, saveError = Window:SaveConfig("Showcase")
    if not saved then Notify("Save failed", tostring(saveError)); return end
    local exported, json = Window:ExportConfig("Showcase")
    if not exported or json == nil then Notify("Export failed", tostring(json)); return end
    local imported, importError = Window:ImportConfig("Showcase_Imported", json)
    Notify(imported and "Import completed" or "Import failed", tostring(importError or "Showcase_Imported"))
end })
Profiles:Button({ Title = "List profiles", ButtonText = "List", Callback = function()
    local names = Window:ListConfigs()
    Console:Write("Profiles: " .. (#names > 0 and table.concat(names, ", ") or "none"), "Info")
    Notify("Profiles", #names > 0 and table.concat(names, ", ") or "No profiles saved")
end })
Profiles:Button({ Title = "Set autoload", ButtonText = "Set Showcase", Callback = function()
    local ok, err = Window:SetAutoload("Showcase")
    Notify(ok and "Autoload set" or "Autoload failed", tostring(err or "Showcase"))
end })
Window:ConfigManager(Settings, "Built-in Config Manager")

local Locale = Settings:Section("Localization")
Locale:Segmented({
    Title = "Language", Options = { "en", "es" }, Default = "en",
    Callback = function(language: string)
        Library:SetLanguage(language)
        Notify("Localization", language == "es" and "Idioma cambiado a español." or "Language changed to English.")
    end,
})
Locale:Button({ Title = "Translate sample key", ButtonText = "Translate", Callback = function() Notify("Translation", Library:Translate("welcome")) end })

-- 07 / Runtime widgets
local Runtime = Window:Tab({ Title = "Runtime" })
local Widgets = Runtime:Section("Floating widgets")
local KeybindList = Window:CreateKeybindList({ Title = "Active keybinds" })
local StateList = Window:CreateStateList({
    Title = "Runtime state",
    Items = {
        { Title = "Library", Value = "SilentUI", Active = true },
        { Title = "Window", Value = "Open", Active = true },
        { Title = "Showcase", Value = "Running", Active = true },
    },
})
local Watermark = Window:Watermark({ Text = "SilentUI / Showcase" })
local Bubble = Window:CreateBubbleToggle({ Text = "UI", Draggable = true })
Widgets:Toggle({ Title = "Show keybind list", Default = true, Callback = function(value: boolean) KeybindList:SetVisible(value) end })
Widgets:Toggle({ Title = "Show state list", Default = true, Callback = function(value: boolean) StateList:SetVisible(value) end })
Widgets:Button({ Title = "Update watermark", ButtonText = "Update", Callback = function() Watermark:Set("SilentUI / Playground / Active") end })
Widgets:Toggle({ Title = "Show floating bubble", Default = true, Callback = function(value: boolean) Bubble:SetVisible(value) end })
Widgets:Button({ Title = "Refresh state list", ButtonText = "Refresh", Callback = function()
    StateList:Set({
        { Title = "Library", Value = "Loaded", Active = true },
        { Title = "Window", Value = "Responsive", Active = true },
        { Title = "Controls", Value = "Interactive", Active = true },
    })
    Notify("Runtime", "State list refreshed.")
end })
Widgets:Button({ Title = "Toggle window", ButtonText = "Toggle", Callback = function() Window:Toggle() end })
Widgets:Button({ Title = "Write console line", ButtonText = "Write", Callback = function()
    Console:Write("Client uptime: " .. tostring(math.floor(os.clock())) .. " seconds", "Info")
end })

-- 08 / Diagnostics
local Diagnostics = Window:Tab({ Title = "Diagnostics" })
local DiagnosticSection = Diagnostics:Section("Flags and state")
DiagnosticSection:InfoGrid({
    Title = "Runtime details",
    Items = {
        { Label = "Theme", Value = "Change in Settings" },
        { Label = "Config adapter", Value = "In-memory by default" },
        { Label = "Input", Value = "Touch / Mouse / Keyboard" },
        { Label = "Cleanup", Value = "Library:Destroy()" },
    },
})
DiagnosticSection:Button({ Title = "Print registered flags", ButtonText = "Print", Callback = function()
    for flag, value in pairs(Library:GetValues()) do print("[SilentUI]", flag, value) end
    Notify("Diagnostics", "Values were written to Output.")
end })
DiagnosticSection:Button({ Title = "Snapshot round-trip", ButtonText = "Create / restore", Callback = function()
    local snapshot = Library:CreateSnapshot()
    local ok, err = Library:RestoreSnapshot(snapshot, true)
    Notify(ok and "Snapshot restored" or "Snapshot failed", tostring(err or "Round-trip completed"))
end })
DiagnosticSection:Button({ Title = "Reset configuration", ButtonText = "Reset", Callback = function()
    Window:Confirm({
        Title = "Reset showcase values?",
        Content = "This resets UI controls to defaults; it does not affect game data.",
        ConfirmText = "Reset",
        Callback = function()
            Library:ResetConfiguration(false)
            Notify("Configuration", "Showcase values reset.")
        end,
    })
end })

DiagnosticSection:Button({
    Title = "Unload SilentUI",
    ButtonText = "Unload",
    Callback = function()
        Library:Destroy()
        print("[SilentUI] Library destroyed.")
    end,
})

Console:Write("SilentUI Showcase loaded", "Success")
Console:Write("Explore all eight tabs to test the UI", "Info")
print("[SilentUI] Complete showcase loaded. Press RightControl to toggle.")

-- Use the "Unload SilentUI" control in Diagnostics to release the UI and connections.
