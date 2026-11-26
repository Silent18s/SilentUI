--!strict
-- SilentUI bundled Luau distribution.
-- Generated from src/SilentUI; no ModuleScript hierarchy required.

-- ===== Module: Core.Janitor =====
local __SUI_Core_Janitor
do
-- Deterministic cleanup for connections, Instances, threads and callbacks.

type Janitor = {
    _items: {any},
    _destroyed: boolean,
    Add: (self: Janitor, item: any, cleanup: ((any) -> ())?) -> any,
    Remove: (self: Janitor, item: any, dispose: boolean?) -> boolean,
    Destroy: (self: Janitor) -> (),
}

local Janitor = {}
Janitor.__index = Janitor

local function dispose(item: any, cleanup: ((any) -> ())?)
    if cleanup ~= nil then
        pcall(cleanup, item)
        return
    end

    local kind = typeof(item)
    if kind == "RBXScriptConnection" then
        pcall(function()
            item:Disconnect()
        end)
    elseif kind == "Instance" then
        pcall(function()
            item:Destroy()
        end)
    elseif kind == "thread" then
        pcall(task.cancel, item)
    elseif type(item) == "function" then
        pcall(item)
    elseif type(item) == "table" then
        local method = item.Destroy or item.Disconnect or item.Cancel
        if type(method) == "function" then
            pcall(method, item)
        end
    end
end

function Janitor.new(): Janitor
    return setmetatable({
        _items = {},
        _destroyed = false,
    }, Janitor) :: any
end

function Janitor:Add(item: any, cleanup: ((any) -> ())?): any
    if self._destroyed then
        dispose(item, cleanup)
        return item
    end

    table.insert(self._items, {
        Item = item,
        Cleanup = cleanup,
    })
    return item
end

function Janitor:Remove(item: any, shouldDispose: boolean?): boolean
    for index = #self._items, 1, -1 do
        local entry = self._items[index]
        if entry.Item == item then
            table.remove(self._items, index)
            if shouldDispose == true then
                dispose(entry.Item, entry.Cleanup)
            end
            return true
        end
    end
    return false
end

function Janitor:Destroy()
    if self._destroyed then
        return
    end

    self._destroyed = true
    for index = #self._items, 1, -1 do
        local entry = self._items[index]
        self._items[index] = nil
        dispose(entry.Item, entry.Cleanup)
    end
end

__SUI_Core_Janitor = Janitor
end

-- ===== Module: Core.Signal =====
local __SUI_Core_Signal
do
-- Small signal implementation used for consistent control callbacks.

type Connection = {
    Connected: boolean,
    Disconnect: (self: Connection) -> (),
}

type Signal = {
    _listeners: {[number]: (...any) -> ()},
    _nextId: number,
    _destroyed: boolean,
    Connect: (self: Signal, callback: (...any) -> ()) -> Connection,
    Fire: (self: Signal, ...any) -> (),
    Destroy: (self: Signal) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal
    return setmetatable({
        _listeners = {},
        _nextId = 0,
        _destroyed = false,
    }, Signal) :: any
end

function Signal:Connect(callback: (...any) -> ()): Connection
    assert(type(callback) == "function", "Signal:Connect expects a function")
    assert(not self._destroyed, "Cannot connect to a destroyed Signal")

    self._nextId += 1
    local id = self._nextId
    self._listeners[id] = callback

    local signal = self
    local connection = {
        Connected = true,
    }

    function connection:Disconnect()
        if not self.Connected then
            return
        end
        self.Connected = false
        signal._listeners[id] = nil
    end

    return connection :: any
end

function Signal:Fire(...: any)
    if self._destroyed then
        return
    end

    local arguments = table.pack(...)
    local snapshot = {}
    for id, callback in pairs(self._listeners) do
        table.insert(snapshot, { id, callback })
    end

    for _, entry in ipairs(snapshot) do
        local id = entry[1]
        local callback = entry[2]
        if self._listeners[id] == callback then
            local ok, err = pcall(callback, table.unpack(arguments, 1, arguments.n))
            if not ok then
                warn("[SilentUI] Signal listener failed: " .. tostring(err))
            end
        end
    end
end

function Signal:Destroy()
    if self._destroyed then
        return
    end
    self._destroyed = true
    table.clear(self._listeners)
end

__SUI_Core_Signal = Signal
end

-- ===== Module: Core.InstancePool =====
local __SUI_Core_InstancePool
do
-- A deliberately narrow pool for short-lived notification card Frames.
-- Child objects and their event connections must be removed before Release.

type InstancePool = {
    _frames: {Frame},
    _limit: number,
    _destroyed: boolean,
    AcquireFrame: (self: InstancePool, parent: Instance) -> Frame,
    ReleaseFrame: (self: InstancePool, frame: Frame) -> (),
    Destroy: (self: InstancePool) -> (),
}

local InstancePool = {}
InstancePool.__index = InstancePool

local function reset(frame: Frame)
    frame.Parent = nil
    frame.Name = "PooledNotificationFrame"
    frame.Visible = false
    frame.Active = false
    frame.Selectable = false
    frame.LayoutOrder = 0
    frame.Position = UDim2.fromOffset(0, 0)
    frame.Size = UDim2.fromOffset(0, 0)
    frame.AnchorPoint = Vector2.zero
    frame.BackgroundColor3 = Color3.new(1, 1, 1)
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.ZIndex = 1
    frame.ClipsDescendants = false
end

function InstancePool.new(limit: number?): InstancePool
    return setmetatable({
        _frames = {},
        _limit = math.max(1, math.floor(limit or 8)),
        _destroyed = false,
    }, InstancePool) :: any
end

function InstancePool:AcquireFrame(parent: Instance): Frame
    assert(not self._destroyed, "InstancePool has been destroyed")

    local frame = table.remove(self._frames)
    if frame == nil then
        frame = Instance.new("Frame")
    end

    reset(frame)
    frame.Visible = true
    frame.Parent = parent
    return frame
end

function InstancePool:ReleaseFrame(frame: Frame)
    if frame.Parent ~= nil then
        frame.Parent = nil
    end

    for _, child in ipairs(frame:GetChildren()) do
        child:Destroy()
    end

    reset(frame)
    if self._destroyed or #self._frames >= self._limit then
        frame:Destroy()
        return
    end

    table.insert(self._frames, frame)
end

function InstancePool:Destroy()
    if self._destroyed then
        return
    end
    self._destroyed = true

    for index = #self._frames, 1, -1 do
        local frame = self._frames[index]
        self._frames[index] = nil
        frame:Destroy()
    end
end

__SUI_Core_InstancePool = InstancePool
end

-- ===== Module: Core.ConfigStore =====
local __SUI_Core_ConfigStore
do
-- JSON profile persistence behind an adapter boundary.
-- The default adapter is memory-only; persistence is supplied by the embedding application.

local HttpService = game:GetService("HttpService")

type Adapter = {
    Read: (key: string) -> string?,
    Write: (key: string, value: string) -> boolean,
    Delete: ((key: string) -> boolean)?,
    List: (() -> {string})?,
}

local ConfigStore = {}
ConfigStore.__index = ConfigStore

local function createMemoryAdapter(): Adapter
    local data: {[string]: string} = {}
    return {
        Read = function(key: string): string?
            return data[key]
        end,
        Write = function(key: string, value: string): boolean
            data[key] = value
            return true
        end,
        Delete = function(key: string): boolean
            data[key] = nil
            return true
        end,
        List = function(): {string}
            local result = {}
            for key in pairs(data) do
                if key ~= "__autoload" then
                    table.insert(result, key)
                end
            end
            table.sort(result)
            return result
        end,
    }
end

local function packValue(value: any, seen: {[any]: boolean}?): any
    local valueType = typeof(value)
    if valueType == "Color3" then
        return {
            __silentuiType = "Color3",
            R = value.R,
            G = value.G,
            B = value.B,
        }
    end

    if type(value) == "number" and (value ~= value or value == math.huge or value == -math.huge) then
        error("Non-finite numbers cannot be saved to a profile")
    end

    if type(value) ~= "table" then
        return value
    end

    local visited = seen or {}
    if visited[value] then
        error("Cyclic values cannot be saved to a profile")
    end
    visited[value] = true

    local result = {}
    for key, child in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            result[key] = packValue(child, visited)
        end
    end

    visited[value] = nil
    return result
end

local function unpackValue(value: any): any
    if type(value) ~= "table" then
        return value
    end

    if value.__silentuiType == "Color3" then
        return Color3.new(
            math.clamp(tonumber(value.R) or 1, 0, 1),
            math.clamp(tonumber(value.G) or 1, 0, 1),
            math.clamp(tonumber(value.B) or 1, 0, 1)
        )
    end

    local result = {}
    for key, child in pairs(value) do
        result[key] = unpackValue(child)
    end
    return result
end

local function validProfileName(name: string): boolean
    return #name > 0 and #name <= 48 and string.match(name, "^[%w_-]+$") ~= nil
end

function ConfigStore.new(flags: {[string]: any}): any
    return setmetatable({
        Flags = flags,
        Adapter = createMemoryAdapter(),
        Version = 1,
        _pendingValues = nil,
        _pendingSilent = false,
        _pendingSource = "Config",
        _autoloadName = nil,
        _migrations = {},
    }, ConfigStore)
end

function ConfigStore:SetAdapter(adapter: Adapter)
    assert(type(adapter) == "table", "Config adapter must be a table")
    assert(type(adapter.Read) == "function", "Config adapter requires Read(key)")
    assert(type(adapter.Write) == "function", "Config adapter requires Write(key, value)")
    self.Adapter = adapter
    self:PrepareAutoload()
    return true
end

function ConfigStore:_ReadProfile(profile: string): (boolean, any)
    local ok, raw = pcall(self.Adapter.Read, profile)
    if not ok then
        return false, "Adapter.Read failed: " .. tostring(raw)
    end
    if type(raw) ~= "string" then
        return false, "Profile does not exist: " .. profile
    end

    local decodeOk, decoded = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if not decodeOk or type(decoded) ~= "table" then
        return false, "Profile JSON is invalid"
    end

    if type(decoded.Values) ~= "table" then
        return false, "Profile is missing Values"
    end
    for oldFlag, newFlag in pairs(self._migrations) do
        if decoded.Values[oldFlag] ~= nil and decoded.Values[newFlag] == nil then
            decoded.Values[newFlag] = decoded.Values[oldFlag]
        end
        decoded.Values[oldFlag] = nil
    end
    return true, decoded
end

function ConfigStore:Save(profile: string): (boolean, string?)
    assert(type(profile) == "string" and validProfileName(profile), "Profile name may contain only letters, numbers, _ and - (1-48 chars)")

    local values = {}
    for flag, control in pairs(self.Flags) do
        if not control.Destroyed and type(control.Get) == "function" then
            local ok, value = pcall(control.Get, control)
            if ok then
                values[flag] = packValue(value)
            end
        end
    end

    local encodeOk, encoded = pcall(function()
        return HttpService:JSONEncode({
            Version = self.Version,
            SavedAt = os.time(),
            Values = values,
        })
    end)
    if not encodeOk then
        return false, "JSON encoding failed: " .. tostring(encoded)
    end

    local writeOk, result = pcall(self.Adapter.Write, profile, encoded)
    if not writeOk or result == false then
        return false, "Adapter.Write failed: " .. tostring(result)
    end
    return true, nil
end

function ConfigStore:_ApplyValues(values: {[string]: any}, silent: boolean, source: string?)
    for flag, packed in pairs(values) do
        local control = self.Flags[flag]
        if control and type(control.Set) == "function" and not control.Destroyed then
            local ok, err = pcall(control.Set, control, unpackValue(packed), silent, source or "Config")
            if not ok then
                warn("[SilentUI] Could not apply config flag '" .. flag .. "': " .. tostring(err))
            end
        end
    end
end

function ConfigStore:Load(profile: string, silent: boolean?): (boolean, string?)
    assert(type(profile) == "string" and validProfileName(profile), "Invalid profile name")
    local ok, result = self:_ReadProfile(profile)
    if not ok then
        return false, tostring(result)
    end

    local decoded = result
    self._pendingValues = decoded.Values
    self._pendingSilent = silent == true
    self._pendingSource = "Config"
    self:_ApplyValues(decoded.Values, silent == true, "Config")
    return true, nil
end

function ConfigStore:RegisterFlag(flag: string, control: any)
    if self._pendingValues and self._pendingValues[flag] ~= nil then
        local ok, err = pcall(control.Set, control, unpackValue(self._pendingValues[flag]), self._pendingSilent == true, self._pendingSource or "Config")
        if not ok then
            warn("[SilentUI] Autoload failed for flag '" .. flag .. "': " .. tostring(err))
        end
    end
end

function ConfigStore:List(): {string}
    if type(self.Adapter.List) ~= "function" then
        return {}
    end
    local ok, result = pcall(self.Adapter.List)
    if not ok or type(result) ~= "table" then
        return {}
    end

    local names = {}
    for _, name in ipairs(result) do
        if type(name) == "string" and validProfileName(name) then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

function ConfigStore:Delete(profile: string): (boolean, string?)
    assert(type(profile) == "string" and validProfileName(profile), "Invalid profile name")
    if type(self.Adapter.Delete) ~= "function" then
        return false, "Adapter does not support Delete"
    end
    local ok, result = pcall(self.Adapter.Delete, profile)
    if not ok or result == false then
        return false, "Adapter.Delete failed: " .. tostring(result)
    end
    if self:GetAutoload() == profile then
        local autoloadOk, autoloadError = self:SetAutoload(nil)
        if not autoloadOk then
            return false, "Profile deleted, but autoload could not be cleared: " .. tostring(autoloadError)
        end
    end
    return true, nil
end

function ConfigStore:Rename(oldName: string, newName: string): (boolean, string?)
    assert(validProfileName(oldName), "Invalid source profile name")
    assert(validProfileName(newName), "Invalid target profile name")
    if oldName == newName then
        return true, nil
    end
    if type(self.Adapter.Delete) ~= "function" then
        return false, "Adapter does not support Delete"
    end
    local previousAutoload = self:GetAutoload()
    local readOk, raw = pcall(self.Adapter.Read, oldName)
    if not readOk or type(raw) ~= "string" then
        return false, "Source profile does not exist"
    end
    local targetOk, target = pcall(self.Adapter.Read, newName)
    if targetOk and type(target) == "string" then
        return false, "Target profile already exists"
    end
    local writeOk, writeResult = pcall(self.Adapter.Write, newName, raw)
    if not writeOk or writeResult == false then
        return false, "Adapter.Write failed: " .. tostring(writeResult)
    end
    local deleteOk, deleteResult = pcall(self.Adapter.Delete, oldName)
    if not deleteOk or deleteResult == false then
        pcall(self.Adapter.Delete, newName)
        return false, "Adapter.Delete failed: " .. tostring(deleteResult)
    end
    if previousAutoload == oldName then
        local autoloadOk, autoloadError = pcall(self.Adapter.Write, "__autoload", newName)
        if not autoloadOk or autoloadError == false then
            pcall(self.Adapter.Write, oldName, raw)
            pcall(self.Adapter.Delete, newName)
            return false, "Could not update autoload profile: " .. tostring(autoloadError)
        end
        self._autoloadName = newName
    end
    return true, nil
end

function ConfigStore:SetAutoload(profile: string?): (boolean, string?)
    if profile ~= nil then
        assert(validProfileName(profile), "Invalid autoload profile name")
    end

    local ok, result = pcall(self.Adapter.Write, "__autoload", profile or "")
    if not ok or result == false then
        return false, "Could not write autoload profile: " .. tostring(result)
    end

    self._autoloadName = profile
    self:PrepareAutoload()
    return true, nil
end

function ConfigStore:GetAutoload(): string?
    local ok, value = pcall(self.Adapter.Read, "__autoload")
    if ok and type(value) == "string" and validProfileName(value) then
        self._autoloadName = value
        return value
    end
    return nil
end

function ConfigStore:PrepareAutoload()
    local profile = self:GetAutoload()
    self._pendingValues = nil
    if not profile then
        return false
    end

    local ok, result = self:_ReadProfile(profile)
    if not ok then
        warn("[SilentUI] Autoload skipped: " .. tostring(result))
        return false
    end

    self._pendingValues = result.Values
    self._pendingSilent = false
    self._pendingSource = "Autoload"
    -- Autoload is an activation path, not a silent UI restore: feature callbacks
    -- must receive the loaded values even when SetAutoload is called after the
    -- controls have already been created.
    self:_ApplyValues(result.Values, false, "Autoload")
    return true
end


function ConfigStore:GetValues(): {[string]: any}
    local values = {}
    for flag, control in pairs(self.Flags) do
        if not control.Destroyed and type(control.Get) == "function" then
            local ok, value = pcall(control.Get, control)
            if ok then values[flag] = packValue(value) end
        end
    end
    return values
end

function ConfigStore:SetValues(values: {[string]: any}, silent: boolean?)
    assert(type(values) == "table", "Config values must be a table")
    local packed = {}
    for flag, value in pairs(values) do
        if type(flag) == "string" then packed[flag] = packValue(value) end
    end
    self:_ApplyValues(packed, silent == true, "SetConfig")
    self._pendingValues = packed
    self._pendingSilent = silent == true
    self._pendingSource = "SetConfig"
    return true
end

function ConfigStore:CreateSnapshot(): {[string]: any}
    return {
        Version = self.Version,
        SavedAt = os.time(),
        Values = self:GetValues(),
    }
end

function ConfigStore:RestoreSnapshot(snapshot: any, silent: boolean?)
    if type(snapshot) ~= "table" or type(snapshot.Values) ~= "table" then
        return false, "Snapshot format is invalid"
    end
    self._pendingValues = snapshot.Values
    self._pendingSilent = silent == true
    self._pendingSource = "Snapshot"
    self:_ApplyValues(snapshot.Values, silent == true, "Snapshot")
    return true, nil
end

function ConfigStore:Reset(silent: boolean?)
    for _, control in pairs(self.Flags) do
        if not control.Destroyed and control.InitialValue ~= nil and type(control.Set) == "function" then
            pcall(control.Set, control, control.InitialValue, silent == true, "Reset")
        end
    end
    return true
end

function ConfigStore:RegisterFlagMigration(oldFlag: string, newFlag: string)
    assert(type(oldFlag) == "string" and oldFlag ~= "", "Old flag is required")
    assert(type(newFlag) == "string" and newFlag ~= "", "New flag is required")
    self._migrations[oldFlag] = newFlag
    return self
end

function ConfigStore:GetProfile(profile: string): (boolean, any)
    assert(type(profile) == "string" and validProfileName(profile), "Invalid profile name")
    return self:_ReadProfile(profile)
end

function ConfigStore:Export(profile: string): (boolean, string?)
    local ok, err = self:Save(profile)
    if not ok then
        return false, err
    end
    local readOk, raw = pcall(self.Adapter.Read, profile)
    if not readOk or type(raw) ~= "string" then
        return false, "Could not read saved profile for export"
    end
    return true, raw
end

function ConfigStore:Import(profile: string, json: string): (boolean, string?)
    assert(type(profile) == "string" and validProfileName(profile), "Invalid profile name")
    assert(type(json) == "string", "JSON must be a string")

    local decodeOk, decoded = pcall(function()
        return HttpService:JSONDecode(json)
    end)
    if not decodeOk or type(decoded) ~= "table" or type(decoded.Values) ~= "table" then
        return false, "JSON profile format is invalid"
    end

    local encodeOk, normalizedJson = pcall(function()
        return HttpService:JSONEncode(decoded)
    end)
    if not encodeOk then
        return false, "JSON normalization failed"
    end

    local writeOk, result = pcall(self.Adapter.Write, profile, normalizedJson)
    if not writeOk or result == false then
        return false, "Adapter.Write failed: " .. tostring(result)
    end
    return true, nil
end

ConfigStore.CreateMemoryAdapter = createMemoryAdapter

__SUI_Core_ConfigStore = ConfigStore
end

-- ===== Module: Core.IconRegistry =====
local __SUI_Core_IconRegistry
do
-- Local icon packs and Roblox asset descriptors; no remote icon loader is used.

local IconRegistry = {}
IconRegistry.__index = IconRegistry

local function normalizeIcon(value: any): any
    if type(value) == "number" then
        if value <= 0 or value ~= value or value == math.huge then
            return nil
        end
        return { Image = "rbxassetid://" .. tostring(math.floor(value)) }
    end

    if type(value) == "string" then
        if value == "" then return nil end
        if string.match(value, "^%d+$") then
            return { Image = "rbxassetid://" .. value }
        end
        if string.match(value, "^rbxassetid://") or string.match(value, "^rbxthumb://") then
            return { Image = value }
        end
        return nil
    end

    if type(value) ~= "table" then
        return nil
    end

    local image = normalizeIcon(value.Image or value.image or value.Id or value.id)
    if image == nil then return nil end

    local result = {
        Image = image.Image,
        ImageRectSize = value.ImageRectSize or value.imageRectSize,
        ImageRectOffset = value.ImageRectOffset or value.ImageRectPosition or value.imageRectOffset,
        Parts = type(value.Parts) == "table" and table.clone(value.Parts) or nil,
    }

    if result.ImageRectSize ~= nil and typeof(result.ImageRectSize) ~= "Vector2" then
        return nil
    end
    if result.ImageRectOffset ~= nil and typeof(result.ImageRectOffset) ~= "Vector2" then
        return nil
    end
    return result
end

function IconRegistry.new(defaultPack: string?): any
    return setmetatable({
        Packs = {},
        DefaultPack = defaultPack or "default",
        Destroyed = false,
    }, IconRegistry)
end

function IconRegistry:RegisterPack(packName: string, icons: {[string]: any}, makeDefault: boolean?): (boolean, string?)
    assert(not self.Destroyed, "IconRegistry has been destroyed")
    assert(type(packName) == "string" and packName ~= "", "Icon pack name is required")
    assert(type(icons) == "table", "Icon pack data must be a table")

    local normalized = {}
    for name, value in pairs(icons) do
        if type(name) == "string" and name ~= "" then
            local icon = normalizeIcon(value)
            if icon ~= nil then
                normalized[name] = icon
            end
        end
    end

    self.Packs[packName] = normalized
    if makeDefault == true then
        self.DefaultPack = packName
    end
    return true, nil
end

function IconRegistry:SetDefaultPack(packName: string): boolean
    assert(not self.Destroyed, "IconRegistry has been destroyed")
    if self.Packs[packName] == nil then return false end
    self.DefaultPack = packName
    return true
end

function IconRegistry:Get(icon: any, packName: string?): any?
    if self.Destroyed then return nil end
    if type(icon) == "number" then
        return normalizeIcon(icon)
    end
    if type(icon) == "table" then
        return normalizeIcon(icon)
    end
    if type(icon) ~= "string" or icon == "" then
        return nil
    end

    local descriptor = normalizeIcon(icon)
    if descriptor ~= nil then return descriptor end

    local selectedPack = packName or self.DefaultPack
    local iconName = icon
    local prefix, remainder = string.match(icon, "^([^:]+):(.+)$")
    if prefix and remainder then
        selectedPack = prefix
        iconName = remainder
    end

    local pack = self.Packs[selectedPack]
    local value = pack and pack[iconName]
    if value == nil and packName == nil and selectedPack ~= self.DefaultPack then
        local default = self.Packs[self.DefaultPack]
        value = default and default[iconName]
    end
    if value == nil then return nil end

    local copy = {}
    for key, item in pairs(value) do
        copy[key] = item
    end
    return copy
end

function IconRegistry:GetPackNames(): {string}
    local result = {}
    for name in pairs(self.Packs) do table.insert(result, name) end
    table.sort(result)
    return result
end

function IconRegistry:RemovePack(packName: string): boolean
    if self.Destroyed then return false end
    if self.Packs[packName] == nil then return false end
    self.Packs[packName] = nil
    if self.DefaultPack == packName then
        self.DefaultPack = "default"
    end
    return true
end

function IconRegistry:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    table.clear(self.Packs)
end

__SUI_Core_IconRegistry = IconRegistry
end

-- ===== Module: Core.Localization =====
local __SUI_Core_Localization
do
-- Small token-based localization service with live bindings.

local Signal = __SUI_Core_Signal

local Localization = {}
Localization.__index = Localization

function Localization.new(defaultLanguage: string?): any
    return setmetatable({
        Language = defaultLanguage or "en",
        Locales = {},
        Changed = Signal.new(),
        _bindings = setmetatable({}, { __mode = "k" }),
        _callbacks = {},
    }, Localization)
end

function Localization:Register(language: string, dictionary: {[string]: any})
    assert(type(language) == "string" and language ~= "", "Language code is required")
    assert(type(dictionary) == "table", "Locale dictionary must be a table")
    self.Locales[string.lower(language)] = table.clone(dictionary)
    if string.lower(language) == string.lower(self.Language) then
        self:Refresh()
    end
    return self
end

function Localization:Translate(key: string, variables: {[string]: any}?): string
    local language = string.lower(self.Language)
    local locale = self.Locales[language] or self.Locales.en or {}
    local fallback = self.Locales.en or {}
    local value = locale[key]
    if value == nil then value = fallback[key] end
    if value == nil then value = key end
    local result = tostring(value)
    for name, replacement in pairs(variables or {}) do
        result = result:gsub("{" .. tostring(name) .. "}", tostring(replacement))
    end
    return result
end

function Localization:Bind(instance: Instance, key: string, property: string?)
    assert(instance ~= nil and instance.Parent ~= nil, "Localization target must be parented")
    local targetProperty = property or "Text"
    local bindings = self._bindings[instance]
    if not bindings then
        bindings = {}
        self._bindings[instance] = bindings
    end
    bindings[targetProperty] = key
    self:_Apply(instance, bindings)
    return instance
end

function Localization:_Apply(instance: Instance, bindings: {[string]: string})
    if instance.Parent == nil then
        self._bindings[instance] = nil
        return
    end
    for property, key in pairs(bindings) do
        local value = self:Translate(key)
        pcall(function() (instance :: any)[property] = value end)
    end
end

function Localization:Refresh()
    for instance, bindings in pairs(self._bindings) do
        self:_Apply(instance, bindings)
    end
    self.Changed:Fire(self.Language)
    for _, callback in ipairs(self._callbacks) do
        local ok, err = pcall(callback, self.Language)
        if not ok then warn("[SilentUI] Locale callback failed: " .. tostring(err)) end
    end
end

function Localization:SetLanguage(language: string)
    assert(type(language) == "string" and language ~= "", "Language code is required")
    self.Language = language
    self:Refresh()
    return self
end

function Localization:OnChanged(callback: (string) -> ())
    assert(type(callback) == "function", "Locale callback must be a function")
    table.insert(self._callbacks, callback)
    return self.Changed:Connect(callback)
end

function Localization:Destroy()
    self.Changed:Destroy()
    table.clear(self._callbacks)
    table.clear(self.Locales)
    table.clear(self._bindings)
end

__SUI_Core_Localization = Localization
end

-- ===== Module: Core.ThemeManager =====
local __SUI_Core_ThemeManager
do
-- Runtime theme tokens. Bindings are weak-keyed so destroyed UI can be collected.

local TweenService = game:GetService("TweenService")
local Signal = __SUI_Core_Signal

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

__SUI_Core_ThemeManager = ThemeManager
end

-- ===== Module: UI.Controls =====
local __SUI_UI_Controls
do
-- Reusable control implementations. All controls share Set/Get/OnChanged/Destroy.

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Janitor = __SUI_Core_Janitor
local Signal = __SUI_Core_Signal

local Controls = {}
local Control = {}
Control.__index = Control

local function make(className: string, properties: {[string]: any}, parent: Instance?): Instance
    local instance = Instance.new(className)
    for property, value in pairs(properties) do
        (instance :: any)[property] = value
    end
    if parent then
        instance.Parent = parent
    end
    return instance
end

local function corner(instance: Instance, radius: number)
    make("UICorner", { CornerRadius = UDim.new(0, radius) }, instance)
end

local function label(parent: Instance, text: string, size: number, color: Color3, properties: {[string]: any}?): TextLabel
    local props = properties or {}
    props.BackgroundTransparency = 1
    props.Text = text
    props.TextSize = size
    props.TextColor3 = color
    props.Font = Enum.Font.Gotham
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    props.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
    return make("TextLabel", props, parent) :: TextLabel
end

local function button(parent: Instance, text: string, properties: {[string]: any}?): TextButton
    local props = properties or {}
    props.Text = text
    props.Font = Enum.Font.GothamMedium
    props.TextSize = props.TextSize or 12
    props.AutoButtonColor = false
    props.BorderSizePixel = 0
    return make("TextButton", props, parent) :: TextButton
end

local function cloneArray(value: {any}): {any}
    local copy = {}
    for _, item in ipairs(value) do
        table.insert(copy, item)
    end
    return copy
end

local function sameValue(first: any, second: any): boolean
    if typeof(first) == "Color3" and typeof(second) == "Color3" then
        return first == second
    end
    if type(first) == "table" and type(second) == "table" then
        if #first ~= #second then
            return false
        end
        for index, value in ipairs(first) do
            if value ~= second[index] then
                return false
            end
        end
        return true
    end
    return first == second
end

local function normalizeOptions(options: {any}): ({any}, {[string]: string})
    local normalized = {}
    local labels = {}
    for _, option in ipairs(options) do
        local value: any
        local text: string
        if type(option) == "table" then
            value = option.Value
            if value == nil then
                value = option.Name or option.Text or option.Title
            end
            text = tostring(option.Label or option.Text or option.Name or option.Title or value or "")
        else
            value = option
            text = tostring(option)
        end
        if value ~= nil then
            table.insert(normalized, value)
            labels[tostring(value)] = text
        end
    end
    return normalized, labels
end

function Control:Get(): any
    if type(self.Value) == "table" then
        return cloneArray(self.Value)
    end
    return self.Value
end

function Control:Set(value: any, silent: boolean?, source: string?): boolean
    if self.Destroyed or (self.Disabled and (source == "UI" or source == "Keybind")) then
        return false
    end

    local normalized = value
    if self._normalize then
        normalized = self._normalize(value)
    end
    if sameValue(self.Value, normalized) then
        if self._render then
            self._render()
        end
        return false
    end

    local previous = self:Get()
    self.Value = if type(normalized) == "table" then cloneArray(normalized) else normalized
    if self._render then
        self._render()
    end

    if silent ~= true then
        local info = {
            Flag = self.Flag,
            Source = source or "Code",
            Previous = previous,
        }
        self._changed:Fire(self:Get(), info)
        if type(self.Callback) == "function" and self.Kind ~= "Keybind" then
            local callback = self.Callback
            local nextValue = self:Get()
            task.spawn(function()
                local ok, err = pcall(callback, nextValue, info)
                if not ok then
                    warn("[SilentUI] Callback for " .. self.Kind .. " failed: " .. tostring(err))
                end
            end)
        end
    end
    return true
end

function Control:OnChanged(callback: (...any) -> ()): any
    return self._changed:Connect(callback)
end

function Control:SetVisible(visible: boolean)
    if not self.Destroyed then
        self.UserVisible = visible == true
        self.ElementFrame.Visible = self.UserVisible and self.SearchVisible ~= false
    end
    return self
end

function Control:SetSearchMatch(matches: boolean)
    if not self.Destroyed then
        self.SearchVisible = matches == true
        self.ElementFrame.Visible = self.UserVisible ~= false and self.SearchVisible
    end
    return self
end

function Control:SetTitle(title: string)
    if self.TitleLabel and not self.Destroyed then
        self.TitleLabel.Text = tostring(title)
        self.SearchText = string.lower(self.TitleLabel.Text .. " " .. (self.DescriptionLabel and self.DescriptionLabel.Text or ""))
    end
    return self
end

function Control:SetTooltip(message: string)
    self.Tooltip = tostring(message)
    if self._tooltipJanitor then
        self._janitor:Remove(self._tooltipJanitor, true)
        self._tooltipJanitor = nil
    end
    if self.Tooltip ~= "" and self.ElementFrame then
        local tooltipJanitor = Janitor.new()
        tooltipJanitor:Add(self.ElementFrame.MouseEnter:Connect(function()
            self.Window:_ShowTooltip(self.ElementFrame, self.Tooltip)
        end))
        tooltipJanitor:Add(self.ElementFrame.MouseLeave:Connect(function()
            self.Window:_HideTooltip()
        end))
        tooltipJanitor:Add(self.ElementFrame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch then
                self.Window:_ShowTooltip(self.ElementFrame, self.Tooltip)
            end
        end))
        self._tooltipJanitor = tooltipJanitor
        self._janitor:Add(tooltipJanitor)
    end
    return self
