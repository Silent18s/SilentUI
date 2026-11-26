--!strict
-- Advanced, composable UI elements inspired by the five supplied libraries.
-- Advanced presentation components built with Roblox client APIs.

local TweenService = game:GetService("TweenService")
local Janitor = require(script.Parent.Parent.Core.Janitor)
local Signal = require(script.Parent.Parent.Core.Signal)

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

return AdvancedControls
