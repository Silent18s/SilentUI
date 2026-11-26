--!strict
-- Reusable control implementations. All controls share Set/Get/OnChanged/Destroy.

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Janitor = require(script.Parent.Parent.Core.Janitor)
local Signal = require(script.Parent.Parent.Core.Signal)

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

return Controls
