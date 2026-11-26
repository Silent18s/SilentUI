--!strict
-- JSON profile persistence behind an adapter boundary.
-- The default adapter is memory-only; persistence is supplied by the embedding application.

local HttpService = game:GetService("HttpService")

export type Adapter = {
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

return ConfigStore
