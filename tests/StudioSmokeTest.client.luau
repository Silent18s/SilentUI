--!strict
-- Manual Roblox Studio smoke test. Run as a LocalScript in StarterPlayerScripts.
-- Confirm every control renders and responds, then stop the play session.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SilentUI = require(ReplicatedStorage:WaitForChild("SilentUI"))

local Window = SilentUI:CreateWindow({
    Title = "SilentUI Smoke Test",
    Subtitle = "Manual UI validation",
    Width = 720,
    Height = 520,
    MinWidth = 320,
    MinHeight = 340,
    Resizable = true,
    ToggleKey = Enum.KeyCode.RightControl,
})

local Main = Window:Tab({ Title = "Smoke Test" })
local Section = Main:Section("Core controls")
Section:Toggle({ Title = "Toggle", Flag = "Smoke_Toggle", Default = true })
Section:Slider({ Title = "Slider", Flag = "Smoke_Slider", Min = 0, Max = 100, Default = 50 })
Section:Dropdown({ Title = "Dropdown", Flag = "Smoke_Dropdown", Options = { "A", "B", "C" }, Default = "A" })
Section:Textbox({ Title = "Textbox", Flag = "Smoke_Textbox", Default = "Test" })
Section:ColorPicker({ Title = "Color", Default = Color3.fromRGB(80, 150, 255) })
Section:Keybind({ Title = "Keybind", Default = Enum.KeyCode.G })
Section:Button({
    Title = "Notification",
    ButtonText = "Show",
    Callback = function()
        Window:Notify({ Title = "Smoke test", Content = "Notification rendered." })
    end,
})

local Feedback = Window:Tab({ Title = "Feedback" })
local FeedbackSection = Feedback:Section("Dialogs and state")
FeedbackSection:Button({
    Title = "Confirmation",
    ButtonText = "Open",
    Callback = function()
        Window:Confirm({
            Title = "Smoke test",
            Content = "Confirm dialog rendering.",
            ConfirmText = "OK",
            Callback = function() print("[SilentUI Smoke Test] Confirm callback") end,
        })
    end,
})

print("[SilentUI Smoke Test] UI created. Verify drag, resize, toggle, input, popup and cleanup manually.")
script.Destroying:Connect(function()
    SilentUI:Destroy()
end)
