--!strict
-- Runtime theme tokens. Bindings are weak-keyed so destroyed UI can be collected.

local TweenService = game:GetService("TweenService")
local Signal = require(script.Parent.Signal)

local PRESETS: {[string]: {[string]: any}} = {
    Dark = {
        Name = "Dark",
        Window = Color3.fromRGB(15, 17, 23),
        Surface = Color3.fromRGB(22, 25, 33),
        SurfaceAlt = Color3.fromRGB(29, 33, 43),
        Border = Color3.fromRGB(55, 61, 75),
        Text = Color3.fromRGB(244, 246, 250),
        Muted = Color3.fromRGB(157, 165, 180),
        Accent = Color3.fromRGB(69, 148, 255),
        AccentText = Color3.fromRGB(255, 255, 255),
        Success = Color3.fromRGB(65, 190, 125),
        Danger = Color3.fromRGB(235, 87, 87),
        Overlay = Color3.fromRGB(0, 0, 0),
        OverlayTransparency = 0.34,
    },
    Light = {
        Name = "Light",
        Window = Color3.fromRGB(241, 243, 247),
        Surface = Color3.fromRGB(255, 255, 255),
        SurfaceAlt = Color3.fromRGB(232, 236, 243),
        Border = Color3.fromRGB(207, 213, 224),
        Text = Color3.fromRGB(26, 30, 39),
        Muted = Color3.fromRGB(105, 113, 128),
        Accent = Color3.fromRGB(40, 112, 222),
        AccentText = Color3.fromRGB(255, 255, 255),
        Success = Color3.fromRGB(32, 145, 91),
        Danger = Color3.fromRGB(204, 57, 57),
        Overlay = Color3.fromRGB(15, 19, 28),
        OverlayTransparency = 0.58,
    },
    Midnight = {
        Name = "Midnight",
        Window = Color3.fromRGB(8, 15, 30),
        Surface = Color3.fromRGB(14, 25, 47),
        SurfaceAlt = Color3.fromRGB(22, 39, 67),
        Border = Color3.fromRGB(39, 66, 105),
        Text = Color3.fromRGB(230, 241, 255),
        Muted = Color3.fromRGB(138, 164, 199),
        Accent = Color3.fromRGB(67, 166, 255),
        AccentText = Color3.fromRGB(6, 20, 39),
        Success = Color3.fromRGB(61, 200, 151),
        Danger = Color3.fromRGB(255, 100, 115),
        Overlay = Color3.fromRGB(0, 5, 16),
        OverlayTransparency = 0.26,
    },
    Rose = {
        Name = "Rose",
        Window = Color3.fromRGB(31, 14, 24),
        Surface = Color3.fromRGB(46, 21, 36),
        SurfaceAlt = Color3.fromRGB(63, 29, 49),
        Border = Color3.fromRGB(102, 52, 79),
        Text = Color3.fromRGB(255, 239, 247),
        Muted = Color3.fromRGB(204, 155, 179),
        Accent = Color3.fromRGB(236, 82, 143),
        AccentText = Color3.fromRGB(255, 255, 255),
        Success = Color3.fromRGB(94, 194, 133),
        Danger = Color3.fromRGB(255, 105, 105),
        Overlay = Color3.fromRGB(15, 3, 9),
        OverlayTransparency = 0.28,
    },
    -- Monochrome SilentUI preset.
    SilentUI = {
        Name = "SilentUI",
        Window = Color3.fromRGB(9, 9, 9), Surface = Color3.fromRGB(14, 14, 14),
        SurfaceAlt = Color3.fromRGB(20, 20, 20), Border = Color3.fromRGB(42, 42, 42),
        Text = Color3.fromRGB(242, 242, 242), Muted = Color3.fromRGB(157, 157, 157),
        Accent = Color3.fromRGB(235, 235, 235), AccentText = Color3.fromRGB(12, 12, 12),
        Success = Color3.fromRGB(128, 200, 145), Danger = Color3.fromRGB(220, 88, 88),
        Overlay = Color3.fromRGB(0, 0, 0), OverlayTransparency = 0.42,
    },
    White = {
        Name = "White",
        Window = Color3.fromRGB(248, 248, 250), Surface = Color3.fromRGB(241, 241, 244),
        SurfaceAlt = Color3.fromRGB(232, 232, 236), Border = Color3.fromRGB(201, 201, 208),
        Text = Color3.fromRGB(20, 20, 24), Muted = Color3.fromRGB(88, 88, 98),
        Accent = Color3.fromRGB(48, 48, 58), AccentText = Color3.fromRGB(255, 255, 255),
        Success = Color3.fromRGB(45, 145, 94), Danger = Color3.fromRGB(194, 62, 62),
        Overlay = Color3.fromRGB(20, 20, 24), OverlayTransparency = 0.62,
    },
    -- Additional color presets.
    Plant = {
        Name = "Plant", Window = Color3.fromRGB(10, 27, 15), Surface = Color3.fromRGB(5, 46, 22),
        SurfaceAlt = Color3.fromRGB(16, 80, 42), Border = Color3.fromRGB(52, 120, 75),
        Text = Color3.fromRGB(240, 253, 244), Muted = Color3.fromRGB(145, 190, 158),
        Accent = Color3.fromRGB(34, 197, 94), AccentText = Color3.fromRGB(255, 255, 255),
        Success = Color3.fromRGB(74, 222, 128), Danger = Color3.fromRGB(248, 113, 113),
        Overlay = Color3.fromRGB(0, 15, 5), OverlayTransparency = 0.3,
    },
    Red = {
        Name = "Red", Window = Color3.fromRGB(28, 6, 6), Surface = Color3.fromRGB(69, 10, 10),
        SurfaceAlt = Color3.fromRGB(110, 25, 25), Border = Color3.fromRGB(145, 48, 48),
        Text = Color3.fromRGB(254, 242, 242), Muted = Color3.fromRGB(218, 145, 145),
        Accent = Color3.fromRGB(220, 38, 38), AccentText = Color3.fromRGB(255, 255, 255),
        Success = Color3.fromRGB(74, 190, 120), Danger = Color3.fromRGB(248, 113, 113),
        Overlay = Color3.fromRGB(20, 0, 0), OverlayTransparency = 0.28,
    },
    Indigo = {
        Name = "Indigo", Window = Color3.fromRGB(15, 10, 46), Surface = Color3.fromRGB(30, 27, 75),
        SurfaceAlt = Color3.fromRGB(48, 45, 115), Border = Color3.fromRGB(78, 75, 155),
        Text = Color3.fromRGB(241, 245, 249), Muted = Color3.fromRGB(165, 168, 218),
        Accent = Color3.fromRGB(99, 102, 241), AccentText = Color3.fromRGB(255, 255, 255),
        Success = Color3.fromRGB(74, 190, 120), Danger = Color3.fromRGB(248, 113, 113),
        Overlay = Color3.fromRGB(8, 5, 30), OverlayTransparency = 0.3,
    },
    Sky = {
        Name = "Sky", Window = Color3.fromRGB(5, 26, 38), Surface = Color3.fromRGB(10, 77, 102),
        SurfaceAlt = Color3.fromRGB(14, 95, 119), Border = Color3.fromRGB(50, 150, 175),
        Text = Color3.fromRGB(230, 247, 255), Muted = Color3.fromRGB(120, 190, 207),
        Accent = Color3.fromRGB(0, 212, 255), AccentText = Color3.fromRGB(4, 28, 38),
        Success = Color3.fromRGB(45, 190, 150), Danger = Color3.fromRGB(245, 95, 95),
        Overlay = Color3.fromRGB(0, 14, 24), OverlayTransparency = 0.28,
    },
    Violet = {
        Name = "Violet", Window = Color3.fromRGB(30, 10, 62), Surface = Color3.fromRGB(60, 19, 97),
        SurfaceAlt = Color3.fromRGB(85, 35, 135), Border = Color3.fromRGB(115, 70, 165),
        Text = Color3.fromRGB(250, 245, 255), Muted = Color3.fromRGB(190, 155, 220),
        Accent = Color3.fromRGB(124, 58, 237), AccentText = Color3.fromRGB(255, 255, 255),
        Success = Color3.fromRGB(80, 190, 135), Danger = Color3.fromRGB(245, 100, 120),
        Overlay = Color3.fromRGB(14, 3, 35), OverlayTransparency = 0.3,
    },
    Amber = {
        Name = "Amber", Window = Color3.fromRGB(28, 16, 3), Surface = Color3.fromRGB(69, 26, 3),
        SurfaceAlt = Color3.fromRGB(110, 46, 8), Border = Color3.fromRGB(145, 87, 20),
        Text = Color3.fromRGB(255, 251, 235), Muted = Color3.fromRGB(214, 170, 95),
        Accent = Color3.fromRGB(217, 119, 6), AccentText = Color3.fromRGB(255, 251, 235),
        Success = Color3.fromRGB(120, 190, 100), Danger = Color3.fromRGB(220, 80, 60),
        Overlay = Color3.fromRGB(18, 9, 0), OverlayTransparency = 0.28,
    },
    Emerald = {
        Name = "Emerald", Window = Color3.fromRGB(1, 20, 17), Surface = Color3.fromRGB(2, 44, 34),
        SurfaceAlt = Color3.fromRGB(4, 80, 62), Border = Color3.fromRGB(35, 110, 88),
        Text = Color3.fromRGB(236, 253, 245), Muted = Color3.fromRGB(125, 190, 165),
        Accent = Color3.fromRGB(5, 150, 105), AccentText = Color3.fromRGB(255, 255, 255),
        Success = Color3.fromRGB(52, 211, 153), Danger = Color3.fromRGB(248, 113, 113),
        Overlay = Color3.fromRGB(0, 15, 12), OverlayTransparency = 0.32,
    },
    Crimson = {
        Name = "Crimson", Window = Color3.fromRGB(12, 4, 4), Surface = Color3.fromRGB(69, 10, 10),
        SurfaceAlt = Color3.fromRGB(112, 25, 25), Border = Color3.fromRGB(150, 55, 55),
        Text = Color3.fromRGB(254, 242, 242), Muted = Color3.fromRGB(180, 120, 125),
        Accent = Color3.fromRGB(185, 28, 28), AccentText = Color3.fromRGB(255, 255, 255),
        Success = Color3.fromRGB(64, 180, 120), Danger = Color3.fromRGB(248, 113, 113),
        Overlay = Color3.fromRGB(12, 0, 0), OverlayTransparency = 0.28,
    },
    Monokai = {
        Name = "Monokai", Window = Color3.fromRGB(25, 22, 34), Surface = Color3.fromRGB(35, 32, 45),
        SurfaceAlt = Color3.fromRGB(51, 47, 63), Border = Color3.fromRGB(85, 78, 96),
        Text = Color3.fromRGB(252, 252, 250), Muted = Color3.fromRGB(164, 160, 170),
        Accent = Color3.fromRGB(252, 152, 103), AccentText = Color3.fromRGB(30, 25, 30),
        Success = Color3.fromRGB(169, 220, 118), Danger = Color3.fromRGB(255, 97, 136),
        Overlay = Color3.fromRGB(10, 8, 18), OverlayTransparency = 0.34,
    },
    CottonCandy = {
        Name = "Cotton Candy", Window = Color3.fromRGB(26, 11, 46), Surface = Color3.fromRGB(45, 27, 61),
        SurfaceAlt = Color3.fromRGB(72, 38, 83), Border = Color3.fromRGB(110, 62, 125),
        Text = Color3.fromRGB(253, 242, 248), Muted = Color3.fromRGB(180, 140, 190),
        Accent = Color3.fromRGB(236, 72, 153), AccentText = Color3.fromRGB(255, 255, 255),
        Success = Color3.fromRGB(74, 190, 140), Danger = Color3.fromRGB(255, 110, 140),
        Overlay = Color3.fromRGB(10, 3, 20), OverlayTransparency = 0.28,
    },
    Sand = {
        Name = "Sand", Window = Color3.fromRGB(28, 16, 2), Surface = Color3.fromRGB(41, 28, 19),
        SurfaceAlt = Color3.fromRGB(52, 42, 30), Border = Color3.fromRGB(107, 90, 69),
        Text = Color3.fromRGB(245, 235, 221), Muted = Color3.fromRGB(175, 155, 128),
        Accent = Color3.fromRGB(169, 135, 63), AccentText = Color3.fromRGB(255, 250, 235),
        Success = Color3.fromRGB(120, 175, 105), Danger = Color3.fromRGB(205, 90, 75),
        Overlay = Color3.fromRGB(15, 8, 1), OverlayTransparency = 0.3,
    },
    Black = {
        Name = "Black", Window = Color3.fromRGB(8, 8, 8), Surface = Color3.fromRGB(12, 12, 12),
        SurfaceAlt = Color3.fromRGB(22, 22, 22), Border = Color3.fromRGB(48, 48, 48),
        Text = Color3.fromRGB(244, 238, 229), Muted = Color3.fromRGB(150, 139, 126),
        Accent = Color3.fromRGB(41, 255, 244), AccentText = Color3.fromRGB(8, 8, 8),
        Success = Color3.fromRGB(128, 224, 134), Danger = Color3.fromRGB(240, 90, 100),
        Overlay = Color3.fromRGB(0, 0, 0), OverlayTransparency = 0.32,
    },
    SoftLight = {
        Name = "Soft Light", Window = Color3.fromRGB(238, 238, 241), Surface = Color3.fromRGB(245, 245, 248),
        SurfaceAlt = Color3.fromRGB(232, 232, 237), Border = Color3.fromRGB(208, 208, 215),
        Text = Color3.fromRGB(30, 30, 36), Muted = Color3.fromRGB(112, 112, 122),
        Accent = Color3.fromRGB(41, 190, 190), AccentText = Color3.fromRGB(6, 28, 30),
        Success = Color3.fromRGB(70, 170, 100), Danger = Color3.fromRGB(205, 70, 70),
        Overlay = Color3.fromRGB(18, 18, 24), OverlayTransparency = 0.62,
    },
}

