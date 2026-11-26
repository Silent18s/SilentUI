--!strict
-- SilentUI public entry point. Roblox client-side ModuleScript.

local Janitor = require(script.Core.Janitor)
local InstancePool = require(script.Core.InstancePool)
local ThemeManager = require(script.Core.ThemeManager)
local ConfigStore = require(script.Core.ConfigStore)
local Localization = require(script.Core.Localization)
local Signal = require(script.Core.Signal)
local IconRegistry = require(script.Core.IconRegistry)
local Window = require(script.UI.Window)

local Library = {}
Library.__index = Library

export type Library = typeof(setmetatable({} :: {
    ThemeManager: any,
    InstancePool: any,
    ConfigStore: any,
    Localization: any,
    IconRegistry: any,
    Flags: {[string]: any},
    ActiveKeybindContext: string,
    Controls: {any},
    ControlsChanged: any,
    _windows: {any},
    _janitor: any,
    Destroyed: boolean,
}, Library))

function Library.new(options: {[string]: any}?): Library
    local opts = options or {}
    local themeManager = ThemeManager.new(opts.Theme)
    local flags: {[string]: any} = {}

    local self = setmetatable({
        ThemeManager = themeManager,
        InstancePool = InstancePool.new(tonumber(opts.NotificationPoolSize) or 8),
        ConfigStore = ConfigStore.new(flags),
        Localization = Localization.new(opts.Language or "en"),
        IconRegistry = IconRegistry.new(opts.IconPack or "default"),
        Flags = flags,
        ActiveKeybindContext = "Global",
        Controls = {},
        ControlsChanged = Signal.new(),
        _windows = {},
        _janitor = Janitor.new(),
        Destroyed = false,
    }, Library)

    return self :: any
end

function Library:CreateWindow(options: {[string]: any}?): any
    assert(not self.Destroyed, "SilentUI library has been destroyed")
    if options and options.Theme ~= nil then
        self.ThemeManager:Set(options.Theme, false)
    end
    local window = Window.new(self, options)
    table.insert(self._windows, window)
    return window
end

function Library:Window(options: {[string]: any}?): any
    return self:CreateWindow(options)
end

function Library:SetTheme(theme: string | {[string]: any}, animate: boolean?): any
    assert(not self.Destroyed, "SilentUI library has been destroyed")
    return self.ThemeManager:Set(theme, animate)
end

function Library:RegisterTheme(name: string, theme: {[string]: any})
    assert(not self.Destroyed, "SilentUI library has been destroyed")
    self.ThemeManager:Register(name, theme)
end

function Library:GetThemes(): {string}
    return self.ThemeManager:GetNames()
end

function Library:SetAccent(color: Color3, animate: boolean?): any
    assert(not self.Destroyed, "SilentUI library has been destroyed")
    self.ThemeManager:SetAccent(color, animate)
    return self
end

function Library:GetTheme(): {[string]: any}
    return self.ThemeManager:Get()
end

function Library:OnThemeChanged(callback: (any) -> ()): any
    return self.ThemeManager.Changed:Connect(callback)
end

function Library:RegisterLocale(language: string, dictionary: {[string]: any})
    assert(not self.Destroyed, "SilentUI library has been destroyed")
    self.Localization:Register(language, dictionary)
    return self
end

function Library:SetLanguage(language: string)
    assert(not self.Destroyed, "SilentUI library has been destroyed")
    self.Localization:SetLanguage(language)
    return self
end

function Library:GetLanguage(): string
    return self.Localization.Language
end

function Library:Translate(key: string, variables: {[string]: any}?): string
    return self.Localization:Translate(key, variables)
end

function Library:BindLocale(instance: Instance, key: string, property: string?): Instance
    return self.Localization:Bind(instance, key, property)
end

function Library:OnLocaleChanged(callback: (string) -> ()): any
    return self.Localization:OnChanged(callback)
end

function Library:RegisterIconPack(packName: string, icons: {[string]: any}, makeDefault: boolean?): (boolean, string?)
    assert(not self.Destroyed, "SilentUI library has been destroyed")
    return self.IconRegistry:RegisterPack(packName, icons, makeDefault)
end

Library.RegisterIcons = Library.RegisterIconPack

function Library:SetDefaultIconPack(packName: string): boolean
    assert(not self.Destroyed, "SilentUI library has been destroyed")
    return self.IconRegistry:SetDefaultPack(packName)
end

function Library:GetIcon(icon: any, packName: string?): any?
    return self.IconRegistry:Get(icon, packName)
end

function Library:GetIconPacks(): {string}
    return self.IconRegistry:GetPackNames()
end

function Library:RemoveIconPack(packName: string): boolean
    assert(not self.Destroyed, "SilentUI library has been destroyed")
    return self.IconRegistry:RemovePack(packName)
end

function Library:SetKeybindContext(context: string)
    assert(type(context) == "string" and context ~= "", "Keybind context must be a non-empty string")
    self.ActiveKeybindContext = context
    return self
end

function Library:GetKeybindContext(): string
    return self.ActiveKeybindContext
end

function Library:SetConfigAdapter(adapter: any)
    assert(not self.Destroyed, "SilentUI library has been destroyed")
    return self.ConfigStore:SetAdapter(adapter)
end

function Library:SaveConfig(profile: string)
    return self.ConfigStore:Save(profile)
end

function Library:LoadConfig(profile: string, silent: boolean?)
    return self.ConfigStore:Load(profile, silent)
end

function Library:ListConfigs(): {string}
    return self.ConfigStore:List()
end

function Library:DeleteConfig(profile: string)
    return self.ConfigStore:Delete(profile)
end

function Library:RenameConfig(oldName: string, newName: string)
    return self.ConfigStore:Rename(oldName, newName)
end

function Library:SetAutoload(profile: string?)
    return self.ConfigStore:SetAutoload(profile)
end

function Library:GetAutoload(): string?
    return self.ConfigStore:GetAutoload()
end

function Library:GetConfig(profile: string): (boolean, any)
    return self.ConfigStore:GetProfile(profile)
end

function Library:GetValues(): {[string]: any}
    return self.ConfigStore:GetValues()
end

function Library:SetValues(values: {[string]: any}, silent: boolean?)
    return self.ConfigStore:SetValues(values, silent)
end

function Library:CreateSnapshot(): {[string]: any}
    return self.ConfigStore:CreateSnapshot()
end

function Library:RestoreSnapshot(snapshot: any, silent: boolean?)
    return self.ConfigStore:RestoreSnapshot(snapshot, silent)
end

function Library:ResetConfiguration(silent: boolean?)
    return self.ConfigStore:Reset(silent)
end

function Library:RegisterFlagMigration(oldFlag: string, newFlag: string)
    return self.ConfigStore:RegisterFlagMigration(oldFlag, newFlag)
end

function Library:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true

    local windows = table.clone(self._windows)
    for _, window in ipairs(windows) do
        window:Destroy()
    end
    table.clear(self._windows)

    self._janitor:Destroy()
    self.InstancePool:Destroy()
    self.ThemeManager:Destroy()
    self.Localization:Destroy()
    self.IconRegistry:Destroy()
    self.ControlsChanged:Destroy()
    table.clear(self.Controls)
    table.clear(self.Flags)
end

Library.Unload = Library.Destroy

return Library.new()