end

function Control:SetDescription(description: string)
    if self.DescriptionLabel == nil and self.ElementFrame then
        self.DescriptionLabel = label(self.ElementFrame, "", 10, self.Library.ThemeManager.Current.Muted, {
            Name = "Description",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = 2,
        })
    end
    if self.DescriptionLabel then
        self.DescriptionLabel.Text = tostring(description)
        self.DescriptionLabel.Visible = self.DescriptionLabel.Text ~= ""
        self.DescriptionLabel.TextColor3 = self.Library.ThemeManager.Current.Muted
    end
    self.SearchText = string.lower((self.TitleLabel and self.TitleLabel.Text or "") .. " " .. tostring(description))
    return self
end

Control.SetDesc = Control.SetDescription

function Control:SetDisabled(disabled: boolean)
    self.Disabled = disabled == true
    if self.ElementFrame then
        self.ElementFrame.BackgroundTransparency = self.Disabled and 0.56 or (tonumber(self.Library.ThemeManager.Current.SurfaceAltTransparency) or 0.3)
        for _, descendant in ipairs(self.ElementFrame:GetDescendants()) do
            if descendant:IsA("GuiButton") then
                descendant.Active = not self.Disabled
                descendant.Selectable = not self.Disabled
                descendant.AutoButtonColor = false
            elseif descendant:IsA("TextBox") then
                descendant.TextEditable = not self.Disabled
                descendant.Active = not self.Disabled
            end
        end
    end
    return self
end

function Control:SetEnabled(enabled: boolean)
    return self:SetDisabled(not (enabled == true))
end

function Control:Lock()
    return self:SetDisabled(true)
end

function Control:Unlock()
    return self:SetDisabled(false)
end

function Control:Show()
    return self:SetVisible(true)
end

function Control:Hide()
    return self:SetVisible(false)
end

function Control:SetValue(value: any, silent: boolean?, source: string?)
    return self:Set(value, silent, source)
end

function Control:Activate()
    if self.Destroyed or self.Disabled then
        return
    end
    if type(self.Callback) == "function" then
        local info = { Flag = self.Flag, Source = "UI", Action = "Activated" }
        local ok, err = pcall(self.Callback, true, info)
        if not ok then
            warn("[SilentUI] Button callback failed: " .. tostring(err))
        end
    end
end

function Control:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true

    if self.Window._popup and self.Window._popup.Owner == self then
        self.Window:_ClosePopup()
    end
    if self.Flag and self.Library.Flags[self.Flag] == self then
        self.Library.Flags[self.Flag] = nil
    end

    self._janitor:Destroy()
    self._changed:Destroy()
    if self.ElementFrame and self.ElementFrame.Parent ~= nil then
        self.ElementFrame:Destroy()
    end

    for index, control in ipairs(self.Section.Elements) do
        if control == self then
            table.remove(self.Section.Elements, index)
            break
        end
    end
    for index, control in ipairs(self.Library.Controls) do
        if control == self then
            table.remove(self.Library.Controls, index)
            break
        end
    end
    self.Library.ControlsChanged:Fire("Removed", self)
end

Control.GetValue = Control.Get
Control.Refresh = function(_self: any, _options: {any}?, _keepValue: boolean?)
    return false
end

local function makeBase(section: any, kind: string, options: any): (any, Frame, Frame, TextLabel, TextLabel?)
    local library = section.Window.Library
    local theme = library.ThemeManager.Current
    local row = make("Frame", {
        Name = kind,
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = tonumber(theme.SurfaceAltTransparency) or 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = #section.Elements + 1,
        ClipsDescendants = false,
    }, section.Frame) :: Frame
    corner(row, 8)
    local rowStroke = make("UIStroke", {
        Color = theme.Border,
        Transparency = 0.72,
        Thickness = 1,
    }, row) :: UIStroke
    make("UIPadding", {
        PaddingTop = UDim.new(0, 9),
        PaddingBottom = UDim.new(0, 9),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
    }, row)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 7),
    }, row)

    local title = label(row, tostring(options.Title or options.Name or kind), 12, theme.Text, {
        Name = "Title",
        Size = UDim2.new(1, 0, 0, 18),
        Font = Enum.Font.GothamMedium,
        LayoutOrder = 1,
    })
    local description: TextLabel? = nil
    if options.Description ~= nil and tostring(options.Description) ~= "" then
        description = label(row, tostring(options.Description), 10, theme.Muted, {
            Name = "Description",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = 2,
        })
    end

    local body = make("Frame", {
        Name = "ControlBody",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 3,
    }, row) :: Frame

    local api = setmetatable({
        Library = library,
        Window = section.Window,
        Tab = section.Tab,
        Section = section,
        Kind = kind,
        Flag = options.Flag,
        Callback = options.Callback,
        Tooltip = options.Tooltip,
        ElementFrame = row,
        Body = body,
        TitleLabel = title,
        DescriptionLabel = description,
        SearchText = string.lower(table.concat({ tostring(options.Title or options.Name or kind), tostring(options.Description or "") }, " ")),
        UserVisible = options.Visible ~= false,
        SearchVisible = true,
        _stroke = rowStroke,
        _janitor = Janitor.new(),
        _changed = Signal.new(),
        Destroyed = false,
        Disabled = options.Disabled == true,
        Value = nil,
    }, Control)

    row.Visible = options.Visible ~= false
    api._janitor:Add(row)
    api._janitor:Add(library.ThemeManager.Changed:Connect(function()
        if api.Destroyed then
            return
        end
        local activeTheme = library.ThemeManager.Current
        row.BackgroundColor3 = activeTheme.SurfaceAlt
        row.BackgroundTransparency = tonumber(activeTheme.SurfaceAltTransparency) or 0.3
        rowStroke.Color = activeTheme.Border
        title.TextColor3 = activeTheme.Text
        if description then
            description.TextColor3 = activeTheme.Muted
        end
        if api._applyTheme then
            api._applyTheme(activeTheme)
        end
    end))

    if api.Flag ~= nil then
        assert(kind ~= "Button" and kind ~= "Label" and kind ~= "Paragraph", "Flags are supported only by stateful controls")
        assert(type(api.Flag) == "string" and api.Flag ~= "", "Control Flag must be a non-empty string")
        assert(library.Flags[api.Flag] == nil, "Duplicate SilentUI flag: " .. api.Flag)
        library.Flags[api.Flag] = api
    end
    if api.Tooltip and tostring(api.Tooltip) ~= "" then
        api:SetTooltip(tostring(api.Tooltip))
    end

    return api, row, body, title, description
end

local function initialize(api: any, defaultValue: any, normalize: (any) -> any, render: () -> ())
    api._normalize = normalize
    api._render = render
    api:Set(defaultValue, true, "Init")
    api.InitialValue = api:Get()
    if api.Disabled then
        api:SetDisabled(true)
    end

    if api.Flag then
        api.Library.ConfigStore:RegisterFlag(api.Flag, api)
    end
end

local function normalizeBoolean(value: any): boolean
    return value == true
end

local function normalizeNumber(value: any, minimum: number, maximum: number, step: number): number
    local numeric = tonumber(value) or minimum
    numeric = math.clamp(numeric, minimum, maximum)
    if step > 0 then
        numeric = minimum + math.floor(((numeric - minimum) / step) + 0.5) * step
    end
    return math.clamp(numeric, minimum, maximum)
end

local function createToggle(section: any, options: any): any
    local api, _, body = makeBase(section, "Toggle", options)
    local theme = api.Library.ThemeManager.Current
    body.Size = UDim2.new(1, 0, 0, 26)
    body.AutomaticSize = Enum.AutomaticSize.None
    local track = make("Frame", {
        Name = "SwitchTrack",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(42, 23),
        BackgroundColor3 = theme.Border,
        BorderSizePixel = 0,
    }, body) :: Frame
    corner(track, 12)
    local knob = make("Frame", {
        Name = "Knob",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromOffset(3, 11.5),
        Size = UDim2.fromOffset(17, 17),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, track) :: Frame
    corner(knob, 10)
    local click = button(body, "", {
        Name = "ToggleButton",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 5,
    })
    api._janitor:Add(click.Activated:Connect(function()
        api:Set(not api:Get(), false, "UI")
    end))

    local function render()
        local active = api.Value == true
        local activeTheme = api.Library.ThemeManager.Current
        TweenService:Create(track, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = active and activeTheme.Accent or activeTheme.Border,
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = UDim2.fromOffset(active and 22 or 3, 11.5),
            BackgroundColor3 = activeTheme.AccentText,
        }):Play()
    end
    api._applyTheme = render
    initialize(api, options.Default == true, normalizeBoolean, render)
    return api
end

local function createSlider(section: any, options: any): any
    local api, _, body = makeBase(section, "Slider", options)
    body.Size = UDim2.new(1, 0, 0, 34)
    body.AutomaticSize = Enum.AutomaticSize.None
    local minimum = tonumber(options.Min) or 0
    local maximum = tonumber(options.Max) or 100
    assert(maximum > minimum, "Slider Max must be greater than Min")
    local step = math.max(0, tonumber(options.Step) or 1)
    local theme = api.Library.ThemeManager.Current

    local valueLabel = label(body, "0", 10, theme.Muted, {
        Name = "Value",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(70, 16),
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    local track = make("Frame", {
        Name = "Track",
        Position = UDim2.fromOffset(0, 22),
        Size = UDim2.new(1, 0, 0, 8),
        BackgroundColor3 = theme.Border,
        BorderSizePixel = 0,
        Active = true,
    }, body) :: Frame
    corner(track, 5)
    local fill = make("Frame", {
        Name = "Fill",
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = theme.Accent,
        BorderSizePixel = 0,
    }, track) :: Frame
    corner(fill, 5)
    local hitbox = button(track, "", {
        Name = "SliderHitbox",
        Size = UDim2.new(1, 0, 0, 28),
        Position = UDim2.new(0, 0, 0.5, -14),
        BackgroundTransparency = 1,
        ZIndex = 5,
    })

    local draggingInput: InputObject? = nil
    local function updateFromPosition(position: Vector3)
        local width = math.max(track.AbsoluteSize.X, 1)
        local alpha = math.clamp((position.X - track.AbsolutePosition.X) / width, 0, 1)
        api:Set(minimum + (maximum - minimum) * alpha, false, "UI")
    end

    api._janitor:Add(hitbox.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingInput = input
            updateFromPosition(input.Position)
        end
    end))
    api._janitor:Add(UserInputService.InputChanged:Connect(function(input)
        if draggingInput == nil then
            return
        end
        local sameTouch = draggingInput.UserInputType == Enum.UserInputType.Touch and input == draggingInput
        local mouseMove = draggingInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement
        if sameTouch or mouseMove then
            updateFromPosition(input.Position)
        end
    end))
    api._janitor:Add(UserInputService.InputEnded:Connect(function(input)
        if draggingInput == input or (draggingInput ~= nil and draggingInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
            draggingInput = nil
        end
    end))

    local decimals = 0
    if step > 0 then
        local text = string.format("%.6f", step):gsub("0+$", "")
        decimals = math.max(0, (#text - (string.find(text, ".", 1, true) or (#text + 1))))
    end
    local function render()
        local alpha = (api.Value - minimum) / (maximum - minimum)
        fill.Size = UDim2.new(math.clamp(alpha, 0, 1), 0, 1, 0)
        valueLabel.Text = string.format("%." .. tostring(decimals) .. "f", api.Value)
        local activeTheme = api.Library.ThemeManager.Current
        fill.BackgroundColor3 = activeTheme.Accent
        track.BackgroundColor3 = activeTheme.Border
        valueLabel.TextColor3 = activeTheme.Muted
    end
    api._applyTheme = render
    initialize(api, tonumber(options.Default) or minimum, function(value)
        return normalizeNumber(value, minimum, maximum, step)
    end, render)
    return api
end

local function createDropdown(section: any, options: any): any
    local api, _, body = makeBase(section, "Dropdown", options)
    body.Size = UDim2.new(1, 0, 0, 34)
    body.AutomaticSize = Enum.AutomaticSize.None
    local optionValues, optionLabels = normalizeOptions(options.Options or {})
    local multi = options.Multi == true
    local theme = api.Library.ThemeManager.Current
    local selector = button(body, "Select...   ▾", {
        Name = "DropdownButton",
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = theme.Surface,
        TextColor3 = theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 8,
    })
    corner(selector, 7)
    make("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
    }, selector)

    local function getDisplay(value: any): string
        if multi then
            if type(value) ~= "table" or #value == 0 then
                return "Select..."
            end
            local display = {}
            for _, item in ipairs(value) do
                table.insert(display, optionLabels[tostring(item)] or tostring(item))
            end
            return table.concat(display, ", ")
        end
        if value == nil then
            return "Select..."
        end
        return optionLabels[tostring(value)] or tostring(value)
    end

    local function isSelected(value: any): boolean
        if multi then
            return table.find(api.Value, value) ~= nil
        end
        return api.Value == value
    end

    local function buildPopup()
        local searchable = options.Searchable == true or #optionValues >= (tonumber(options.SearchThreshold) or 12)
        local searchHeight = searchable and 34 or 0
        local maxVisible = math.clamp(math.floor(tonumber(options.MaxVisible) or 6), 2, 12)
        local popupHeight = math.min(270, math.max(72, maxVisible * 32 + searchHeight + 14))
        local panel, popupJanitor = api.Window:_OpenPopup(api, selector, selector.AbsoluteSize.X, popupHeight)
        local listTop = searchable and 42 or 6
        local scroll = make("ScrollingFrame", {
            Name = "Options",
            Position = UDim2.fromOffset(5, listTop),
            Size = UDim2.new(1, -10, 1, -(listTop + 6)),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 3,
            CanvasSize = UDim2.fromOffset(0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ZIndex = 51,
        }, panel) :: ScrollingFrame
        popupJanitor:Add(scroll)
        local searchBox: TextBox? = nil
        if searchable then
            searchBox = make("TextBox", {
                Name = "OptionSearch",
                Position = UDim2.fromOffset(6, 6),
                Size = UDim2.new(1, -12, 0, 30),
                BackgroundColor3 = api.Library.ThemeManager.Current.Surface,
                BorderSizePixel = 0,
                ClearTextOnFocus = false,
                PlaceholderText = tostring(options.SearchPlaceholder or "Search options..."),
                Text = "",
                TextColor3 = api.Library.ThemeManager.Current.Text,
                PlaceholderColor3 = api.Library.ThemeManager.Current.Muted,
                TextSize = 11,
                Font = Enum.Font.Gotham,
                ZIndex = 52,
            }, panel) :: TextBox
            corner(searchBox, 6)
            popupJanitor:Add(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
                local query = string.lower(searchBox and searchBox.Text or "")
                for _, child in ipairs(scroll:GetChildren()) do
                    if child:IsA("TextButton") then
                        child.Visible = query == "" or string.find(string.lower(child.Text), query, 1, true) ~= nil
                    end
                end
            end))
            popupJanitor:Add(api.Library.ThemeManager.Changed:Connect(function(active)
                if searchBox and searchBox.Parent then
                    searchBox.BackgroundColor3 = active.Surface
                    searchBox.TextColor3 = active.Text
                    searchBox.PlaceholderColor3 = active.Muted
                end
            end))
        end
        local listLayout = make("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 3),
        }, scroll)
        for index, value in ipairs(optionValues) do
            local selected = isSelected(value)
            local optionButton = button(scroll, (selected and "✓  " or "   ") .. (optionLabels[tostring(value)] or tostring(value)), {
                Size = UDim2.new(1, -4, 0, 29),
                BackgroundColor3 = selected and api.Library.ThemeManager.Current.Accent or api.Library.ThemeManager.Current.SurfaceAlt,
                BackgroundTransparency = selected and 0.12 or 0.65,
                TextColor3 = selected and api.Library.ThemeManager.Current.AccentText or api.Library.ThemeManager.Current.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = index,
                ZIndex = 52,
            })
            corner(optionButton, 6)
            popupJanitor:Add(optionButton.Activated:Connect(function()
                if multi then
                    local selection = cloneArray(api.Value)
                    local selectedIndex = table.find(selection, value)
                    if selectedIndex then
                        table.remove(selection, selectedIndex)
                    else
                        table.insert(selection, value)
                    end
                    api:Set(selection, false, "UI")
                    api.Window:_ClosePopup()
                    buildPopup()
                else
                    api:Set(value, false, "UI")
                    api.Window:_ClosePopup()
                end
            end))
        end
        popupJanitor:Add(listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            scroll.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 4)
        end))
    end

    api._janitor:Add(selector.Activated:Connect(function()
        if api.Window._popup and api.Window._popup.Owner == api then
            api.Window:_ClosePopup()
        else
            buildPopup()
        end
    end))

    local function normalize(value: any): any
        if multi then
            local result = {}
            if type(value) == "table" then
                for _, item in ipairs(value) do
                    if table.find(optionValues, item) and not table.find(result, item) then
                        table.insert(result, item)
                    end
                end
            elseif value ~= nil and table.find(optionValues, value) then
                table.insert(result, value)
            end
            return result
        end
        if value ~= nil and table.find(optionValues, value) then
            return value
        end
        return nil
    end

    function api:Refresh(newOptions: {any}, keepValue: boolean?)
        optionValues, optionLabels = normalizeOptions(newOptions)
        if keepValue ~= true then
            self:Set(if multi then {} else nil, true, "Refresh")
        else
            self:Set(self:Get(), true, "Refresh")
        end
        if self.Window._popup and self.Window._popup.Owner == self then
            self.Window:_ClosePopup()
        end
        return self
    end
    function api:AddOption(option: any)
        local nextOptions = table.clone(options.Options or {})
        table.insert(nextOptions, option)
        options.Options = nextOptions
        self:Refresh(nextOptions, true)
        return self
    end
    function api:RemoveOption(value: any)
        local nextOptions = {}
        for _, item in ipairs(optionValues) do
            if item ~= value then
                table.insert(nextOptions, { Value = item, Label = optionLabels[tostring(item)] or tostring(item) })
            end
        end
        options.Options = nextOptions
        self:Refresh(nextOptions, true)
        return self
    end
    function api:GetOptions(): {any}
        return table.clone(optionValues)
    end

    local function render()
        selector.Text = getDisplay(api.Value) .. "   ▾"
        local activeTheme = api.Library.ThemeManager.Current
        selector.BackgroundColor3 = activeTheme.Surface
        selector.TextColor3 = activeTheme.Text
    end
    api._applyTheme = render
    local default = options.Default
    if multi and type(default) ~= "table" then
        default = {}
    end
    initialize(api, default, normalize, render)
    return api
end

local function createTextbox(section: any, options: any): any
    local api, _, body = makeBase(section, "Textbox", options)
    body.Size = UDim2.new(1, 0, 0, 34)
    body.AutomaticSize = Enum.AutomaticSize.None
    local theme = api.Library.ThemeManager.Current
    local input = make("TextBox", {
        Name = "TextboxInput",
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = theme.Surface,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Text = tostring(options.Default or ""),
        PlaceholderText = tostring(options.Placeholder or "Enter text..."),
        TextColor3 = theme.Text,
        PlaceholderColor3 = theme.Muted,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 8,
    }, body) :: TextBox
    corner(input, 7)
    make("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
    }, input)

    api._janitor:Add(input.FocusLost:Connect(function()
        api:Set(input.Text, false, "UI")
    end))

    local function render()
        if input.Text ~= tostring(api.Value or "") then
            input.Text = tostring(api.Value or "")
        end
        local activeTheme = api.Library.ThemeManager.Current
        input.BackgroundColor3 = activeTheme.Surface
        input.TextColor3 = activeTheme.Text
        input.PlaceholderColor3 = activeTheme.Muted
    end
    api._applyTheme = render
    initialize(api, tostring(options.Default or ""), function(value)
        return tostring(value or "")
    end, render)
    return api
end

local function createKeybind(section: any, options: any): any
    local api, _, body = makeBase(section, "Keybind", options)
    body.Size = UDim2.new(1, 0, 0, 34)
    body.AutomaticSize = Enum.AutomaticSize.None
    local theme = api.Library.ThemeManager.Current
    local capture = button(body, "None", {
        Name = "KeybindCapture",
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = theme.Surface,
        TextColor3 = theme.Text,
        ZIndex = 8,
    })
    corner(capture, 7)
    local listening = false
    api.Context = tostring(options.Context or "Global")
    api.Mode = string.lower(tostring(options.Mode or "Press"))
    if api.Mode ~= "hold" and api.Mode ~= "toggle" then api.Mode = "press" end
    api.Modifiers = {}
    local initialModifiers = options.Modifiers or (options.Modifier and { options.Modifier }) or {}
    if type(initialModifiers) == "table" then
        for _, modifier in ipairs(initialModifiers) do
            local name = if typeof(modifier) == "EnumItem" then modifier.Name else tostring(modifier)
            if Enum.KeyCode[name] ~= nil and not table.find(api.Modifiers, name) then
                table.insert(api.Modifiers, name)
            end
        end
    end
    api.Active = false
    api.ActiveChanged = Signal.new()
    api._janitor:Add(api.ActiveChanged)
    local render: () -> ()

    function api:SetContext(context: string)
        self.Context = tostring(context or "Global")
        return self
    end

    function api:SetMode(mode: string)
        local normalized = string.lower(tostring(mode or "press"))
        assert(normalized == "press" or normalized == "toggle" or normalized == "hold", "Keybind mode must be Press, Toggle or Hold")
        self.Mode = normalized
        self.Active = false
        self.ActiveChanged:Fire(false, { Source = "Code", Action = "ModeChanged" })
        return self
    end

    function api:SetModifiers(modifiers: {any})
        local normalized = {}
        for _, modifier in ipairs(modifiers or {}) do
            local name = if typeof(modifier) == "EnumItem" then modifier.Name else tostring(modifier)
            if Enum.KeyCode[name] ~= nil and not table.find(normalized, name) then
                table.insert(normalized, name)
            end
        end
        self.Modifiers = normalized
        render()
        return self
    end

    local function normalize(value: any): string
        if typeof(value) == "EnumItem" then
            return value.Name
        end
        local key = tostring(value or "")
        if key == "nil" or key == "Unknown" then
            return ""
        end
        if key ~= "" and Enum.KeyCode[key] == nil then
            return ""
        end
        return key
    end

    local function modifiersMatch(): boolean
        for _, name in ipairs(api.Modifiers) do
            local keyCode = Enum.KeyCode[name]
            if keyCode == nil or not UserInputService:IsKeyDown(keyCode) then
                return false
            end
        end
        return true
    end

    local function displayKey(): string
        local parts = table.clone(api.Modifiers)
        if api.Value ~= "" then table.insert(parts, api.Value) end
        return #parts > 0 and table.concat(parts, " + ") or "None"
    end

    local function emit(active: boolean, actionName: string)
        api.Active = active
        local info = {
            Flag = api.Flag,
            Source = "UI",
            Action = actionName,
            Mode = api.Mode,
            Active = active,
            Modifiers = table.clone(api.Modifiers),
        }
        api.ActiveChanged:Fire(active, info)
        if type(api.Callback) == "function" then
            local ok, err = pcall(api.Callback, api.Value, info, active)
            if not ok then warn("[SilentUI] Keybind callback failed: " .. tostring(err)) end
        end
    end

    api._janitor:Add(capture.Activated:Connect(function()
        listening = true
        capture.Text = "Press a key..."
    end))
    api._janitor:Add(UserInputService.InputBegan:Connect(function(input, processed)
        if UserInputService:GetFocusedTextBox() ~= nil then
            return
        end
        if listening then
            if input.KeyCode == Enum.KeyCode.Unknown then
                return
            end
            listening = false
            if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
                api:Set("", false, "UI")
            else
                api:Set(input.KeyCode.Name, false, "UI")
            end
            return
        end

        local activeContext = api.Library.ActiveKeybindContext or "Global"
        local contextMatches = api.Context == "Global" or api.Context == activeContext
        if not api.Disabled and not processed and contextMatches and api.Value ~= "" and input.KeyCode.Name == api.Value and modifiersMatch() then
            if api.Mode == "hold" then
                emit(true, "KeyDown")
            elseif api.Mode == "toggle" then
                emit(not api.Active, "KeyToggle")
            else
                emit(true, "KeyPressed")
            end
        end
    end))
    api._janitor:Add(UserInputService.InputEnded:Connect(function(input)
        if api.Mode == "hold" and api.Active and input.KeyCode.Name == api.Value then
            emit(false, "KeyUp")
        end
    end))

    function api:BeginCapture()
        listening = true
        capture.Text = "Press a key..."
    end

    function api:OnActiveChanged(callback: (...any) -> ())
        return self.ActiveChanged:Connect(callback)
    end

    render = function()
        capture.Text = listening and "Press a key..." or displayKey()
        local activeTheme = api.Library.ThemeManager.Current
        capture.BackgroundColor3 = activeTheme.Surface
        capture.TextColor3 = activeTheme.Text
    end
    api._applyTheme = render
    initialize(api, normalize(options.Default), normalize, render)
    return api
