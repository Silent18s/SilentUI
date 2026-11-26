--!strict
-- Window shell, viewport bounds, tabs, popups, notifications and dialogs.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Janitor = require(script.Parent.Parent.Core.Janitor)
local InstancePool = require(script.Parent.Parent.Core.InstancePool)
local Tab = require(script.Parent.Tab)

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

return Window
