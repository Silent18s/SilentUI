--!strict
-- Tab navigation and page ownership.

local Janitor = require(script.Parent.Parent.Core.Janitor)
local Section = require(script.Parent.Section)

local Tab = {}
Tab.__index = Tab

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

function Tab.new(window: any, options: any?): any
    local opts = options or {}
    local title = tostring(opts.Title or opts.Name or ("Tab " .. tostring(#window.Tabs + 1)))
    local theme = window.Library.ThemeManager.Current

    local self = setmetatable({
        Window = window,
        Title = title,
        Options = opts,
        Sections = {},
        SubTabs = {},
        _defaultSection = nil,
        Private = opts.Private == true,
        UserVisible = opts.Visible ~= false and opts.Private ~= true,
        SearchVisible = true,
        CurrentSubTab = nil,
        SubTabBar = nil,
        Selected = false,
        Destroyed = false,
        _janitor = Janitor.new(),
    }, Tab)

    local button = make("TextButton", {
        Name = "TabButton",
        Size = UDim2.fromOffset(math.max(82, math.min(138, #title * 8 + 28)), 32),
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = 0.52,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = title,
        TextColor3 = theme.Muted,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        LayoutOrder = #window.Tabs + 1,
        ZIndex = 6,
        Visible = opts.Visible ~= false and opts.Private ~= true,
    }, window.TabBar) :: TextButton
    self.Button = button
    make("UICorner", { CornerRadius = UDim.new(0, 8) }, button)
    local icon = opts.Icon
    local iconDescriptor = if icon ~= nil then window.Library:GetIcon(icon, opts.IconPack) else nil
    if iconDescriptor ~= nil then
        self.IconImage = make("ImageLabel", {
            Name = "TabIcon",
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(8, 8),
            Size = UDim2.fromOffset(16, 16),
            Image = iconDescriptor.Image,
            ImageRectSize = iconDescriptor.ImageRectSize or Vector2.zero,
            ImageRectOffset = iconDescriptor.ImageRectOffset or Vector2.zero,
            ImageColor3 = theme.Muted,
            ZIndex = 7,
        }, button) :: ImageLabel
        button.TextXAlignment = Enum.TextXAlignment.Left
        make("UIPadding", { PaddingLeft = UDim.new(0, 28), PaddingRight = UDim.new(0, 8) }, button)
    end

    local page = make("ScrollingFrame", {
        Name = "Page_" .. title:gsub("%W", ""),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = theme.Accent,
        Visible = false,
        ZIndex = 6,
    }, window.Content) :: ScrollingFrame
    self.Page = page

    local padding = make("UIPadding", {
        PaddingTop = UDim.new(0, 5),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 2),
        PaddingRight = UDim.new(0, 5),
    }, page)
    local layout = make("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
    }, page)
    self._janitor:Add(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 20)
    end))
    self._janitor:Add(button.Activated:Connect(function()
        window:SelectTab(self)
    end))
    self._janitor:Add(window.Library.ThemeManager.Changed:Connect(function()
        self:ApplyTheme()
    end))

    self:ApplyTheme()
    return self
end

function Tab:ApplyTheme()
    if self.Destroyed then
        return
    end
    local theme = self.Window.Library.ThemeManager.Current
    self.Button.BackgroundColor3 = self.Selected and theme.Accent or theme.SurfaceAlt
    self.Button.BackgroundTransparency = self.Selected and 0.05 or 0.52
    self.Button.TextColor3 = self.Selected and theme.AccentText or theme.Muted
    if self.IconImage then self.IconImage.ImageColor3 = self.Selected and theme.AccentText or theme.Muted end
    self.Page.ScrollBarImageColor3 = theme.Accent
end

function Tab:SetSelected(selected: boolean)
    if self.Destroyed then
        return
    end
    self.Selected = selected
    self.Page.Visible = selected
    self.Button.Visible = self.UserVisible and self.SearchVisible
    self:ApplyTheme()
end

function Tab:SetVisible(visible: boolean)
    self.UserVisible = visible == true
    self.Button.Visible = self.UserVisible and self.SearchVisible
    if not self.Button.Visible and self.Selected then
        for _, candidate in ipairs(self.Window.Tabs) do
            if candidate ~= self and candidate.Button.Visible then
                self.Window:SelectTab(candidate)
                break
            end
        end
    end
    return self
end

function Tab:SetPrivate(private: boolean)
    self.Private = private == true
    self.UserVisible = not self.Private
    self.Button.Visible = self.UserVisible and self.SearchVisible
    return self
end

function Tab:SetTitle(title: string)
    self.Title = tostring(title)
    self.Button.Text = self.Title
    self.Button.Size = UDim2.fromOffset(math.max(82, math.min(138, #self.Title * 8 + 28)), 32)
    return self
end

function Tab:SetIcon(icon: any)
    if icon == nil or tostring(icon) == "" then
        if self.IconImage then self.IconImage:Destroy(); self.IconImage = nil end
        local padding = self.Button:FindFirstChildOfClass("UIPadding")
        if padding then padding:Destroy() end
        self.Button.TextXAlignment = Enum.TextXAlignment.Center
        return self
    end
    local descriptor = self.Window.Library:GetIcon(icon)
    if descriptor == nil then return self end
    if not self.IconImage then
        self.IconImage = make("ImageLabel", { Name = "TabIcon", BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(16, 16), ZIndex = 7 }, self.Button) :: ImageLabel
        self.Button.TextXAlignment = Enum.TextXAlignment.Left
        make("UIPadding", { PaddingLeft = UDim.new(0, 28), PaddingRight = UDim.new(0, 8) }, self.Button)
    end
    self.IconImage.Image = descriptor.Image
    self.IconImage.ImageRectSize = descriptor.ImageRectSize or Vector2.zero
    self.IconImage.ImageRectOffset = descriptor.ImageRectOffset or Vector2.zero
    self:ApplyTheme()
    return self
end

function Tab:Section(options: any?): any
    assert(not self.Destroyed, "Tab has been destroyed")
    local section = Section.new(self, options)
    table.insert(self.Sections, section)
    return section
end

local SubTab = {}
SubTab.__index = SubTab

function SubTab.new(tab: any, options: any): any
    local opts = if type(options) == "string" then { Title = options } else (options or {})
    local theme = tab.Window.Library.ThemeManager.Current
    if tab.SubTabBar == nil then
        local bar = make("Frame", {
            Name = "SubTabBar",
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 32),
            LayoutOrder = -1000,
        }, tab.Page) :: Frame
        make("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
        }, bar)
        tab.SubTabBar = bar
    end

    local self = setmetatable({
        Tab = tab,
        Window = tab.Window,
        Title = tostring(opts.Title or opts.Name or ("SubTab " .. tostring(#tab.SubTabs + 1))),
        Sections = {},
        _defaultSection = nil,
        Destroyed = false,
        Selected = false,
        UserVisible = opts.Visible ~= false,
        _janitor = Janitor.new(),
    }, SubTab)

    self.Button = make("TextButton", {
        Name = "SubTabButton",
        Size = UDim2.fromOffset(math.max(76, math.min(132, #self.Title * 7 + 25)), 28),
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = self.Title,
        TextColor3 = theme.Muted,
        TextSize = 11,
        Font = Enum.Font.GothamMedium,
        LayoutOrder = #tab.SubTabs + 1,
        Visible = self.UserVisible,
    }, tab.SubTabBar) :: TextButton
    make("UICorner", { CornerRadius = UDim.new(0, 7) }, self.Button)

    self.Page = make("Frame", {
        Name = "SubTabPage_" .. self.Title:gsub("%W", ""),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = #tab.SubTabs + 1,
        Visible = false,
    }, tab.Page) :: Frame
    local layout = make("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
    }, self.Page) :: UIListLayout
    self._janitor:Add(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        self.Page.Size = UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y + 4)
    end))
    self._janitor:Add(self.Button.Activated:Connect(function()
        tab:SelectSubTab(self)
    end))
    self._janitor:Add(tab.Window.Library.ThemeManager.Changed:Connect(function()
        self:ApplyTheme()
    end))
    table.insert(tab.SubTabs, self)
    if tab.CurrentSubTab == nil then
        tab:SelectSubTab(self)
    end
    return self
end

function SubTab:ApplyTheme()
    if self.Destroyed then return end
    local theme = self.Window.Library.ThemeManager.Current
    self.Button.BackgroundColor3 = self.Selected and theme.Accent or theme.SurfaceAlt
    self.Button.BackgroundTransparency = self.Selected and 0.05 or 0.45
    self.Button.TextColor3 = self.Selected and theme.AccentText or theme.Muted
end

function SubTab:Section(options: any?): any
    assert(not self.Destroyed, "SubTab has been destroyed")
    local section = Section.new(self, options)
    table.insert(self.Sections, section)
    return section
end

SubTab.AddSection = SubTab.Section
SubTab.CreateSection = SubTab.Section

function SubTab:SetTitle(title: string)
    self.Title = tostring(title)
    self.Button.Text = self.Title
    self.Button.Size = UDim2.fromOffset(math.max(82, math.min(138, #self.Title * 8 + 28)), 28)
    return self
end

function SubTab:SetVisible(visible: boolean)
    self.UserVisible = visible == true
    self.Button.Visible = self.UserVisible
    if not self.UserVisible and self.Selected then
        self.Page.Visible = false
        for _, candidate in ipairs(self.Tab.SubTabs) do
            if candidate ~= self and candidate.UserVisible then
                self.Tab:SelectSubTab(candidate)
                break
            end
        end
    end
    return self
end

function SubTab:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    local sections = table.clone(self.Sections)
    for _, section in ipairs(sections) do section:Destroy() end
    table.clear(self.Sections)
    self._janitor:Destroy()
    if self.Button.Parent then self.Button:Destroy() end
    if self.Page.Parent then self.Page:Destroy() end
    for index, subtab in ipairs(self.Tab.SubTabs) do
        if subtab == self then table.remove(self.Tab.SubTabs, index); break end
    end
    if self.Tab.CurrentSubTab == self then
        self.Tab.CurrentSubTab = nil
        if self.Tab.SubTabs[1] then self.Tab:SelectSubTab(self.Tab.SubTabs[1]) end
    end
end

function Tab:SubTab(options: any): any
    assert(not self.Destroyed, "Tab has been destroyed")
    return SubTab.new(self, options)
end

Tab.AddSubTab = Tab.SubTab
Tab.CreateSubTab = Tab.SubTab

function Tab:Select()
    self.Window:SelectTab(self)
    return self
end

function Tab:LockAll()
    for _, section in ipairs(self.Sections) do section:LockAll() end
    for _, subTab in ipairs(self.SubTabs) do for _, section in ipairs(subTab.Sections) do section:LockAll() end end
    return self
end

function Tab:UnlockAll()
    for _, section in ipairs(self.Sections) do section:UnlockAll() end
    for _, subTab in ipairs(self.SubTabs) do for _, section in ipairs(subTab.Sections) do section:UnlockAll() end end
    return self
end

function Tab:SelectSubTab(subTab: any)
    if self.Destroyed then return end
    local selected = subTab
    if type(subTab) == "number" then
        selected = self.SubTabs[subTab]
    elseif type(subTab) == "string" then
        for _, candidate in ipairs(self.SubTabs) do
            if candidate.Title == subTab then selected = candidate; break end
        end
    end
    if selected == nil or selected.UserVisible == false then return end
    self.CurrentSubTab = selected
    for _, candidate in ipairs(self.SubTabs) do
        candidate.Selected = candidate == selected
        candidate.Page.Visible = candidate == selected
        candidate:ApplyTheme()
    end
end

function SubTab:Select()
    self.Tab:SelectSubTab(self)
    return self
end

Tab.AddSection = Tab.Section
Tab.CreateSection = Tab.Section

-- Direct element API. Components created this way share one
-- implicit section; callers can still use explicit Section() for layout.
function Tab:_GetDefaultSection(): any
    assert(not self.Destroyed, "Tab has been destroyed")
    if self._defaultSection == nil or self._defaultSection.Destroyed then
        self._defaultSection = self:Section({ Title = self.Options.DefaultSectionTitle or "" })
    end
    return self._defaultSection
end

local DIRECT_CONTROLS: {[string]: string} = {
    toggle = "Toggle", slider = "Slider", dropdown = "Dropdown",
    multidropdown = "MultiDropdown", textbox = "Textbox", input = "Input",
    keybind = "Keybind", colorpicker = "ColorPicker", color = "ColorPicker",
    button = "Button", label = "Label", paragraph = "Paragraph",
    stepper = "Stepper", progress = "Progress", divider = "Divider",
    segmented = "Segmented", segmentedcontrol = "Segmented", stats = "Stats",
    image = "Image", video = "Video", code = "Code", tag = "Tag",
    card = "Card", table = "Table", console = "Console",
    changelog = "Changelog", changelogentry = "Changelog",
    rating = "Rating", assetgrid = "AssetGrid", cardgrid = "CardGrid",
    infogrid = "InfoGrid", systeminfogrid = "SystemInfoGrid",
    loadoutgroup = "LoadoutGroup", statelist = "StateList",
    gradientcard = "GradientCard", linetext = "LineText",
}

function Tab:AddControl(options: any): any
    assert(type(options) == "table", "AddControl expects an options table")
    local kind = string.lower(tostring(options.Type or options.Control or options.Kind or "")):gsub("[%s_%-]", "")
    local methodName = DIRECT_CONTROLS[kind]
    assert(methodName ~= nil, "Unknown control type: " .. kind)
    local section = options.Section
    if type(section) ~= "table" or type(section._Create) ~= "function" then
        section = self:_GetDefaultSection()
    end
    return (section :: any)[methodName](section, options)
end

function Tab:AddControls(definitions: {any}): {any}
    assert(type(definitions) == "table", "AddControls expects an array")
    local result = {}
    for _, definition in ipairs(definitions) do
        table.insert(result, self:AddControl(definition))
    end
    return result
end

function Tab:Group(options: any?): any
    return self:_GetDefaultSection():Group(options)
end

function Tab:MultiSection(options: any?): {any}
    return self:_GetDefaultSection():MultiSection(options)
end

function Tab:BindEnabledWhen(source: any, predicate: (any) -> boolean, targets: any): any
    return self:_GetDefaultSection():BindEnabledWhen(source, predicate, targets)
end

function Tab:BindVisibleWhen(source: any, predicate: (any) -> boolean, targets: any): any
    return self:_GetDefaultSection():BindVisibleWhen(source, predicate, targets)
end

local function addDirect(name: string, sectionMethod: string)
    (Tab :: any)[name] = function(self: any, options: any)
        local section = self:_GetDefaultSection()
        return (section :: any)[sectionMethod](section, options or {})
    end
end

for _, pair in ipairs({
    {"Toggle", "Toggle"}, {"Slider", "Slider"}, {"Dropdown", "Dropdown"},
    {"MultiDropdown", "MultiDropdown"}, {"Textbox", "Textbox"}, {"Input", "Input"},
    {"Keybind", "Keybind"}, {"ColorPicker", "ColorPicker"}, {"Colorpicker", "Colorpicker"},
    {"Button", "Button"}, {"Label", "Label"}, {"Paragraph", "Paragraph"},
    {"Stepper", "Stepper"}, {"Progress", "Progress"}, {"Divider", "Divider"},
    {"Segmented", "Segmented"}, {"Stats", "Stats"}, {"Image", "Image"},
    {"Video", "Video"}, {"Code", "Code"}, {"Tag", "Tag"}, {"Card", "Card"},
    {"Table", "Table"}, {"Console", "Console"}, {"Changelog", "Changelog"},
    {"Rating", "Rating"}, {"AssetGrid", "AssetGrid"}, {"CardGrid", "CardGrid"},
    {"InfoGrid", "InfoGrid"}, {"SystemInfoGrid", "SystemInfoGrid"},
    {"LoadoutGroup", "LoadoutGroup"}, {"StateList", "StateList"},
    {"GradientCard", "GradientCard"}, {"LineText", "LineText"},
    {"ToggleKeybind", "ToggleKeybind"}, {"ButtonKeybind", "ButtonKeybind"},
}) do
    addDirect("Add" .. pair[1], pair[2])
    addDirect("Create" .. pair[1], pair[2])
end

function SubTab:_GetDefaultSection(): any
    assert(not self.Destroyed, "SubTab has been destroyed")
    if self._defaultSection == nil or self._defaultSection.Destroyed then
        self._defaultSection = self:Section({ Title = self.Tab.Options.DefaultSectionTitle or "" })
    end
    return self._defaultSection
end

function SubTab:AddControl(options: any): any
    assert(type(options) == "table", "AddControl expects an options table")
    local kind = string.lower(tostring(options.Type or options.Control or options.Kind or "")):gsub("[%s_%-]", "")
    local methodName = DIRECT_CONTROLS[kind]
    assert(methodName ~= nil, "Unknown control type: " .. kind)
    local section = options.Section
    if type(section) ~= "table" or type(section._Create) ~= "function" then
        section = self:_GetDefaultSection()
    end
    return (section :: any)[methodName](section, options)
end

function SubTab:AddControls(definitions: {any}): {any}
    local result = {}
    for _, definition in ipairs(definitions) do
        table.insert(result, self:AddControl(definition))
    end
    return result
end

local function addSubTabDirect(name: string, sectionMethod: string)
    (SubTab :: any)[name] = function(self: any, options: any)
        local section = self:_GetDefaultSection()
        return (section :: any)[sectionMethod](section, options or {})
    end
end

for _, pair in ipairs({
    {"Toggle", "Toggle"}, {"Slider", "Slider"}, {"Dropdown", "Dropdown"},
    {"MultiDropdown", "MultiDropdown"}, {"Textbox", "Textbox"}, {"Input", "Input"},
    {"Keybind", "Keybind"}, {"ColorPicker", "ColorPicker"}, {"Colorpicker", "Colorpicker"},
    {"Button", "Button"}, {"Label", "Label"}, {"Paragraph", "Paragraph"},
    {"Stepper", "Stepper"}, {"Progress", "Progress"}, {"Divider", "Divider"},
    {"Segmented", "Segmented"}, {"Stats", "Stats"}, {"Image", "Image"},
    {"Video", "Video"}, {"Code", "Code"}, {"Tag", "Tag"}, {"Card", "Card"},
    {"Table", "Table"}, {"Console", "Console"}, {"Changelog", "Changelog"},
    {"Rating", "Rating"}, {"AssetGrid", "AssetGrid"}, {"CardGrid", "CardGrid"},
    {"InfoGrid", "InfoGrid"}, {"SystemInfoGrid", "SystemInfoGrid"},
    {"LoadoutGroup", "LoadoutGroup"}, {"StateList", "StateList"},
    {"GradientCard", "GradientCard"}, {"LineText", "LineText"},
    {"ToggleKeybind", "ToggleKeybind"}, {"ButtonKeybind", "ButtonKeybind"},
}) do
    addSubTabDirect("Add" .. pair[1], pair[2])
    addSubTabDirect("Create" .. pair[1], pair[2])
end

function Tab:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true

    local subTabs = table.clone(self.SubTabs)
    for _, subTab in ipairs(subTabs) do subTab:Destroy() end
    table.clear(self.SubTabs)

    local sections = table.clone(self.Sections)
    for _, section in ipairs(sections) do
        section:Destroy()
    end
    table.clear(self.Sections)
    self._janitor:Destroy()

    if self.Button.Parent ~= nil then
        self.Button:Destroy()
    end
    if self.Page.Parent ~= nil then
        self.Page:Destroy()
    end

    for index, tab in ipairs(self.Window.Tabs) do
        if tab == self then
            table.remove(self.Window.Tabs, index)
            break
        end
    end
    if self.Window.CurrentTab == self then
        self.Window.CurrentTab = nil
        local first = self.Window.Tabs[1]
        if first then
            self.Window:SelectTab(first)
        end
    end
end

return Tab