end

local function createColorPicker(section: any, options: any): any
    local api, _, body = makeBase(section, "ColorPicker", options)
    body.Size = UDim2.new(1, 0, 0, 34)
    body.AutomaticSize = Enum.AutomaticSize.None
    local theme = api.Library.ThemeManager.Current
    local colorButton = button(body, "#FFFFFF", {
        Name = "ColorButton",
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = theme.Surface,
        TextColor3 = theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 8,
    })
    corner(colorButton, 7)
    make("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
    }, colorButton)
    local swatch = make("Frame", {
        Name = "ColorSwatch",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -3, 0.5, 0),
        Size = UDim2.fromOffset(24, 24),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 9,
    }, colorButton) :: Frame
    corner(swatch, 6)

    local hue = 0
    local saturation = 1
    local value = 1

    local function normalize(input: any): Color3
        if typeof(input) == "Color3" then
            return input
        end
        if type(input) == "string" then
            local hex = input:gsub("#", "")
            if #hex == 6 and tonumber(hex, 16) then
                return Color3.fromRGB(
                    tonumber(hex:sub(1, 2), 16) or 255,
                    tonumber(hex:sub(3, 4), 16) or 255,
                    tonumber(hex:sub(5, 6), 16) or 255
                )
            end
        end
        return Color3.new(1, 1, 1)
    end

    local function hexString(color: Color3): string
        return string.format("#%02X%02X%02X",
            math.floor(color.R * 255 + 0.5),
            math.floor(color.G * 255 + 0.5),
            math.floor(color.B * 255 + 0.5)
        )
    end

    local function openPicker()
        local panel, popupJanitor = api.Window:_OpenPopup(api, colorButton, 238, 252)
        local inner = make("Frame", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(10, 10),
            Size = UDim2.new(1, -20, 1, -20),
            ZIndex = 51,
        }, panel) :: Frame
        popupJanitor:Add(inner)

        local currentColor = api.Value
        hue, saturation, value = Color3.toHSV(currentColor)
        local sv = make("Frame", {
            Name = "SaturationValue",
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.new(1, 0, 0, 132),
            BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
            BorderSizePixel = 0,
            Active = true,
            ZIndex = 52,
        }, inner) :: Frame
        corner(sv, 7)
        local whiteOverlay = make("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 53,
        }, sv) :: Frame
        corner(whiteOverlay, 7)
        make("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }, whiteOverlay)
        local blackOverlay = make("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BorderSizePixel = 0,
            ZIndex = 54,
        }, sv) :: Frame
        corner(blackOverlay, 7)
        make("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(1, 0),
            }),
        }, blackOverlay)
        local marker = make("Frame", {
            Name = "SVMarker",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(saturation, 1 - value),
            Size = UDim2.fromOffset(10, 10),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 55,
        }, sv) :: Frame
        corner(marker, 6)
        make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }, marker)

        local dragging: string? = nil
        local activeInput: InputObject? = nil
        local applyFromPosition: (Vector3) -> () = function(_position: Vector3) end
        local svHitbox = button(sv, "", {
            Name = "SVHitbox",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            ZIndex = 56,
        })
        popupJanitor:Add(svHitbox.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = "SV"
                activeInput = input
                applyFromPosition(input.Position)
            end
        end))

        local hueBar = make("Frame", {
            Name = "HueBar",
            Position = UDim2.fromOffset(0, 142),
            Size = UDim2.new(1, 0, 0, 12),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            Active = true,
            ZIndex = 52,
        }, inner) :: Frame
        corner(hueBar, 6)
        make("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
                ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
                ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
                ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
                ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
                ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
            }),
        }, hueBar)

        local hexInput = make("TextBox", {
            Name = "HexInput",
            Position = UDim2.fromOffset(0, 164),
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundColor3 = api.Library.ThemeManager.Current.SurfaceAlt,
            BorderSizePixel = 0,
            ClearTextOnFocus = false,
            Text = hexString(api.Value),
            TextColor3 = api.Library.ThemeManager.Current.Text,
            PlaceholderText = "#RRGGBB",
            TextSize = 12,
            Font = Enum.Font.Gotham,
            ZIndex = 52,
        }, inner) :: TextBox
        corner(hexInput, 6)

        applyFromPosition = function(position: Vector3)
            if dragging == "SV" then
                local relative = position - sv.AbsolutePosition
                saturation = math.clamp(relative.X / math.max(sv.AbsoluteSize.X, 1), 0, 1)
                value = 1 - math.clamp(relative.Y / math.max(sv.AbsoluteSize.Y, 1), 0, 1)
            elseif dragging == "Hue" then
                local relative = position.X - hueBar.AbsolutePosition.X
                hue = math.clamp(relative / math.max(hueBar.AbsoluteSize.X, 1), 0, 1)
            end
            sv.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
            marker.Position = UDim2.fromScale(saturation, 1 - value)
            local nextColor = Color3.fromHSV(hue, saturation, value)
            api:Set(nextColor, false, "UI")
            hexInput.Text = hexString(nextColor)
        end

        popupJanitor:Add(hueBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = "Hue"
                activeInput = input
                applyFromPosition(input.Position)
            end
        end))
        popupJanitor:Add(UserInputService.InputChanged:Connect(function(input)
            if dragging == nil then
                return
            end
            local sameTouch = activeInput ~= nil and activeInput.UserInputType == Enum.UserInputType.Touch and input == activeInput
            local mouseMove = activeInput ~= nil and activeInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement
            if sameTouch or mouseMove then
                applyFromPosition(input.Position)
            end
        end))
        popupJanitor:Add(UserInputService.InputEnded:Connect(function(input)
            if activeInput == input or (activeInput and activeInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
                dragging = nil
                activeInput = nil
            end
        end))
        popupJanitor:Add(hexInput.FocusLost:Connect(function()
            local nextColor = normalize(hexInput.Text)
            api:Set(nextColor, false, "UI")
            hue, saturation, value = Color3.toHSV(nextColor)
            hexInput.Text = hexString(nextColor)
            sv.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
            marker.Position = UDim2.fromScale(saturation, 1 - value)
        end))
    end

    api._janitor:Add(colorButton.Activated:Connect(function()
        if api.Window._popup and api.Window._popup.Owner == api then
            api.Window:_ClosePopup()
        else
            openPicker()
        end
    end))

    local function render()
        local color = api.Value
        colorButton.Text = hexString(color)
        swatch.BackgroundColor3 = color
        local activeTheme = api.Library.ThemeManager.Current
        colorButton.BackgroundColor3 = activeTheme.Surface
        colorButton.TextColor3 = activeTheme.Text
    end
    api._applyTheme = render
    initialize(api, normalize(options.Default or Color3.fromRGB(255, 255, 255)), normalize, render)
    return api
end

local function createButton(section: any, options: any): any
    local api, _, body = makeBase(section, "Button", options)
    body.Size = UDim2.new(1, 0, 0, 34)
    body.AutomaticSize = Enum.AutomaticSize.None
    local theme = api.Library.ThemeManager.Current
    local action = button(body, tostring(options.ButtonText or options.Title or "Run"), {
        Name = "ActionButton",
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = theme.Accent,
        TextColor3 = theme.AccentText,
        ZIndex = 8,
    })
    corner(action, 7)
    api._janitor:Add(action.Activated:Connect(function()
        api:Activate()
    end))
    api._applyTheme = function(activeTheme: {[string]: any})
        action.BackgroundColor3 = activeTheme.Accent
        action.TextColor3 = activeTheme.AccentText
    end
    api.Value = false
    function api:SetText(text: string)
        action.Text = tostring(text)
        return self
    end
    return api
end

local function createLabel(section: any, options: any): any
    local api, _, body = makeBase(section, "Label", options)
    local text = label(body, tostring(options.Text or options.Content or options.Title or ""), 11, api.Library.ThemeManager.Current.Muted, {
        Name = "LabelText",
        Size = UDim2.new(1, 0, 0, 18),
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    function api:Set(value: any, silent: boolean?, source: string?)
        if self.Destroyed then
            return false
        end
        text.Text = tostring(value)
        self.Value = text.Text
        return true
    end
    function api:SetText(value: any)
        return self:Set(value, true, "Code")
    end
    api.Value = text.Text
    api._applyTheme = function(activeTheme: {[string]: any})
        text.TextColor3 = activeTheme.Muted
    end
    return api
end

local function createParagraph(section: any, options: any): any
    local api, _, body = makeBase(section, "Paragraph", options)
    local content = label(body, tostring(options.Content or options.Text or ""), 11, api.Library.ThemeManager.Current.Muted, {
        Name = "ParagraphContent",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    function api:Set(value: any, silent: boolean?, source: string?)
        if self.Destroyed then
            return false
        end
        content.Text = tostring(value)
        self.Value = content.Text
        return true
    end
    function api:SetContent(value: any)
        return self:Set(value, true, "Code")
    end
    api.Value = content.Text
    api._applyTheme = function(activeTheme: {[string]: any})
        content.TextColor3 = activeTheme.Muted
    end
    return api
end

function Controls.Create(section: any, kind: string, options: any): any
    if kind == "Toggle" then
        return createToggle(section, options)
    elseif kind == "Slider" then
        return createSlider(section, options)
    elseif kind == "Dropdown" then
        return createDropdown(section, options)
    elseif kind == "Textbox" then
        return createTextbox(section, options)
    elseif kind == "Keybind" then
        return createKeybind(section, options)
    elseif kind == "ColorPicker" then
        return createColorPicker(section, options)
    elseif kind == "Button" then
        return createButton(section, options)
    elseif kind == "Label" then
        return createLabel(section, options)
    elseif kind == "Paragraph" then
        return createParagraph(section, options)
    end

    error("Unknown SilentUI control type: " .. tostring(kind))
end

__SUI_UI_Controls = Controls
end

-- ===== Module: UI.AdvancedControls =====
local __SUI_UI_AdvancedControls
do
-- Advanced, composable UI elements inspired by the five supplied libraries.
-- Advanced presentation components built with Roblox client APIs.

local TweenService = game:GetService("TweenService")
local Janitor = __SUI_Core_Janitor
local Signal = __SUI_Core_Signal

local AdvancedControls = {}
local API = {}
API.__index = API

local SUPPORTED: {[string]: boolean} = {
    Stepper = true,
    Progress = true,
    Divider = true,
    Segmented = true,
    Stats = true,
    Image = true,
    Video = true,
    Code = true,
    Tag = true,
    Card = true,
    Table = true,
    Console = true,
    Changelog = true,
    Rating = true,
    AssetGrid = true,
    CardGrid = true,
    InfoGrid = true,
    LoadoutGroup = true,
    StateList = true,
    SystemInfoGrid = true,
    GradientCard = true,
    LineText = true,
}

local function make(className: string, props: {[string]: any}, parent: Instance?): Instance
    local object = Instance.new(className)
    for property, value in pairs(props) do
        (object :: any)[property] = value
    end
    if parent then
        object.Parent = parent
    end
    return object
end

local function round(instance: Instance, radius: number)
    make("UICorner", { CornerRadius = UDim.new(0, radius) }, instance)
end

local function stroke(instance: Instance, color: Color3, transparency: number?)
    return make("UIStroke", {
        Color = color,
        Transparency = transparency or 0.5,
        Thickness = 1,
    }, instance)
end

local function text(parent: Instance, value: string, size: number, color: Color3, props: {[string]: any}?): TextLabel
    local properties = props or {}
    properties.BackgroundTransparency = 1
    properties.Text = value
    properties.TextSize = size
    properties.TextColor3 = color
    properties.Font = properties.Font or Enum.Font.Gotham
    properties.TextXAlignment = properties.TextXAlignment or Enum.TextXAlignment.Left
    properties.TextYAlignment = properties.TextYAlignment or Enum.TextYAlignment.Center
    return make("TextLabel", properties, parent) :: TextLabel
end

local function button(parent: Instance, value: string, props: {[string]: any}?): TextButton
    local properties = props or {}
    properties.Text = value
    properties.Font = properties.Font or Enum.Font.GothamMedium
    properties.TextSize = properties.TextSize or 12
    properties.AutoButtonColor = false
    properties.BorderSizePixel = 0
    return make("TextButton", properties, parent) :: TextButton
end

local function clone(value: any): any
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = clone(item)
    end
    return result
end

local function same(first: any, second: any): boolean
    if typeof(first) == "Color3" and typeof(second) == "Color3" then
        return first == second
    end
    if type(first) ~= type(second) then
        return false
    end
    if type(first) ~= "table" then
        return first == second
    end
    for key, value in pairs(first) do
        if not same(value, second[key]) then
            return false
        end
    end
    for key in pairs(second) do
        if first[key] == nil then
            return false
        end
    end
    return true
end

local function normalizeItems(items: any): {any}
    local result = {}
    if type(items) ~= "table" then
        return result
    end
    for _, item in ipairs(items) do
        if type(item) == "table" then
            table.insert(result, {
                Value = item.Value ~= nil and item.Value or item.Id or item.Name or item.Title,
                Title = tostring(item.Title or item.Name or item.Label or item.Value or "Item"),
                Description = tostring(item.Description or item.Desc or ""),
                Image = item.Image,
                Color = item.Color,
                Icon = item.Icon,
                Status = item.Status,
                Callback = item.Callback,
            })
        else
            table.insert(result, { Value = item, Title = tostring(item), Description = "" })
        end
    end
    return result
end

local function createBase(section: any, kind: string, options: any): any
    local theme = section.Window.Library.ThemeManager.Current
    local row = make("Frame", {
        Name = kind,
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = tonumber(theme.SurfaceAltTransparency) or 0.27,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = #section.Elements + 1,
        ClipsDescendants = false,
    }, section.Frame) :: Frame
    round(row, 8)
    local rowStroke = stroke(row, theme.Border, 0.72)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 9),
        PaddingBottom = UDim.new(0, 9),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
    }, row)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
    }, row)

    local title = text(row, tostring(options.Title or options.Name or kind), 12, theme.Text, {
        Name = "Title",
        Size = UDim2.new(1, 0, 0, 18),
        Font = Enum.Font.GothamMedium,
        LayoutOrder = 1,
    })
    local desc: TextLabel? = nil
    local description = tostring(options.Description or options.Desc or "")
    if description ~= "" then
        desc = text(row, description, 10, theme.Muted, {
            Name = "Description",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = 2,
        })
    end

    local body = make("Frame", {
        Name = "Body",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 3,
    }, row) :: Frame

    local api = setmetatable({
        Library = section.Window.Library,
        Window = section.Window,
        Tab = section.Tab,
        Section = section,
        Kind = kind,
        Flag = options.Flag,
        Callback = options.Callback,
        Value = nil,
        Disabled = options.Disabled == true,
        Destroyed = false,
        ElementFrame = row,
        Body = body,
        TitleLabel = title,
        DescriptionLabel = desc,
        SearchText = string.lower(table.concat({ tostring(options.Title or options.Name or kind), description }, " ")),
        UserVisible = options.Visible ~= false,
        SearchVisible = true,
        _janitor = Janitor.new(),
        _changed = Signal.new(),
        _applyTheme = nil,
        _normalize = nil,
        _render = nil,
    }, API)

    row.Visible = options.Visible ~= false
    api._janitor:Add(row)
    api._janitor:Add(section.Window.Library.ThemeManager.Changed:Connect(function()
        if api.Destroyed then
            return
        end
        local current = api.Library.ThemeManager.Current
        row.BackgroundColor3 = current.SurfaceAlt
        row.BackgroundTransparency = tonumber(current.SurfaceAltTransparency) or 0.27
        rowStroke.Color = current.Border
        title.TextColor3 = current.Text
        if desc then
            desc.TextColor3 = current.Muted
        end
        if api._applyTheme then
            api._applyTheme(current)
        end
    end))

    if api.Flag ~= nil then
        assert(type(api.Flag) == "string" and api.Flag ~= "", kind .. " Flag must be a non-empty string")
        assert(api.Library.Flags[api.Flag] == nil, "Duplicate SilentUI flag: " .. api.Flag)
        api.Library.Flags[api.Flag] = api
    end

    return api, row, body, theme
end

function API:Get(): any
    return clone(self.Value)
end

function API:Set(value: any, silent: boolean?, source: string?): boolean
    if self.Destroyed or (self.Disabled and (source == "UI" or source == "Keybind")) then
        return false
    end
    local nextValue = if self._normalize then self._normalize(value) else value
    if same(self.Value, nextValue) then
        if self._render then self._render() end
        return false
    end
    local previous = self:Get()
    self.Value = clone(nextValue)
    if self._render then self._render() end
    if silent ~= true then
        local info = { Flag = self.Flag, Source = source or "Code", Previous = previous }
        self._changed:Fire(self:Get(), info)
        if type(self.Callback) == "function" then
            local callback = self.Callback
            local current = self:Get()
            task.spawn(function()
                local ok, err = pcall(callback, current, info)
                if not ok then
                    warn("[SilentUI] " .. self.Kind .. " callback failed: " .. tostring(err))
                end
            end)
        end
    end
    return true
end

function API:OnChanged(callback: (...any) -> ()): any
    return self._changed:Connect(callback)
end

function API:SetDisabled(disabled: boolean)
    self.Disabled = disabled == true
    if self.ElementFrame then
        self.ElementFrame.BackgroundTransparency = self.Disabled and 0.58 or 0.27
        for _, descendant in ipairs(self.ElementFrame:GetDescendants()) do
            if descendant:IsA("GuiButton") then
                descendant.Active = not self.Disabled
                descendant.Selectable = not self.Disabled
            elseif descendant:IsA("TextBox") then
                descendant.TextEditable = not self.Disabled
            end
        end
    end
    return self
end

function API:SetEnabled(enabled: boolean)
    return self:SetDisabled(not (enabled == true))
end

function API:SetTooltip(message: string)
    self.Tooltip = tostring(message)
    if self._tooltipJanitor then
        self._janitor:Remove(self._tooltipJanitor, true)
        self._tooltipJanitor = nil
    end
    if self.Tooltip ~= "" and self.ElementFrame then
        local tooltipJanitor = Janitor.new()
        tooltipJanitor:Add(self.ElementFrame.MouseEnter:Connect(function()
            self.Window:_ShowTooltip(self.ElementFrame, self.Tooltip)
        end))
        tooltipJanitor:Add(self.ElementFrame.MouseLeave:Connect(function()
            self.Window:_HideTooltip()
        end))
        tooltipJanitor:Add(self.ElementFrame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch then
                self.Window:_ShowTooltip(self.ElementFrame, self.Tooltip)
            end
        end))
        self._tooltipJanitor = tooltipJanitor
        self._janitor:Add(tooltipJanitor)
    end
    return self
end

function API:SetDescription(description: string)
    if self.DescriptionLabel == nil and self.ElementFrame then
        self.DescriptionLabel = text(self.ElementFrame, "", 10, self.Library.ThemeManager.Current.Muted, {
            Name = "Description",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = 2,
        })
    end
    if self.DescriptionLabel then
        self.DescriptionLabel.Text = tostring(description)
        self.DescriptionLabel.Visible = self.DescriptionLabel.Text ~= ""
        self.DescriptionLabel.TextColor3 = self.Library.ThemeManager.Current.Muted
    end
    self.SearchText = string.lower((self.TitleLabel and self.TitleLabel.Text or "") .. " " .. tostring(description))
    return self
end

API.SetDesc = API.SetDescription

function API:SetValue(value: any, silent: boolean?, source: string?)
    return self:Set(value, silent, source)
end

function API:Lock()
    return self:SetDisabled(true)
end

function API:Unlock()
    return self:SetDisabled(false)
end

function API:Show()
    return self:SetVisible(true)
end

function API:Hide()
    return self:SetVisible(false)
end

function API:SetVisible(visible: boolean)
    if not self.Destroyed then
        self.UserVisible = visible == true
        self.ElementFrame.Visible = self.UserVisible and self.SearchVisible ~= false
    end
    return self
end

function API:SetSearchMatch(matches: boolean)
    if not self.Destroyed then
        self.SearchVisible = matches == true
        self.ElementFrame.Visible = self.UserVisible ~= false and self.SearchVisible
    end
    return self
end

function API:SetTitle(title: string)
    if not self.Destroyed then
        self.TitleLabel.Text = tostring(title)
        self.SearchText = string.lower(self.TitleLabel.Text .. " " .. (self.DescriptionLabel and self.DescriptionLabel.Text or ""))
    end
    return self
end

function API:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    if self.Flag and self.Library.Flags[self.Flag] == self then
        self.Library.Flags[self.Flag] = nil
    end
    if self.Window._popup and self.Window._popup.Owner == self then
        self.Window:_ClosePopup()
    end
    self._janitor:Destroy()
    self._changed:Destroy()
    if self.ElementFrame and self.ElementFrame.Parent then
        self.ElementFrame:Destroy()
    end
    for index, item in ipairs(self.Section.Elements) do
        if item == self then
            table.remove(self.Section.Elements, index)
            break
        end
    end
    for index, item in ipairs(self.Library.Controls) do
        if item == self then
            table.remove(self.Library.Controls, index)
            break
        end
    end
    self.Library.ControlsChanged:Fire("Removed", self)
end

local function finish(api: any, defaultValue: any, normalize: ((any) -> any)?, render: (() -> ())?)
    api._normalize = normalize
    api._render = render
    api:Set(defaultValue, true)
    api.InitialValue = api:Get()
    if api.Flag then
        api.Library.ConfigStore:RegisterFlag(api.Flag, api)
    end
    if render then render() end
    if api.Disabled then api:SetDisabled(true) end
    return api
end

local function createStepper(section: any, options: any): any
    local api, _, body, theme = createBase(section, "Stepper", options)
    local minimum = tonumber(options.Min) or 0
    local maximum = tonumber(options.Max) or 100
    local step = math.max(tonumber(options.Step) or 1, 0.000001)
    local valueLabel = text(body, "0", 12, theme.Text, {
        Name = "Value",
        Size = UDim2.new(1, 0, 0, 20),
        TextXAlignment = Enum.TextXAlignment.Center,
        LayoutOrder = 1,
    })
    local controls = make("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 32),
        LayoutOrder = 2,
    }, body) :: Frame
    local minus = button(controls, "−", {
        Size = UDim2.fromOffset(38, 30),
        BackgroundColor3 = theme.Surface,
        TextColor3 = theme.Text,
        Position = UDim2.fromOffset(0, 0),
    })
    round(minus, 7)
    local plus = button(controls, "+", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(38, 30),
        BackgroundColor3 = theme.Surface,
        TextColor3 = theme.Text,
    })
    round(plus, 7)
    local fill = make("Frame", {
        Position = UDim2.fromOffset(44, 0),
        Size = UDim2.new(1, -88, 0, 30),
        BackgroundColor3 = theme.Surface,
        BorderSizePixel = 0,
    }, controls)
    round(fill, 7)
    local function normalize(value: any): number
        local numberValue = tonumber(value) or minimum
        local snapped = minimum + math.floor((numberValue - minimum) / step + 0.5) * step
        return math.clamp(snapped, minimum, maximum)
    end
    local function render()
        valueLabel.Text = tostring(api.Value)
        local active = api.Library.ThemeManager.Current
        minus.BackgroundColor3 = active.Surface
        plus.BackgroundColor3 = active.Surface
        minus.TextColor3 = active.Text
        plus.TextColor3 = active.Text
    end
    api._janitor:Add(minus.Activated:Connect(function() api:Set((api.Value or minimum) - step, false, "UI") end))
    api._janitor:Add(plus.Activated:Connect(function() api:Set((api.Value or minimum) + step, false, "UI") end))
    api._applyTheme = render
    return finish(api, options.Default ~= nil and options.Default or minimum, normalize, render)
end

local function createProgress(section: any, options: any): any
    local api, _, body, theme = createBase(section, "Progress", options)
    local minimum = tonumber(options.Min) or 0
    local maximum = tonumber(options.Max) or 100
    local valueLabel = text(body, "0%", 10, theme.Muted, { Size = UDim2.new(1, 0, 0, 16) })
    local track = make("Frame", {
        Size = UDim2.new(1, 0, 0, 8),
        BackgroundColor3 = theme.Surface,
        BorderSizePixel = 0,
    }, body) :: Frame
    round(track, 5)
    local fill = make("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = options.Color or theme.Accent,
        BorderSizePixel = 0,
    }, track) :: Frame
    round(fill, 5)
    local function normalize(value: any): number
        return math.clamp(tonumber(value) or minimum, minimum, maximum)
    end
    local function render()
        local alpha = if maximum == minimum then 0 else (api.Value - minimum) / (maximum - minimum)
        valueLabel.Text = tostring(math.floor(alpha * 100 + 0.5)) .. "%"
        local active = api.Library.ThemeManager.Current
        track.BackgroundColor3 = active.Surface
        fill.BackgroundColor3 = options.Color or active.Accent
        TweenService:Create(fill, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(alpha, 0, 1, 0),
        }):Play()
    end
    api._applyTheme = render
    return finish(api, options.Default ~= nil and options.Default or minimum, normalize, render)
end

local function createDivider(section: any, options: any): any
    local api, row, body = createBase(section, "Divider", options)
    api.TitleLabel.Visible = false
    if api.DescriptionLabel then api.DescriptionLabel.Visible = false end
    row.BackgroundTransparency = 1
    local caption = tostring(options.Text or options.Title or "")
    local line = make("Frame", {
        BackgroundColor3 = api.Library.ThemeManager.Current.Border,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 1),
    }, body)
    if caption ~= "" then
        text(body, caption, 10, api.Library.ThemeManager.Current.Muted, {
            Size = UDim2.new(1, 0, 0, 16),
            TextXAlignment = Enum.TextXAlignment.Center,
        })
    end
    api._applyTheme = function(active: {[string]: any}) line.BackgroundColor3 = active.Border end
    api.Value = false
    return api
end

