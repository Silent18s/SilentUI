--!strict
-- Deterministic cleanup for connections, Instances, threads and callbacks.

export type Janitor = {
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

return Janitor
