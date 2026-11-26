--!strict
-- Section layout and component factory surface.

local Janitor = require(script.Parent.Parent.Core.Janitor)
local Controls = require(script.Parent.Controls)
local AdvancedControls = require(script.Parent.AdvancedControls)

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

return Section