local function createSegmented(section: any, options: any): any
    local api, _, body, theme = createBase(section, "Segmented", options)
    local items = normalizeItems(options.Options or options.Items or {})
    local holder = make("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = theme.Surface,
        BorderSizePixel = 0,
    }, body) :: Frame
    round(holder, 7)
    local layout = make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
    }, holder)
    local buttons = {}
    local function normalize(value: any): any
        for _, item in ipairs(items) do
            if item.Value == value then return value end
        end
        return items[1] and items[1].Value or nil
    end
    local function render()
        local active = api.Library.ThemeManager.Current
        holder.BackgroundColor3 = active.Surface
        for _, entry in ipairs(buttons) do
            local selected = entry.Value == api.Value
            entry.Button.BackgroundColor3 = selected and active.Accent or active.Surface
            entry.Button.TextColor3 = selected and active.AccentText or active.Muted
        end
    end
    for index, item in ipairs(items) do
        local itemButton = button(holder, item.Title, {
            Size = UDim2.new(1 / math.max(#items, 1), -2, 1, 0),
            BackgroundColor3 = theme.Surface,
            TextColor3 = theme.Muted,
            LayoutOrder = index,
        })
        round(itemButton, 6)
        table.insert(buttons, { Value = item.Value, Button = itemButton })
        api._janitor:Add(itemButton.Activated:Connect(function()
            api:Set(item.Value, false, "UI")
        end))
    end
    api._applyTheme = render
    return finish(api, options.Default ~= nil and options.Default or (items[1] and items[1].Value), normalize, render)
end

local function createStats(section: any, options: any): any
    local api, _, body, theme = createBase(section, "Stats", options)
    local grid = make("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
    }, body) :: Frame
    local gridLayout = make("UIGridLayout", {
        CellSize = UDim2.new(0.5, -5, 0, 58),
        CellPadding = UDim2.fromOffset(8, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, grid)
    local function render()
        for _, child in ipairs(grid:GetChildren()) do
            if child:IsA("Frame") then child:Destroy() end
        end
        local entries = type(api.Value) == "table" and api.Value or {}
        for index, entry in ipairs(entries) do
            local item = if type(entry) == "table" then entry else { Title = tostring(index), Value = entry }
            local tile = make("Frame", {
                BackgroundColor3 = api.Library.ThemeManager.Current.Surface,
                BorderSizePixel = 0,
                LayoutOrder = index,
            }, grid) :: Frame
            round(tile, 7)
            text(tile, tostring(item.Title or item.Label or "Stat"), 10, api.Library.ThemeManager.Current.Muted, {
                Position = UDim2.fromOffset(9, 6),
                Size = UDim2.new(1, -18, 0, 15),
            })
            text(tile, tostring(item.Value or "—"), 16, api.Library.ThemeManager.Current.Text, {
                Position = UDim2.fromOffset(9, 23),
                Size = UDim2.new(1, -18, 0, 24),
                Font = Enum.Font.GothamBold,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })
        end
        local columns = tonumber(options.Columns) or 2
        gridLayout.CellSize = UDim2.new(1 / math.max(columns, 1), -8, 0, 58)
    end
    api._applyTheme = render
    return finish(api, options.Items or {}, function(value) return type(value) == "table" and clone(value) or {} end, render)
end

local function createImage(section: any, options: any): any
    local api, _, body = createBase(section, "Image", options)
    local aspect = math.max(0.25, tonumber(options.AspectRatio) or 2.4)
    local image = make("ImageLabel", {
        Name = "ContentImage",
        Size = UDim2.new(1, 0, 0, tonumber(options.Height) or math.floor(180 / aspect)),
        BackgroundColor3 = api.Library.ThemeManager.Current.Surface,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Image = tostring(options.Image or options.Source or ""),
        ScaleType = options.ScaleType or Enum.ScaleType.Crop,
    }, body) :: ImageLabel
    round(image, 7)
    if options.Caption then
        text(body, tostring(options.Caption), 10, api.Library.ThemeManager.Current.Muted, {
            Size = UDim2.new(1, 0, 0, 16),
        })
    end
    if options.Activated then
        local hit = button(image, "", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
        })
        api._janitor:Add(hit.Activated:Connect(function()
            local ok, err = pcall(options.Activated, api.Value, { Source = "UI", Action = "ImageActivated" })
            if not ok then warn("[SilentUI] Image callback failed: " .. tostring(err)) end
        end))
    end
    function api:SetImage(source: string)
        image.Image = tostring(source)
        return self
    end
    api.Value = image.Image
    return api
end

local function createVideo(section: any, options: any): any
    local api, _, body = createBase(section, "Video", options)
    local video = make("VideoFrame", {
        Name = "VideoContent",
        Size = UDim2.new(1, 0, 0, tonumber(options.Height) or 150),
        BackgroundColor3 = api.Library.ThemeManager.Current.Surface,
        BorderSizePixel = 0,
        Video = tostring(options.Video or options.Source or ""),
        Looped = options.Looped == true,
        Volume = math.clamp(tonumber(options.Volume) or 0, 0, 10),
    }, body) :: VideoFrame
    round(video, 7)
    if options.AutoPlay == true then
        task.defer(function()
            if video.Parent then video:Play() end
        end)
    end
    local controls = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30) }, body)
    local play = button(controls, "Play", { Size = UDim2.fromOffset(64, 28), BackgroundColor3 = api.Library.ThemeManager.Current.Surface, TextColor3 = api.Library.ThemeManager.Current.Text })
    round(play, 6)
    local pause = button(controls, "Pause", { Position = UDim2.fromOffset(70, 0), Size = UDim2.fromOffset(64, 28), BackgroundColor3 = api.Library.ThemeManager.Current.Surface, TextColor3 = api.Library.ThemeManager.Current.Text })
    round(pause, 6)
    api._janitor:Add(play.Activated:Connect(function() video:Play() end))
    api._janitor:Add(pause.Activated:Connect(function() video:Pause() end))
    function api:Play() video:Play(); return self end
    function api:Pause() video:Pause(); return self end
    function api:SetVideo(source: string)
        video.Video = tostring(source)
        return self
    end
    api._applyTheme = function(active: {[string]: any})
        video.BackgroundColor3 = active.Surface
        play.BackgroundColor3 = active.Surface
        pause.BackgroundColor3 = active.Surface
        play.TextColor3 = active.Text
        pause.TextColor3 = active.Text
    end
    api.Value = video.Video
    return api
end