local ThemeManager = {}
ThemeManager.__index = ThemeManager

PRESETS.Glass = {
    Name = "Glass",
    Window = Color3.fromRGB(10, 12, 17), WindowTransparency = 0.24,
    Surface = Color3.fromRGB(20, 23, 31), SurfaceTransparency = 0.24,
    SurfaceAlt = Color3.fromRGB(35, 39, 49), SurfaceAltTransparency = 0.34,
    Border = Color3.fromRGB(105, 116, 137),
    Text = Color3.fromRGB(245, 247, 252), Muted = Color3.fromRGB(164, 174, 191),
    Accent = Color3.fromRGB(68, 168, 255), AccentText = Color3.fromRGB(5, 18, 32),
    Success = Color3.fromRGB(68, 195, 129), Danger = Color3.fromRGB(239, 92, 92),
    Overlay = Color3.fromRGB(0, 0, 0), OverlayTransparency = 0.36,
}
PRESETS.Tinted = {
    Name = "Tinted",
    Window = Color3.fromRGB(10, 20, 27), WindowTransparency = 0.08,
    Surface = Color3.fromRGB(15, 36, 47), SurfaceTransparency = 0.12,
    SurfaceAlt = Color3.fromRGB(23, 53, 66), SurfaceAltTransparency = 0.2,
    Border = Color3.fromRGB(45, 101, 119),
    Text = Color3.fromRGB(231, 248, 252), Muted = Color3.fromRGB(143, 188, 199),
    Accent = Color3.fromRGB(39, 255, 244), AccentText = Color3.fromRGB(7, 24, 27),
    Success = Color3.fromRGB(89, 210, 143), Danger = Color3.fromRGB(255, 95, 104),
    Overlay = Color3.fromRGB(0, 9, 15), OverlayTransparency = 0.3,
}

