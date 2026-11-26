--!strict
-- Put this LocalScript in StarterPlayerScripts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SilentUI = require(ReplicatedStorage:WaitForChild("SilentUI"))

local Window = SilentUI:CreateWindow({
    Title = "My Interface",
    Subtitle = "Basic example",
    Width = 680,
    Height = 500,
    MinWidth = 320,
    MinHeight = 340,
    Resizable = true,
    ToggleKey = Enum.KeyCode.RightControl,
})

local Main = Window:Tab({ Title = "Main" })
local Section = Main:Section("Controls")
Section:Toggle({
    Title = "Enabled", Flag = "Example_Enabled", Default = false,
    Callback = function(value: boolean, info: any) print("Enabled:", value, info.Source) end,
})
Section:Slider({ Title = "Volume", Flag = "Example_Volume", Min = 0, Max = 100, Step = 1, Default = 50 })
Section:Dropdown({ Title = "Quality", Flag = "Example_Quality", Options = { "Low", "Medium", "High" }, Default = "Medium" })
Section:Button({
    Title = "Notification", ButtonText = "Show",
    Callback = function() Window:Notify({ Title = "SilentUI", Content = "Button activated." }) end,
})

script.Destroying:Connect(function()
    SilentUI:Destroy()
end)