local function createCode(section: any, options: any): any
    local api, _, body = createBase(section, "Code", options)
    local scroll = make("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, tonumber(options.Height) or 160),
        BackgroundColor3 = api.Library.ThemeManager.Current.Window,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, body) :: ScrollingFrame
    round(scroll, 7)
    local codeLabel = text(scroll, tostring(options.Code or options.Text or ""), tonumber(options.TextSize) or 11, api.Library.ThemeManager.Current.Text, {
        Position = UDim2.fromOffset(10, 8),
        Size = UDim2.new(1, -20, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Font = Enum.Font.Code,
        TextWrapped = options.Wrap == true,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    function api:SetText(value: string)
        codeLabel.Text = tostring(value)
        self.Value = codeLabel.Text
        return self
    end
    api._applyTheme = function(active: {[string]: any})
        scroll.BackgroundColor3 = active.Window
        codeLabel.TextColor3 = active.Text
    end
    api.Value = codeLabel.Text
    return api
end

local function createTag(section: any, options: any): any
    local api, _, body = createBase(section, "Tag", options)
    local tag = text(body, tostring(options.Text or options.Value or "TAG"), 10, options.TextColor or api.Library.ThemeManager.Current.AccentText, {
        Size = UDim2.fromOffset(110, 25),
        TextXAlignment = Enum.TextXAlignment.Center,
        Font = Enum.Font.GothamBold,
    })
    tag.BackgroundColor3 = options.Color or api.Library.ThemeManager.Current.Accent
    tag.BackgroundTransparency = 0
    round(tag, 7)
    function api:SetText(value: string) tag.Text = tostring(value); self.Value = tag.Text; return self end
    api._applyTheme = function(active: {[string]: any})
        if options.Color == nil then tag.BackgroundColor3 = active.Accent end
        if options.TextColor == nil then tag.TextColor3 = active.AccentText end
    end
    api.Value = tag.Text
    return api
end

local function createCard(section: any, options: any): any
    local api, _, body, theme = createBase(section, "Card", options)
    local content = text(body, tostring(options.Content or options.Description or ""), 11, theme.Muted, {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    if options.Image then
        local image = make("ImageLabel", {
            Size = UDim2.new(1, 0, 0, tonumber(options.ImageHeight) or 90),
            BackgroundColor3 = theme.Surface,
            BorderSizePixel = 0,
            Image = tostring(options.Image),
            ScaleType = Enum.ScaleType.Crop,
        }, body)
        round(image, 7)
    end
    if options.ButtonText or options.Callback then
        local action = button(body, tostring(options.ButtonText or "Open"), {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundColor3 = theme.Accent,
            TextColor3 = theme.AccentText,
        })
        round(action, 7)
        api._janitor:Add(action.Activated:Connect(function()
            if type(options.Callback) == "function" then
                local ok, err = pcall(options.Callback, true, { Source = "UI", Action = "CardActivated" })
                if not ok then warn("[SilentUI] Card callback failed: " .. tostring(err)) end
            end
        end))
    end
    api._applyTheme = function(active: {[string]: any}) content.TextColor3 = active.Muted end
    api.Value = false
    return api
end

local function createTable(section: any, options: any): any
    local api, _, body = createBase(section, "Table", options)
    local scroller = make("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, tonumber(options.Height) or 180),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, body) :: ScrollingFrame
    local list = make("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
    }, scroller)
    local columns = options.Columns or {}
    local function clearRows()
        for _, child in ipairs(scroller:GetChildren()) do
            if child:IsA("Frame") then child:Destroy() end
        end
    end
    local function setRows(rows: any)
        clearRows()
        if type(columns) == "table" and #columns > 0 then
            local header = make("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = api.Library.ThemeManager.Current.Surface, BorderSizePixel = 0, LayoutOrder = 1 }, scroller)
            round(header, 5)
            for index, name in ipairs(columns) do
                text(header, tostring(name), 10, api.Library.ThemeManager.Current.Muted, {
                    Position = UDim2.new((index - 1) / #columns, 7, 0, 0),
                    Size = UDim2.new(1 / #columns, -10, 1, 0),
                    TextTruncate = Enum.TextTruncate.AtEnd,
                })
            end
        end
        for rowIndex, rawRowData in ipairs(type(rows) == "table" and rows or {}) do
            local rowData = if type(rawRowData) == "table" then rawRowData else { rawRowData }
            local row = make("Frame", {
                Size = UDim2.new(1, 0, 0, 28),
                BackgroundColor3 = api.Library.ThemeManager.Current.SurfaceAlt,
                BackgroundTransparency = rowIndex % 2 == 0 and 0.15 or 0.35,
                BorderSizePixel = 0,
                LayoutOrder = rowIndex + 1,
            }, scroller)
            round(row, 4)
            for columnIndex = 1, math.max(#columns, #rowData) do
                local value = rowData[columnIndex]
                text(row, tostring(value or ""), 10, api.Library.ThemeManager.Current.Text, {
                    Position = UDim2.new((columnIndex - 1) / math.max(#columns, #rowData), 7, 0, 0),
                    Size = UDim2.new(1 / math.max(#columns, #rowData), -10, 1, 0),
                    TextTruncate = Enum.TextTruncate.AtEnd,
                })
            end
        end
    end
    api._normalize = function(value: any): any
        return type(value) == "table" and clone(value) or {}
    end
    api._render = function() setRows(api.Value or {}) end
    function api:SetRows(rows: any)
        self:Set(rows, false, "Code")
        return self
    end
    api._applyTheme = function() setRows(api.Value or {}) end
    api:Set(options.Rows or {}, true, "Init")
    api.InitialValue = api:Get()
    if api.Flag then api.Library.ConfigStore:RegisterFlag(api.Flag, api) end
    api._render()
    if api.Disabled then api:SetDisabled(true) end
    return api
end

local function createConsole(section: any, options: any): any
    assert(options.Flag == nil, "Console logs cannot be registered as config flags")
    local api, _, body = createBase(section, "Console", options)
    local output = make("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, tonumber(options.Height) or 150),
        BackgroundColor3 = api.Library.ThemeManager.Current.Window,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, body) :: ScrollingFrame
    round(output, 7)
    make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, output)
    local lines = {}
    local maxLines = math.clamp(math.floor(tonumber(options.MaxLines) or 120), 10, 1000)
    local function renderLines()
        for _, child in ipairs(output:GetChildren()) do
            if child:IsA("TextLabel") then child:Destroy() end
        end
        local theme = api.Library.ThemeManager.Current
        for index, entry in ipairs(lines) do
            local color = theme.Text
            if entry.Level == "Error" then
                color = theme.Danger
            elseif entry.Level == "Success" then
                color = theme.Success
            elseif entry.Level == "Warning" then
                color = theme.Accent
            end
            text(output, "[" .. entry.Level .. "] " .. entry.Text, 10, color, {
                Size = UDim2.new(1, -12, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                TextWrapped = true,
                TextYAlignment = Enum.TextYAlignment.Top,
                LayoutOrder = index,
                Font = Enum.Font.Code,
                Position = UDim2.fromOffset(6, 0),
            })
        end
        api.Value = clone(lines)
    end
    local function write(message: any, level: string?)
        table.insert(lines, { Text = tostring(message), Level = level or "Info" })
        while #lines > maxLines do table.remove(lines, 1) end
        renderLines()
    end
    function api:Write(message: any, level: string?) write(message, level); return self end
    function api:Clear()
        table.clear(lines)
        renderLines()
        return self
    end
    api._applyTheme = function(active: {[string]: any})
        output.BackgroundColor3 = active.Window
        renderLines()
    end
    api.Value = {}
    if options.InitialText then write(options.InitialText, "Info") end
    if api.Disabled then api:SetDisabled(true) end
    return api
end

local function createChangelog(section: any, options: any): any
    local api, _, body = createBase(section, "Changelog", options)
    local list = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, body)
    make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, list)
    local function render()
        for _, child in ipairs(list:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
        for index, entry in ipairs(type(api.Value) == "table" and api.Value or {}) do
            local item = type(entry) == "table" and entry or { Title = tostring(entry) }
            local card = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = api.Library.ThemeManager.Current.Surface, BorderSizePixel = 0, LayoutOrder = index }, list)
            round(card, 6)
            text(card, tostring(item.Version or item.Date or "UPDATE"), 9, api.Library.ThemeManager.Current.Accent, { Position = UDim2.fromOffset(9, 6), Size = UDim2.new(1, -18, 0, 14), Font = Enum.Font.GothamBold })
            text(card, tostring(item.Title or "Update"), 12, api.Library.ThemeManager.Current.Text, { Position = UDim2.fromOffset(9, 22), Size = UDim2.new(1, -18, 0, 18), Font = Enum.Font.GothamBold })
            text(card, tostring(item.Content or item.Description or ""), 10, api.Library.ThemeManager.Current.Muted, { Position = UDim2.fromOffset(9, 42), Size = UDim2.new(1, -18, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
        end
    end
    function api:SetEntries(entries: {any}) self:Set(entries); return self end
    api._render = render
    api._applyTheme = render
    return finish(api, options.Entries or options.Items or {}, function(value) return type(value) == "table" and clone(value) or {} end, render)
end

local function createRating(section: any, options: any): any
    local api, _, body, theme = createBase(section, "Rating", options)
    local maximum = math.clamp(math.floor(tonumber(options.Max) or 5), 1, 10)
    local stars = make("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, body)
    make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, stars)
    local starButtons = {}
    local function render()
        for index, star in ipairs(starButtons) do
            star.TextColor3 = index <= (api.Value or 0) and api.Library.ThemeManager.Current.Accent or api.Library.ThemeManager.Current.Muted
        end
    end
    for index = 1, maximum do
        local star = button(stars, "★", { Size = UDim2.fromOffset(25, 28), BackgroundTransparency = 1, TextColor3 = theme.Muted, TextSize = 22, LayoutOrder = index })
        table.insert(starButtons, star)
        api._janitor:Add(star.Activated:Connect(function() api:Set(index, false, "UI") end))
    end
    api._applyTheme = render
    return finish(api, options.Default or 0, function(value) return math.clamp(math.floor(tonumber(value) or 0), 0, maximum) end, render)
end

local function createGrid(section: any, kind: string, options: any): any
    local api, _, body = createBase(section, kind, options)
    local grid = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, body)
    local columns = math.clamp(math.floor(tonumber(options.Columns) or 3), 1, 6)
    local cellHeight = tonumber(options.CellHeight) or (kind == "AssetGrid" and 104 or 88)
    local gridLayout = make("UIGridLayout", {
        CellSize = UDim2.new(1 / columns, -7, 0, cellHeight),
        CellPadding = UDim2.fromOffset(7, 7),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, grid)
    local items = normalizeItems(options.Items or {})
    local renderJanitor = Janitor.new()
    api._janitor:Add(function() renderJanitor:Destroy() end)
    local function render()
        renderJanitor:Destroy()
        renderJanitor = Janitor.new()
        for _, child in ipairs(grid:GetChildren()) do
            if child:IsA("ImageButton") or child:IsA("TextButton") then child:Destroy() end
        end
        for index, item in ipairs(items) do
            local selected = same(item.Value, api.Value)
            local tile = button(grid, "", {
                BackgroundColor3 = selected and api.Library.ThemeManager.Current.Accent or api.Library.ThemeManager.Current.Surface,
                LayoutOrder = index,
            })
            round(tile, 7)
            local imageSource = item.Image
            if imageSource then
                make("ImageLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, -10, 0, cellHeight - 36),
                    Position = UDim2.fromOffset(5, 5),
                    Image = tostring(imageSource),
                    ScaleType = Enum.ScaleType.Crop,
                }, tile)
            end
            text(tile, item.Title, 9, selected and api.Library.ThemeManager.Current.AccentText or api.Library.ThemeManager.Current.Text, {
                Position = UDim2.new(0, 5, 1, -27),
                Size = UDim2.new(1, -10, 0, 22),
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Center,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })
            renderJanitor:Add(tile.Activated:Connect(function()
                api:Set(item.Value, false, "UI")
                if type(item.Callback) == "function" then
                    local ok, err = pcall(item.Callback, item.Value, { Source = "UI", Action = "GridItemSelected" })
                    if not ok then warn("[SilentUI] Grid callback failed: " .. tostring(err)) end
                end
            end))
        end
        gridLayout.CellSize = UDim2.new(1 / columns, -7, 0, cellHeight)
    end
    function api:SetItems(nextItems: {any})
        items = normalizeItems(nextItems)
        self:Set(self.Value, true)
        render()
        return self
    end
    api._normalize = function(value: any): any
        for _, item in ipairs(items) do
            if same(item.Value, value) then return value end
        end
        return value
    end
    api._render = render
    api._applyTheme = render
    return finish(api, options.Default, api._normalize, render)
end

local function createInfoGrid(section: any, options: any, kind: string?): any
    local api, _, body = createBase(section, kind or "InfoGrid", options)
    local container = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, body)
    make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, container)
    local function render()
        for _, child in ipairs(container:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
        for index, rawEntry in ipairs(type(api.Value) == "table" and api.Value or {}) do
            local entry = if type(rawEntry) == "table" then rawEntry else { Label = tostring(rawEntry) }
            local row = make("Frame", { Size = UDim2.new(1, 0, 0, 25), BackgroundTransparency = 1, LayoutOrder = index }, container)
            text(row, tostring(entry.Label or entry.Name or ""), 10, api.Library.ThemeManager.Current.Muted, { Size = UDim2.new(0.45, 0, 1, 0) })
            text(row, tostring(entry.Value or "—"), 10, api.Library.ThemeManager.Current.Text, { Position = UDim2.new(0.45, 0, 0, 0), Size = UDim2.new(0.55, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
            make("Frame", { Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = api.Library.ThemeManager.Current.Border, BackgroundTransparency = 0.7, BorderSizePixel = 0 }, row)
        end
    end
    function api:SetItems(items: {any}) self:Set(items); return self end
    api._render = render
    api._applyTheme = render
    return finish(api, options.Items or {}, function(value) return type(value) == "table" and clone(value) or {} end, render)
end

local function createLineText(section: any, options: any): any
    local api, _, body, theme = createBase(section, "LineText", options)
    local row = make("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1 }, body)
    local left = text(row, tostring(options.Label or options.Name or options.Title or ""), 10, theme.Muted, {
        Size = UDim2.new(0.55, -6, 1, 0),
    })
    local right = text(row, tostring(options.Value or "—"), 10, theme.Text, {
        Position = UDim2.new(0.55, 6, 0, 0),
        Size = UDim2.new(0.45, -6, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    local line = make("Frame", {
        Position = UDim2.new(0, 0, 1, -1),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = theme.Border,
        BackgroundTransparency = 0.65,
        BorderSizePixel = 0,
    }, row)
    local function render()
        left.TextColor3 = api.Library.ThemeManager.Current.Muted
        right.TextColor3 = api.Library.ThemeManager.Current.Text
        line.BackgroundColor3 = api.Library.ThemeManager.Current.Border
    end
    function api:SetText(value: string)
        right.Text = tostring(value)
        self.Value = right.Text
        return self
    end
    api._applyTheme = render
    api.Value = right.Text
    return finish(api, api.Value, function(value) return tostring(value or "") end, function()
        right.Text = tostring(api.Value)
        render()
    end)
end

local function createGradientCard(section: any, options: any): any
    local api, row, body, theme = createBase(section, "GradientCard", options)
    local gradient = make("UIGradient", {
        Color = if typeof(options.Gradient) == "ColorSequence" then options.Gradient else ColorSequence.new(
            options.StartColor or theme.Accent,
            options.EndColor or theme.Surface
        ),
        Rotation = tonumber(options.Rotation) or 35,
    }, row) :: UIGradient
    local heading = text(body, tostring(options.Heading or options.Title or ""), 13, options.TextColor or theme.Text, {
        Size = UDim2.new(1, 0, 0, 22),
        Font = Enum.Font.GothamBold,
        LayoutOrder = 1,
    })
    local description = text(body, tostring(options.Content or options.Description or ""), 10, theme.Muted, {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = 2,
    })
    if options.ButtonText or options.Callback then
        local action = button(body, tostring(options.ButtonText or "Open"), {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundColor3 = options.ButtonColor or theme.Accent,
            TextColor3 = options.ButtonTextColor or theme.AccentText,
            LayoutOrder = 3,
        })
        round(action, 7)
        api._janitor:Add(action.Activated:Connect(function()
            if type(options.Callback) == "function" then
                local ok, err = pcall(options.Callback, true, { Source = "UI", Action = "GradientCardActivated" })
                if not ok then warn("[SilentUI] GradientCard callback failed: " .. tostring(err)) end
            end
        end))
    end
    function api:SetContent(value: string)
        description.Text = tostring(value)
        self.Value = description.Text
        return self
    end
    api._applyTheme = function(active: {[string]: any})
        if options.Gradient == nil then
            gradient.Color = ColorSequence.new(options.StartColor or active.Accent, options.EndColor or active.Surface)
        end
        heading.TextColor3 = options.TextColor or active.Text
        description.TextColor3 = active.Muted
    end
    api.Value = description.Text
    return finish(api, api.Value, function(value) return tostring(value or "") end, function()
        description.Text = tostring(api.Value)
        api._applyTheme(theme)
    end)
end

local function createLoadout(section: any, options: any): any
    local api, _, body = createBase(section, "LoadoutGroup", options)
    local container = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, body)
    make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5) }, container)
    local function render()
        for _, child in ipairs(container:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
        for index, rawEntry in ipairs(type(api.Value) == "table" and api.Value or {}) do
            local entry = if type(rawEntry) == "table" then rawEntry else { Value = tostring(rawEntry) }
            local row = make("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = api.Library.ThemeManager.Current.Surface, BorderSizePixel = 0, LayoutOrder = index }, container)
            round(row, 6)
            text(row, tostring(entry.Slot or entry.Title or "Slot"), 10, api.Library.ThemeManager.Current.Muted, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0.32, -8, 1, 0) })
            text(row, tostring(entry.Value or entry.Item or "Empty"), 10, api.Library.ThemeManager.Current.Text, { Position = UDim2.new(0.32, 0, 0, 0), Size = UDim2.new(0.68, -12, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
        end
    end
    function api:SetSlots(slots: {any}) self:Set(slots); return self end
    api._render = render
    api._applyTheme = render
    return finish(api, options.Slots or options.Items or {}, function(value) return type(value) == "table" and clone(value) or {} end, render)
end

local function createStateList(section: any, options: any): any
    local api, _, body = createBase(section, "StateList", options)
    local container = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, body)
    make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, container)
    local function render()
        for _, child in ipairs(container:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
        for index, rawEntry in ipairs(type(api.Value) == "table" and api.Value or {}) do
            local entry = if type(rawEntry) == "table" then rawEntry else { Title = tostring(rawEntry) }
            local row = make("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = index }, container)
            local active = entry.Active == true or entry.State == true or entry.Status == "Online" or entry.Status == "Active"
            local dot = make("Frame", { Size = UDim2.fromOffset(7, 7), Position = UDim2.fromOffset(2, 8), BackgroundColor3 = active and api.Library.ThemeManager.Current.Success or api.Library.ThemeManager.Current.Muted, BorderSizePixel = 0 }, row)
            round(dot, 4)
            text(row, tostring(entry.Title or entry.Name or "State"), 10, api.Library.ThemeManager.Current.Text, { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(0.65, -16, 1, 0) })
            text(row, tostring(entry.Value or entry.Status or (active and "Active" or "Inactive")), 9, api.Library.ThemeManager.Current.Muted, { Position = UDim2.new(0.65, 0, 0, 0), Size = UDim2.new(0.35, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
        end
    end
    function api:SetStates(states: {any}) self:Set(states); return self end
    api._render = render
    api._applyTheme = render
    return finish(api, options.Items or options.States or {}, function(value) return type(value) == "table" and clone(value) or {} end, render)
end

function AdvancedControls.Supports(kind: string): boolean
    return SUPPORTED[kind] == true
end

function AdvancedControls.Create(section: any, kind: string, options: any): any
    assert(SUPPORTED[kind], "Unsupported advanced control: " .. kind)
    if kind == "Stepper" then return createStepper(section, options) end
    if kind == "Progress" then return createProgress(section, options) end
    if kind == "Divider" then return createDivider(section, options) end
    if kind == "Segmented" then return createSegmented(section, options) end
    if kind == "Stats" then return createStats(section, options) end
    if kind == "Image" then return createImage(section, options) end
    if kind == "Video" then return createVideo(section, options) end
    if kind == "Code" then return createCode(section, options) end
    if kind == "Tag" then return createTag(section, options) end
    if kind == "Card" then return createCard(section, options) end
    if kind == "Table" then return createTable(section, options) end
    if kind == "Console" then return createConsole(section, options) end
    if kind == "Changelog" then return createChangelog(section, options) end
    if kind == "Rating" then return createRating(section, options) end
    if kind == "AssetGrid" or kind == "CardGrid" then return createGrid(section, kind, options) end
    if kind == "InfoGrid" then return createInfoGrid(section, options, "InfoGrid") end
    if kind == "SystemInfoGrid" then return createInfoGrid(section, options, "SystemInfoGrid") end
    if kind == "GradientCard" then return createGradientCard(section, options) end
    if kind == "LineText" then return createLineText(section, options) end
    if kind == "LoadoutGroup" then return createLoadout(section, options) end
    if kind == "StateList" then return createStateList(section, options) end
    error("Advanced control factory is missing: " .. kind)
end

__SUI_UI_AdvancedControls = AdvancedControls
end

-- ===== Module: UI.Section =====
local __SUI_UI_Section
do
-- Section layout and component factory surface.

local Janitor = __SUI_Core_Janitor
local Controls = __SUI_UI_Controls
local AdvancedControls = __SUI_UI_AdvancedControls

local Section = {}
Section.__index = Section

local function make(className: string, properties: {[string]: any}, parent: Instance?): Instance
    local instance = Instance.new(className)
    for property, value in pairs(properties) do
        (instance :: any)[property] = value
    end
    if parent then
        instance.Parent = parent
    end
    return instance
end

function Section.new(tab: any, options: any?): any
    local opts = if type(options) == "string" then { Title = options } else (options or {})
    local theme = tab.Window.Library.ThemeManager.Current
    local self = setmetatable({
        Tab = tab,
        Window = tab.Window,
        Title = tostring(opts.Title or opts.Name or ""),
        Options = opts,
        Elements = {},
        Groups = {},
        Destroyed = false,
        _janitor = Janitor.new(),
    }, Section)

    local frame = make("Frame", {
        Name = "Section",
        BackgroundColor3 = theme.Surface,
        BackgroundTransparency = tonumber(theme.SurfaceTransparency) or 0.16,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -4, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = #tab.Sections + 1,
        ClipsDescendants = false,
    }, tab.Page) :: Frame
    self.Frame = frame
    make("UICorner", { CornerRadius = UDim.new(0, 10) }, frame)
    self._stroke = make("UIStroke", {
        Color = theme.Border,
        Transparency = 0.42,
        Thickness = 1,
    }, frame) :: UIStroke
    make("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 11),
        PaddingRight = UDim.new(0, 11),
    }, frame)

    local layout = make("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
    }, frame) :: UIListLayout
    self._janitor:Add(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        frame.Size = UDim2.new(1, -4, 0, layout.AbsoluteContentSize.Y + 20)
    end))

    if self.Title ~= "" then
        local heading = make("TextLabel", {
            Name = "SectionTitle",
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 20),
            Text = string.upper(self.Title),
            TextColor3 = theme.Muted,
            TextSize = 10,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = 1,
        }, frame) :: TextLabel
        self.Heading = heading
    end

    self._janitor:Add(tab.Window.Library.ThemeManager.Changed:Connect(function()
        self:ApplyTheme()
    end))
    self:ApplyTheme()
    return self
end

function Section:SetTitle(title: string)
    self.Title = tostring(title)
    if self.Heading then
        self.Heading.Text = string.upper(self.Title)
        self.Heading.Visible = self.Title ~= ""
    elseif self.Title ~= "" then
        self.Heading = make("TextLabel", {
            Name = "SectionTitle",
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 20),
            Text = string.upper(self.Title),
            TextColor3 = self.Window.Library.ThemeManager.Current.Muted,
            TextSize = 10,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = 1,
        }, self.Frame) :: TextLabel
    end
    return self
end

function Section:SetVisible(visible: boolean)
    if not self.Destroyed then self.Frame.Visible = visible == true end
    return self
end

function Section:Show() return self:SetVisible(true) end
function Section:Hide() return self:SetVisible(false) end
function Section:Open() return self:SetVisible(true) end
function Section:Close() return self:SetVisible(false) end

function Section:LockAll()
    for _, control in ipairs(self.Elements) do
        if type(control.SetDisabled) == "function" then control:SetDisabled(true) end
    end
    for _, group in ipairs(self.Groups) do group:LockAll() end
    return self
end

function Section:UnlockAll()
    for _, control in ipairs(self.Elements) do
        if type(control.SetDisabled) == "function" then control:SetDisabled(false) end
    end
    for _, group in ipairs(self.Groups) do group:UnlockAll() end
    return self
end

function Section:ApplyTheme()
    if self.Destroyed then
        return
    end
    local theme = self.Window.Library.ThemeManager.Current
    self.Frame.BackgroundColor3 = theme.Surface
    self.Frame.BackgroundTransparency = tonumber(theme.SurfaceTransparency) or 0.16
    self._stroke.Color = theme.Border
    if self.Heading then
        self.Heading.TextColor3 = theme.Muted
    end
end

function Section:_Create(kind: string, options: any): any
    assert(not self.Destroyed, "Section has been destroyed")
    local control = if AdvancedControls.Supports(kind) then AdvancedControls.Create(self, kind, options or {}) else Controls.Create(self, kind, options or {})
    table.insert(self.Elements, control)
    table.insert(self.Window.Library.Controls, control)
    self.Window.Library.ControlsChanged:Fire("Added", control)
    return control
end

function Section:Toggle(options: any): any
    return self:_Create("Toggle", options)
end

function Section:Slider(options: any): any
    return self:_Create("Slider", options)
end

function Section:Dropdown(options: any): any
    return self:_Create("Dropdown", options)
end

function Section:Textbox(options: any): any
    return self:_Create("Textbox", options)
end

function Section:Keybind(options: any): any
    return self:_Create("Keybind", options)
end

function Section:ColorPicker(options: any): any
    return self:_Create("ColorPicker", options)
end

function Section:Button(options: any): any
    return self:_Create("Button", options)
end

function Section:Label(options: any): any
    return self:_Create("Label", options)
end

function Section:Paragraph(options: any): any
    return self:_Create("Paragraph", options)
end


function Section:Stepper(options: any): any
    return self:_Create("Stepper", options)
end

function Section:Progress(options: any): any
    return self:_Create("Progress", options)
end

function Section:Divider(options: any?): any
    return self:_Create("Divider", options or {})
end

function Section:Segmented(options: any): any
    return self:_Create("Segmented", options)
end

function Section:Stats(options: any): any
    return self:_Create("Stats", options)
end

function Section:Image(options: any): any
    return self:_Create("Image", options)
end

function Section:Video(options: any): any
    return self:_Create("Video", options)
end

function Section:Code(options: any): any
    return self:_Create("Code", options)
end

function Section:Tag(options: any): any
    return self:_Create("Tag", options)
end

function Section:Card(options: any): any
    return self:_Create("Card", options)
end

function Section:Table(options: any): any
    return self:_Create("Table", options)
end

function Section:Console(options: any): any
    return self:_Create("Console", options)
end

function Section:Changelog(options: any): any
    return self:_Create("Changelog", options)
end

function Section:Rating(options: any): any
    return self:_Create("Rating", options)
end

function Section:AssetGrid(options: any): any
    return self:_Create("AssetGrid", options)
end

function Section:CardGrid(options: any): any
    return self:_Create("CardGrid", options)
end

function Section:InfoGrid(options: any): any
    return self:_Create("InfoGrid", options)
end

function Section:SystemInfoGrid(options: any): any
    return self:_Create("SystemInfoGrid", options)
end

function Section:GradientCard(options: any): any
    return self:_Create("GradientCard", options)
end

function Section:LineText(options: any): any
    return self:_Create("LineText", options)
end

function Section:LoadoutGroup(options: any): any
    return self:_Create("LoadoutGroup", options)
end

function Section:StateList(options: any): any
    return self:_Create("StateList", options)
end

-- Nested groups provide the Section -> Group -> Element composition used by
-- Direct element creation reuses this section's ownership and input manager.
function Section:Group(options: any): any
    assert(not self.Destroyed, "Section has been destroyed")
    local hostTab = {
        Window = self.Window,
        Page = self.Frame,
        Sections = self.Groups,
    }
    local group = Section.new(hostTab, options)
    table.insert(self.Groups, group)
    return group
end

-- Creates multiple side-by-side section groups. Each returned group exposes
-- the same control API as a regular Section.
function Section:MultiSection(options: any): {any}
    assert(not self.Destroyed, "Section has been destroyed")
    local config = options or {}
    local titles = config.Sections or config.Titles or {"Left", "Right"}
    local count = math.max(1, #titles)
    local container = make("Frame", {
        Name = "MultiSection",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = #self.Elements + #self.Groups + 1,
    }, self.Frame)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        VerticalAlignment = Enum.VerticalAlignment.Top,
    }, container)

    local groups = {}
    for index, title in ipairs(titles) do
        local column = make("Frame", {
            Name = "MultiSectionColumn" .. tostring(index),
            BackgroundTransparency = 1,
            Size = UDim2.new(1 / count, -6, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = index,
        }, container)
        make("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
        }, column)
        local hostTab = {
            Window = self.Window,
            Page = column,
            Sections = self.Groups,
        }
        local group = Section.new(hostTab, title)
        group.Frame.Size = UDim2.new(1, -2, 0, 0)
        table.insert(self.Groups, group)
        table.insert(groups, group)
    end
    return groups
end


function Section:ToggleKeybind(options: any): any
    local config = options or {}
    local toggle = self:Toggle({
        Title = config.Title or config.Name or "Toggle",
        Description = config.Description,
        Flag = config.Flag,
        Default = config.Default == true,
        Callback = config.Callback,
        Tooltip = config.Tooltip,
    })
    local keybind = self:Keybind({
        Title = config.KeybindTitle or "Activation key",
        Description = config.KeybindDescription,
        Flag = config.KeybindFlag,
        Default = config.Key or config.Keybind,
        Context = config.Context,
        Callback = function()
            toggle:Set(not toggle:Get(), false, "Keybind")
        end,
    })
    local composite = { Toggle = toggle, Keybind = keybind }
    function composite:Get() return toggle:Get() end
    function composite:Set(value: boolean, silent: boolean?) return toggle:Set(value, silent) end
    function composite:SetVisible(visible: boolean)
        toggle:SetVisible(visible)
        keybind:SetVisible(visible)
        return self
    end
    function composite:Destroy()
        keybind:Destroy()
        toggle:Destroy()
    end
    return composite
end

function Section:ButtonKeybind(options: any): any
    local config = options or {}
    local buttonControl = self:Button({
        Title = config.Title or config.Name or "Action",
        ButtonText = config.ButtonText,
        Description = config.Description,
        Callback = config.Callback,
    })
    local keybind = self:Keybind({
        Title = config.KeybindTitle or "Action key",
        Flag = config.KeybindFlag,
        Default = config.Key or config.Keybind,
        Context = config.Context,
        Callback = function()
            buttonControl:Activate()
        end,
    })
    local composite = { Button = buttonControl, Keybind = keybind }
    function composite:Click() buttonControl:Activate(); return self end
    function composite:SetVisible(visible: boolean)
        buttonControl:SetVisible(visible)
        keybind:SetVisible(visible)
        return self
    end
    function composite:Destroy()
        keybind:Destroy()
        buttonControl:Destroy()
    end
    return composite
end

function Section:MultiDropdown(options: any): any
    local config = table.clone(options or {})
    config.Multi = true
    return self:Dropdown(config)
end

function Section:Input(options: any): any
    return self:Textbox(options)
end

function Section:Colorpicker(options: any): any
    return self:ColorPicker(options)
end

local function resolveControlList(controls: any): {any}
    if type(controls) ~= "table" then return { controls } end
    if controls.Get or controls.SetVisible or controls.SetDisabled then return { controls } end
    return controls
end

function Section:BindEnabledWhen(sourceControl: any, predicate: (any) -> boolean, controls: any): any
    assert(sourceControl and type(sourceControl.Get) == "function" and type(sourceControl.OnChanged) == "function", "Binding source must be a control")
    assert(type(predicate) == "function", "Predicate must be a function")
    local targets = resolveControlList(controls)
    local janitor = Janitor.new()
    local function apply(value: any)
        local ok, result = pcall(predicate, value)
        local enabled = ok and result == true
        for _, target in ipairs(targets) do
            if target and not target.Destroyed and type(target.SetDisabled) == "function" then
                target:SetDisabled(not enabled)
            end
        end
    end
    apply(sourceControl:Get())
    janitor:Add(sourceControl:OnChanged(apply))
    local binding = {}
    function binding:Destroy() janitor:Destroy() end
    return binding
end

function Section:BindVisibleWhen(sourceControl: any, predicate: (any) -> boolean, controls: any): any
    assert(sourceControl and type(sourceControl.Get) == "function" and type(sourceControl.OnChanged) == "function", "Binding source must be a control")
    assert(type(predicate) == "function", "Predicate must be a function")
    local targets = resolveControlList(controls)
    local janitor = Janitor.new()
    local function apply(value: any)
        local ok, result = pcall(predicate, value)
        local visible = ok and result == true
        for _, target in ipairs(targets) do
            if target and not target.Destroyed and type(target.SetVisible) == "function" then
                target:SetVisible(visible)
            end
        end
    end
    apply(sourceControl:Get())
    janitor:Add(sourceControl:OnChanged(apply))
    local binding = {}
    function binding:Destroy() janitor:Destroy() end
    return binding
end

Section.AddToggle = Section.Toggle
Section.AddSlider = Section.Slider
Section.AddDropdown = Section.Dropdown
Section.AddTextbox = Section.Textbox
Section.AddInput = Section.Input
Section.AddKeybind = Section.Keybind
Section.AddColorPicker = Section.ColorPicker
Section.AddButton = Section.Button
Section.AddLabel = Section.Label
Section.AddParagraph = Section.Paragraph
Section.AddProgress = Section.Progress
Section.AddStepper = Section.Stepper
Section.AddSegmented = Section.Segmented
Section.AddStats = Section.Stats
Section.AddImage = Section.Image
Section.AddVideo = Section.Video
Section.AddCode = Section.Code
Section.AddTable = Section.Table
Section.AddConsole = Section.Console
Section.AddCard = Section.Card
Section.AddTag = Section.Tag
Section.AddChangelog = Section.Changelog
Section.AddRating = Section.Rating
Section.AddSubSection = Section.Group
Section.CreateToggle = Section.Toggle
Section.CreateSlider = Section.Slider
Section.CreateDropdown = Section.Dropdown
Section.CreateInput = Section.Input
Section.CreateKeybind = Section.Keybind
Section.CreateColorPicker = Section.ColorPicker
Section.CreateButton = Section.Button
Section.CreateLabel = Section.Label
Section.CreateParagraph = Section.Paragraph
Section.CreateStepper = Section.Stepper
Section.CreateProgress = Section.Progress
Section.CreateSegmented = Section.Segmented
Section.CreateStats = Section.Stats
Section.CreateImage = Section.Image
Section.CreateVideo = Section.Video
Section.CreateCode = Section.Code
Section.CreateTag = Section.Tag
Section.CreateCard = Section.Card
Section.CreateTable = Section.Table
Section.CreateConsole = Section.Console
Section.CreateChangelog = Section.Changelog
Section.CreateRating = Section.Rating
Section.CreateAssetGrid = Section.AssetGrid
Section.CreateCardGrid = Section.CardGrid
Section.CreateInfoGrid = Section.InfoGrid
Section.CreateSystemInfoGrid = Section.SystemInfoGrid
Section.CreateGradientCard = Section.GradientCard
Section.CreateLineText = Section.LineText
Section.CreateLoadoutGroup = Section.LoadoutGroup
Section.CreateStateList = Section.StateList

function Section:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true

    local groups = table.clone(self.Groups)
    for _, group in ipairs(groups) do
        group:Destroy()
    end
    table.clear(self.Groups)

    local controls = table.clone(self.Elements)
    for _, control in ipairs(controls) do
        control:Destroy()
    end
    table.clear(self.Elements)
    self._janitor:Destroy()
    if self.Frame.Parent ~= nil then
        self.Frame:Destroy()
    end

    for index, section in ipairs(self.Tab.Sections) do
        if section == self then
            table.remove(self.Tab.Sections, index)
            break
        end
    end
end

__SUI_UI_Section = Section
end

-- ===== Module: UI.Tab =====
local __SUI_UI_Tab
do
-- Tab navigation and page ownership.

local Janitor = __SUI_Core_Janitor
local Section = __SUI_UI_Section

local Tab = {}
Tab.__index = Tab

local function make(className: string, properties: {[string]: any}, parent: Instance?): Instance
    local instance = Instance.new(className)
    for property, value in pairs(properties) do
        (instance :: any)[property] = value
    end
    if parent then
        instance.Parent = parent
    end
    return instance
end

function Tab.new(window: any, options: any?): any
    local opts = options or {}
    local title = tostring(opts.Title or opts.Name or ("Tab " .. tostring(#window.Tabs + 1)))
    local theme = window.Library.ThemeManager.Current

    local self = setmetatable({
        Window = window,
        Title = title,
        Options = opts,
        Sections = {},
        SubTabs = {},
        _defaultSection = nil,
        Private = opts.Private == true,
        UserVisible = opts.Visible ~= false and opts.Private ~= true,
        SearchVisible = true,
        CurrentSubTab = nil,
        SubTabBar = nil,
        Selected = false,
        Destroyed = false,
        _janitor = Janitor.new(),
    }, Tab)

    local button = make("TextButton", {
        Name = "TabButton",
        Size = UDim2.fromOffset(math.max(82, math.min(138, #title * 8 + 28)), 32),
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = 0.52,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = title,
        TextColor3 = theme.Muted,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        LayoutOrder = #window.Tabs + 1,
        ZIndex = 6,
        Visible = opts.Visible ~= false and opts.Private ~= true,
    }, window.TabBar) :: TextButton
    self.Button = button
    make("UICorner", { CornerRadius = UDim.new(0, 8) }, button)
    local icon = opts.Icon
    local iconDescriptor = if icon ~= nil then window.Library:GetIcon(icon, opts.IconPack) else nil
    if iconDescriptor ~= nil then
        self.IconImage = make("ImageLabel", {
            Name = "TabIcon",
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(8, 8),
            Size = UDim2.fromOffset(16, 16),
            Image = iconDescriptor.Image,
            ImageRectSize = iconDescriptor.ImageRectSize or Vector2.zero,
            ImageRectOffset = iconDescriptor.ImageRectOffset or Vector2.zero,
            ImageColor3 = theme.Muted,
            ZIndex = 7,
        }, button) :: ImageLabel
        button.TextXAlignment = Enum.TextXAlignment.Left
        make("UIPadding", { PaddingLeft = UDim.new(0, 28), PaddingRight = UDim.new(0, 8) }, button)
    end

    local page = make("ScrollingFrame", {
        Name = "Page_" .. title:gsub("%W", ""),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = theme.Accent,
        Visible = false,
        ZIndex = 6,
    }, window.Content) :: ScrollingFrame
    self.Page = page

    local padding = make("UIPadding", {
        PaddingTop = UDim.new(0, 5),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 2),
        PaddingRight = UDim.new(0, 5),
    }, page)
    local layout = make("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
    }, page)
    self._janitor:Add(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 20)
    end))
    self._janitor:Add(button.Activated:Connect(function()
        window:SelectTab(self)
    end))
    self._janitor:Add(window.Library.ThemeManager.Changed:Connect(function()
        self:ApplyTheme()
    end))

    self:ApplyTheme()
    return self
end

function Tab:ApplyTheme()
    if self.Destroyed then
        return
    end
    local theme = self.Window.Library.ThemeManager.Current
    self.Button.BackgroundColor3 = self.Selected and theme.Accent or theme.SurfaceAlt
    self.Button.BackgroundTransparency = self.Selected and 0.05 or 0.52
    self.Button.TextColor3 = self.Selected and theme.AccentText or theme.Muted
    if self.IconImage then self.IconImage.ImageColor3 = self.Selected and theme.AccentText or theme.Muted end
    self.Page.ScrollBarImageColor3 = theme.Accent
end

function Tab:SetSelected(selected: boolean)
    if self.Destroyed then
        return
    end
    self.Selected = selected
    self.Page.Visible = selected
    self.Button.Visible = self.UserVisible and self.SearchVisible
    self:ApplyTheme()
end

function Tab:SetVisible(visible: boolean)
    self.UserVisible = visible == true
    self.Button.Visible = self.UserVisible and self.SearchVisible
    if not self.Button.Visible and self.Selected then
        for _, candidate in ipairs(self.Window.Tabs) do
            if candidate ~= self and candidate.Button.Visible then
                self.Window:SelectTab(candidate)
                break
            end
        end
    end
    return self
end

function Tab:SetPrivate(private: boolean)
    self.Private = private == true
    self.UserVisible = not self.Private
    self.Button.Visible = self.UserVisible and self.SearchVisible
    return self
end

function Tab:SetTitle(title: string)
    self.Title = tostring(title)
    self.Button.Text = self.Title
    self.Button.Size = UDim2.fromOffset(math.max(82, math.min(138, #self.Title * 8 + 28)), 32)
    return self
end

function Tab:SetIcon(icon: any)
    if icon == nil or tostring(icon) == "" then
        if self.IconImage then self.IconImage:Destroy(); self.IconImage = nil end
        local padding = self.Button:FindFirstChildOfClass("UIPadding")
        if padding then padding:Destroy() end
        self.Button.TextXAlignment = Enum.TextXAlignment.Center
        return self
    end
    local descriptor = self.Window.Library:GetIcon(icon)
    if descriptor == nil then return self end
    if not self.IconImage then
        self.IconImage = make("ImageLabel", { Name = "TabIcon", BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(16, 16), ZIndex = 7 }, self.Button) :: ImageLabel
        self.Button.TextXAlignment = Enum.TextXAlignment.Left
        make("UIPadding", { PaddingLeft = UDim.new(0, 28), PaddingRight = UDim.new(0, 8) }, self.Button)
    end
    self.IconImage.Image = descriptor.Image
    self.IconImage.ImageRectSize = descriptor.ImageRectSize or Vector2.zero
    self.IconImage.ImageRectOffset = descriptor.ImageRectOffset or Vector2.zero
    self:ApplyTheme()
    return self
end

function Tab:Section(options: any?): any
    assert(not self.Destroyed, "Tab has been destroyed")
    local section = Section.new(self, options)
    table.insert(self.Sections, section)
    return section
end

local SubTab = {}
SubTab.__index = SubTab

function SubTab.new(tab: any, options: any): any
    local opts = if type(options) == "string" then { Title = options } else (options or {})
    local theme = tab.Window.Library.ThemeManager.Current
    if tab.SubTabBar == nil then
        local bar = make("Frame", {
            Name = "SubTabBar",
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 32),
            LayoutOrder = -1000,
        }, tab.Page) :: Frame
        make("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
        }, bar)
        tab.SubTabBar = bar
    end

    local self = setmetatable({
        Tab = tab,
        Window = tab.Window,
        Title = tostring(opts.Title or opts.Name or ("SubTab " .. tostring(#tab.SubTabs + 1))),
        Sections = {},
        _defaultSection = nil,
        Destroyed = false,
        Selected = false,
        UserVisible = opts.Visible ~= false,
        _janitor = Janitor.new(),
    }, SubTab)

    self.Button = make("TextButton", {
        Name = "SubTabButton",
        Size = UDim2.fromOffset(math.max(76, math.min(132, #self.Title * 7 + 25)), 28),
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = self.Title,
        TextColor3 = theme.Muted,
        TextSize = 11,
        Font = Enum.Font.GothamMedium,
        LayoutOrder = #tab.SubTabs + 1,
        Visible = self.UserVisible,
    }, tab.SubTabBar) :: TextButton
    make("UICorner", { CornerRadius = UDim.new(0, 7) }, self.Button)

    self.Page = make("Frame", {
        Name = "SubTabPage_" .. self.Title:gsub("%W", ""),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = #tab.SubTabs + 1,
        Visible = false,
    }, tab.Page) :: Frame
    local layout = make("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
    }, self.Page) :: UIListLayout
    self._janitor:Add(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        self.Page.Size = UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y + 4)
    end))
    self._janitor:Add(self.Button.Activated:Connect(function()
        tab:SelectSubTab(self)
    end))
    self._janitor:Add(tab.Window.Library.ThemeManager.Changed:Connect(function()
        self:ApplyTheme()
    end))
    table.insert(tab.SubTabs, self)
    if tab.CurrentSubTab == nil then
        tab:SelectSubTab(self)
    end
    return self
end

function SubTab:ApplyTheme()
    if self.Destroyed then return end
    local theme = self.Window.Library.ThemeManager.Current
    self.Button.BackgroundColor3 = self.Selected and theme.Accent or theme.SurfaceAlt
    self.Button.BackgroundTransparency = self.Selected and 0.05 or 0.45
    self.Button.TextColor3 = self.Selected and theme.AccentText or theme.Muted
end

function SubTab:Section(options: any?): any
    assert(not self.Destroyed, "SubTab has been destroyed")
    local section = Section.new(self, options)
    table.insert(self.Sections, section)
    return section
end

SubTab.AddSection = SubTab.Section
SubTab.CreateSection = SubTab.Section

function SubTab:SetTitle(title: string)
    self.Title = tostring(title)
    self.Button.Text = self.Title
    self.Button.Size = UDim2.fromOffset(math.max(82, math.min(138, #self.Title * 8 + 28)), 28)
    return self
end

function SubTab:SetVisible(visible: boolean)
    self.UserVisible = visible == true
    self.Button.Visible = self.UserVisible
    if not self.UserVisible and self.Selected then
        self.Page.Visible = false
        for _, candidate in ipairs(self.Tab.SubTabs) do
            if candidate ~= self and candidate.UserVisible then
                self.Tab:SelectSubTab(candidate)
                break
            end
        end
    end
    return self
end

function SubTab:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    local sections = table.clone(self.Sections)
    for _, section in ipairs(sections) do section:Destroy() end
    table.clear(self.Sections)
    self._janitor:Destroy()
    if self.Button.Parent then self.Button:Destroy() end
    if self.Page.Parent then self.Page:Destroy() end
    for index, subtab in ipairs(self.Tab.SubTabs) do
        if subtab == self then table.remove(self.Tab.SubTabs, index); break end
    end
    if self.Tab.CurrentSubTab == self then
        self.Tab.CurrentSubTab = nil
        if self.Tab.SubTabs[1] then self.Tab:SelectSubTab(self.Tab.SubTabs[1]) end
    end
end

function Tab:SubTab(options: any): any
    assert(not self.Destroyed, "Tab has been destroyed")
    return SubTab.new(self, options)
end

Tab.AddSubTab = Tab.SubTab
Tab.CreateSubTab = Tab.SubTab

function Tab:Select()
    self.Window:SelectTab(self)
    return self
end

function Tab:LockAll()
    for _, section in ipairs(self.Sections) do section:LockAll() end
    for _, subTab in ipairs(self.SubTabs) do for _, section in ipairs(subTab.Sections) do section:LockAll() end end
    return self
end

function Tab:UnlockAll()
    for _, section in ipairs(self.Sections) do section:UnlockAll() end
    for _, subTab in ipairs(self.SubTabs) do for _, section in ipairs(subTab.Sections) do section:UnlockAll() end end
    return self
end

function Tab:SelectSubTab(subTab: any)
    if self.Destroyed then return end
    local selected = subTab
    if type(subTab) == "number" then
        selected = self.SubTabs[subTab]
    elseif type(subTab) == "string" then
        for _, candidate in ipairs(self.SubTabs) do
            if candidate.Title == subTab then selected = candidate; break end
        end
    end
    if selected == nil or selected.UserVisible == false then return end
    self.CurrentSubTab = selected
    for _, candidate in ipairs(self.SubTabs) do
        candidate.Selected = candidate == selected
        candidate.Page.Visible = candidate == selected
        candidate:ApplyTheme()
    end
end

function SubTab:Select()
    self.Tab:SelectSubTab(self)
    return self
end

Tab.AddSection = Tab.Section
Tab.CreateSection = Tab.Section

-- Direct element API. Components created this way share one
-- implicit section; callers can still use explicit Section() for layout.
function Tab:_GetDefaultSection(): any
    assert(not self.Destroyed, "Tab has been destroyed")
    if self._defaultSection == nil or self._defaultSection.Destroyed then
        self._defaultSection = self:Section({ Title = self.Options.DefaultSectionTitle or "" })
    end
    return self._defaultSection
end

local DIRECT_CONTROLS: {[string]: string} = {
    toggle = "Toggle", slider = "Slider", dropdown = "Dropdown",
    multidropdown = "MultiDropdown", textbox = "Textbox", input = "Input",
    keybind = "Keybind", colorpicker = "ColorPicker", color = "ColorPicker",
    button = "Button", label = "Label", paragraph = "Paragraph",
    stepper = "Stepper", progress = "Progress", divider = "Divider",
    segmented = "Segmented", segmentedcontrol = "Segmented", stats = "Stats",
    image = "Image", video = "Video", code = "Code", tag = "Tag",
    card = "Card", table = "Table", console = "Console",
    changelog = "Changelog", changelogentry = "Changelog",
    rating = "Rating", assetgrid = "AssetGrid", cardgrid = "CardGrid",
    infogrid = "InfoGrid", systeminfogrid = "SystemInfoGrid",
    loadoutgroup = "LoadoutGroup", statelist = "StateList",
    gradientcard = "GradientCard", linetext = "LineText",
}

function Tab:AddControl(options: any): any
    assert(type(options) == "table", "AddControl expects an options table")
    local kind = string.lower(tostring(options.Type or options.Control or options.Kind or "")):gsub("[%s_%-]", "")
    local methodName = DIRECT_CONTROLS[kind]
    assert(methodName ~= nil, "Unknown control type: " .. kind)
    local section = options.Section
    if type(section) ~= "table" or type(section._Create) ~= "function" then
        section = self:_GetDefaultSection()
    end
    return (section :: any)[methodName](section, options)
end

function Tab:AddControls(definitions: {any}): {any}
    assert(type(definitions) == "table", "AddControls expects an array")
    local result = {}
    for _, definition in ipairs(definitions) do
        table.insert(result, self:AddControl(definition))
    end
    return result
end

function Tab:Group(options: any?): any
    return self:_GetDefaultSection():Group(options)
end

function Tab:MultiSection(options: any?): {any}
    return self:_GetDefaultSection():MultiSection(options)
end

function Tab:BindEnabledWhen(source: any, predicate: (any) -> boolean, targets: any): any
    return self:_GetDefaultSection():BindEnabledWhen(source, predicate, targets)
end

function Tab:BindVisibleWhen(source: any, predicate: (any) -> boolean, targets: any): any
    return self:_GetDefaultSection():BindVisibleWhen(source, predicate, targets)
end

local function addDirect(name: string, sectionMethod: string)
    (Tab :: any)[name] = function(self: any, options: any)
        local section = self:_GetDefaultSection()
        return (section :: any)[sectionMethod](section, options or {})
    end
end

for _, pair in ipairs({
    {"Toggle", "Toggle"}, {"Slider", "Slider"}, {"Dropdown", "Dropdown"},
    {"MultiDropdown", "MultiDropdown"}, {"Textbox", "Textbox"}, {"Input", "Input"},
    {"Keybind", "Keybind"}, {"ColorPicker", "ColorPicker"}, {"Colorpicker", "Colorpicker"},
    {"Button", "Button"}, {"Label", "Label"}, {"Paragraph", "Paragraph"},
    {"Stepper", "Stepper"}, {"Progress", "Progress"}, {"Divider", "Divider"},
    {"Segmented", "Segmented"}, {"Stats", "Stats"}, {"Image", "Image"},
    {"Video", "Video"}, {"Code", "Code"}, {"Tag", "Tag"}, {"Card", "Card"},
    {"Table", "Table"}, {"Console", "Console"}, {"Changelog", "Changelog"},
    {"Rating", "Rating"}, {"AssetGrid", "AssetGrid"}, {"CardGrid", "CardGrid"},
    {"InfoGrid", "InfoGrid"}, {"SystemInfoGrid", "SystemInfoGrid"},
    {"LoadoutGroup", "LoadoutGroup"}, {"StateList", "StateList"},
    {"GradientCard", "GradientCard"}, {"LineText", "LineText"},
    {"ToggleKeybind", "ToggleKeybind"}, {"ButtonKeybind", "ButtonKeybind"},
}) do
    addDirect("Add" .. pair[1], pair[2])
    addDirect("Create" .. pair[1], pair[2])
end

function SubTab:_GetDefaultSection(): any
    assert(not self.Destroyed, "SubTab has been destroyed")
    if self._defaultSection == nil or self._defaultSection.Destroyed then
        self._defaultSection = self:Section({ Title = self.Tab.Options.DefaultSectionTitle or "" })
    end
    return self._defaultSection
end

function SubTab:AddControl(options: any): any
    assert(type(options) == "table", "AddControl expects an options table")
    local kind = string.lower(tostring(options.Type or options.Control or options.Kind or "")):gsub("[%s_%-]", "")
    local methodName = DIRECT_CONTROLS[kind]
    assert(methodName ~= nil, "Unknown control type: " .. kind)
    local section = options.Section
    if type(section) ~= "table" or type(section._Create) ~= "function" then
        section = self:_GetDefaultSection()
    end
    return (section :: any)[methodName](section, options)
end

function SubTab:AddControls(definitions: {any}): {any}
    local result = {}
    for _, definition in ipairs(definitions) do
        table.insert(result, self:AddControl(definition))
    end
    return result
end

local function addSubTabDirect(name: string, sectionMethod: string)
    (SubTab :: any)[name] = function(self: any, options: any)
        local section = self:_GetDefaultSection()
        return (section :: any)[sectionMethod](section, options or {})
    end
end

for _, pair in ipairs({
    {"Toggle", "Toggle"}, {"Slider", "Slider"}, {"Dropdown", "Dropdown"},
    {"MultiDropdown", "MultiDropdown"}, {"Textbox", "Textbox"}, {"Input", "Input"},
    {"Keybind", "Keybind"}, {"ColorPicker", "ColorPicker"}, {"Colorpicker", "Colorpicker"},
    {"Button", "Button"}, {"Label", "Label"}, {"Paragraph", "Paragraph"},
    {"Stepper", "Stepper"}, {"Progress", "Progress"}, {"Divider", "Divider"},
    {"Segmented", "Segmented"}, {"Stats", "Stats"}, {"Image", "Image"},
    {"Video", "Video"}, {"Code", "Code"}, {"Tag", "Tag"}, {"Card", "Card"},
    {"Table", "Table"}, {"Console", "Console"}, {"Changelog", "Changelog"},
    {"Rating", "Rating"}, {"AssetGrid", "AssetGrid"}, {"CardGrid", "CardGrid"},
    {"InfoGrid", "InfoGrid"}, {"SystemInfoGrid", "SystemInfoGrid"},
    {"LoadoutGroup", "LoadoutGroup"}, {"StateList", "StateList"},
    {"GradientCard", "GradientCard"}, {"LineText", "LineText"},
    {"ToggleKeybind", "ToggleKeybind"}, {"ButtonKeybind", "ButtonKeybind"},
}) do
    addSubTabDirect("Add" .. pair[1], pair[2])
    addSubTabDirect("Create" .. pair[1], pair[2])
end

function Tab:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true

    local subTabs = table.clone(self.SubTabs)
    for _, subTab in ipairs(subTabs) do subTab:Destroy() end
    table.clear(self.SubTabs)

    local sections = table.clone(self.Sections)
    for _, section in ipairs(sections) do
        section:Destroy()
    end
    table.clear(self.Sections)
    self._janitor:Destroy()

    if self.Button.Parent ~= nil then
        self.Button:Destroy()
    end
    if self.Page.Parent ~= nil then
        self.Page:Destroy()
    end

    for index, tab in ipairs(self.Window.Tabs) do
        if tab == self then
            table.remove(self.Window.Tabs, index)
            break
        end
    end
    if self.Window.CurrentTab == self then
        self.Window.CurrentTab = nil
        local first = self.Window.Tabs[1]
        if first then
            self.Window:SelectTab(first)
        end
    end
end

__SUI_UI_Tab = Tab
end

-- ===== Module: UI.Window =====
local __SUI_UI_Window
do
-- Window shell, viewport bounds, tabs, popups, notifications and dialogs.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Janitor = __SUI_Core_Janitor
local InstancePool = __SUI_Core_InstancePool
local Tab = __SUI_UI_Tab

local Window = {}
Window.__index = Window

local function make(className: string, properties: {[string]: any}, parent: Instance?): Instance
    local instance = Instance.new(className)
    for property, value in pairs(properties) do
        (instance :: any)[property] = value
    end
    if parent then
        instance.Parent = parent
    end
    return instance
end

local function round(instance: Instance, radius: number)
    make("UICorner", {
        CornerRadius = UDim.new(0, radius),
    }, instance)
end

local function stroke(instance: Instance, color: Color3, transparency: number?): UIStroke
    return make("UIStroke", {
        Color = color,
        Transparency = transparency or 0,
        Thickness = 1,
    }, instance) :: UIStroke
end

local function textLabel(parent: Instance, text: string, size: number, color: Color3, properties: {[string]: any}?): TextLabel
    local props = properties or {}
    props.BackgroundTransparency = 1
    props.Text = text
    props.TextColor3 = color
    props.TextSize = size
    props.Font = Enum.Font.Gotham
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    props.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
    props.TextWrapped = props.TextWrapped == true
    return make("TextLabel", props, parent) :: TextLabel
end

local function textButton(parent: Instance, text: string, properties: {[string]: any}?): TextButton
    local props = properties or {}
    props.Text = text
    props.Font = Enum.Font.GothamMedium
    props.TextSize = props.TextSize or 13
    props.AutoButtonColor = false
    props.BorderSizePixel = 0
    return make("TextButton", props, parent) :: TextButton
end

local function tween(instance: Instance, duration: number, properties: {[string]: any})
    local animation = TweenService:Create(instance, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), properties)
    animation:Play()
    return animation
end

function Window.new(library: any, options: any?): any
    local opts = options or {}
    local player = Players.LocalPlayer
    assert(player ~= nil, "SilentUI must be created from a client context")

    local playerGui = player:WaitForChild("PlayerGui")
    local self = setmetatable({
        Library = library,
        Options = opts,
        Title = tostring(opts.Title or "SilentUI"),
        Author = tostring(opts.Author or ""),
        Subtitle = tostring(opts.Subtitle or "Custom interface"),
        ToggleKey = opts.ToggleKey or Enum.KeyCode.RightControl,
        Resizable = opts.Resizable ~= false,
        IsOpen = true,
        Destroyed = false,
        Tabs = {},
        CurrentTab = nil,
        _janitor = Janitor.new(),
        _popup = nil,
        _tooltip = nil,
        _notifications = {},
        _dialogs = {},
        _floatingWidgets = {},
        _dragInput = nil,
        _resizeInput = nil,
        _floatingInput = nil,
        _floatingMoved = false,
        _hasFloatingPosition = false,
        _openCallbacks = {},
        _closeCallbacks = {},
        _destroyCallbacks = {},
        _desiredWidth = tonumber(opts.Width) or 660,
        _desiredHeight = tonumber(opts.Height) or 470,
        _minWidth = tonumber(opts.MinWidth) or 300,
        _minHeight = tonumber(opts.MinHeight) or 300,
        _hasPosition = false,
        _openToken = 0,
        _closeThread = nil,
    }, Window)

    local screenGui = make("ScreenGui", {
        Name = tostring(opts.Name or "SilentUI"),
        ResetOnSpawn = false,
        DisplayOrder = tonumber(opts.DisplayOrder) or 1000,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        AutoLocalize = false,
        ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
    }, playerGui) :: ScreenGui
    self.ScreenGui = screenGui

    local root = make("Frame", {
        Name = "Window",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(self._desiredWidth, self._desiredHeight),
        BackgroundColor3 = library.ThemeManager.Current.Window,
        BackgroundTransparency = tonumber(library.ThemeManager.Current.WindowTransparency) or 0,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 2,
    }, screenGui) :: Frame
    self.Root = root
    self._rootScale = make("UIScale", {
        Scale = 1,
    }, root) :: UIScale
    round(root, 14)
    self._rootStroke = stroke(root, library.ThemeManager.Current.Border, 0.15)

    local background = make("ImageLabel", {
        Name = "BackgroundImage",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Image = tostring(opts.BackgroundImage or ""),
        ImageTransparency = math.clamp(tonumber(opts.BackgroundImageTransparency) or 0.34, 0, 1),
        ScaleType = Enum.ScaleType.Crop,
        ZIndex = 2,
    }, root) :: ImageLabel
    self.BackgroundImage = background
    round(background, 14)

    local backgroundShade = make("Frame", {
        Name = "BackgroundShade",
        BackgroundColor3 = library.ThemeManager.Current.Window,
        BackgroundTransparency = opts.BackgroundImage and 0.28 or (tonumber(library.ThemeManager.Current.WindowTransparency) or 0),
        Size = UDim2.fromScale(1, 1),
        BorderSizePixel = 0,
        ZIndex = 3,
    }, root) :: Frame
    self.BackgroundShade = backgroundShade
    self._interfaceTransparency = nil
    round(backgroundShade, 14)
    self.BackgroundGradient = make("UIGradient", {
        Rotation = 35,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, library.ThemeManager.Current.Window),
            ColorSequenceKeypoint.new(1, library.ThemeManager.Current.Surface),
        }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.02),
            NumberSequenceKeypoint.new(1, 0.14),
        }),
    }, backgroundShade) :: UIGradient

    local topbar = make("Frame", {
        Name = "Topbar",
        BackgroundColor3 = library.ThemeManager.Current.Surface,
        BackgroundTransparency = tonumber(library.ThemeManager.Current.SurfaceTransparency) or 0.08,
        Active = true,
        Size = UDim2.new(1, 0, 0, 48),
        BorderSizePixel = 0,
        ZIndex = 5,
    }, root) :: Frame
    self.Topbar = topbar
    round(topbar, 14)
    make("Frame", {
        BackgroundColor3 = library.ThemeManager.Current.Surface,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, -14),
        Size = UDim2.new(1, 0, 0, 14),
        ZIndex = 5,
    }, topbar)

    local accent = make("Frame", {
        Name = "AccentLine",
        BackgroundColor3 = library.ThemeManager.Current.Accent,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 14, 1, -1),
        Size = UDim2.new(1, -28, 0, 1),
        ZIndex = 7,
    }, topbar)

    local title = textLabel(topbar, self.Title, 15, library.ThemeManager.Current.Text, {
        Name = "Title",
        Position = UDim2.fromOffset(16, 5),
        Size = UDim2.new(1, -100, 0, 20),
        Font = Enum.Font.GothamBold,
        ZIndex = 7,
    })
    self.TitleLabel = title
    local subtitle = textLabel(topbar, self.Subtitle, 10, library.ThemeManager.Current.Muted, {
        Name = "Subtitle",
        Position = UDim2.fromOffset(17, 26),
        Size = UDim2.new(1, -105, 0, 14),
        ZIndex = 7,
    })
    self.SubtitleLabel = subtitle

    local searchButton = textButton(topbar, "⌕", {
        Name = "SearchButton",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -46, 0.5, 0),
        Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = library.ThemeManager.Current.SurfaceAlt,
        TextColor3 = library.ThemeManager.Current.Text,
        TextSize = 19,
        ZIndex = 8,
        Visible = opts.SearchEnabled ~= false,
    })
    round(searchButton, 8)
    self.SearchButton = searchButton
    local searchBox = make("TextBox", {
        Name = "SearchBox",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -80, 0.5, 0),
        Size = UDim2.fromOffset(160, 28),
        BackgroundColor3 = library.ThemeManager.Current.Window,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Text = "",
        PlaceholderText = "Search controls...",
        TextColor3 = library.ThemeManager.Current.Text,
        PlaceholderColor3 = library.ThemeManager.Current.Muted,
        TextSize = 11,
        Font = Enum.Font.Gotham,
        Visible = false,
        ZIndex = 9,
    }, topbar) :: TextBox
    round(searchBox, 7)
    stroke(searchBox, library.ThemeManager.Current.Border, 0.2)
    self.SearchBox = searchBox
    self._janitor:Add(searchButton.Activated:Connect(function()
        searchBox.Visible = not searchBox.Visible
        if searchBox.Visible then
            self.TitleLabel.Visible = false
            self.SubtitleLabel.Visible = false
            searchBox:CaptureFocus()
        else
            self.TitleLabel.Visible = true
            self.SubtitleLabel.Visible = true
            searchBox.Text = ""
            self:Search("")
        end
    end))
    self._janitor:Add(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        self:Search(searchBox.Text)
    end))
    self._janitor:Add(searchBox.FocusLost:Connect(function(enterPressed)
        if not enterPressed and searchBox.Text == "" then
            self:Search("")
        end
    end))

    local closeButton = textButton(topbar, "×", {
        Name = "Close",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = library.ThemeManager.Current.SurfaceAlt,
        TextColor3 = library.ThemeManager.Current.Text,
        TextSize = 22,
        ZIndex = 8,
    })
    round(closeButton, 9)
    self._janitor:Add(closeButton.Activated:Connect(function()
        self:Close()
    end))

    local tabBar = make("ScrollingFrame", {
        Name = "TabBar",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(12, 56),
        Size = UDim2.new(1, -24, 0, 36),
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        ScrollingDirection = Enum.ScrollingDirection.X,
        ScrollBarThickness = 0,
        ZIndex = 5,
    }, root) :: ScrollingFrame
    self.TabBar = tabBar
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 7),
    }, tabBar)

    local content = make("Frame", {
        Name = "Content",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12, 100),
        Size = UDim2.new(1, -24, 1, -112),
        ZIndex = 5,
    }, root) :: Frame
    self.Content = content

    local openButtonConfig = if type(opts.OpenButton) == "table" then table.clone(opts.OpenButton) else {}
    self.OpenButtonConfig = openButtonConfig
    local initialOpenScale = math.clamp(tonumber(openButtonConfig.Scale) or 1, 0.55, 1.4)
    local initialOpenSize = math.floor(46 * initialOpenScale + 0.5)
    local floatingButton = textButton(screenGui, tostring(openButtonConfig.Title or opts.FloatingButtonText or "S"), {
        Name = "FloatingToggle",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -18, 1, -18),
        Size = UDim2.fromOffset(initialOpenSize, initialOpenSize),
        BackgroundColor3 = typeof(openButtonConfig.Color) == "Color3" and openButtonConfig.Color or library.ThemeManager.Current.Accent,
        TextColor3 = library.ThemeManager.Current.AccentText,
        TextSize = 15,
        ZIndex = 20,
    }) :: TextButton
    self.FloatingButton = floatingButton
    local initialRadius = openButtonConfig.CornerRadius
    make("UICorner", {
        CornerRadius = typeof(initialRadius) == "UDim" and initialRadius or UDim.new(0, tonumber(initialRadius) or initialOpenSize / 2),
    }, floatingButton)
    stroke(floatingButton, library.ThemeManager.Current.Border, 0.25)
    if typeof(openButtonConfig.Color) == "ColorSequence" then
        self._floatingGradient = make("UIGradient", { Color = openButtonConfig.Color, Rotation = 35 }, floatingButton) :: UIGradient
    end
    self:SetOpenButtonVisible(openButtonConfig.Enabled ~= false and openButtonConfig.Visible ~= false)
    self._janitor:Add(floatingButton.InputBegan:Connect(function(input)
        self:_BeginFloatingDrag(input)
    end))
    self._janitor:Add(floatingButton.Activated:Connect(function()
        if self._floatingMoved then
            self._floatingMoved = false
        else
            self:Toggle()
        end
    end))

    local resizeHandle = textButton(root, "◢", {
        Name = "ResizeHandle",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -4, 1, -3),
        Size = UDim2.fromOffset(22, 22),
        BackgroundTransparency = 1,
        TextColor3 = library.ThemeManager.Current.Muted,
        TextSize = 14,
        ZIndex = 15,
        Visible = self.Resizable,
    }) :: TextButton
    self.ResizeHandle = resizeHandle

    self.NotificationHolder = make("ScrollingFrame", {
        Name = "Notifications",
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 14),
        Size = UDim2.fromOffset(320, 400),
        AutomaticSize = Enum.AutomaticSize.None,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.fromOffset(0, 0),
        ScrollBarThickness = 3,
        ScrollBarImageTransparency = 0.55,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ClipsDescendants = true,
        ZIndex = 80,
    }, screenGui) :: ScrollingFrame
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
    }, self.NotificationHolder)

    self._janitor:Add(topbar.InputBegan:Connect(function(input)
        self:_BeginDrag(input)
    end))
    self._janitor:Add(resizeHandle.InputBegan:Connect(function(input)
        self:_BeginResize(input)
    end))
    self._janitor:Add(UserInputService.InputChanged:Connect(function(input)
        self:_UpdatePointer(input)
    end))
    self._janitor:Add(UserInputService.InputEnded:Connect(function(input)
        self:_EndPointer(input)
    end))
    self._janitor:Add(UserInputService.InputBegan:Connect(function(input, processed)
        if processed or UserInputService:GetFocusedTextBox() ~= nil then
            return
        end
        if input.KeyCode == self.ToggleKey then
            self:Toggle()
        elseif input.KeyCode == Enum.KeyCode.Escape and self._popup then
            self:_ClosePopup()
        end
    end))

    self._janitor:Add(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        self:_WatchCamera()
        self:_ApplyViewport()
    end))
    self:_WatchCamera()
    self._janitor:Add(screenGui.Destroying:Connect(function()
        if not self.Destroyed then
            self:Destroy()
        end
    end))

    self._themeConnection = library.ThemeManager.Changed:Connect(function()
        self:ApplyTheme()
    end)
    self._janitor:Add(self._themeConnection)

    self:_ApplyViewport()
    self:ApplyTheme()
    return self
end

function Window:_WatchCamera()
    if self._cameraConnection then
        self._janitor:Remove(self._cameraConnection, false)
        self._cameraConnection:Disconnect()
        self._cameraConnection = nil
    end

    local camera = Workspace.CurrentCamera
    if camera then
        self._cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            self:_ApplyViewport()
        end)
        self._janitor:Add(self._cameraConnection)
    end
end

function Window:_ViewportSize(): Vector2
    local guiSize = self.ScreenGui.AbsoluteSize
    if guiSize.X > 0 and guiSize.Y > 0 then
        return guiSize
    end
    local camera = Workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

function Window:_ApplyViewport()
    if self.Destroyed then
        return
    end

    local viewport = self:_ViewportSize()
    local horizontalMargin = 18
    local verticalMargin = 18
    local maxWidth = math.max(1, viewport.X - horizontalMargin * 2)
    local maxHeight = math.max(1, viewport.Y - verticalMargin * 2)
    local isTouchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
    local minimumWidth = math.min(self._minWidth, maxWidth)
    local minimumHeight = math.min(self._minHeight, maxHeight)

    local width = math.clamp(self._desiredWidth, minimumWidth, maxWidth)
    local height = math.clamp(self._desiredHeight, minimumHeight, maxHeight)
    if isTouchOnly then
        width = math.clamp(math.max(width, math.min(320, maxWidth)), minimumWidth, maxWidth)
        height = math.clamp(math.max(height, math.min(380, maxHeight)), minimumHeight, maxHeight)
    end

    self.Root.Size = UDim2.fromOffset(width, height)
    if self.NotificationHolder then
        self.NotificationHolder.Size = UDim2.fromOffset(
            math.max(1, math.min(320, viewport.X - 28)),
            math.max(1, viewport.Y - 28)
        )
    end
    if self.FloatingButton then
        local baseButtonSize = 46 * math.clamp(tonumber(self.OpenButtonConfig and self.OpenButtonConfig.Scale) or 1, 0.55, 1.4)
        local buttonSize = math.max(1, math.min(baseButtonSize, viewport.X - 8, viewport.Y - 8))
        self.FloatingButton.Size = UDim2.fromOffset(buttonSize, buttonSize)
        if not self._hasFloatingPosition then
            self.FloatingButton.Position = UDim2.fromOffset(
                math.max(buttonSize + 4, viewport.X - 10),
                math.max(buttonSize + 4, viewport.Y - 10)
            )
            self._hasFloatingPosition = true
        else
            local position = self.FloatingButton.Position
            self.FloatingButton.Position = UDim2.fromOffset(
                math.clamp(position.X.Offset, buttonSize + 4, math.max(buttonSize + 4, viewport.X - 4)),
                math.clamp(position.Y.Offset, buttonSize + 4, math.max(buttonSize + 4, viewport.Y - 4))
            )
        end
    end
    if not self._hasPosition then
        self.Root.Position = UDim2.fromOffset(viewport.X / 2, viewport.Y / 2)
        self._hasPosition = true
    end
    self:_ClampToScreen()
    for _, widget in ipairs(self._floatingWidgets) do
        if widget and type(widget._OnViewportChanged) == "function" then
            widget:_OnViewportChanged()
        end
    end
end

function Window:_ClampToScreen()
    if self.Destroyed then
        return
    end

    local viewport = self:_ViewportSize()
    -- Use the unscaled target size so the opening UIScale tween cannot move
    -- the final rendered window outside the safe viewport.
    local rootWidth = self.Root.Size.X.Offset
    local rootHeight = self.Root.Size.Y.Offset
    local half = Vector2.new(rootWidth / 2, rootHeight / 2)
    local margin = 8
    local minX = half.X + margin
    local maxX = viewport.X - half.X - margin
    local minY = half.Y + margin
    local maxY = viewport.Y - half.Y - margin
    local targetX = if maxX < minX then viewport.X / 2 else math.clamp(self.Root.Position.X.Offset, minX, maxX)
    local targetY = if maxY < minY then viewport.Y / 2 else math.clamp(self.Root.Position.Y.Offset, minY, maxY)
    self.Root.Position = UDim2.fromOffset(targetX, targetY)
end

function Window:_BeginFloatingDrag(input: InputObject)
    if self.Destroyed or self.OpenButtonConfig.Draggable == false then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    self._floatingInput = input
    self._floatingStart = input.Position
    self._floatingOrigin = Vector2.new(self.FloatingButton.Position.X.Offset, self.FloatingButton.Position.Y.Offset)
    self._floatingMoved = false
end

function Window:_BeginDrag(input: InputObject)
    if self.Destroyed then
        return
    end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    self._dragInput = input
    self._dragStart = input.Position
    self._dragOrigin = Vector2.new(self.Root.Position.X.Offset, self.Root.Position.Y.Offset)
end

function Window:_BeginResize(input: InputObject)
    if self.Destroyed or not self.Resizable then
        return
    end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    self._resizeInput = input
    self._resizeStart = input.Position
    self._resizeOrigin = Vector2.new(self.Root.AbsoluteSize.X, self.Root.AbsoluteSize.Y)
end

function Window:_UpdatePointer(input: InputObject)
    if self._floatingInput ~= nil then
        local isMouseMove = self._floatingInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement
        local isSameTouch = self._floatingInput.UserInputType == Enum.UserInputType.Touch and input == self._floatingInput
        if isMouseMove or isSameTouch then
            local delta = input.Position - self._floatingStart
            if delta.Magnitude > 5 then self._floatingMoved = true end
            if self._floatingMoved then
                local viewport = self:_ViewportSize()
                local size = self.FloatingButton.AbsoluteSize
                local x = math.clamp(self._floatingOrigin.X + delta.X, size.X + 4, math.max(size.X + 4, viewport.X - 4))
                local y = math.clamp(self._floatingOrigin.Y + delta.Y, size.Y + 4, math.max(size.Y + 4, viewport.Y - 4))
                self.FloatingButton.Position = UDim2.fromOffset(x, y)
                self._hasFloatingPosition = true
            end
        end
    end

    if self._dragInput ~= nil then
        local isMouseMove = self._dragInput.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement
        local isSameTouch = self._dragInput.UserInputType == Enum.UserInputType.Touch and input == self._dragInput
        if isMouseMove or isSameTouch then
            local delta = input.Position - self._dragStart
            self.Root.Position = UDim2.fromOffset(self._dragOrigin.X + delta.X, self._dragOrigin.Y + delta.Y)
            self:_ClampToScreen()
        end
    end

    if self._resizeInput ~= nil then
        local isMouseMove = self._resizeInput.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement
        local isSameTouch = self._resizeInput.UserInputType == Enum.UserInputType.Touch and input == self._resizeInput
        if isMouseMove or isSameTouch then
            local delta = input.Position - self._resizeStart
            local viewport = self:_ViewportSize()
            local maxWidth = math.max(1, viewport.X - 20)
            local maxHeight = math.max(1, viewport.Y - 20)
            local minWidth = math.min(self._minWidth, maxWidth)
            local minHeight = math.min(self._minHeight, maxHeight)
            local width = math.clamp(self._resizeOrigin.X + delta.X, minWidth, maxWidth)
            local height = math.clamp(self._resizeOrigin.Y + delta.Y, minHeight, maxHeight)
            self._desiredWidth = width
            self._desiredHeight = height
            self.Root.Size = UDim2.fromOffset(width, height)
            self:_ClampToScreen()
        end
    end
end

function Window:_EndPointer(input: InputObject)
    if self._floatingInput == input or (self._floatingInput and self._floatingInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
        self._floatingInput = nil
    end
    if self._dragInput == input or (self._dragInput and self._dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
        self._dragInput = nil
    end
    if self._resizeInput == input or (self._resizeInput and self._resizeInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
        self._resizeInput = nil
    end
end

function Window:ApplyTheme()
    if self.Destroyed then
        return
    end
    local theme = self.Library.ThemeManager.Current
    self.Root.BackgroundColor3 = theme.Window
    self.Root.BackgroundTransparency = tonumber(theme.WindowTransparency) or 0
    self.BackgroundShade.BackgroundColor3 = theme.Window
    local baseTransparency = self._interfaceTransparency
    if baseTransparency == nil then
        baseTransparency = self.BackgroundImage.Image ~= "" and 0.28 or (tonumber(theme.WindowTransparency) or 0)
    end
    self.BackgroundShade.BackgroundTransparency = self._acrylicEnabled and 0.42 or baseTransparency
    self.Topbar.BackgroundColor3 = theme.Surface
    self.Topbar.BackgroundTransparency = tonumber(theme.SurfaceTransparency) or 0.08
    self.SearchButton.BackgroundColor3 = theme.SurfaceAlt
    self.SearchButton.TextColor3 = theme.Text
    self.SearchBox.BackgroundColor3 = theme.Window
    self.SearchBox.TextColor3 = theme.Text
    self.SearchBox.PlaceholderColor3 = theme.Muted
    self._rootStroke.Color = theme.Border
    self.BackgroundGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, theme.Window),
        ColorSequenceKeypoint.new(1, theme.Surface),
    })
    self.TitleLabel.TextColor3 = theme.Text
    self.SubtitleLabel.TextColor3 = theme.Muted
    if not self.OpenButtonConfig or typeof(self.OpenButtonConfig.Color) ~= "Color3" then
        self.FloatingButton.BackgroundColor3 = theme.Accent
    end
    self.FloatingButton.TextColor3 = theme.AccentText
    self.ResizeHandle.TextColor3 = theme.Muted
    for _, notice in ipairs(self._notifications) do
        local card = notice.Card
        if card and card.Parent ~= nil then
            card.BackgroundColor3 = theme.Surface
            local title = card:FindFirstChild("NotificationTitle")
            if title and title:IsA("TextLabel") then title.TextColor3 = theme.Text end
            local content = card:FindFirstChild("NotificationContent")
            if content and content:IsA("TextLabel") then content.TextColor3 = theme.Muted end
            local accent = card:FindFirstChild("Accent")
            if accent and accent:IsA("Frame") then accent.BackgroundColor3 = theme.Accent end
            local cardStroke = card:FindFirstChildOfClass("UIStroke")
            if cardStroke then cardStroke.Color = theme.Border end
        end
    end
    if self._popup and self._popup.Panel.Parent ~= nil then
        self._popup.Panel.BackgroundColor3 = theme.Surface
    end
end

function Window:SetTitle(title: string, subtitle: string?)
    self.Title = tostring(title)
    self.TitleLabel.Text = self.Title
    if subtitle ~= nil then
        self.Subtitle = tostring(subtitle)
        self.SubtitleLabel.Text = self.Subtitle
    end
    return self
end

function Window:SetBackgroundImage(image: string, transparency: number?)
    self.BackgroundImage.Image = image
    if transparency ~= nil then
        self.BackgroundImage.ImageTransparency = math.clamp(transparency, 0, 1)
    end
    self.BackgroundImage.Visible = image ~= ""
    self._interfaceTransparency = nil
    self.BackgroundShade.BackgroundTransparency = image ~= "" and 0.28 or (tonumber(self.Library.ThemeManager.Current.WindowTransparency) or 0)
    return self
end

function Window:SetOpen(open: boolean)
    if self.Destroyed then
        return self
    end

    local nextOpen = open == true
    if self.IsOpen == nextOpen then return self end
    self._openToken += 1
    local token = self._openToken
    self.IsOpen = nextOpen

    if self._closeThread then
        self._janitor:Remove(self._closeThread, true)
        self._closeThread = nil
    end

    if self.IsOpen then
        self.Root.Visible = true
        self._rootScale.Scale = 0.97
        tween(self._rootScale, 0.15, { Scale = 1 })
        self:_ClampToScreen()
        for _, callback in ipairs(self._openCallbacks) do
            local ok, err = pcall(callback, self)
            if not ok then warn("[SilentUI] OnOpen callback failed: " .. tostring(err)) end
        end
    else
        for _, callback in ipairs(self._closeCallbacks) do
            local ok, err = pcall(callback, self)
            if not ok then warn("[SilentUI] OnClose callback failed: " .. tostring(err)) end
        end
        tween(self._rootScale, 0.12, { Scale = 0.97 })
        local closeThread: thread? = nil
        closeThread = task.delay(0.13, function()
            if self._closeThread == closeThread then
                self._closeThread = nil
                self._janitor:Remove(closeThread, false)
            end
            if not self.Destroyed and not self.IsOpen and self._openToken == token then
                self.Root.Visible = false
            end
        end)
        self._closeThread = closeThread
        self._janitor:Add(closeThread)
    end
    return self
end

function Window:Open()
    return self:SetOpen(true)
end

function Window:Close()
    return self:SetOpen(false)
end

function Window:Toggle()
    return self:SetOpen(not self.IsOpen)
end

function Window:SetResizable(enabled: boolean)
    self.Resizable = enabled == true
    self.ResizeHandle.Visible = self.Resizable
    return self
end

function Window:SetSize(width: number, height: number)
    self._desiredWidth = math.max(self._minWidth, tonumber(width) or self._desiredWidth)
    self._desiredHeight = math.max(self._minHeight, tonumber(height) or self._desiredHeight)
    self:_ApplyViewport()
    return self
end

function Window:GetSize(): Vector2
    return Vector2.new(self.Root.AbsoluteSize.X, self.Root.AbsoluteSize.Y)
end

function Window:Center()
    self._hasPosition = false
    self.Root.Position = UDim2.fromScale(0.5, 0.5)
    self:_ClampToScreen()
    return self
end

function Window:SetToTheCenter()
    return self:Center()
end

function Window:SetKeepOnScreen(_enabled: boolean?)
    -- SilentUI always clamps the window; exposing this no-op keeps the safety invariant.
    self:_ClampToScreen()
    return self
end

function Window:SetUIScale(scale: number)
    self._rootScale.Scale = math.clamp(tonumber(scale) or 1, 0.5, 1.5)
    self:_ClampToScreen()
    return self
end

function Window:GetUIScale(): number
    return self._rootScale.Scale
end

function Window:SetToggleKey(keyCode: Enum.KeyCode)
    assert(typeof(keyCode) == "EnumItem" and keyCode.EnumType == Enum.KeyCode, "Toggle key must be an Enum.KeyCode")
    self.ToggleKey = keyCode
    return self
end

function Window:SetOpenButtonVisible(visible: boolean)
    self.FloatingButton.Visible = visible == true
        and self.OpenButtonConfig.Enabled ~= false
        and self.OpenButtonConfig.Visible ~= false
        and (self.OpenButtonConfig.OnlyMobile ~= true or UserInputService.TouchEnabled)
    return self
end

function Window:_ApplyOpenButtonConfig()
    local config = self.OpenButtonConfig or {}
    local scale = math.clamp(tonumber(config.Scale) or 1, 0.55, 1.4)
    local size = math.floor(46 * scale + 0.5)
    self.FloatingButton.Size = UDim2.fromOffset(size, size)
    self.FloatingButton.Text = tostring(config.Title or config.Text or "S")
    self.FloatingButton.BackgroundTransparency = config.Ghosted == true and 0.48 or 0
    if typeof(config.Color) == "Color3" then
        if self._floatingGradient then self._floatingGradient:Destroy(); self._floatingGradient = nil end
        self.FloatingButton.BackgroundColor3 = config.Color
    elseif typeof(config.Color) == "ColorSequence" then
        if not self._floatingGradient then
            self._floatingGradient = make("UIGradient", { Rotation = 35 }, self.FloatingButton) :: UIGradient
        end
        self._floatingGradient.Color = config.Color
    else
        if self._floatingGradient then self._floatingGradient:Destroy(); self._floatingGradient = nil end
        self.FloatingButton.BackgroundColor3 = self.Library.ThemeManager.Current.Accent
    end
    local radius = config.CornerRadius
    local corner = self.FloatingButton:FindFirstChildOfClass("UICorner")
    if corner then
        corner.CornerRadius = typeof(radius) == "UDim" and radius or UDim.new(0, tonumber(radius) or size / 2)
    end
    self:_ApplyViewport()
    self:SetOpenButtonVisible(config.Visible ~= false and config.Enabled ~= false)
end

function Window:EditOpenButton(options: any)
    local config = options or {}
    for key, value in pairs(config) do self.OpenButtonConfig[key] = value end
    if config.Draggable ~= nil then self.OpenButtonConfig.Draggable = config.Draggable == true end
    self:_ApplyOpenButtonConfig()
    return self
end

function Window:SetBackgroundImageTransparency(value: number)
    self.BackgroundImage.ImageTransparency = math.clamp(tonumber(value) or 0.3, 0, 1)
    return self
end

function Window:SetInterfaceTransparency(value: number)
    local alpha = math.clamp(tonumber(value) or 0, 0, 1)
    self._interfaceTransparency = alpha
    self.Root.BackgroundTransparency = alpha
    self.BackgroundShade.BackgroundTransparency = alpha
    return self
end

function Window:ToggleFullscreen()
    if not self._fullscreen then
        self._restoreSize = Vector2.new(self._desiredWidth, self._desiredHeight)
        local viewport = self:_ViewportSize()
        self._desiredWidth = math.max(self._minWidth, viewport.X - 24)
        self._desiredHeight = math.max(self._minHeight, viewport.Y - 24)
        self._fullscreen = true
    else
        if self._restoreSize then
            self._desiredWidth = self._restoreSize.X
            self._desiredHeight = self._restoreSize.Y
        end
        self._fullscreen = false
    end
    self:_ApplyViewport()
    return self
end

function Window:OnOpen(callback: (any) -> ())
    assert(type(callback) == "function", "OnOpen expects a callback")
    table.insert(self._openCallbacks, callback)
    return self
end

function Window:OnClose(callback: (any) -> ())
    assert(type(callback) == "function", "OnClose expects a callback")
    table.insert(self._closeCallbacks, callback)
    return self
end

function Window:OnDestroy(callback: (any) -> ())
    assert(type(callback) == "function", "OnDestroy expects a callback")
    table.insert(self._destroyCallbacks, callback)
    return self
end

local function visitSection(section: any, callback: (any) -> ())
    callback(section)
    for _, group in ipairs(section.Groups or {}) do visitSection(group, callback) end
end

function Window:Search(query: string)
    local normalized = string.lower(tostring(query or "")):match("^%s*(.-)%s*$") or ""
    self.SearchQuery = normalized
    local function searchSections(sections: {any}): boolean
        local hasMatch = false
        for _, section in ipairs(sections) do
            visitSection(section, function(currentSection)
                for _, control in ipairs(currentSection.Elements or {}) do
                    local haystack = tostring(control.SearchText or "")
                    local matches = normalized == "" or string.find(string.lower(haystack), normalized, 1, true) ~= nil
                    if type(control.SetSearchMatch) == "function" then
                        control:SetSearchMatch(matches)
                    elseif control.ElementFrame then
                        control.ElementFrame.Visible = matches
                    end
                    if matches then hasMatch = true end
                end
            end)
        end
        return hasMatch
    end

    for _, tab in ipairs(self.Tabs) do
        local hasMatch = searchSections(tab.Sections or {})
        for _, subTab in ipairs(tab.SubTabs or {}) do
            local subMatch = searchSections(subTab.Sections or {})
            subTab.SearchVisible = normalized == "" or subMatch
            subTab.Button.Visible = subTab.UserVisible ~= false and subTab.SearchVisible
            if subTab.SearchVisible then hasMatch = true end
        end
        if #((tab.SubTabs) or {}) > 0 then
            local current = tab.CurrentSubTab
            if current and current.Button.Visible == false then
                for _, candidate in ipairs(tab.SubTabs) do
                    if candidate.Button.Visible then tab:SelectSubTab(candidate); break end
                end
            end
        end
        tab.SearchVisible = normalized == "" or hasMatch
        tab.Button.Visible = tab.UserVisible ~= false and tab.SearchVisible
    end
    if normalized ~= "" and self.CurrentTab and not self.CurrentTab.Button.Visible then
        for _, tab in ipairs(self.Tabs) do
            if tab.Button.Visible then self:SelectTab(tab); break end
        end
    end
    return self
end

function Window:ClearSearch()
    if self.SearchBox then self.SearchBox.Text = "" end
    return self:Search("")
end

local function normalizeTargets(targets: any): {any}
    if type(targets) ~= "table" then return { targets } end
    if targets.SetVisible or targets.SetDisabled then return { targets } end
    return targets
end

function Window:_BindCondition(sourceControl: any, predicate: (any) -> boolean, targets: any, mode: string): any
    assert(sourceControl and type(sourceControl.Get) == "function" and type(sourceControl.OnChanged) == "function", "Binding source must be a stateful control")
    assert(type(predicate) == "function", "Binding predicate must be a function")
    local targetList = normalizeTargets(targets)
    local bindingJanitor = Janitor.new()
    local function apply(value: any)
        local ok, result = pcall(predicate, value)
        local enabled = ok and result == true
        for _, target in ipairs(targetList) do
            if target and not target.Destroyed then
                if mode == "Enabled" and type(target.SetDisabled) == "function" then
                    target:SetDisabled(not enabled)
                elseif mode == "Visible" and type(target.SetVisible) == "function" then
                    target:SetVisible(enabled)
                end
            end
        end
    end
    apply(sourceControl:Get())
    bindingJanitor:Add(sourceControl:OnChanged(function(value) apply(value) end))
    local handle = {}
    function handle:Destroy() bindingJanitor:Destroy() end
    return handle
end

function Window:BindEnabledWhen(sourceControl: any, predicate: (any) -> boolean, targets: any): any
    return self:_BindCondition(sourceControl, predicate, targets, "Enabled")
end

function Window:BindVisibleWhen(sourceControl: any, predicate: (any) -> boolean, targets: any): any
    return self:_BindCondition(sourceControl, predicate, targets, "Visible")
end

function Window:CreateKeybindList(options: any?): any
    local selfWindow = self
    local opts = options or {}
    local theme = self.Library.ThemeManager.Current
    local frame = make("Frame", {
        Name = "KeybindList",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, tonumber(opts.Top) or 88),
        Size = UDim2.fromOffset(tonumber(opts.Width) or 190, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = theme.Surface,
        BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
        ZIndex = 110,
    }, self.ScreenGui)
    round(frame, 8)
    local border = stroke(frame, theme.Border, 0.2)
    make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, frame)
    local layout = make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, frame)
    local heading = textLabel(frame, tostring(opts.Title or "KEYBINDS"), 10, theme.Muted, { Size = UDim2.new(1, 0, 0, 16), Font = Enum.Font.GothamBold, ZIndex = 111 })
    local rowJanitor = Janitor.new()
    local observedKeybinds: {[any]: boolean} = {}
    local selfJanitor = Janitor.new()
    local function render()
        rowJanitor:Destroy()
        rowJanitor = Janitor.new()
        for _, child in ipairs(frame:GetChildren()) do
            if child:IsA("Frame") and child.Name == "KeybindRow" then child:Destroy() end
        end
        local order = 1
        for _, control in ipairs(self.Library.Controls) do
            if control.Window == self and control.Kind == "Keybind" then
                if not observedKeybinds[control] then
                    observedKeybinds[control] = true
                    selfJanitor:Add(control:OnChanged(function() render() end))
                end
            end
            if control.Window == self and control.Kind == "Keybind" and control.Value and control.Value ~= "" and not control.Destroyed and control.ElementFrame.Visible then
                local row = make("Frame", { Name = "KeybindRow", Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 111 }, frame)
                textLabel(row, tostring(control.TitleLabel and control.TitleLabel.Text or "Action"), 10, self.Library.ThemeManager.Current.Text, { Size = UDim2.new(1, -60, 1, 0), ZIndex = 112 })
                local key = textLabel(row, tostring(control.Value), 9, self.Library.ThemeManager.Current.Accent, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(54, 18), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 112 })
                key.Font = Enum.Font.GothamBold
                order += 1
            end
        end
    end
    local api = { Frame = frame }
    function api:SetVisible(visible: boolean) frame.Visible = visible == true; return self end
    function api:Refresh() render(); return self end
    function api:Destroy()
        rowJanitor:Destroy()
        selfJanitor:Destroy()
        if frame.Parent then frame:Destroy() end
        for index, widget in ipairs(selfWindow._floatingWidgets) do
            if widget == self then table.remove(selfWindow._floatingWidgets, index); break end
        end
    end
    selfJanitor:Add(self.Library.ControlsChanged:Connect(render))
    selfJanitor:Add(self.Library.ThemeManager.Changed:Connect(function(active)
        frame.BackgroundColor3 = active.Surface
        border.Color = active.Border
        heading.TextColor3 = active.Muted
        render()
    end))
    selfJanitor:Add(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        frame.Size = UDim2.fromOffset(tonumber(opts.Width) or 190, layout.AbsoluteContentSize.Y + 16)
    end))
    render()
    table.insert(self._floatingWidgets, api)
    return api