local function cloneTheme(source: {[string]: any}): {[string]: any}
    local result = {}
    for key, value in pairs(source) do
        result[key] = value
    end
    return result
end

local function clonePresets(): {[string]: {[string]: any}}
    local result: {[string]: {[string]: any}} = {}
    for name, theme in pairs(PRESETS) do
        result[name] = cloneTheme(theme)
    end
    return result
end

function ThemeManager.new(initialTheme: any?): any
    local self = setmetatable({
        Presets = clonePresets(),
        Current = cloneTheme(PRESETS.Dark),
        Changed = Signal.new(),
        _bindings = setmetatable({}, { __mode = "k" }),
    }, ThemeManager)

    if initialTheme ~= nil then
        self:Set(initialTheme, false)
    end
    return self
end

function ThemeManager:Get(name: string?): {[string]: any}
    if name == nil then
        return self.Current
    end
    return self.Presets[name] or self.Current
end

function ThemeManager:GetNames(): {string}
    local names = {}
    for name in pairs(self.Presets) do table.insert(names, name) end
    table.sort(names)
    return names
end

function ThemeManager:Register(name: string, definition: {[string]: any})
    assert(type(name) == "string" and name ~= "", "Theme name must be a non-empty string")
    assert(type(definition) == "table", "Theme definition must be a table")
    local merged = cloneTheme(self.Current)
    for key, value in pairs(definition) do
        merged[key] = value
    end
    merged.Name = name
    self.Presets[name] = merged
