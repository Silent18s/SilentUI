--!strict
-- Small token-based localization service with live bindings.

local Signal = require(script.Parent.Signal)

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

return Localization