end

function Window:SetBlurEnabled(enabled: boolean)
    if enabled then
        if self._blurEffect == nil then
            local lighting = game:GetService("Lighting")
            local blur = Instance.new("BlurEffect")
            blur.Name = "SilentUI_Blur_" .. tostring(self.ScreenGui.Name):gsub("%W", "")
            blur.Size = 8
            blur.Parent = lighting
            self._blurEffect = blur
        end
    elseif self._blurEffect then
        self._blurEffect:Destroy()
        self._blurEffect = nil
    end
    return self
end

function Window:SetAcrylicEnabled(enabled: boolean)
    -- Roblox's standard client UI does not expose true background sampling.
    -- This lightweight acrylic treatment is an overlay/gradient approximation.
    self._acrylicEnabled = enabled == true
    self.BackgroundShade.BackgroundTransparency = enabled and 0.42 or (self._interfaceTransparency or (self.BackgroundImage.Image ~= "" and 0.28 or (tonumber(self.Library.ThemeManager.Current.WindowTransparency) or 0)))
    self.BackgroundShade.BackgroundColor3 = self.Library.ThemeManager.Current.Overlay
    return self
end

function Window:CreateBubbleToggle(options: any?): any
    assert(not self.Destroyed, "Window has been destroyed")
    local opts = options or {}
    local theme = self.Library.ThemeManager.Current
    local size = math.clamp(tonumber(opts.Size) or 48, 30, 88)
    local button = textButton(self.ScreenGui, tostring(opts.Text or opts.Title or "S"), {
        Name = tostring(opts.Name or "SilentUIBubbleToggle"),
        AnchorPoint = opts.AnchorPoint or Vector2.new(1, 1),
        Position = opts.Position or UDim2.new(1, -16, 1, -16),
        Size = UDim2.fromOffset(size, size),
        BackgroundColor3 = typeof(opts.Color) == "Color3" and opts.Color or theme.Accent,
        TextColor3 = opts.TextColor or theme.AccentText,
        TextSize = tonumber(opts.TextSize) or 14,
        ZIndex = 125,
    })
    round(button, math.clamp(tonumber(opts.CornerRadius) or math.floor(size / 2), 0, 44))
    stroke(button, theme.Border, 0.25)
    local gradient: UIGradient? = nil
    if typeof(opts.Gradient) == "ColorSequence" then
        gradient = make("UIGradient", { Color = opts.Gradient, Rotation = 35 }, button) :: UIGradient
    end

    local janitor = Janitor.new()
    janitor:Add(button)
    local api: any = {
        Button = button,
        Destroyed = false,
        Visible = true,
    }
    local dragging = false
    local moved = false
    local dragInput: InputObject? = nil
    local dragStart = Vector2.zero
    local origin = Vector2.zero

    local function clampPosition()
        if api.Destroyed or button.Parent == nil then return end
        local viewport = self:_ViewportSize()
        local width, height = button.AbsoluteSize.X, button.AbsoluteSize.Y
        local anchor = button.AnchorPoint
        local absolutePosition = button.AbsolutePosition - self.ScreenGui.AbsolutePosition
        local left = math.clamp(absolutePosition.X, 4, math.max(4, viewport.X - width - 4))
        local top = math.clamp(absolutePosition.Y, 4, math.max(4, viewport.Y - height - 4))
        button.Position = UDim2.fromOffset(left + width * anchor.X, top + height * anchor.Y)
    end
    api._OnViewportChanged = clampPosition

    janitor:Add(button.InputBegan:Connect(function(input)
        if opts.Draggable == false then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging = true
        moved = false
        dragInput = input
        dragStart = input.Position
        origin = Vector2.new(button.Position.X.Offset, button.Position.Y.Offset)
    end))
    janitor:Add(UserInputService.InputChanged:Connect(function(input)
        if not dragging or dragInput == nil then return end
        local isMouse = dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement
        local isTouch = dragInput.UserInputType == Enum.UserInputType.Touch and input == dragInput
        if not isMouse and not isTouch then return end
        local delta = input.Position - dragStart
        if delta.Magnitude > 4 then moved = true end
        if moved then
            button.Position = UDim2.fromOffset(origin.X + delta.X, origin.Y + delta.Y)
            clampPosition()
        end
    end))
    janitor:Add(UserInputService.InputEnded:Connect(function(input)
        if dragInput == input or (dragInput and dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
            dragging = false
            dragInput = nil
        end
    end))
    janitor:Add(button.Activated:Connect(function()
        if moved then
            moved = false
            return
        end
        self:Toggle()
        if type(opts.Callback) == "function" then
            local ok, err = pcall(opts.Callback, self.IsOpen, { Source = "UI", Action = "BubbleToggle" })
            if not ok then warn("[SilentUI] Bubble toggle callback failed: " .. tostring(err)) end
        end
    end))
    janitor:Add(self.Library.ThemeManager.Changed:Connect(function(active)
        if typeof(opts.Color) ~= "Color3" and not gradient then button.BackgroundColor3 = active.Accent end
        if opts.TextColor == nil then button.TextColor3 = active.AccentText end
        local outline = button:FindFirstChildOfClass("UIStroke")
        if outline then outline.Color = active.Border end
    end))
    janitor:Add(function()
        for index, widget in ipairs(self._floatingWidgets) do
            if widget == api then table.remove(self._floatingWidgets, index); break end
        end
    end)

    function api:SetText(value: string)
        button.Text = tostring(value)
        return self
    end
    function api:SetVisible(visible: boolean)
        api.Visible = visible == true
        button.Visible = api.Visible
        return self
    end
    function api:SetPosition(position: UDim2)
        button.Position = position
        clampPosition()
        return self
    end
    function api:Destroy()
        if api.Destroyed then return end
        api.Destroyed = true
        janitor:Destroy()
    end

    table.insert(self._floatingWidgets, api)
    clampPosition()
    return api
end

Window.CreateDockButton = Window.CreateBubbleToggle
Window.AddDockButton = Window.CreateBubbleToggle

function Window:CreateStateList(options: any?): any
    assert(not self.Destroyed, "Window has been destroyed")
    local opts = options or {}
    local theme = self.Library.ThemeManager.Current
    local width = math.clamp(tonumber(opts.Width) or 240, 150, 420)
    local height = math.clamp(tonumber(opts.Height) or 190, 90, 480)
    local frame = make("Frame", {
        Name = tostring(opts.Name or "SilentUIStateList"),
        Position = opts.Position or UDim2.fromOffset(14, 58),
        Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = theme.Surface,
        BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
        ZIndex = 115,
        ClipsDescendants = true,
    }, self.ScreenGui) :: Frame
    round(frame, 9)
    stroke(frame, theme.Border, 0.25)
    local heading = textLabel(frame, tostring(opts.Title or "STATUS"), 10, theme.Muted, {
        Position = UDim2.fromOffset(10, 4),
        Size = UDim2.new(1, -20, 0, 22),
        Font = Enum.Font.GothamBold,
        ZIndex = 117,
    })
    local scroller = make("ScrollingFrame", {
        Name = "Rows",
        Position = UDim2.fromOffset(8, 29),
        Size = UDim2.new(1, -16, 1, -37),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.fromOffset(0, 0),
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = theme.Accent,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 116,
    }, frame) :: ScrollingFrame
    local layout = make("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 3),
    }, scroller) :: UIListLayout

    local janitor = Janitor.new()
    janitor:Add(frame)
    local api: any = { Frame = frame, Destroyed = false, Items = {} }
    local function clampStateList()
        if api.Destroyed or frame.Parent == nil then return end
        local viewport = self:_ViewportSize()
        local safeWidth = math.max(1, math.min(width, viewport.X - 8))
        local safeHeight = math.max(1, math.min(height, viewport.Y - 8))
        frame.Size = UDim2.fromOffset(safeWidth, safeHeight)
        local position = frame.Position
        frame.Position = UDim2.fromOffset(
            math.clamp(position.X.Offset, 4, math.max(4, viewport.X - safeWidth - 4)),
            math.clamp(position.Y.Offset, 4, math.max(4, viewport.Y - safeHeight - 4))
        )
    end
    api._OnViewportChanged = clampStateList
    local function render()
        if api.Destroyed then return end
        local active = self.Library.ThemeManager.Current
        frame.BackgroundColor3 = active.Surface
        heading.TextColor3 = active.Muted
        scroller.ScrollBarImageColor3 = active.Accent
        for _, child in ipairs(scroller:GetChildren()) do
            if child:IsA("Frame") then child:Destroy() end
        end
        for index, raw in ipairs(api.Items) do
            local entry = if type(raw) == "table" then raw else { Title = tostring(raw) }
            local title = tostring(entry.Title or entry.Name or "State")
            local value = tostring(entry.Value or entry.Status or (entry.Active == true and "Active" or "Inactive"))
            local status = tostring(entry.Status or value):lower()
            local positive = entry.Active == true or entry.State == true or status == "active" or status == "online" or status == "ready" or status == "enabled"
            local negative = status == "error" or status == "offline" or status == "failed"
            local row = make("Frame", {
                Size = UDim2.new(1, 0, 0, 24),
                BackgroundTransparency = 1,
                LayoutOrder = index,
                ZIndex = 117,
            }, scroller)
            local dotColor = if positive then active.Success elseif negative then active.Danger else active.Muted
            local dot = make("Frame", {
                Position = UDim2.fromOffset(1, 8),
                Size = UDim2.fromOffset(7, 7),
                BackgroundColor3 = dotColor,
                BorderSizePixel = 0,
                ZIndex = 118,
            }, row)
            round(dot, 4)
            textLabel(row, title, 10, active.Text, {
                Position = UDim2.fromOffset(14, 0),
                Size = UDim2.new(0.62, -14, 1, 0),
                TextTruncate = Enum.TextTruncate.AtEnd,
                ZIndex = 118,
            })
            textLabel(row, value, 9, active.Muted, {
                Position = UDim2.new(0.62, 0, 0, 0),
                Size = UDim2.new(0.38, 0, 1, 0),
                TextXAlignment = Enum.TextXAlignment.Right,
                TextTruncate = Enum.TextTruncate.AtEnd,
                ZIndex = 118,
            })
        end
    end
    function api:Set(items: {any})
        api.Items = if type(items) == "table" then table.clone(items) else {}
        render()
        return self
    end
    function api:SetStates(items: {any}) return self:Set(items) end
    function api:SetTitle(value: string)
        heading.Text = tostring(value)
        return self
    end
    function api:SetVisible(visible: boolean)
        frame.Visible = visible == true
        return self
    end
    function api:SetPosition(position: UDim2)
        frame.Position = position
        return self
    end
    function api:Destroy()
        if api.Destroyed then return end
        api.Destroyed = true
        janitor:Destroy()
    end
    janitor:Add(self.Library.ThemeManager.Changed:Connect(render))
    janitor:Add(function()
        for index, widget in ipairs(self._floatingWidgets) do
            if widget == api then table.remove(self._floatingWidgets, index); break end
        end
    end)
    table.insert(self._floatingWidgets, api)
    api:Set(opts.Items or opts.States or {})
    clampStateList()
    return api
