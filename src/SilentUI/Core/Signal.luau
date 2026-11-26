--!strict
-- Small signal implementation used for consistent control callbacks.

export type Connection = {
    Connected: boolean,
    Disconnect: (self: Connection) -> (),
}

export type Signal = {
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

return Signal
