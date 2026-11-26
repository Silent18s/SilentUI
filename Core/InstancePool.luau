--!strict
-- A deliberately narrow pool for short-lived notification card Frames.
-- Child objects and their event connections must be removed before Release.

export type InstancePool = {
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

return InstancePool