end

function Window:Watermark(options: any): any
    local window = self
    local opts = if type(options) == "string" then { Text = options } else (options or {})
    local theme = self.Library.ThemeManager.Current
    local frame = make("Frame", {
        Name = "Watermark",
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.fromOffset(12, 12),
        Size = UDim2.fromOffset(tonumber(opts.Width) or 210, tonumber(opts.Height) or 30),
        BackgroundColor3 = theme.Surface,
        BackgroundTransparency = 0.12,
        BorderSizePixel = 0,
        ZIndex = 120,
    }, self.ScreenGui)
    round(frame, 8)
    stroke(frame, theme.Border, 0.2)
    local label = textLabel(frame, tostring(opts.Text or self.Title), 11, theme.Text, {
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -20, 1, 0),
        Font = Enum.Font.GothamBold,
        ZIndex = 121,
    })
    local janitor = Janitor.new()
    janitor:Add(frame)
    local function clampWatermark()
        if frame.Parent == nil then return end
        local viewport = self:_ViewportSize()
        local safeWidth = math.max(1, math.min(tonumber(opts.Width) or 210, viewport.X - 8))
        local safeHeight = math.max(1, math.min(tonumber(opts.Height) or 30, viewport.Y - 8))
        frame.Size = UDim2.fromOffset(safeWidth, safeHeight)
        frame.Position = UDim2.fromOffset(
            math.clamp(frame.Position.X.Offset, 4, math.max(4, viewport.X - safeWidth - 4)),
            math.clamp(frame.Position.Y.Offset, 4, math.max(4, viewport.Y - safeHeight - 4))
        )
    end
    local api = {}
    api._OnViewportChanged = clampWatermark
    janitor:Add(self.Library.ThemeManager.Changed:Connect(function(active)
        frame.BackgroundColor3 = active.Surface
        label.TextColor3 = active.Text
        local border = frame:FindFirstChildOfClass("UIStroke")
        if border then border.Color = active.Border end
    end))
    function api:Set(value: string) label.Text = tostring(value); return self end
    function api:Destroy()
        janitor:Destroy()
        for index, widget in ipairs(window._floatingWidgets) do
            if widget == api then table.remove(window._floatingWidgets, index); break end
        end
    end
    table.insert(window._floatingWidgets, api)
    clampWatermark()
    return api
