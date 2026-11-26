--!strict
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

return IconRegistry