end

function ThemeManager:Bind(instance: Instance, properties: {[string]: string})
    self._bindings[instance] = properties
    self:_ApplyInstance(instance, properties, false)
    return instance
end

function ThemeManager:_ApplyInstance(instance: Instance, properties: {[string]: string}, animate: boolean)
    local targetProperties = {}
    for property, token in pairs(properties) do
        local value = self.Current[token]
        if value ~= nil then
            targetProperties[property] = value
        end
    end

    if animate and next(targetProperties) ~= nil then
        local tween = TweenService:Create(instance, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), targetProperties)
        tween:Play()
    else
        for property, value in pairs(targetProperties) do
            pcall(function()
                (instance :: any)[property] = value
            end)
        end
    end
end

function ThemeManager:Set(theme: any, animate: boolean?)
    local nextTheme: {[string]: any}
    if type(theme) == "string" then
        local preset = self.Presets[theme]
        assert(preset ~= nil, "Unknown theme: " .. theme)
        nextTheme = cloneTheme(preset)
    elseif type(theme) == "table" then
        nextTheme = cloneTheme(self.Current)
        for key, value in pairs(theme) do
            nextTheme[key] = value
        end
        nextTheme.Name = theme.Name or "Custom"
    else
        error("ThemeManager:Set expects a preset name or theme table")
    end

    self.Current = nextTheme
    for instance, properties in pairs(self._bindings) do
        self:_ApplyInstance(instance, properties, animate == true)
    end
    self.Changed:Fire(self.Current)
    return self.Current
end

function ThemeManager:SetAccent(color: Color3, animate: boolean?)
    assert(typeof(color) == "Color3", "Accent must be a Color3")
    local current = cloneTheme(self.Current)
    current.Accent = color
    local luminance = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
    current.AccentText = luminance > 0.58 and Color3.fromRGB(12, 12, 14) or Color3.new(1, 1, 1)
    current.Name = tostring(self.Current.Name or "Custom") .. " (Accent)"
    return self:Set(current, animate)
end

function ThemeManager:Destroy()
    self.Changed:Destroy()
    table.clear(self._bindings)
end

return ThemeManager