end

function Window:SetAuthor(author: string)
    self.Author = tostring(author)
    return self
end

function Window:SetSubtitle(subtitle: string)
    self.Subtitle = tostring(subtitle)
    self.SubtitleLabel.Text = self.Subtitle
    return self
end

function Window:SetTheme(theme: string | {[string]: any}, animate: boolean?)
    self.Library.ThemeManager:Set(theme, animate)
    return self
end

function Window:GetTheme(): {[string]: any}
    return self.Library.ThemeManager:Get()
end

function Window:GetThemes(): {string}
    return self.Library.ThemeManager:GetNames()
end

function Window:SetOpenButtonGhosted(ghosted: boolean)
    self.OpenButtonConfig.Ghosted = ghosted == true
    self.FloatingButton.BackgroundTransparency = ghosted and 0.48 or 0
    return self
end

function Window:SetSearchEnabled(enabled: boolean)
    self.SearchButton.Visible = enabled == true
    if not enabled then
        self.SearchBox.Visible = false
        self.TitleLabel.Visible = true
        self.SubtitleLabel.Visible = true
        self:ClearSearch()
    end
    return self
end

function Window:LockAll()
    for _, control in ipairs(self.Library.Controls) do
        if control.Window == self and type(control.SetDisabled) == "function" then
            control:SetDisabled(true)
        end
    end
    return self
end

function Window:UnlockAll()
    for _, control in ipairs(self.Library.Controls) do
        if control.Window == self and type(control.SetDisabled) == "function" then
            control:SetDisabled(false)
        end
    end
    return self
end

function Window:ExportConfig(profile: string): (boolean, string?)
    return self.Library.ConfigStore:Export(profile)
end

function Window:ImportConfig(profile: string, json: string): (boolean, string?)
    return self.Library.ConfigStore:Import(profile, json)
end

function Window:CreateSnapshot(): {[string]: any}
    return self.Library.ConfigStore:CreateSnapshot()
end

function Window:RestoreSnapshot(snapshot: any, silent: boolean?)
    return self.Library.ConfigStore:RestoreSnapshot(snapshot, silent)
end

function Window:ResetConfiguration(silent: boolean?)
    return self.Library.ConfigStore:Reset(silent)
end

function Window:ConfigManager(sectionOrTab: any, title: string?): any
    assert(type(sectionOrTab) == "table", "ConfigManager expects a Section or Tab")
    local section = sectionOrTab
    if type(sectionOrTab.Section) == "function" then
        section = sectionOrTab:Section(title or "Configuration")
    end
    assert(type(section) == "table" and type(section.Button) == "function", "ConfigManager expects a Section or Tab")

    local profileName = "Default"
    local profiles = self:ListConfigs()
    local selection = if #profiles > 0 then profiles[1] else profileName
    local nameBox = section:Textbox({
        Title = "Profile name",
        Default = profileName,
        Callback = function(value) profileName = tostring(value) end,
    })
    local profilePicker = section:Dropdown({
        Title = "Saved profiles",
        Options = profiles,
        Default = selection,
        Searchable = true,
        Callback = function(value)
            if value ~= nil then
                profileName = tostring(value)
                nameBox:Set(profileName, true, "ConfigManager")
            end
        end,
    })
    local renameBox = section:Textbox({ Title = "New profile name", Default = "" })

    local function notify(ok: boolean, action: string, err: string?)
        self:Notify({
            Title = ok and (action .. " completed") or (action .. " failed"),
            Content = err or profileName,
            Duration = 3,
        })
    end
    local function refreshProfiles()
        local refreshed = self:ListConfigs()
        profilePicker:Refresh(refreshed, true)
    end

    section:Button({ Title = "Save profile", Callback = function()
        local ok, err = self:SaveConfig(profileName)
        notify(ok, "Save", err)
        refreshProfiles()
    end })
    section:Button({ Title = "Load profile", Callback = function()
        local ok, err = self:LoadConfig(profileName)
        notify(ok, "Load", err)
    end })
    section:Button({ Title = "Set autoload", Callback = function()
        local ok, err = self:SetAutoload(profileName)
        notify(ok, "Autoload", err)
    end })
    section:Button({ Title = "Refresh profiles", Callback = refreshProfiles })
    section:Button({ Title = "Rename profile", Callback = function()
        local targetName = tostring(renameBox:Get() or "")
        local ok, err = self:RenameConfig(profileName, targetName)
        notify(ok, "Rename", err)
        if ok then
            profileName = targetName
            nameBox:Set(targetName, true, "ConfigManager")
            refreshProfiles()
        end
    end })
    section:Button({ Title = "Delete profile", Callback = function()
        self:Confirm({
            Title = "Delete profile?",
            Content = profileName,
            ConfirmText = "Delete",
            Callback = function()
                local ok, err = self:DeleteConfig(profileName)
                notify(ok, "Delete", err)
                refreshProfiles()
            end,
        })
    end })
    section:Button({ Title = "Reset current configuration", Callback = function()
        self:Confirm({
            Title = "Reset settings?",
            Content = "All registered controls return to their initial values.",
            ConfirmText = "Reset",
            Callback = function()
                self:ResetConfiguration(false)
                self:Notify({ Title = "Configuration reset", Content = "Initial values restored" })
            end,
        })
    end })
    return section
end

function Window:Tab(options: any): any
    assert(not self.Destroyed, "Window has been destroyed")
    local tab = Tab.new(self, options)
    table.insert(self.Tabs, tab)
    if self.CurrentTab == nil and not tab.Private then
        self:SelectTab(tab)
    end
    return tab
end

function Window:PrivateTab(options: any): any
    local config = if type(options) == "string" then { Title = options } else table.clone(options or {})
    config.Private = true
    return self:Tab(config)
end

Window.CreateTab = Window.Tab
Window.AddTab = Window.Tab
Window.AddPrivateTab = Window.PrivateTab

function Window:SelectTab(tab: any)
    if self.Destroyed then
        return
    end
    local selected = tab
    if type(tab) == "number" then
        selected = self.Tabs[tab]
    elseif type(tab) == "string" then
        for _, candidate in ipairs(self.Tabs) do
            if candidate.Title == tab then
                selected = candidate
                break
            end
        end
    end

    if selected == nil then
        return
    end

    self.CurrentTab = selected
    for _, candidate in ipairs(self.Tabs) do
        candidate:SetSelected(candidate == selected)
    end
end

function Window:_ClosePopup()
    if self._popup == nil then
        return
    end
    local popup = self._popup
    self._popup = nil
    popup.Janitor:Destroy()
end

function Window:_OpenPopup(owner: any, anchor: GuiObject, width: number?, height: number?): (Frame, any)
    self:_ClosePopup()

    local popupJanitor = Janitor.new()
    local overlay = textButton(self.ScreenGui, "", {
        Name = "PopupBackdrop",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ZIndex = 49,
        Active = true,
    })
    popupJanitor:Add(overlay)

    local panelWidth = math.max(180, width or anchor.AbsoluteSize.X)
    local panelHeight = math.max(70, height or 170)
    local viewport = self:_ViewportSize()
    local anchorPos = anchor.AbsolutePosition - self.ScreenGui.AbsolutePosition
    local anchorSize = anchor.AbsoluteSize
    local x = math.clamp(anchorPos.X, 8, math.max(8, viewport.X - panelWidth - 8))
    local belowY = anchorPos.Y + anchorSize.Y + 6
    local y = belowY + panelHeight <= viewport.Y - 8 and belowY or math.max(8, anchorPos.Y - panelHeight - 6)

    local panel = make("Frame", {
        Name = "PopupPanel",
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(math.min(panelWidth, viewport.X - 16), math.min(panelHeight, viewport.Y - 16)),
        BackgroundColor3 = self.Library.ThemeManager.Current.Surface,
        BorderSizePixel = 0,
        ZIndex = 50,
        ClipsDescendants = true,
    }, self.ScreenGui) :: Frame
    popupJanitor:Add(panel)
    round(panel, 10)
    stroke(panel, self.Library.ThemeManager.Current.Border, 0.12)

    popupJanitor:Add(overlay.Activated:Connect(function()
        self:_ClosePopup()
    end))

    self._popup = {
        Owner = owner,
        Panel = panel,
        Janitor = popupJanitor,
    }
    return panel, popupJanitor
end

function Window:_ShowTooltip(anchor: GuiObject, message: string)
    self:_HideTooltip()
    if message == "" or self.Destroyed then
        return
    end

    local viewport = self:_ViewportSize()
    local width = math.max(1, math.min(math.clamp(#message * 7 + 24, 110, 250), viewport.X - 12))
    local theme = self.Library.ThemeManager.Current
    local panel = make("Frame", {
        Name = "Tooltip",
        Size = UDim2.fromOffset(width, 34),
        BackgroundColor3 = theme.SurfaceAlt,
        BorderSizePixel = 0,
        ZIndex = 100,
    }, self.ScreenGui) :: Frame
    round(panel, 7)
    stroke(panel, theme.Border, 0.15)
    textLabel(panel, message, 11, theme.Text, {
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -20, 1, 0),
        TextWrapped = true,
        ZIndex = 101,
    })

    local position = anchor.AbsolutePosition - self.ScreenGui.AbsolutePosition
    local size = anchor.AbsoluteSize
    local x = math.clamp(position.X + size.X / 2 - width / 2, 6, math.max(6, viewport.X - width - 6))
    local y = position.Y + size.Y + 6
    if y + 34 > viewport.Y then
        y = math.max(6, position.Y - 40)
    end
    panel.Position = UDim2.fromOffset(x, y)
    self._tooltip = panel
end

function Window:_HideTooltip()
    if self._tooltip then
        self._tooltip:Destroy()
        self._tooltip = nil
    end
end

function Window:Notify(options: any): any
    if self.Destroyed then
        return nil
    end

    local opts = options or {}
    local pool: any = self.Library.InstancePool
    local card = pool:AcquireFrame(self.NotificationHolder)
    card.Name = "Notification"
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = self.Library.ThemeManager.Current.Surface
    card.BackgroundTransparency = 0.04
    card.BorderSizePixel = 0
    card.ZIndex = 80
    round(card, 10)
    stroke(card, self.Library.ThemeManager.Current.Border, 0.12)

    local padding = make("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
    }, card)
    local layout = make("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 3),
    }, card)
    local title = textLabel(card, tostring(opts.Title or "Notification"), 13, self.Library.ThemeManager.Current.Text, {
        Size = UDim2.new(1, 0, 0, 18),
        LayoutOrder = 1,
        Font = Enum.Font.GothamBold,
        Name = "NotificationTitle",
        ZIndex = 81,
    })
    local content = textLabel(card, tostring(opts.Content or opts.Description or ""), 11, self.Library.ThemeManager.Current.Muted, {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 2,
        TextWrapped = true,
        Name = "NotificationContent",
        ZIndex = 81,
    })
    local accent = make("Frame", {
        Name = "Accent",
        BackgroundColor3 = self.Library.ThemeManager.Current.Accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 3, 1, -12),
        Position = UDim2.fromOffset(0, 6),
        ZIndex = 82,
    }, card)
    round(accent, 2)
    card.LayoutOrder = #self._notifications + 1

    local noticeJanitor = Janitor.new()
    local closed = false
    local notice = {}
    local selfWindow = self
    function notice:Close()
        if closed then
            return
        end
        closed = true
        noticeJanitor:Destroy()
        for index, item in ipairs(selfWindow._notifications) do
            if item == notice then
                table.remove(selfWindow._notifications, index)
                break
            end
        end
        if card.Parent ~= nil then
            tween(card, 0.12, { BackgroundTransparency = 1 })
            task.delay(0.13, function()
                if selfWindow.Destroyed then
                    pcall(function() card:Destroy() end)
                else
                    pool:ReleaseFrame(card)
                end
            end)
        else
            if selfWindow.Destroyed then
                pcall(function() card:Destroy() end)
            else
                pool:ReleaseFrame(card)
            end
        end
    end
    notice.Card = card
    table.insert(self._notifications, notice)

    if type(opts.Buttons) == "table" and #opts.Buttons > 0 then
        local actions = make("Frame", {
            Name = "NotificationActions",
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundTransparency = 1,
            LayoutOrder = 3,
            ZIndex = 83,
        }, card) :: Frame
        local actionsLayout = make("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 6),
        }, actions)
        for index, buttonConfig in ipairs(opts.Buttons) do
            local config = if type(buttonConfig) == "table" then buttonConfig else { Title = tostring(buttonConfig) }
            local actionButton = textButton(actions, tostring(config.Title or config.Text or "Action"), {
                Size = UDim2.fromOffset(tonumber(config.Width) or 84, 27),
                BackgroundColor3 = config.Primary == true and self.Library.ThemeManager.Current.Accent or self.Library.ThemeManager.Current.SurfaceAlt,
                TextColor3 = config.Primary == true and self.Library.ThemeManager.Current.AccentText or self.Library.ThemeManager.Current.Text,
                TextSize = 10,
                LayoutOrder = index,
                ZIndex = 84,
            })
            round(actionButton, 6)
            noticeJanitor:Add(actionButton.Activated:Connect(function()
                if closed then return end
                if type(config.Callback) == "function" then
                    local ok, err = pcall(config.Callback, notice, index)
                    if not ok then warn("[SilentUI] Notification action failed: " .. tostring(err)) end
                end
                if config.CloseOnClick ~= false then notice:Close() end
            end))
        end
        noticeJanitor:Add(self.Library.ThemeManager.Changed:Connect(function(active)
            for _, child in ipairs(actions:GetChildren()) do
                if child:IsA("TextButton") then
                    local config = opts.Buttons[child.LayoutOrder]
                    local primary = type(config) == "table" and config.Primary == true
                    child.BackgroundColor3 = primary and active.Accent or active.SurfaceAlt
                    child.TextColor3 = primary and active.AccentText or active.Text
                end
            end
        end))
    end

    local duration = math.clamp(tonumber(opts.Duration) or 3.5, 1, 12)
    local timer = task.delay(duration, function()
        notice:Close()
    end)
    noticeJanitor:Add(timer)
    noticeJanitor:Add(card.Destroying:Connect(function()
        if not closed then
            closed = true
            noticeJanitor:Destroy()
        end
    end))
    noticeJanitor:Add(self.Library.ThemeManager.Changed:Connect(function(active)
        if card.Parent then
            card.BackgroundColor3 = active.Surface
            title.TextColor3 = active.Text
            content.TextColor3 = active.Muted
            accent.BackgroundColor3 = active.Accent
            local border = card:FindFirstChildOfClass("UIStroke")
            if border then border.Color = active.Border end
        end
    end))

    while #self._notifications > 4 do
        local oldest = self._notifications[1]
        if oldest then
            oldest:Close()
        else
            break
        end
    end

    tween(card, 0.16, { BackgroundTransparency = 0.04 })
    return notice
end

function Window:Dialog(options: any): any
    assert(not self.Destroyed, "Window has been destroyed")
    local opts = options or {}
    local theme = self.Library.ThemeManager.Current
    local viewport = self:_ViewportSize()
    local dialogWidth = math.max(1, math.min(380, viewport.X - 24))
    local dialogHeight = math.max(1, math.min(300, viewport.Y - 24))
    local janitor = Janitor.new()

    local overlay = make("Frame", {
        Name = "DialogOverlay",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = theme.Overlay,
        BackgroundTransparency = theme.OverlayTransparency,
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 110,
    }, self.ScreenGui) :: Frame
    janitor:Add(overlay)

    local dialog = make("Frame", {
        Name = "Dialog",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(dialogWidth, dialogHeight),
        BackgroundColor3 = theme.Surface,
        ClipsDescendants = true,
        BorderSizePixel = 0,
        ZIndex = 111,
    }, overlay) :: Frame
    janitor:Add(dialog)
    round(dialog, 12)
    stroke(dialog, theme.Border, 0.12)

    textLabel(dialog, tostring(opts.Title or "Confirm"), 16, theme.Text, {
        Position = UDim2.fromOffset(16, 12),
        Size = UDim2.new(1, -32, 0, 24),
        Font = Enum.Font.GothamBold,
        ZIndex = 112,
    })

    local contentScroll = make("ScrollingFrame", {
        Name = "DialogContentScroll",
        Position = UDim2.fromOffset(16, 44),
        Size = UDim2.new(1, -32, 1, -100),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = theme.Accent,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ZIndex = 112,
    }, dialog) :: ScrollingFrame
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
    }, contentScroll)
    local content = textLabel(contentScroll, tostring(opts.Content or opts.Description or ""), 12, theme.Muted, {
        Name = "DialogContent",
        Size = UDim2.new(1, -4, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = 1,
        ZIndex = 113,
    })
    local inputConfig = if type(opts.Input) == "table" then opts.Input elseif opts.Input == true or opts.InputPlaceholder ~= nil then {} else nil
    local inputBox: TextBox? = nil
    if inputConfig ~= nil then
        inputBox = make("TextBox", {
            Name = "DialogInput",
            Size = UDim2.new(1, -4, 0, 36),
            BackgroundColor3 = theme.SurfaceAlt,
            BorderSizePixel = 0,
            ClearTextOnFocus = inputConfig.ClearTextOnFocus == true,
            Text = tostring(inputConfig.Default or opts.InputDefault or ""),
            PlaceholderText = tostring(inputConfig.Placeholder or opts.InputPlaceholder or "Enter text..."),
            TextColor3 = theme.Text,
            PlaceholderColor3 = theme.Muted,
            TextSize = 12,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = 2,
            ZIndex = 113,
        }, contentScroll) :: TextBox
        round(inputBox, 7)
        make("UIPadding", {
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10),
        }, inputBox)
    end
    janitor:Add(contentScroll)

    local buttonRow = make("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 1, -46),
        Size = UDim2.new(1, -24, 0, 34),
        ZIndex = 112,
    }, dialog) :: Frame
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
    }, buttonRow)

    local closed = false
    local api = { Frame = dialog, Overlay = overlay, Input = inputBox }
    local selfWindow = self
    function api:GetInput(): string
        return inputBox and inputBox.Text or ""
    end
    function api:SetInput(value: string)
        if inputBox then inputBox.Text = tostring(value) end
        return self
    end
    function api:Close()
        if closed then
            return
        end
        closed = true
        janitor:Destroy()
        selfWindow._dialogs[api] = nil
    end
    function api:Destroy()
        self:Close()
    end
    janitor:Add(self.Library.ThemeManager.Changed:Connect(function(activeTheme)
        if closed then
            return
        end
        overlay.BackgroundColor3 = activeTheme.Overlay
        overlay.BackgroundTransparency = activeTheme.OverlayTransparency
        dialog.BackgroundColor3 = activeTheme.Surface
        contentScroll.ScrollBarImageColor3 = activeTheme.Accent
        local dialogStroke = dialog:FindFirstChildOfClass("UIStroke")
        if dialogStroke then
            dialogStroke.Color = activeTheme.Border
        end
        for _, descendant in ipairs(dialog:GetDescendants()) do
            if descendant:IsA("TextLabel") then
                descendant.TextColor3 = descendant.Name == "DialogContent" and activeTheme.Muted or activeTheme.Text
            elseif descendant:IsA("TextButton") then
                local isPrimary = descendant:GetAttribute("SilentUIPrimary") == true
                descendant.BackgroundColor3 = isPrimary and activeTheme.Accent or activeTheme.SurfaceAlt
                descendant.TextColor3 = isPrimary and activeTheme.AccentText or activeTheme.Text
            end
        end
    end))
    self._dialogs[api] = true

    local buttons = opts.Buttons
    if type(buttons) ~= "table" or #buttons == 0 then
        buttons = { { Title = "OK", Variant = "Primary" } }
    end

    for index, buttonOptions in ipairs(buttons) do
        local buttonConfig = if type(buttonOptions) == "table" then buttonOptions else { Title = tostring(buttonOptions) }
        local primary = buttonConfig.Variant == "Primary"
        local button = textButton(buttonRow, tostring(buttonConfig.Title or "OK"), {
            Size = UDim2.fromOffset(math.max(70, tonumber(buttonConfig.Width) or 88), 34),
            BackgroundColor3 = primary and theme.Accent or theme.SurfaceAlt,
            TextColor3 = primary and theme.AccentText or theme.Text,
            LayoutOrder = index,
            ZIndex = 113,
        })
        button:SetAttribute("SilentUIPrimary", primary)
        round(button, 8)
        janitor:Add(button.Activated:Connect(function()
            if type(buttonConfig.Callback) == "function" then
                local ok, err = pcall(buttonConfig.Callback, api)
                if not ok then
                    warn("[SilentUI] Dialog callback failed: " .. tostring(err))
                end
            end
            if buttonConfig.CloseOnClick ~= false then
                api:Close()
            end
        end))
    end

    return api
end

function Window:Confirm(options: any): any
    local opts = options or {}
    local callback = opts.Callback
    return self:Dialog({
        Title = opts.Title or "Confirm",
        Content = opts.Content or opts.Description or "Are you sure?",
        Buttons = {
            {
                Title = opts.CancelText or "Cancel",
                Variant = "Secondary",
            },
            {
                Title = opts.ConfirmText or "Confirm",
                Variant = "Primary",
                Callback = function(dialog)
                    if type(callback) == "function" then
                        callback(dialog)
                    end
                end,
            },
        },
    })
end

function Window:Prompt(options: any): any
    local opts = options or {}
    local callback = opts.Callback
    return self:Dialog({
        Title = opts.Title or "Input",
        Content = opts.Content or opts.Description or "",
        Input = {
            Placeholder = opts.InputPlaceholder or opts.Placeholder or "Enter text...",
            Default = opts.Default or "",
            ClearTextOnFocus = opts.ClearTextOnFocus == true,
        },
        Buttons = {
            { Title = opts.CancelText or "Cancel", Variant = "Secondary" },
            {
                Title = opts.ConfirmText or opts.SubmitText or "Submit",
                Variant = "Primary",
                Callback = function(dialog)
                    if type(callback) == "function" then
                        callback(dialog:GetInput(), dialog)
                    end
                end,
            },
        },
    })
end

Window.InputDialog = Window.Prompt

function Window:Modal(options: any): any
    return self:Dialog(options)
end

function Window:Popup(options: any): any
    return self:Dialog(options)
end

function Window:SaveConfig(profile: string)
    return self.Library.ConfigStore:Save(profile)
end

function Window:LoadConfig(profile: string, silent: boolean?)
    return self.Library.ConfigStore:Load(profile, silent)
end

function Window:ListConfigs(): {string}
    return self.Library.ConfigStore:List()
end

function Window:DeleteConfig(profile: string)
    return self.Library.ConfigStore:Delete(profile)
end

function Window:RenameConfig(oldName: string, newName: string)
    return self.Library.ConfigStore:Rename(oldName, newName)
end

function Window:SetAutoload(profile: string?)
    return self.Library.ConfigStore:SetAutoload(profile)
end

function Window:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    for _, callback in ipairs(self._destroyCallbacks) do
        local ok, err = pcall(callback, self)
        if not ok then warn("[SilentUI] OnDestroy callback failed: " .. tostring(err)) end
    end
    table.clear(self._openCallbacks)
    table.clear(self._closeCallbacks)
    table.clear(self._destroyCallbacks)

    self:_ClosePopup()
    self:_HideTooltip()
    local widgets = table.clone(self._floatingWidgets or {})
    for _, widget in ipairs(widgets) do
        if widget and type(widget.Destroy) == "function" then widget:Destroy() end
    end
    table.clear(self._floatingWidgets or {})
    if self._blurEffect then
        self._blurEffect:Destroy()
        self._blurEffect = nil
    end

    local notifications = table.clone(self._notifications)
    for _, notice in ipairs(notifications) do
        notice:Close()
    end

    local tabs = table.clone(self.Tabs)
    for _, tab in ipairs(tabs) do
        tab:Destroy()
    end
    table.clear(self.Tabs)

    local dialogs = {}
    for dialog in pairs(self._dialogs) do
        table.insert(dialogs, dialog)
    end
    for _, dialog in ipairs(dialogs) do
        dialog:Close()
    end

    self._janitor:Destroy()
    if self.ScreenGui.Parent ~= nil then
        self.ScreenGui:Destroy()
    end

    for index, window in ipairs(self.Library._windows) do
        if window == self then
            table.remove(self.Library._windows, index)
            break
        end
    end
end

__SUI_UI_Window = Window
end

-- ===== Module: init =====
local __SUI_Library
do
-- SilentUI public entry point. Roblox client-side ModuleScript.

local Janitor = __SUI_Core_Janitor
local InstancePool = __SUI_Core_InstancePool
local ThemeManager = __SUI_Core_ThemeManager
local ConfigStore = __SUI_Core_ConfigStore
local Localization = __SUI_Core_Localization
local Signal = __SUI_Core_Signal
local IconRegistry = __SUI_Core_IconRegistry
local Window = __SUI_UI_Window

local Library = {}
Library.__index = Library

type Library = typeof(setmetatable({} :: {
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

__SUI_Library = Library.new()
end

local Library = __SUI_Library


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
