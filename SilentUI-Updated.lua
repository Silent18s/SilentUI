--!nonstrict
local TweenService      = game:GetService("TweenService")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TextService       = game:GetService("TextService")
local Lighting          = game:GetService("Lighting")
local HttpService       = game:GetService("HttpService")
local GuiService        = game:GetService("GuiService")
local AssetService      = game:GetService("AssetService")
 
local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
 
local IsMobileDevice = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
 
local SilentUI = {}
local Private = {}
SilentUI._FloatingWidgets = {}
SilentUI._StateLists = {}
SilentUI.UserSettings = {
    ShowFloatingWidgets = true,
    ShowStatePanels = true,
    ShowStateValues = true,
    LockStatePanels = false,
    StatePanelsPassThrough = false,
}
SilentUI.__index = SilentUI
SilentUI.Version = "2.13.2"
SilentUI.Flags = {}
SilentUI.ConfigFlags = {}
SilentUI.ConfigValidators = {}
SilentUI.FlagMigrations = {}
SilentUI._NextControlRegistration = 0
SilentUI._Windows = {}

--[[
    SILENTUI
    Change these values before distributing the library.
    Background.Image accepts an asset ID, rbxassetid:// reference or HTTPS image URL.
    The fixed Discord dock link belongs to SilentUI; users can enter their own link in the Discord tab.
]]

local SILENTUI_DISCORD_INVITE = "https://discord.gg/k3SVsV7sXs"
SilentUI.DefaultDiscordInvite = SILENTUI_DISCORD_INVITE
SilentUI.DiscordDockIcon = "rbxassetid://18505728250" -- Roblox decal listing: circular Discord mark
SilentUI.Defaults = {
    Title = "SilentUI",
    Subtitle = "Community UI Library",
    Background = {
        Image = "",
        ImageTransparency = 0.22,
        LauncherTransparency = 0.18,
        UseImageAccent = false,
    },
    Discord = {},
}
 
function Private.GetGlobalTable()
	local ok, g = pcall(function()
		if getgenv then return getgenv() end
		return _G
	end)
	return (ok and g) or _G
end
 
do
	local globalTable = Private.GetGlobalTable()
	local initialRootOptions = globalTable.__SilentUI_Options
	SilentUI.RootMode = type(initialRootOptions) == "table" and initialRootOptions.RootMode or "Auto"
	local previousUnload = globalTable.__SilentUI_Unload
	globalTable.__SilentUI_Unload = nil
	if type(previousUnload) == "function" then
		pcall(previousUnload)
	end
end
 
local Janitor = {}
Janitor.__index = Janitor
 
function Janitor.new()
	return setmetatable({ _items = {}, _dead = false }, Janitor)
end
 
function Janitor:Add(item)
	if self._dead then
		if typeof(item) == "RBXScriptConnection" then
			item:Disconnect()
		elseif typeof(item) == "Instance" then
			item:Destroy()
		end
		return item
	end
	table.insert(self._items, item)
	return item
end
 
function Janitor:Destroy()
	if self._dead then return end
	self._dead = true
	for i = #self._items, 1, -1 do
		local item = self._items[i]
		self._items[i] = nil
		local t = typeof(item)
		if t == "RBXScriptConnection" then
			pcall(function() item:Disconnect() end)
		elseif t == "Instance" then
			pcall(function() item:Destroy() end)
		elseif t == "function" then
			pcall(item)
		elseif t == "table" and type(item.Destroy) == "function" then
			pcall(function() item:Destroy() end)
		end
	end
end
 
local LibJanitor = Janitor.new()

-- Public resource scopes can own connections, Instances, Drawing objects, tasks and cleanups.
local ResourceScope = {}
ResourceScope.__index = ResourceScope
local ActiveScopes = {}

function Private.DisposeScopeItem(item, cleanup)
	if type(cleanup) == "function" then
		pcall(cleanup, item)
		return
	end
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		pcall(function() item:Disconnect() end)
	elseif kind == "Instance" then
		pcall(function() item:Destroy() end)
	elseif kind == "thread" then
		pcall(task.cancel, item)
	elseif type(item) == "function" then
		pcall(item)
	elseif type(item) == "table" then
		local dispose = item.Destroy or item.Disconnect or item.Remove or item.Cancel
		if type(dispose) == "function" then pcall(dispose, item) end
	end
end

function ResourceScope:Add(item, cleanup)
	if self._destroyed then
		Private.DisposeScopeItem(item, cleanup)
	else
		table.insert(self._items, { Item = item, Cleanup = cleanup })
	end
	return item
end

function ResourceScope:Remove(item, dispose)
	for i = #self._items, 1, -1 do
		local entry = self._items[i]
		if entry.Item == item then
			table.remove(self._items, i)
			if dispose then Private.DisposeScopeItem(entry.Item, entry.Cleanup) end
			return true
		end
	end
	return false
end

function ResourceScope:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	ActiveScopes[self] = nil
	for i = #self._items, 1, -1 do
		local entry = self._items[i]
		self._items[i] = nil
		Private.DisposeScopeItem(entry.Item, entry.Cleanup)
	end
end

function SilentUI:CreateScope()
	local scope = setmetatable({ _items = {}, _destroyed = false }, ResourceScope)
	ActiveScopes[scope] = true
	return scope
end

function Private.DestroyActiveScopes()
	local scopes = {}
	for scope in pairs(ActiveScopes) do table.insert(scopes, scope) end
	for _, scope in ipairs(scopes) do scope:Destroy() end
end

local LocalizedEntries = setmetatable({}, { __mode = "k" })
local LocaleListeners = {}
local KnownLocaleKeys = {}

SilentUI.Language = "en"
SilentUI.Locales = {
	en = {},
	es = {
		["Search"] = "Buscar",
		["Find"] = "Buscar",
		["Search controls..."] = "Buscar controles...",
		["Type to search controls"] = "Escribe para buscar controles",
		["No controls found"] = "No se encontraron controles",
		["Search options..."] = "Buscar opciones...",
		["No options found"] = "No hay opciones",
		["Notice"] = "Aviso",
		["Confirm"] = "Confirmar",
		["Cancel"] = "Cancelar",
		["OK"] = "Aceptar",
		["Enter a value..."] = "Escribe un valor...",
		["Save"] = "Guardar",
		["Load"] = "Cargar",
		["Delete"] = "Eliminar",
		["Configs"] = "Configuraciones",
		["Settings"] = "Ajustes",
		["Rename"] = "Renombrar",
		["Create"] = "Crear",
		["Close"] = "Cerrar",
		["Name"] = "Nombre",
		["Description"] = "Descripción",
		["Search local configs..."] = "Buscar configuraciones locales...",
		["No local configs saved yet."] = "Todavía no hay configuraciones locales.",
		["Save Current Settings Locally"] = "Guardar ajustes actuales localmente",
	},
}

function Private.IsValidTranslation(value)
	if type(value) == "string" then return true end
	if type(value) ~= "table" or type(value.other) ~= "string" then return false end
	for key, translation in pairs(value) do
		if key ~= "zero" and key ~= "one" and key ~= "other" then return false end
		if type(translation) ~= "string" then return false end
	end
	return true
end

function SilentUI:Translate(text, variables)
	if type(text) ~= "string" then return text end
	KnownLocaleKeys[text] = true
	local activeLocale = self.Locales[self.Language]
	local translated = activeLocale and activeLocale[text]
	if translated == nil then translated = self.Locales.en[text] or text end
	if type(variables) == "number" then variables = { count = variables } end
	if type(translated) == "table" then
		local count = type(variables) == "table" and variables.count or nil
		local category = count == 0 and "zero" or count == 1 and "one" or "other"
		translated = translated[category] or translated.other
	end
	if type(translated) ~= "string" then translated = text end
	if type(variables) == "table" then
		translated = translated:gsub("{([%w_]+)}", function(key)
			local value = variables[key]
			return value == nil and "{" .. key .. "}" or tostring(value)
		end)
	end
	return translated
end

function SilentUI:_TrackLocalizedText(instance, property, key)
	if type(key) ~= "string" or key == "" then return end
	if instance:IsA("GuiBase2d") then instance.AutoLocalize = false end
	local properties = LocalizedEntries[instance]
	if not properties then
		properties = {}
		LocalizedEntries[instance] = properties
	end
	local translated = self:Translate(key)
	properties[property] = { Key = key, Current = translated, Explicit = true }
	if translated ~= key then pcall(function() instance[property] = translated end) end
end

function SilentUI:Localize(instance, key, property)
	assert(instance and type(key) == "string", "Localize expects an instance and a string key")
	property = property or "Text"
	self:_TrackLocalizedText(instance, property, key)
	local ok, value = pcall(function() return instance[property] end)
	return ok and value or nil
end

function SilentUI:BindLocale(instance, properties)
	assert(typeof(instance) == "Instance" and type(properties) == "table",
		"BindLocale expects an Instance and a property-to-key table")
	for property, key in pairs(properties) do
		self:Localize(instance, key, property)
	end
	return instance
end

function SilentUI:LocalizeControl(control, keys)
	assert(type(control) == "table" and typeof(control.Instance) == "Instance",
		"LocalizeControl expects a control with an Instance")
	keys = keys or {}
	local card = control.Instance
	local title = card:FindFirstChild("Title", true)
	local description = card:FindFirstChild("Description", true)
	if keys.TextKey and title then self:Localize(title, keys.TextKey) end
	if keys.DescriptionKey and description then self:Localize(description, keys.DescriptionKey) end
	return control
end

function SilentUI:GetLanguage()
	return self.Language
end

local function RefreshLocalizedEntries()
	for instance, properties in pairs(LocalizedEntries) do
		local exists = pcall(function() return instance.Parent end)
		if not exists then
			LocalizedEntries[instance] = nil
		else
			if instance:IsA("GuiBase2d") then instance.AutoLocalize = false end
			for property, entry in pairs(properties) do
				local ok, current = pcall(function() return instance[property] end)
				if ok then
					if current ~= entry.Current and not entry.Explicit then entry.Key = current end
					local translated = SilentUI:Translate(entry.Key)
					pcall(function() instance[property] = translated end)
					entry.Current = translated
				end
			end
		end
	end
end

function SilentUI:SetLanguage(language)
	assert(type(language) == "string" and language:match("^[%a][%w_-]*$"), "language must be a locale code")
	language = string.lower(language)
	if not self.Locales[language] then return false, "Locale '" .. language .. "' is not registered" end
	self.Language = language
	if self._Root then self._Root:SetAttribute("SilentLanguage", language) end
	RefreshLocalizedEntries()
	for _, listener in ipairs(LocaleListeners) do
		if listener.Connected then
			local ok, err = pcall(listener.Callback, language)
			if not ok then warn("[SilentUI] language listener error: " .. tostring(err)) end
		end
	end
	RefreshLocalizedEntries()
	task.defer(function()
		if SilentUI.Language == language then RefreshLocalizedEntries() end
	end)
	return true
end

function SilentUI:RegisterLocale(language, translations)
	assert(type(language) == "string" and language:match("^[%a][%w_-]*$"), "language must be a locale code")
	assert(type(translations) == "table", "translations must be a table")
	language = string.lower(language)
	local locale = self.Locales[language] or {}
	for key, value in pairs(translations) do
		assert(type(key) == "string" and Private.IsValidTranslation(value), "translation values must be strings or plural tables with a string 'other' value")
		locale[key] = value
	end
	self.Locales[language] = locale
	if self.Language == language then return self:SetLanguage(language) end
	return true
end

function SilentUI:ValidateLocale(language, referenceLanguage)
	assert(type(language) == "string", "language must be a locale code")
	language = string.lower(language)
	referenceLanguage = string.lower(referenceLanguage or "en")
	local locale = self.Locales[language]
	local reference = self.Locales[referenceLanguage]
	if not locale then return false, { Error = "Locale '" .. language .. "' is not registered", Missing = {}, Invalid = {} } end
	if not reference then return false, { Error = "Reference locale '" .. referenceLanguage .. "' is not registered", Missing = {}, Invalid = {} } end
	local keys = {}
	for key in pairs(reference) do keys[key] = true end
	for key in pairs(KnownLocaleKeys) do keys[key] = true end
	local report = { Language = language, Reference = referenceLanguage, Missing = {}, Invalid = {} }
	for key in pairs(keys) do
		if locale[key] == nil then
			-- English is the identity locale, so untranslated source strings are valid.
			if language ~= "en" then table.insert(report.Missing, key) end
		elseif not Private.IsValidTranslation(locale[key]) then
			table.insert(report.Invalid, key)
		end
	end
	table.sort(report.Missing)
	table.sort(report.Invalid)
	return #report.Missing == 0 and #report.Invalid == 0, report
end

function SilentUI:RegisterLocaleCallback(callback)
	assert(type(callback) == "function", "locale callback must be a function")
	local listener = { Callback = callback, Connected = true }
	table.insert(LocaleListeners, listener)
	function listener:Disconnect()
		if not self.Connected then return end
		self.Connected = false
		for index = #LocaleListeners, 1, -1 do
			if LocaleListeners[index] == self then table.remove(LocaleListeners, index) end
		end
	end
	return listener
end

SilentUI.translate = SilentUI.Translate
SilentUI.localize = SilentUI.Localize
SilentUI.set_language = SilentUI.SetLanguage
SilentUI.register_locale = SilentUI.RegisterLocale
SilentUI.validate_locale = SilentUI.ValidateLocale
SilentUI.register_locale_callback = SilentUI.RegisterLocaleCallback

function Private.TrackLocalizedInstance(instance)
	if instance:IsA("GuiBase2d") then instance.AutoLocalize = false end
	if not instance:IsA("TextLabel") and not instance:IsA("TextButton") and not instance:IsA("TextBox") then return end
	local ok, text = pcall(function() return instance.Text end)
	local existing = LocalizedEntries[instance] and LocalizedEntries[instance].Text
	if ok and text ~= "" and not (existing and existing.Explicit) then
		SilentUI:_TrackLocalizedText(instance, "Text", text)
		local entry = LocalizedEntries[instance] and LocalizedEntries[instance].Text
		if entry then entry.Explicit = false end
	end
	if instance:IsA("TextBox") then
		local placeholderOk, placeholder = pcall(function() return instance.PlaceholderText end)
		local existing = LocalizedEntries[instance] and LocalizedEntries[instance].PlaceholderText
		if placeholderOk and placeholder ~= "" and not (existing and existing.Explicit) then
			SilentUI:_TrackLocalizedText(instance, "PlaceholderText", placeholder)
			local entry = LocalizedEntries[instance] and LocalizedEntries[instance].PlaceholderText
			if entry then entry.Explicit = false end
		end
	end
end

function Private.TrackLocalizationRoot(root)
	root.AutoLocalize = false
	for _, instance in ipairs(root:GetDescendants()) do Private.TrackLocalizedInstance(instance) end
	LibJanitor:Add(root.DescendantAdded:Connect(Private.TrackLocalizedInstance))
end
 
local function MakeSignal()
	local listeners = {}
	return {
		Fire = function(...)
			for _, fn in ipairs(table.clone(listeners)) do
				task.spawn(fn, ...)
			end
		end,
		Connect = function(fn)
			table.insert(listeners, fn)
			return {
				Disconnect = function()
					local i = table.find(listeners, fn)
					if i then table.remove(listeners, i) end
				end,
			}
		end,
		Clear = function()
			table.clear(listeners)
		end,
	}
end

local ConfigLoadedSignal = MakeSignal()

local function ChangeInfo(action)
	return {
		Source = SilentUI._ChangeSource or "user",
		Action = action or "change",
	}
end
 
local function SafeClamp(value, lo, hi)
	if hi < lo then return lo end
	return math.clamp(value, lo, hi)
end
 
local function SafeAlpha(value, min, max)
	local range = max - min
	if range == 0 then return 0 end
	return math.clamp((value - min) / range, 0, 1)
end
 
local function SnapToIncrement(raw, min, max, increment)
	if increment <= 0 then increment = 1 end
	local snapped = math.floor((raw - min) / increment + 0.5) * increment + min
	snapped = math.clamp(snapped, min, max)
	local decimals = 0
	local probe = increment
	while decimals < 6 and math.abs(probe - math.floor(probe + 0.5)) > 1e-9 do
		probe = probe * 10
		decimals = decimals + 1
	end
	local factor = 10 ^ decimals
	return math.floor(snapped * factor + (snapped >= 0 and 0.5 or -0.5)) / factor
end
 
local function FormatNumber(v)
	if math.abs(v - math.floor(v + 0.5)) < 1e-9 then
		return tostring(math.floor(v + 0.5))
	end
	return string.format("%.4g", v)
end
 
Private.ACRYLIC_DOF_NAME = "SilentUI_AcrylicDOF"
Private.ACRYLIC_DISTANCE = 0.001
Private.ACRYLIC_TRANSPARENCY = 0.98
Private.AcrylicDOF = nil
local AcrylicControllers = {}
Private.CameraConnections = {}
Private.AcrylicShuttingDown = false
 
SilentUI.Config = { Blur = true, MaxNotifications = 5 }
 
function Private.DisconnectCameraSignals()
	for i = #Private.CameraConnections, 1, -1 do
		Private.CameraConnections[i]:Disconnect()
		Private.CameraConnections[i] = nil
	end
end
 
function Private.EnsureAcrylicDOF()
	if Private.AcrylicDOF and Private.AcrylicDOF.Parent then return Private.AcrylicDOF end
	local stale = Lighting:FindFirstChild(Private.ACRYLIC_DOF_NAME)
	if stale then stale:Destroy() end
	local previousDof = Lighting:FindFirstChild("SilentUI_AcrylicDOF")
	if previousDof then previousDof:Destroy() end
 
	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = Private.ACRYLIC_DOF_NAME
	dof.FarIntensity = 0
	dof.FocusDistance = 0.05
	dof.InFocusRadius = 0.1
	dof.NearIntensity = 1
	dof.Enabled = false
	dof.Parent = Lighting
	Private.AcrylicDOF = dof
	LibJanitor:Add(dof)
	return dof
end
 
function Private.RefreshAcrylicEffect()
	if Private.AcrylicShuttingDown then return end
	local dof = Private.EnsureAcrylicDOF()
	dof.Enabled = SilentUI.Config.Blur ~= false and #AcrylicControllers > 0
end
 
local function UpdateAllAcrylic()
	for index = #AcrylicControllers, 1, -1 do
		local controller = AcrylicControllers[index]
		if controller.Destroyed then
			table.remove(AcrylicControllers, index)
		else
			controller:Update()
		end
	end
end
 
function Private.BindAcrylicCamera(camera)
	Private.DisconnectCameraSignals()
	if not camera then return end
 
	local function connect(property)
		table.insert(Private.CameraConnections,
			camera:GetPropertyChangedSignal(property):Connect(UpdateAllAcrylic))
	end
	connect("CFrame")
	connect("ViewportSize")
	connect("FieldOfView")
	UpdateAllAcrylic()
end
 
function Private.CreateWindowAcrylic(guiObject)
	local folder = Instance.new("Folder")
	folder.Name = "SilentUI_AcrylicWindow"
 
	local part = Instance.new("Part")
	part.Name = "Glass"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Material = Enum.Material.Glass
	part.Color = Color3.new(0, 0, 0)
	part.Reflectance = 0
	part.Size = Vector3.new(1, 1, 0.001)
	part.Transparency = 1
	part.Parent = folder
 
	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "AcrylicMesh"
	mesh.MeshType = Enum.MeshType.Brick
	mesh.Offset = Vector3.new(0, 0, -0.000001)
	mesh.Scale = Vector3.new(1, 1, 0.001)
	mesh.Parent = part
 
	local controller = {
		Gui = guiObject,
		Folder = folder,
		Part = part,
		Mesh = mesh,
		Connections = {},
		Destroyed = false,
	}
 
	function controller:Update()
		if self.Destroyed then return end
		if not self.Part.Parent or not self.Mesh.Parent then
			self:Destroy()
			return
		end
		local camera = workspace.CurrentCamera
		local gui = self.Gui
		if not camera or not gui or not gui.Parent then
			self.Part.Transparency = 1
			return
		end
 
		if self.Folder.Parent ~= camera then
			local parented = pcall(function()
				self.Folder.Parent = camera
			end)
			if not parented then
				self:Destroy()
				return
			end
		end
 
		local size = gui.AbsoluteSize
		local visible = SilentUI.Config.Blur ~= false
			and gui.Visible and size.X > 2 and size.Y > 2
		self.Part.Transparency = visible and Private.ACRYLIC_TRANSPARENCY or 1
		if not visible then return end
 
		local edgeInset = math.clamp(camera.ViewportSize.Y * 0.012, 8, 18)
		local position = gui.AbsolutePosition + Vector2.new(edgeInset, edgeInset)
		local panelSize = Vector2.new(
			math.max(1, size.X - edgeInset * 2),
			math.max(1, size.Y - edgeInset * 2)
		)
 
		local function ScreenToWorld(point)
			local ray = camera:ScreenPointToRay(point.X, point.Y)
			return ray.Origin + ray.Direction * Private.ACRYLIC_DISTANCE
		end
 
		local topLeft3D = ScreenToWorld(position)
		local topRight3D = ScreenToWorld(position + Vector2.new(panelSize.X, 0))
		local bottomRight3D = ScreenToWorld(position + panelSize)
		local width = (topRight3D - topLeft3D).Magnitude
		local height = (bottomRight3D - topRight3D).Magnitude
		local renderCFrame = camera:GetRenderCFrame()
 
		self.Part.CFrame = CFrame.fromMatrix(
			(topLeft3D + bottomRight3D) / 2,
			renderCFrame.XVector,
			renderCFrame.YVector,
			renderCFrame.ZVector
		)
		self.Mesh.Scale = Vector3.new(width, height, 0.001)
	end
 
	function controller:Destroy()
		if self.Destroyed then return end
		self.Destroyed = true
		for _, connection in ipairs(self.Connections) do
			connection:Disconnect()
		end
		table.clear(self.Connections)
		local index = table.find(AcrylicControllers, self)
		if index then table.remove(AcrylicControllers, index) end
		if self.Folder then self.Folder:Destroy() end
		Private.RefreshAcrylicEffect()
	end
 
	table.insert(controller.Connections, folder.Destroying:Connect(function()
		controller:Destroy()
	end))

	for _, property in ipairs({ "AbsolutePosition", "AbsoluteSize", "Visible" }) do
		table.insert(controller.Connections,
			guiObject:GetPropertyChangedSignal(property):Connect(function()
				controller:Update()
			end))
	end
	table.insert(controller.Connections, guiObject.AncestryChanged:Connect(function()
		if not guiObject.Parent then controller:Destroy() end
	end))
 
	table.insert(AcrylicControllers, controller)
	Private.RefreshAcrylicEffect()
	controller:Update()
	return controller
end
 
Private.BindAcrylicCamera(workspace.CurrentCamera)
LibJanitor:Add(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	Private.BindAcrylicCamera(workspace.CurrentCamera)
end))
LibJanitor:Add(function()
	Private.DisconnectCameraSignals()
end)
 
function SilentUI:SetBlurEnabled(enabled)
	SilentUI.Config.Blur = enabled and true or false
	Private.RefreshAcrylicEffect()
	UpdateAllAcrylic()
end
 
function Private.DestroyAllAcrylicControllers()
	for index = #AcrylicControllers, 1, -1 do
		AcrylicControllers[index]:Destroy()
	end
	table.clear(AcrylicControllers)
end
 
local STORAGE_FOLDER = "SilentUI"
local ASSETS_FOLDER = STORAGE_FOLDER .. "/Assets"
SilentUI.directory = STORAGE_FOLDER
SilentUI.settings_folder = "Randoms"
SilentUI.settings_directory = STORAGE_FOLDER .. "/Settings/Randoms"
 
local function hasFn(name)
	local ok, fn = pcall(function()
		if getgenv then
			local v = getgenv()[name]
			if type(v) == "function" then return v end
		end
		if getfenv then
			local v = getfenv(1)[name]
			if type(v) == "function" then return v end
		end
		return _G[name]
	end)
	if ok and type(fn) == "function" then return fn end
	return nil
end
 
Private.fn_isfolder    = hasFn("isfolder")
Private.fn_makefolder  = hasFn("makefolder")
local fn_isfile      = hasFn("isfile")
local fn_writefile   = hasFn("writefile")
local fn_readfile    = hasFn("readfile")
local fn_delfile     = hasFn("delfile")
Private.fn_listfiles   = hasFn("listfiles")
Private.fn_customasset = hasFn("getcustomasset") or hasFn("getsynasset")
 
function Private.EnsureAssetsFolder()
	if not (Private.fn_isfolder and Private.fn_makefolder) then return false end
	local function ensure(path)
		local existsOk, exists = pcall(Private.fn_isfolder, path)
		if existsOk and exists then return true end
		pcall(Private.fn_makefolder, path)
		local verifyOk, nowExists = pcall(Private.fn_isfolder, path)
		return verifyOk and nowExists == true
	end
	return ensure(STORAGE_FOLDER) and ensure(ASSETS_FOLDER)
end
 
function Private.PrivateTabFlagPath(name)
	local safe = tostring(name or ""):gsub("[^%w_%-]", "_")
	return STORAGE_FOLDER .. "/PrivateTab_" .. safe .. ".remember"
end

function Private.IsPrivateTabRemembered(name)
	if not fn_isfile then return false end
	local ok, exists = pcall(fn_isfile, Private.PrivateTabFlagPath(name))
	return ok and exists == true
end
 
function Private.SetPrivateTabRemembered(name, remember)
	local path = Private.PrivateTabFlagPath(name)
	if remember then
		if not fn_writefile then return end
		Private.EnsureAssetsFolder()
		pcall(fn_writefile, path, "1")
	else
		if not (fn_isfile and fn_delfile) then return end
		local ok, exists = pcall(fn_isfile, path)
		if ok and exists then pcall(fn_delfile, path) end
	end
end
 
function Private.GetExecutorName()
	local ok, name, version = pcall(function()
		if identifyexecutor then return identifyexecutor() end
		if getexecutorname then return getexecutorname() end
		if syn and syn.get_executor_name then return syn.get_executor_name() end
		return nil
	end)
	if ok and name and name ~= "" then
		return version and version ~= "" and (tostring(name) .. " " .. tostring(version)) or tostring(name)
	end
	return "Unknown"
end
 
function Private.FormatClock(minutesAfterMidnight)
	minutesAfterMidnight = minutesAfterMidnight or 0
	local h = math.floor(minutesAfterMidnight / 60) % 24
	local m = math.floor(minutesAfterMidnight % 60)
	local suffix = h >= 12 and "PM" or "AM"
	local h12 = h % 12
	if h12 == 0 then h12 = 12 end
	return string.format("%02d:%02d %s", h12, m, suffix)
end
 
function Private.LooksLikeFontFile(data)
	if type(data) ~= "string" or #data < 4096 then return false end
	local sig = data:sub(1, 4)
	return sig == "\0\1\0\0"
		or sig == "OTTO"
		or sig == "true"
		or sig == "ttcf"
		or sig == "wOFF"
		or sig == "wOF2"
end
 
function Private.DownloadFontFile(path, url)
	if not (fn_isfile and fn_writefile) then return false end
 
	local cached = nil
	if fn_isfile(path) and fn_readfile then
		local ok, data = pcall(fn_readfile, path)
		if ok and Private.LooksLikeFontFile(data) then
			return true
		end
		cached = ok and data or nil
	end
 
	if cached ~= nil and fn_delfile then
		pcall(fn_delfile, path)
	end
 
	local ok, body = pcall(function() return game:HttpGet(url) end)
	if not ok or not Private.LooksLikeFontFile(body) then
		return false
	end
 
	local wrote = pcall(fn_writefile, path, body)
	return wrote
end
 
function Private.IsImagePayload(data)
	if type(data) ~= "string" or #data < 256 then return false end
	return data:sub(1, 8) == "\137PNG\r\n\26\n"
		or data:sub(1, 3) == "\255\216\255"
		or data:sub(1, 6) == "GIF87a"
		or data:sub(1, 6) == "GIF89a"
		or (data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "WEBP")
end

function Private.DownloadBackgroundAsset(url, cacheName)
	if type(url) ~= "string" or not url:match("^https?://") then
		return nil, "invalid image URL"
	end
	if not (Private.fn_customasset and fn_writefile and Private.EnsureAssetsFolder()) then
		return nil, "this executor needs getcustomasset and file APIs for remote backgrounds"
	end

	local safeName = tostring(cacheName or "custom-background"):gsub("[^%w_%-]", "_")
	local filePath = ASSETS_FOLDER .. "/background-" .. safeName .. ".img"

	if fn_isfile and fn_isfile(filePath) then
		if not fn_readfile then
			local okAsset, cachedAsset = pcall(Private.fn_customasset, filePath)
			if okAsset and type(cachedAsset) == "string" and cachedAsset ~= "" then
				return cachedAsset
			end
		else
			local okRead, cachedData = pcall(fn_readfile, filePath)
			if okRead and Private.IsImagePayload(cachedData) then
				local okAsset, cachedAsset = pcall(Private.fn_customasset, filePath)
				if okAsset and type(cachedAsset) == "string" and cachedAsset ~= "" then
					return cachedAsset
				end
			elseif fn_delfile then
				pcall(fn_delfile, filePath)
			end
		end
	end

	local body
	local globals = Private.GetGlobalTable()
	local synTable = type(globals.syn) == "table" and globals.syn or nil
	local httpTable = type(globals.http) == "table" and globals.http or nil
	local httpRequest = (synTable and synTable.request)
		or (httpTable and httpTable.request)
		or hasFn("http_request")
		or hasFn("request")

	if type(httpRequest) == "function" then
		local okRequest, response = pcall(httpRequest, {
			Url = url,
			Method = "GET",
			Headers = { ["User-Agent"] = "SilentUI/2.13.2" },
		})
		if okRequest and type(response) == "table" then
			local status = tonumber(response.StatusCode or response.Status)
			if (not status or (status >= 200 and status < 300))
				and Private.IsImagePayload(response.Body) then
				body = response.Body
			end
		end
	end

	if not body then
		local okHttp, responseBody = pcall(function()
			return game:HttpGet(url)
		end)
		if okHttp and Private.IsImagePayload(responseBody) then
			body = responseBody
		end
	end

	if not body then return nil, "image download failed or returned an unsupported image format" end

	local okWrite, writeResult = pcall(fn_writefile, filePath, body)
	if not okWrite or writeResult == false then
		return nil, "could not cache the image file"
	end

	local okAsset, asset = pcall(Private.fn_customasset, filePath)
	if okAsset and type(asset) == "string" and asset ~= "" then
		return asset
	end
	return nil, "getcustomasset could not load the cached image"
end

function Private.LoadCustomFigtree()
	if not (Private.fn_customasset and fn_writefile) then return nil end
 
	local okFolder = Private.EnsureAssetsFolder()
	if not okFolder then return nil end
 
	local base = "https://raw.githubusercontent.com/Skinny-yz/NullUI-Assets/main/fonts/"
	local semiPath = ASSETS_FOLDER .. "/Figtree-SemiBold.ttf"
	local regPath  = ASSETS_FOLDER .. "/Figtree-Medium.ttf"
 
	if not Private.DownloadFontFile(semiPath, base .. "Figtree-SemiBold.ttf") then
		return nil
	end
	local hasRegular = Private.DownloadFontFile(regPath, base .. "Figtree-Medium.ttf")
	if not hasRegular then regPath = semiPath end
 
	local result = nil
	pcall(function()
		local family = {
			name = "Figtree",
			faces = {
				{ name = "Regular",  weight = 400, style = "normal", assetId = Private.fn_customasset(regPath) },
				{ name = "SemiBold", weight = 600, style = "normal", assetId = Private.fn_customasset(semiPath) },
			},
		}
		local familyPath = ASSETS_FOLDER .. "/Figtree.font"
		fn_writefile(familyPath, HttpService:JSONEncode(family))
 
		local asset = Private.fn_customasset(familyPath)
		result = {
			Regular  = Font.new(asset, Enum.FontWeight.Regular,  Enum.FontStyle.Normal),
			SemiBold = Font.new(asset, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
		}
	end)
 
	return result
end
 
function Private.LoadFonts()
	local custom = Private.LoadCustomFigtree()
	if custom and custom.Regular and custom.SemiBold then
		return custom
	end
 
	local ok, native = pcall(function()
		return {
			Regular  = Font.new("rbxasset://fonts/families/Figtree.json", Enum.FontWeight.Regular,  Enum.FontStyle.Normal),
			SemiBold = Font.new("rbxasset://fonts/families/Figtree.json", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
		}
	end)
	if ok and native then return native end
 
	return {
		Regular  = Font.fromEnum(Enum.Font.Gotham),
		SemiBold = Font.fromEnum(Enum.Font.GothamSemibold),
	}
end
 
local Fonts = Private.LoadFonts()
 
SilentUI.Theme = {
	Background     = Color3.fromRGB(16, 16, 16),
	Surface        = Color3.fromRGB(24, 24, 24),
	SurfaceHover   = Color3.fromRGB(33, 33, 35),
	Border         = Color3.fromRGB(240, 240, 240),
	Text           = Color3.fromRGB(240, 240, 240),
	TextDim        = Color3.fromRGB(150, 150, 155),
	Accent         = Color3.fromRGB(255, 255, 255),
	Danger         = Color3.fromRGB(205, 205, 210),
 
	Font           = Fonts.SemiBold,
	FontRegular    = Fonts.Regular,
 
	MeasureFont    = Enum.Font.GothamSemibold,
 
	CornerRadius   = 16,
	CornerRadiusSm = 8,
	Margin         = 14,
	AnimFast       = 0.15,
	AnimSlow       = 0.32,
}
 
local Z = {
	Glass    = 0,
	Window   = 1,
	Content  = 2,
	Backdrop = 390,
	Popup    = 400,
	PopupTop = 410,
	Toast    = 600,
	Modal    = 800,
	ModalTop = 810,
}
 
local function Tween(instance, props, duration, style, direction)
	local t = TweenService:Create(
		instance,
		TweenInfo.new(
			math.max(duration or 0.25, 0),
			style or Enum.EasingStyle.Quint,
			direction or Enum.EasingDirection.Out
		),
		props
	)
	t:Play()
	return t
end
 
local function Corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or SilentUI.Theme.CornerRadius)
	c.Parent = parent
	return c
end
 
local function Stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or SilentUI.Theme.Border
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0.9
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end
 
function Private.GlassLayer(parent, radius, transparency)
	local glass = Instance.new("Frame")
	glass.Name = "Glass"
	glass.Size = UDim2.fromScale(1, 1)
	glass.BackgroundColor3 = SilentUI.Theme.Surface
	glass.BackgroundTransparency = transparency or 0.985
	glass.BorderSizePixel = 0
	glass.ZIndex = Z.Glass
	glass.Parent = parent
	Corner(glass, radius)
	return glass
end

function Private.SameColor(a, b)
	return typeof(a) == "Color3" and typeof(b) == "Color3"
		and a.R == b.R and a.G == b.G and a.B == b.B
end

function Private.IsNeutralColor(value)
	return typeof(value) == "Color3"
		and value.R > 0.05 and value.R <= 1
		and math.abs(value.R - value.G) < 0.002
		and math.abs(value.G - value.B) < 0.002
end

function Private.RecolorThemeValue(instance, property, value, oldTheme)
	if typeof(value) ~= "Color3" then return nil end
	if property == "StrokeColor" then
		if Private.SameColor(value, oldTheme.Accent) then return SilentUI.Theme.Accent end
		if Private.SameColor(value, oldTheme.Border) or Private.IsNeutralColor(value) then
			return SilentUI.Theme.Border
		end
	elseif property == "BackgroundColor3" then
		if Private.SameColor(value, oldTheme.Background) then return SilentUI.Theme.Background end
		if Private.SameColor(value, oldTheme.Surface) then return SilentUI.Theme.Surface end
		if Private.SameColor(value, oldTheme.SurfaceHover) then return SilentUI.Theme.SurfaceHover end
		if Private.SameColor(value, oldTheme.Accent) then return SilentUI.Theme.Accent end
		if Private.SameColor(value, oldTheme.Text) then return SilentUI.Theme.Text end
		if Private.SameColor(value, oldTheme.TextDim) then return SilentUI.Theme.Surface end
		if Private.IsNeutralColor(value) then
			return value.R < 0.12 and SilentUI.Theme.Background or SilentUI.Theme.Surface
		end
	elseif property == "TextColor3" or property == "ImageColor3" then
		if Private.SameColor(value, oldTheme.Background) then return SilentUI.Theme.Background end
		if Private.SameColor(value, oldTheme.Surface) then return SilentUI.Theme.Surface end
		if Private.SameColor(value, oldTheme.SurfaceHover) then return SilentUI.Theme.TextDim end
		if Private.SameColor(value, oldTheme.Text) then return SilentUI.Theme.Text end
		if Private.SameColor(value, oldTheme.TextDim) then return SilentUI.Theme.TextDim end
		if Private.SameColor(value, oldTheme.Danger) then return SilentUI.Theme.Danger end
		if Private.SameColor(value, oldTheme.Accent) then return SilentUI.Theme.Accent end
		if Private.IsNeutralColor(value) then
			return value.R >= 0.92 and SilentUI.Theme.Text or SilentUI.Theme.TextDim
		end
	elseif property == "GradientColor" then
		if Private.SameColor(value, oldTheme.Accent) then return SilentUI.Theme.Accent end
		if Private.SameColor(value, oldTheme.SurfaceHover) then return SilentUI.Theme.SurfaceHover end
		if Private.SameColor(value, oldTheme.Text) then return SilentUI.Theme.Text end
		if Private.SameColor(value, oldTheme.TextDim) then return SilentUI.Theme.TextDim end
		if Private.IsNeutralColor(value) then
			return value.R >= 0.92 and SilentUI.Theme.Text or SilentUI.Theme.TextDim
		end
	end
	return nil
end

function SilentUI:SetTheme(patch)
	if type(patch) ~= "table" then return false, "theme must be a table" end
	local oldTheme = table.clone(self.Theme)
	for key, value in pairs(patch) do
		local current = self.Theme[key]
		if current == nil then return false, "unknown theme key: " .. tostring(key) end
		if typeof(value) ~= typeof(current) then
			return false, "theme key '" .. tostring(key) .. "' expects " .. typeof(current)
		end
		if type(value) == "number" and (value ~= value or value == math.huge or value == -math.huge or value < 0) then
			return false, "theme key '" .. tostring(key) .. "' must be a finite non-negative number"
		end
	end
	for key, value in pairs(patch) do self.Theme[key] = value end

	local root = self._Root
	if not root then return true end
	local instances = { root }
	for _, instance in ipairs(root:GetDescendants()) do table.insert(instances, instance) end
	for _, instance in ipairs(instances) do
		if instance:GetAttribute("SilentThemeExempt") then continue end
		local colorExempt = instance:GetAttribute("SilentThemeColorExempt") == true
		local colorProperties = {}
		if not colorExempt then table.insert(colorProperties, "BackgroundColor3") end
		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			if not colorExempt then table.insert(colorProperties, "TextColor3") end
			local ok, value = pcall(function() return instance.FontFace end)
			if ok then
				if value == oldTheme.Font then instance.FontFace = self.Theme.Font
				elseif value == oldTheme.FontRegular then instance.FontFace = self.Theme.FontRegular end
			end
		end
		if not colorExempt and not instance:GetAttribute("SilentThemeImageColorExempt") and (instance:IsA("ImageLabel") or instance:IsA("ImageButton")) then table.insert(colorProperties, "ImageColor3") end
		for _, property in ipairs(colorProperties) do
			local ok, value = pcall(function() return instance[property] end)
			if ok then
				local color = Private.RecolorThemeValue(instance, property, value, oldTheme)
				if color then pcall(function() instance[property] = color end) end
			end
		end
		if not colorExempt and instance:IsA("UIStroke") then
			local color = Private.RecolorThemeValue(instance, "StrokeColor", instance.Color, oldTheme)
			if color then instance.Color = color end
		elseif not colorExempt and instance:IsA("UIGradient") then
			local keypoints = {}
			for _, keypoint in ipairs(instance.Color.Keypoints) do
				local color = Private.RecolorThemeValue(instance, "GradientColor", keypoint.Value, oldTheme) or keypoint.Value
				table.insert(keypoints, ColorSequenceKeypoint.new(keypoint.Time, color))
			end
			instance.Color = ColorSequence.new(keypoints)
		elseif instance:IsA("UICorner") then
			local radius = instance.CornerRadius
			if radius.Scale == 0 and radius.Offset == oldTheme.CornerRadius then
				instance.CornerRadius = UDim.new(0, self.Theme.CornerRadius)
			elseif radius.Scale == 0 and radius.Offset == oldTheme.CornerRadiusSm then
				instance.CornerRadius = UDim.new(0, self.Theme.CornerRadiusSm)
			end
		elseif instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			if instance.Font == oldTheme.MeasureFont then instance.Font = self.Theme.MeasureFont end
		end
	end
	for _, window in ipairs(self._Windows or {}) do
		local launcher = window._launcher
		if launcher and launcher.Parent then
			launcher.BackgroundColor3 = self.Theme.Surface
			if window._launcherStroke then window._launcherStroke.Color = self.Theme.Border end
			if window._launcherLogoText then
				window._launcherLogoText.TextColor3 = self.Theme.Accent
				pcall(function() window._launcherLogoText.FontFace = self.Theme.Font end)
			end
			if window._launcherTitle then
				window._launcherTitle.TextColor3 = self.Theme.Text
				pcall(function() window._launcherTitle.FontFace = self.Theme.Font end)
			end
			if window._launcherHint then
				window._launcherHint.TextColor3 = self.Theme.TextDim
				pcall(function() window._launcherHint.FontFace = self.Theme.FontRegular end)
			end
		end
	end
	return true
end
 
local function AddScrollbar(scroll)
	scroll.ScrollBarThickness = 0
	scroll.ScrollBarImageTransparency = 1
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.None
	scroll.HorizontalScrollBarInset = Enum.ScrollBarInset.None
end
 
function Private.AddContentScrollThumb(scroll, listLayout, thumbParent, janitor)
	local thumb = Instance.new("Frame")
	thumb.Name = "ContentScrollThumb"
	thumb.BackgroundColor3 = SilentUI.Theme.TextDim
	thumb.BackgroundTransparency = 0.35
	thumb.BorderSizePixel = 0
	thumb.AnchorPoint = Vector2.new(1, 0)
	thumb.Size = UDim2.new(0, 3, 0, 40)
	thumb.Visible = false
	thumb.ZIndex = (scroll.ZIndex or 0) + 6
	thumb.Parent = thumbParent
	Corner(thumb, 2)
 
	local MARGIN = 4
 
	janitor:Add(RunService.Heartbeat:Connect(function()
		if not thumbParent.Visible then
			thumb.Visible = false
			return
		end
		local windowH = scroll.AbsoluteWindowSize.Y
		local canvasH = scroll.AbsoluteCanvasSize.Y
		local overflow = canvasH - windowH
		if overflow <= 8 or windowH <= 0 then
			thumb.Visible = false
			return
		end
		local trackH = windowH - MARGIN * 2
		if trackH <= 0 then
			thumb.Visible = false
			return
		end
		local parentPos, parentSize = thumbParent.AbsolutePosition, thumbParent.AbsoluteSize
		if parentSize.X <= 0 or parentSize.Y <= 0 then
			thumb.Visible = false
			return
		end
		local thumbH = math.min(trackH, math.max(30, trackH * (windowH / canvasH)))
		local maxThumbY = trackH - thumbH
		local ratio = math.clamp(scroll.CanvasPosition.Y / overflow, 0, 1)
		local topY = (scroll.AbsolutePosition.Y - parentPos.Y) + MARGIN + maxThumbY * ratio
		local rightX = (scroll.AbsolutePosition.X + scroll.AbsoluteSize.X) - parentPos.X - MARGIN
		thumb.Visible = true
		thumb.Size = UDim2.new(0, 3, thumbH / parentSize.Y, 0)
		thumb.Position = UDim2.new(rightX / parentSize.X, 0, topY / parentSize.Y, 0)
	end))
 
	return thumb
end
 
Private.MEASURE_FUDGE = 1.06
Private.MeasureCache = {}
 
local function MeasureText(text, size, maxWidth)
	text = tostring(text or "")
	maxWidth = maxWidth or 10000
	local key = text .. "\1" .. size .. "\1" .. math.floor(maxWidth) .. "\1" .. tostring(SilentUI.Theme.MeasureFont)
	local cached = Private.MeasureCache[key]
	if cached then return cached.X, cached.Y end
 
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(
			text, size, SilentUI.Theme.MeasureFont,
			Vector2.new(maxWidth, 100000)
		)
	end)
	local w, h
	if ok and bounds then
		w = math.ceil(bounds.X * Private.MEASURE_FUDGE)
		h = math.ceil(bounds.Y)
	else
		w = math.ceil(#text * size * 0.55)
		h = size + 2
	end
	Private.MeasureCache[key] = Vector2.new(w, h)
	return w, h
end
 
Private.IconSources = {
	Material = "https://raw.githubusercontent.com/Skinny-yz/NullUI-Assets/main/icons/MaterialIcons.luau",
	Lucide   = "https://raw.githubusercontent.com/Skinny-yz/NullUI-Assets/main/icons/LucideIcons.luau",
	Phosphor = "https://raw.githubusercontent.com/Skinny-yz/NullUI-Assets/main/icons/Phosphor.luau",
	["Phosphor-Filled"] = "https://raw.githubusercontent.com/Skinny-yz/NullUI-Assets/main/icons/Phosphor%20Filled.luau",
	SF       = "https://raw.githubusercontent.com/Skinny-yz/NullUI-Assets/main/icons/SFSymbols.luau",
}
 
Private.IconCache = {}
Private.IconLoading = {}
 
local function LoadIconSource(source)
	if Private.IconCache[source] ~= nil then
		return Private.IconCache[source] or nil
	end
 
	if Private.IconLoading[source] then
		local t0 = os.clock()
		while Private.IconLoading[source] and os.clock() - t0 < 10 do
			task.wait()
		end
		return Private.IconCache[source] or nil
	end
 
	local url = Private.IconSources[source]
	if not url then
		Private.IconCache[source] = false
		return nil
	end
 
	Private.IconLoading[source] = true
	local ok, data = pcall(function()
		return loadstring(game:HttpGet(url))()
	end)
	Private.IconLoading[source] = nil
 
	if ok and type(data) == "table" then
		Private.IconCache[source] = data
		return data
	end
 
	Private.IconCache[source] = false
	return nil
end
 
function SilentUI:GetIcon(name, source)
	source = source or "Lucide"
	local set = LoadIconSource(source)
	local iconId = set and set[name]
	if not iconId then return "" end
	return "rbxassetid://" .. tostring(iconId)
end
 
local function ResolveIcon(icon)
	if icon == nil or icon == "" then return "" end
	if type(icon) ~= "string" then return icon end
	if icon:match("^%a[%w%+%-%.]*://") then return icon end
	if icon:match("^%d+$") then return "rbxassetid://" .. icon end
	local source, name = icon:match("^(%a[%w%-]*):(.+)$")
	if source and name then
		return SilentUI:GetIcon(name, source)
	end
	return SilentUI:GetIcon(icon, "Lucide")
end
 
function SilentUI:PreloadIcons(sources)
	for _, src in ipairs(sources or { "Lucide" }) do
		task.spawn(LoadIconSource, src)
	end
end
 
function Private.ResolveRootParent(mode)
	if mode ~= "Auto" and mode ~= "PlayerGui" and mode ~= "Hidden" then
		return nil, "RootMode must be Auto, PlayerGui or Hidden"
	end
	if mode == "PlayerGui" then return PlayerGui end
	local hidden = hasFn("gethui")
	if hidden then
		local ok, container = pcall(hidden)
		if ok and typeof(container) == "Instance" then return container end
	end
	if mode == "Hidden" then return nil, "gethui is unavailable" end
	return PlayerGui
end

function SilentUI:SetRootMode(mode)
	local parent, err = Private.ResolveRootParent(mode)
	if not parent then return false, err end
	local root = self._Root
	if root and root.Parent ~= parent then
		if #self._Windows > 0 then return false, "cannot change RootMode while windows exist" end
		local conflict = parent:FindFirstChild("SilentUI")
		if conflict and conflict ~= root then conflict:Destroy() end
		root.Parent = parent
	end
	self.RootMode = mode
	return true
end

function Private.GetRoot()
	local parent, err = Private.ResolveRootParent(SilentUI.RootMode)
	if not parent then
		warn("[SilentUI] " .. tostring(err) .. "; using PlayerGui")
		parent = PlayerGui
		SilentUI.RootMode = "PlayerGui"
	end
 
	local stale = parent:FindFirstChild("SilentUI")
	if stale then stale:Destroy() end
 
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SilentUI"
	screenGui:SetAttribute("SilentVersion", SilentUI.Version)
	screenGui:SetAttribute("SilentLanguage", SilentUI.Language)
	screenGui.AutoLocalize = false
	screenGui.ResetOnSpawn = false
	-- Cover the full viewport (including the topbar/safe-inset margins).
	screenGui.IgnoreGuiInset = true
	pcall(function() screenGui.ScreenInsets = Enum.ScreenInsets.None end)
	pcall(function() screenGui.ClipToDeviceSafeArea = false end)
	-- Keep SilentUI above normal PlayerGui ScreenGuis.
	-- Maximum signed 32-bit DisplayOrder; this places SilentUI above other ScreenGuis.
screenGui.DisplayOrder = 2147483647
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = parent
	Private.TrackLocalizationRoot(screenGui)
	return screenGui
end
 
SilentUI._Root = Private.GetRoot()
 
function Private.ViewportSize()
	local root = SilentUI._Root
	if root and root.AbsoluteSize.X > 0 then
		return root.AbsoluteSize
	end
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1280, 720)
end
 
Private.UI_SCALE_BASELINE = IsMobileDevice and 380 or 720
Private.UI_SCALE_MIN = IsMobileDevice and 1.0 or 0.75
Private.UI_SCALE_MAX = IsMobileDevice and 1.5 or 1.35
 
function Private.ComputeUIScale()
	return SafeClamp(Private.ViewportSize().Y / Private.UI_SCALE_BASELINE, Private.UI_SCALE_MIN, Private.UI_SCALE_MAX)
end
 
local GlobalScale = Instance.new("UIScale")
GlobalScale.Name = "GlobalScale"
GlobalScale.Scale = Private.ComputeUIScale()
GlobalScale.Parent = SilentUI._Root
 
local function GetUIScale()
	return GlobalScale.Scale
end
 
function Private.RefreshUIScale()
	GlobalScale.Scale = Private.ComputeUIScale()
end
 
function Private.WatchCamera(cam)
	if not cam then return end
	LibJanitor:Add(cam:GetPropertyChangedSignal("ViewportSize"):Connect(Private.RefreshUIScale))
end
 
Private.WatchCamera(workspace.CurrentCamera)
LibJanitor:Add(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	Private.WatchCamera(workspace.CurrentCamera)
	Private.RefreshUIScale()
end))
 
function SilentUI:SetScaleRange(minScale, maxScale)
	Private.UI_SCALE_MIN = minScale or Private.UI_SCALE_MIN
	Private.UI_SCALE_MAX = maxScale or Private.UI_SCALE_MAX
	Private.RefreshUIScale()
end
 
local ActivePopupClose = nil
 
function Private.RegisterPopupOpen(closeFn)
	if ActivePopupClose and ActivePopupClose ~= closeFn then
		local previous = ActivePopupClose
		ActivePopupClose = nil
		previous()
	end
	ActivePopupClose = closeFn
end
 
function Private.RegisterPopupClose(closeFn)
	if ActivePopupClose == closeFn then
		ActivePopupClose = nil
	end
end
 
function Private.CloseAnyOpenPopup()
	if ActivePopupClose then
		local fn = ActivePopupClose
		ActivePopupClose = nil
		fn()
	end
end
 
function Private.MakePopupBackdrop(onClose)
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "PopupBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = Z.Backdrop
	backdrop.Parent = SilentUI._Root
	backdrop.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			onClose()
		end
	end)
	return backdrop
end
 
LibJanitor:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape and ActivePopupClose then
		Private.CloseAnyOpenPopup()
	end
end))
 
local KeybindCapturing = false
Private.KeybindCaptureStop = nil
local KeybindControls = {}
local ActiveKeybindContext = "global"
Private.KeybindInputHandlersInstalled = false

Private.KeybindMouseAliases = {
	m1 = Enum.UserInputType.MouseButton1, mouse1 = Enum.UserInputType.MouseButton1, mb1 = Enum.UserInputType.MouseButton1,
	m2 = Enum.UserInputType.MouseButton2, mouse2 = Enum.UserInputType.MouseButton2, mb2 = Enum.UserInputType.MouseButton2,
	m3 = Enum.UserInputType.MouseButton3, mouse3 = Enum.UserInputType.MouseButton3, mb3 = Enum.UserInputType.MouseButton3,
}

function Private.ResolveKeybindKey(value)
	if value == nil or value == "" or value == "NONE" or value == "None" then return nil end
	if typeof(value) == "EnumItem" then
		if value.EnumType == Enum.KeyCode and value ~= Enum.KeyCode.Unknown then return value end
		if value.EnumType == Enum.UserInputType and (value == Enum.UserInputType.MouseButton1
			or value == Enum.UserInputType.MouseButton2 or value == Enum.UserInputType.MouseButton3) then
			return value
		end
		return nil, "expected a keyboard/gamepad key or mouse button 1-3"
	end
	if type(value) ~= "string" then return nil, "expected an EnumItem, key name, or nil" end

	local alias = Private.KeybindMouseAliases[string.lower(value):gsub("%s", "")]
	if alias then return alias end
	local enumType, keyName = value:match("^Enum%.([%w_]+)%.([%w_]+)$")
	if not enumType then enumType, keyName = value:match("^([%w_]+)%.([%w_]+)$") end
	if not enumType then
		keyName = value
		enumType = keyName:match("^MouseButton[123]$") and "UserInputType" or "KeyCode"
	end
	local ok, key = pcall(function() return Enum[enumType][keyName] end)
	if not ok or typeof(key) ~= "EnumItem" then return nil, "key is not a valid enum name" end
	if key.EnumType == Enum.KeyCode and key ~= Enum.KeyCode.Unknown then return key end
	if key.EnumType == Enum.UserInputType and (key == Enum.UserInputType.MouseButton1
		or key == Enum.UserInputType.MouseButton2 or key == Enum.UserInputType.MouseButton3) then
		return key
	end
	return nil, "expected a keyboard/gamepad key or mouse button 1-3"
end

local function KeybindInputKey(input)
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.Keyboard or string.find(inputType.Name, "Gamepad", 1, true) then
		return input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode or nil
	end
	if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3 then
		return inputType
	end
	return nil
end

function Private.KeybindLabel(key)
	if not key then return "None" end
	if key.EnumType == Enum.UserInputType then
		return ({
			[Enum.UserInputType.MouseButton1] = "M1",
			[Enum.UserInputType.MouseButton2] = "M2",
			[Enum.UserInputType.MouseButton3] = "M3",
		})[key] or key.Name
	end
	return ({
		[Enum.KeyCode.LeftShift] = "LS", [Enum.KeyCode.RightShift] = "RS",
		[Enum.KeyCode.LeftControl] = "LC", [Enum.KeyCode.RightControl] = "RC",
		[Enum.KeyCode.LeftAlt] = "LA", [Enum.KeyCode.RightAlt] = "RA",
		[Enum.KeyCode.Insert] = "INS", [Enum.KeyCode.Backspace] = "BS",
		[Enum.KeyCode.Return] = "Ent", [Enum.KeyCode.Space] = "SPC",
	})[key] or key.Name
end

local function KeybindContextActive(context)
	return context == "global" or context == ActiveKeybindContext
end

function Private.KeybindContextsOverlap(first, second)
	return first == "global" or second == "global" or first == second
end

function Private.KeybindConflicts(control, other)
	return control ~= other and not control.destroyed and not other.destroyed
		and not (control.api and other.api and control.api.Flag ~= nil and control.api.Flag == other.api.Flag)
		and control.mode ~= "Always" and other.mode ~= "Always"
		and control.key ~= nil and control.key == other.key
		and Private.KeybindContextsOverlap(control.context, other.context)
end

local function RefreshKeybindConflicts()
	for _, control in ipairs(KeybindControls) do
		local conflict = false
		for _, other in ipairs(KeybindControls) do
			if Private.KeybindConflicts(control, other) then conflict = true; break end
		end
		local stroke = control.stroke
		if stroke and stroke.Parent then
			stroke.Color = control.listening and SilentUI.Theme.Accent
				or conflict and SilentUI.Theme.Danger or SilentUI.Theme.Border
			stroke.Transparency = control.listening and 0.3 or conflict and 0.3 or 0.88
		end
	end
end
 
Private.NotificationQueue = {}
 
function Private.GetNotifyHolder()
	local root = SilentUI._Root
	local holder = root:FindFirstChild("NotificationHolder")
	if holder then return holder end
 
	holder = Instance.new("Frame")
	holder.Name = "NotificationHolder"
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -20, 1, -20)
	holder.Size = UDim2.new(0, 280, 1, -40)
	holder.BackgroundTransparency = 1
	holder.ZIndex = Z.Toast
	holder.Parent = root
 
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 10)
	layout.Parent = holder
	holder.ClipsDescendants = true
 
	LibJanitor:Add(RunService.Heartbeat:Connect(function()
		if not holder.Parent then return end
		local s = GetUIScale()
		local view = Private.ViewportSize()
		holder.Size = UDim2.fromOffset(math.max(1, math.min(280, view.X / s - 40)), math.max(1, view.Y / s - 40))
		local used, count = 0, 0
		local function fullHeight(card)
			local anim = card:FindFirstChildOfClass("UIScale")
			return card.AbsoluteSize.Y / (anim and math.max(anim.Scale, 0.01) or 1)
		end
		for _, child in ipairs(holder:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible then
				used += fullHeight(child) + (count > 0 and 10 * s or 0)
				count += 1
			end
		end
		while #Private.NotificationQueue > 0 do
			local entry = Private.NotificationQueue[1]
			if not entry.Card.Parent then
				table.remove(Private.NotificationQueue, 1)
			else
				local h = fullHeight(entry.Card)
				if h <= 0 then break end
				local needed = h + (count > 0 and 10 * s or 0)
				if used + needed > holder.AbsoluteSize.Y then break end
				table.remove(Private.NotificationQueue, 1)
				entry.Start()
				used += needed
				count += 1
			end
		end
	end))
 
	return holder
end
 
SilentUI._NotifyCounter = 0
 
Private.NotifyIcons = {
	info    = "info",
	success = "check",
	warning = "triangle-alert",
	error   = "circle-x",
}
 
Private.NotifyColors = {
	info    = Color3.fromRGB(120, 170, 255),
	success = Color3.fromRGB(110, 220, 140),
	warning = Color3.fromRGB(255, 190, 90),
	error   = Color3.fromRGB(255, 105, 105),
}
 
function SilentUI:Notify(opts)
	opts = opts or {}
	local title      = opts.Title or "Notification"
	local text       = opts.Text or ""
	local duration   = opts.Duration or 4
	local notifyType = opts.Type or "info"
	local color      = opts.Color or Private.NotifyColors[notifyType] or SilentUI.Theme.Accent
	local iconName   = opts.Icon or Private.NotifyIcons[notifyType] or Private.NotifyIcons.info
 
	local holder = Private.GetNotifyHolder()
	SilentUI._NotifyCounter = SilentUI._NotifyCounter + 1
 
	local dismiss
 
	local card = Instance.new("Frame")
	card.Name = "Notification"
	card.BackgroundColor3 = SilentUI.Theme.Surface
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, 0, 0, 0)
	card.LayoutOrder = SilentUI._NotifyCounter
	card.ZIndex = Z.Toast
	card.Visible = false
	card.Parent = holder
	Corner(card, 12)
	local stroke = Stroke(card, SilentUI.Theme.Border, 1, 1)
	local notificationAcrylic = nil
	local scale = Instance.new("UIScale")
	scale.Scale = 0.88
	scale.Parent = card
 
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = card
 
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card
 
	local headerRow = Instance.new("Frame")
	headerRow.BackgroundTransparency = 1
	headerRow.AutomaticSize = Enum.AutomaticSize.XY
	headerRow.Size = UDim2.new(0, 0, 0, 0)
	headerRow.LayoutOrder = 1
	headerRow.ZIndex = Z.Toast + 1
	headerRow.Parent = card
 
	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Horizontal
	headerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	headerLayout.Padding = UDim.new(0, 7)
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Parent = headerRow
 
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = ResolveIcon(iconName)
	icon.ImageColor3 = color
	icon.ImageTransparency = 1
	icon.Size = UDim2.fromOffset(14, 14)
	icon.LayoutOrder = 1
	icon.ZIndex = Z.Toast + 1
	icon.Parent = headerRow
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = SilentUI.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = SilentUI.Theme.Text
	titleLabel.TextTransparency = 1
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.AutomaticSize = Enum.AutomaticSize.XY
	titleLabel.Size = UDim2.fromOffset(0, 14)
	titleLabel.LayoutOrder = 2
	titleLabel.ZIndex = Z.Toast + 1
	titleLabel.Parent = headerRow
 
	local textLabel
	if text ~= "" then
		textLabel = Instance.new("TextLabel")
		textLabel.BackgroundTransparency = 1
		textLabel.FontFace = SilentUI.Theme.FontRegular
		textLabel.Text = text
		textLabel.TextColor3 = SilentUI.Theme.TextDim
		textLabel.TextTransparency = 1
		textLabel.TextSize = 12
		textLabel.TextWrapped = true
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		textLabel.AutomaticSize = Enum.AutomaticSize.Y
		textLabel.LayoutOrder = 2
		textLabel.Size = UDim2.new(1, 0, 0, 14)
		textLabel.ZIndex = Z.Toast + 1
		textLabel.Parent = card
	end
 
	local actionButtons = {}
	if type(opts.Actions) == "table" and #opts.Actions > 0 then
		local actionsRow = Instance.new("Frame")
		actionsRow.Name = "Actions"
		actionsRow.BackgroundTransparency = 1
		actionsRow.AutomaticSize = Enum.AutomaticSize.Y
		actionsRow.Size = UDim2.new(1, 0, 0, 0)
		actionsRow.LayoutOrder = 3
		actionsRow.ZIndex = Z.Toast + 1
		actionsRow.Parent = card
 
		local actionsLayout = Instance.new("UIListLayout")
		actionsLayout.FillDirection = Enum.FillDirection.Horizontal
		actionsLayout.Padding = UDim.new(0, 6)
		actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		actionsLayout.Parent = actionsRow
 
		for i, action in ipairs(opts.Actions) do
			local btn = Instance.new("TextButton")
			btn.AutoButtonColor = false
			btn.BackgroundColor3 = color
			btn.BackgroundTransparency = 1
			btn.BorderSizePixel = 0
			btn.Text = ""
			btn.AutomaticSize = Enum.AutomaticSize.X
			btn.Size = UDim2.fromOffset(0, 22)
			btn.LayoutOrder = i
			btn.ZIndex = Z.Toast + 1
			btn.Parent = actionsRow
			Corner(btn, 6)
			local btnStroke = Stroke(btn, color, 1, 1)
 
			local btnPad = Instance.new("UIPadding")
			btnPad.PaddingLeft = UDim.new(0, 8)
			btnPad.PaddingRight = UDim.new(0, 8)
			btnPad.Parent = btn
 
			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.FontFace = SilentUI.Theme.Font
			lbl.Text = action.Text or "Action"
			lbl.TextColor3 = color
			lbl.TextTransparency = 1
			lbl.TextSize = 12
			lbl.AutomaticSize = Enum.AutomaticSize.X
			lbl.Size = UDim2.fromOffset(0, 22)
			lbl.ZIndex = Z.Toast + 2
			lbl.Parent = btn
 
			Tween(btn, { BackgroundTransparency = 0.85 }, 0.28)
			Tween(btnStroke, { Transparency = 0.6 }, 0.28)
			Tween(lbl, { TextTransparency = 0 }, 0.28)
 
			btn.MouseEnter:Connect(function() Tween(btn, { BackgroundTransparency = 0.7 }, 0.12) end)
			btn.MouseLeave:Connect(function() Tween(btn, { BackgroundTransparency = 0.85 }, 0.12) end)
			btn.MouseButton1Click:Connect(function()
				if action.Callback then task.spawn(action.Callback) end
				if action.DismissOnClick ~= false then dismiss() end
			end)
 
			table.insert(actionButtons, { Button = btn, Stroke = btnStroke, Label = lbl })
		end
	end
 
	local barHolder = Instance.new("Frame")
	barHolder.BackgroundColor3 = SilentUI.Theme.Surface
	barHolder.BackgroundTransparency = 1
	barHolder.BorderSizePixel = 0
	barHolder.Size = UDim2.new(1, 0, 0, 3)
	barHolder.LayoutOrder = 4
	barHolder.ZIndex = Z.Toast + 1
	barHolder.Parent = card
	Corner(barHolder, 2)
 
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = color
	bar.BackgroundTransparency = 1
	bar.BorderSizePixel = 0
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.new(0, 0, 0.5, 0)
	bar.Size = UDim2.fromScale(1, 1)
	bar.ZIndex = Z.Toast + 2
	bar.Parent = barHolder
	Corner(bar, 2)
 
	local barGradient = Instance.new("UIGradient")
	barGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(1, 1, 1), 0.4)),
		ColorSequenceKeypoint.new(1, color),
	})
	barGradient.Parent = bar
 
 
	local dismissed = false
	function dismiss()
		if dismissed or not card.Parent then return end
		dismissed = true
		if not card.Visible then card:Destroy(); return end
 
		local currentHeight = card.AbsoluteSize.Y / GetUIScale()
		card.AutomaticSize = Enum.AutomaticSize.None
		card.Size = UDim2.new(1, 0, 0, currentHeight)
 
		Tween(card, { BackgroundTransparency = 1 }, 0.16)
		Tween(stroke, { Transparency = 1 }, 0.16)
		Tween(scale, { Scale = 0.9 }, 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		Tween(icon, { ImageTransparency = 1 }, 0.16)
		Tween(titleLabel, { TextTransparency = 1 }, 0.16)
		if textLabel then Tween(textLabel, { TextTransparency = 1 }, 0.16) end
 
		task.delay(0.1, function()
			if card and card.Parent then
				Tween(card, { Size = UDim2.new(1, 0, 0, 0) }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			end
		end)
 
		task.delay(0.34, function()
			if notificationAcrylic then
				notificationAcrylic:Destroy()
				notificationAcrylic = nil
			end
			if card then card:Destroy() end
		end)
	end
 
	local function startNotification()
		if dismissed or not card.Parent then return end
		card.Visible = true
		notificationAcrylic = Private.CreateWindowAcrylic(card)
	Tween(card, { BackgroundTransparency = 0.25 }, 0.28)
	Tween(stroke, { Transparency = 0.82 }, 0.28)
	Tween(scale, { Scale = 1 }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	Tween(icon, { ImageTransparency = 0 }, 0.28)
	Tween(titleLabel, { TextTransparency = 0 }, 0.28)
	Tween(barHolder, { BackgroundTransparency = 0.88 }, 0.28)
	Tween(bar, { BackgroundTransparency = 0 }, 0.28)
	if textLabel then
		Tween(textLabel, { TextTransparency = 0 }, 0.28)
	end
 
	task.delay(0.05, function()
		if bar and bar.Parent then
			Tween(bar, { Size = UDim2.new(0, 0, 1, 0) }, duration - 0.05,
				Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		end
	end)
 
		task.delay(duration, dismiss)
	end
	table.insert(Private.NotificationQueue, { Card = card, Start = startNotification })
 
	return {
		Instance = card,
		Dismiss = dismiss,
	}
end
 
function Private.ComputeDialogCenter(anchorFrame)
	local view = Private.ViewportSize()
	if not anchorFrame or anchorFrame.AbsoluteSize.X <= 0 then
		return view.X / 2, view.Y / 2
	end
	local pos, size = anchorFrame.AbsolutePosition, anchorFrame.AbsoluteSize
	local cx = SafeClamp(pos.X + size.X / 2, 190, math.max(190, view.X - 190))
	local cy = SafeClamp(pos.Y + size.Y / 2, 110, math.max(110, view.Y - 110))
	return cx, cy
end
 
function SilentUI:Confirm(opts)
	opts = opts or {}
	local title       = opts.Title or "Confirm"
	local text        = opts.Text or ""
	local confirmText = opts.ConfirmText or "Confirm"
	local cancelText  = opts.CancelText or "Cancel"
	local danger      = opts.Danger == true
	local ownerWindow = type(opts.Window) == "table" and opts.Window or nil
	local anchorFrame = opts.Window
	if ownerWindow then anchorFrame = ownerWindow._gui end
 
	local root = SilentUI._Root
	local jan = Janitor.new()
 
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "ConfirmBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = Z.Modal
	backdrop.Parent = root
 
	local dialog = Instance.new("Frame")
	dialog.Name = "ConfirmDialog"
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	do
		local cx, cy = Private.ComputeDialogCenter(anchorFrame)
		local s = GetUIScale()
		dialog.Position = UDim2.fromOffset(math.round(cx / s), math.round(cy / s))
	end
	dialog.BackgroundColor3 = SilentUI.Theme.Surface
	dialog.BackgroundTransparency = 1
	dialog.BorderSizePixel = 0
	dialog.Active = true
	dialog.ClipsDescendants = true
	dialog.AutomaticSize = Enum.AutomaticSize.Y
	dialog.Size = UDim2.new(0, 340, 0, 0)
	dialog.ZIndex = Z.ModalTop
	dialog.Parent = backdrop
	if ownerWindow then
		dialog:SetAttribute("SilentInterfacePanel", true)
		dialog:SetAttribute("SilentWindowId", ownerWindow._id)
	end
	Corner(dialog, 16)
	local dialogStroke = Stroke(dialog, SilentUI.Theme.Border, 1, 1)
 
	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = dialog
 
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 20)
	padding.PaddingBottom = UDim.new(0, 18)
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 20)
	padding.Parent = dialog
 
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = dialog
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = SilentUI.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = danger and SilentUI.Theme.Danger or SilentUI.Theme.Text
	titleLabel.TextTransparency = 1
	titleLabel.TextSize = 18
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextWrapped = true
	titleLabel.AutomaticSize = Enum.AutomaticSize.Y
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.LayoutOrder = 1
	titleLabel.ZIndex = Z.ModalTop + 1
	titleLabel.Parent = dialog
 
	local textLabel
	if text ~= "" then
		textLabel = Instance.new("TextLabel")
		textLabel.BackgroundTransparency = 1
		textLabel.FontFace = SilentUI.Theme.FontRegular
		textLabel.Text = text
		textLabel.TextColor3 = SilentUI.Theme.TextDim
		textLabel.TextTransparency = 1
		textLabel.TextSize = 14
		textLabel.TextWrapped = true
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		textLabel.LineHeight = 1.25
		textLabel.AutomaticSize = Enum.AutomaticSize.Y
		textLabel.Size = UDim2.new(1, 0, 0, 14)
		textLabel.LayoutOrder = 2
		textLabel.ZIndex = Z.ModalTop + 1
		textLabel.Parent = dialog
	end
 

	local identity = opts.Identity
	if identity == nil and (opts.Avatar ~= nil or opts.Username ~= nil or opts.UserId ~= nil) then
		identity = { Avatar = opts.Avatar, Username = opts.Username, UserId = opts.UserId, Subtitle = opts.Subtitle }
	end
	local contentOrder = 3
	if type(identity) == "table" then
		local identityRow = Instance.new("Frame")
		identityRow.Name = "Identity"
		identityRow.BackgroundTransparency = 1
		identityRow.Size = UDim2.new(1, 0, 0, 56)
		identityRow.LayoutOrder = contentOrder
		identityRow.ZIndex = Z.ModalTop + 1
		identityRow.Parent = dialog
		contentOrder += 1
		local portrait = Instance.new("ImageLabel")
		portrait.Name = "Avatar"
		portrait.BackgroundTransparency = 1
		portrait.Size = UDim2.fromOffset(50, 50)
		portrait.Position = UDim2.fromOffset(0, 3)
		portrait.ZIndex = Z.ModalTop + 2
		portrait.Parent = identityRow
		Corner(portrait, 25)
		local avatar = identity.Avatar
		if type(avatar) == "number" or (type(avatar) == "string" and avatar:match("^%d+$")) then
			avatar = "rbxassetid://" .. tostring(avatar)
		end
		if type(avatar) == "string" then portrait.Image = avatar end
		if not avatar and tonumber(identity.UserId) then
			local userId = tonumber(identity.UserId)
			task.spawn(function()
				local ok, image = pcall(function()
					return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
				end)
				if ok and portrait.Parent then portrait.Image = image end
			end)
		end
		local username = Instance.new("TextLabel")
		username.Name = "Username"
		username.BackgroundTransparency = 1
		username.FontFace = SilentUI.Theme.Font
		username.Text = tostring(identity.Username or identity.Name or ("User " .. tostring(identity.UserId or "")))
		username.TextColor3 = SilentUI.Theme.Text
		username.TextSize = 14
		username.TextTruncate = Enum.TextTruncate.AtEnd
		username.TextXAlignment = Enum.TextXAlignment.Left
		username.Position = UDim2.fromOffset(62, 4)
		username.Size = UDim2.new(1, -62, 0, 22)
		username.ZIndex = Z.ModalTop + 2
		username.Parent = identityRow
		local subtitle = Instance.new("TextLabel")
		subtitle.Name = "Subtitle"
		subtitle.BackgroundTransparency = 1
		subtitle.FontFace = SilentUI.Theme.FontRegular
		subtitle.Text = tostring(identity.Subtitle or "")
		subtitle.TextColor3 = SilentUI.Theme.TextDim
		subtitle.TextSize = 12
		subtitle.TextTruncate = Enum.TextTruncate.AtEnd
		subtitle.TextXAlignment = Enum.TextXAlignment.Left
		subtitle.Position = UDim2.fromOffset(62, 27)
		subtitle.Size = UDim2.new(1, -62, 0, 19)
		subtitle.ZIndex = Z.ModalTop + 2
		subtitle.Parent = identityRow
	end
	local contentHolder
	if opts.Content ~= nil then
		contentHolder = Instance.new("Frame")
		contentHolder.Name = "CustomContent"
		contentHolder.BackgroundTransparency = 1
		contentHolder.AutomaticSize = Enum.AutomaticSize.Y
		contentHolder.Size = UDim2.new(1, 0, 0, 0)
		contentHolder.LayoutOrder = contentOrder
		contentHolder.ZIndex = Z.ModalTop + 1
		contentHolder.Parent = dialog
		if type(opts.Content) == "function" then
			local ok, err = pcall(opts.Content, contentHolder)
			if not ok then warn("[SilentUI] Confirm content error: " .. tostring(err)) end
		elseif typeof(opts.Content) == "Instance" then
			opts.Content:Clone().Parent = contentHolder
		end
		contentOrder += 1
	end

	local buttonsRow = Instance.new("Frame")
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.Size = UDim2.new(1, 0, 0, 38)
	buttonsRow.LayoutOrder = contentOrder
	buttonsRow.ZIndex = Z.ModalTop + 1
	buttonsRow.Parent = dialog
 
	local rowPad = Instance.new("UIPadding")
	rowPad.PaddingTop = UDim.new(0, 6)
	rowPad.Parent = buttonsRow
 
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = buttonsRow
 
	local function makeButton(text_, order, filled)
		local tint = (filled and danger) and SilentUI.Theme.Danger or SilentUI.Theme.Text
 
		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = tint
		btn.BackgroundTransparency = filled and (danger and 0.55 or 0.82) or 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(0.5, -4, 1, 0)
		btn.LayoutOrder = order
		btn.ZIndex = Z.ModalTop + 1
		btn.Parent = buttonsRow
		Corner(btn, 10)
		local btnStroke = Stroke(btn, tint, 1, filled and 0.7 or 0.85)
 
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.FontFace = SilentUI.Theme.Font
		lbl.Text = text_
		lbl.TextColor3 = (filled and danger) and SilentUI.Theme.Danger or SilentUI.Theme.Text
		lbl.TextSize = 14
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.ZIndex = Z.ModalTop + 2
		lbl.Parent = btn
 
		local baseBg = btn.BackgroundTransparency
		local baseStroke = btnStroke.Transparency
 
		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = math.max(baseBg - 0.1, 0) }, 0.12)
			Tween(btnStroke, { Transparency = math.max(baseStroke - 0.15, 0) }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = baseBg }, 0.12)
			Tween(btnStroke, { Transparency = baseStroke }, 0.12)
		end))
 
		return btn
	end
 
	local cancelBtn  = makeButton(cancelText, 1, false)
	local confirmBtn = makeButton(confirmText, 2, true)
 
	local closed = false
	local function close(confirmed)
		if closed then return end
		closed = true
 
		Tween(scale, { Scale = 0.94 }, 0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		Tween(dialog, { BackgroundTransparency = 1 }, 0.15)
		Tween(dialogStroke, { Transparency = 1 }, 0.15)
		Tween(backdrop, { BackgroundTransparency = 1 }, 0.15)
		Tween(titleLabel, { TextTransparency = 1 }, 0.12)
		if textLabel then Tween(textLabel, { TextTransparency = 1 }, 0.12) end
 
		task.delay(0.18, function()
			jan:Destroy()
			if backdrop then backdrop:Destroy() end
		end)
 
		if opts.Callback then task.spawn(opts.Callback, confirmed) end
	end
 
	jan:Add(backdrop.MouseButton1Click:Connect(function() close(false) end))
	jan:Add(cancelBtn.MouseButton1Click:Connect(function() close(false) end))
	jan:Add(confirmBtn.MouseButton1Click:Connect(function() close(true) end))
 
	jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or closed then return end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			close(true)
		elseif input.KeyCode == Enum.KeyCode.Escape then
			close(false)
		end
	end))
 
	Tween(backdrop, { BackgroundTransparency = 0.5 }, 0.18)
	Tween(dialog, { BackgroundTransparency = ownerWindow and ownerWindow._interfaceTransparency or 0 }, 0.18)
	Tween(dialogStroke, { Transparency = 0.8 }, 0.18)
	Tween(titleLabel, { TextTransparency = 0 }, 0.2)
	if textLabel then Tween(textLabel, { TextTransparency = 0 }, 0.2) end
	Tween(scale, { Scale = 1 }, 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
	return { Close = close, Instance = dialog, ContentContainer = contentHolder }
end
 
function SilentUI:Modal(opts)
	opts = opts or {}
	local title       = opts.Title or "Modal"
	local text        = opts.Text or ""
	local confirmText = opts.ConfirmText or "Confirm"
	local cancelText  = opts.CancelText or "Cancel"
	local danger      = opts.Danger == true
	local fields      = opts.Fields or {}
	local ownerWindow = type(opts.Window) == "table" and opts.Window or nil
	local anchorFrame = opts.Window
	if ownerWindow then anchorFrame = ownerWindow._gui end
 
	local root = SilentUI._Root
	local jan = Janitor.new()
 
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "ModalBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = Z.Modal
	backdrop.Parent = root
 
	local dialog = Instance.new("Frame")
	dialog.Name = "ModalDialog"
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	do
		local cx, cy = Private.ComputeDialogCenter(anchorFrame)
		local s = GetUIScale()
		dialog.Position = UDim2.fromOffset(math.round(cx / s), math.round(cy / s))
	end
	dialog.BackgroundColor3 = SilentUI.Theme.Surface
	dialog.BackgroundTransparency = 1
	dialog.BorderSizePixel = 0
	dialog.Active = true
	dialog.ClipsDescendants = true
	dialog.AutomaticSize = Enum.AutomaticSize.Y
	dialog.Size = UDim2.new(0, 360, 0, 0)
	dialog.ZIndex = Z.ModalTop
	dialog.Parent = backdrop
	if ownerWindow then
		dialog:SetAttribute("SilentInterfacePanel", true)
		dialog:SetAttribute("SilentWindowId", ownerWindow._id)
	end
	Corner(dialog, 16)
	local dialogStroke = Stroke(dialog, SilentUI.Theme.Border, 1, 1)
 
	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = dialog
 
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 20)
	padding.PaddingBottom = UDim.new(0, 18)
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 20)
	padding.Parent = dialog
 
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = dialog
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = SilentUI.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = danger and SilentUI.Theme.Danger or SilentUI.Theme.Text
	titleLabel.TextTransparency = 1
	titleLabel.TextSize = 18
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextWrapped = true
	titleLabel.AutomaticSize = Enum.AutomaticSize.Y
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.LayoutOrder = 1
	titleLabel.ZIndex = Z.ModalTop + 1
	titleLabel.Parent = dialog
 
	local textLabel
	if text ~= "" then
		textLabel = Instance.new("TextLabel")
		textLabel.BackgroundTransparency = 1
		textLabel.FontFace = SilentUI.Theme.FontRegular
		textLabel.Text = text
		textLabel.TextColor3 = SilentUI.Theme.TextDim
		textLabel.TextTransparency = 1
		textLabel.TextSize = 13
		textLabel.TextWrapped = true
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		textLabel.LineHeight = 1.25
		textLabel.AutomaticSize = Enum.AutomaticSize.Y
		textLabel.Size = UDim2.new(1, 0, 0, 14)
		textLabel.LayoutOrder = 2
		textLabel.ZIndex = Z.ModalTop + 1
		textLabel.Parent = dialog
	end
 
	local fieldsHolder = Instance.new("Frame")
	fieldsHolder.BackgroundTransparency = 1
	fieldsHolder.AutomaticSize = Enum.AutomaticSize.Y
	fieldsHolder.Size = UDim2.new(1, 0, 0, 0)
	fieldsHolder.LayoutOrder = 3
	fieldsHolder.ZIndex = Z.ModalTop + 1
	fieldsHolder.Parent = dialog
 
	local fieldsLayout = Instance.new("UIListLayout")
	fieldsLayout.Padding = UDim.new(0, 10)
	fieldsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	fieldsLayout.Parent = fieldsHolder
 
	local fieldBoxes = {}
 
	for i, field in ipairs(fields) do
		local isTextarea = field.Type == "textarea"
		local labelH = field.Label and field.Label ~= "" and 16 or 0
		local boxH = isTextarea and 60 or 34
 
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.AutomaticSize = Enum.AutomaticSize.Y
		holder.Size = UDim2.new(1, 0, 0, 0)
		holder.LayoutOrder = i
		holder.ZIndex = Z.ModalTop + 1
		holder.Parent = fieldsHolder
 
		local holderLayout = Instance.new("UIListLayout")
		holderLayout.Padding = UDim.new(0, 4)
		holderLayout.SortOrder = Enum.SortOrder.LayoutOrder
		holderLayout.Parent = holder
 
		if labelH > 0 then
			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.FontFace = SilentUI.Theme.FontRegular
			lbl.Text = string.upper(field.Label)
			lbl.TextColor3 = danger and SilentUI.Theme.Danger or SilentUI.Theme.TextDim
			lbl.TextSize = 11
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.Size = UDim2.new(1, 0, 0, labelH)
			lbl.LayoutOrder = 1
			lbl.ZIndex = Z.ModalTop + 2
			lbl.Parent = holder
		end
 
		local fieldFrame = Instance.new("Frame")
		fieldFrame.BackgroundColor3 = SilentUI.Theme.Surface
		fieldFrame.BackgroundTransparency = 0.93
		fieldFrame.BorderSizePixel = 0
		fieldFrame.Size = UDim2.new(1, 0, 0, boxH)
		fieldFrame.LayoutOrder = 2
		fieldFrame.ZIndex = Z.ModalTop + 2
		fieldFrame.Parent = holder
		Corner(fieldFrame, 9)
		local fieldStroke = Stroke(fieldFrame, SilentUI.Theme.Border, 1, 0.88)
 
		local fieldPad = Instance.new("UIPadding")
		fieldPad.PaddingLeft = UDim.new(0, 10)
		fieldPad.PaddingRight = UDim.new(0, 10)
		fieldPad.PaddingTop = UDim.new(0, isTextarea and 8 or 0)
		fieldPad.Parent = fieldFrame
 
		local box = Instance.new("TextBox")
		box.ClearTextOnFocus = false
		box.MultiLine = isTextarea
		box.FontFace = SilentUI.Theme.FontRegular
		box.PlaceholderText = field.Placeholder or ""
		box.PlaceholderColor3 = SilentUI.Theme.TextDim
		box.Text = tostring(field.Default or "")
		box.TextColor3 = SilentUI.Theme.Text
		box.TextSize = 13
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.TextYAlignment = isTextarea and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
		box.TextWrapped = isTextarea
		box.ClipsDescendants = true
		box.BackgroundTransparency = 1
		box.Size = UDim2.fromScale(1, 1)
		box.ZIndex = Z.ModalTop + 3
		box.Parent = fieldFrame
 
		if field.MaxLength then
			jan:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
				if utf8.len(box.Text) and utf8.len(box.Text) > field.MaxLength then
					box.Text = string.sub(box.Text, 1, field.MaxLength)
				end
			end))
		end
 
		jan:Add(box.Focused:Connect(function()
			Tween(fieldStroke, { Color = SilentUI.Theme.Accent, Transparency = 0.3 }, 0.15)
			Tween(fieldFrame, { BackgroundTransparency = 0.85 }, 0.15)
		end))
		jan:Add(box.FocusLost:Connect(function()
			Tween(fieldStroke, { Color = SilentUI.Theme.Border, Transparency = 0.88 }, 0.15)
			Tween(fieldFrame, { BackgroundTransparency = 0.93 }, 0.15)
		end))
 
		fieldBoxes[field.Key or i] = { Type = field.Type, Box = box }
	end
 
	local buttonsRow = Instance.new("Frame")
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.Size = UDim2.new(1, 0, 0, 38)
	buttonsRow.LayoutOrder = 4
	buttonsRow.ZIndex = Z.ModalTop + 1
	buttonsRow.Parent = dialog
 
	local rowPad = Instance.new("UIPadding")
	rowPad.PaddingTop = UDim.new(0, 4)
	rowPad.Parent = buttonsRow
 
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = buttonsRow
 
	local function makeButton(text_, order, filled)
		local tint = (filled and danger) and SilentUI.Theme.Danger or SilentUI.Theme.Text
 
		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = tint
		btn.BackgroundTransparency = filled and (danger and 0.55 or 0.82) or 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(0.5, -4, 1, 0)
		btn.LayoutOrder = order
		btn.ZIndex = Z.ModalTop + 1
		btn.Parent = buttonsRow
		Corner(btn, 10)
		local btnStroke = Stroke(btn, tint, 1, filled and 0.7 or 0.85)
 
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.FontFace = SilentUI.Theme.Font
		lbl.Text = text_
		lbl.TextColor3 = (filled and danger) and SilentUI.Theme.Danger or SilentUI.Theme.Text
		lbl.TextSize = 14
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.ZIndex = Z.ModalTop + 2
		lbl.Parent = btn
 
		local baseBg = btn.BackgroundTransparency
		local baseStroke = btnStroke.Transparency
 
		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = math.max(baseBg - 0.1, 0) }, 0.12)
			Tween(btnStroke, { Transparency = math.max(baseStroke - 0.15, 0) }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = baseBg }, 0.12)
			Tween(btnStroke, { Transparency = baseStroke }, 0.12)
		end))
 
		return btn
	end
 
	local cancelBtn  = makeButton(cancelText, 1, false)
	local confirmBtn = makeButton(confirmText, 2, true)
 
	local function collectValues()
		local values = {}
		for key, entry in pairs(fieldBoxes) do
			if entry.Type == "tags" then
				local list = {}
				for piece in string.gmatch(entry.Box.Text, "[^,]+") do
					local trimmed = piece:gsub("^%s+", ""):gsub("%s+$", "")
					if trimmed ~= "" then table.insert(list, trimmed) end
				end
				values[key] = list
			else
				values[key] = entry.Box.Text
			end
		end
		return values
	end
 
	local closed = false
	local function close(confirmed)
		if closed then return end
		closed = true
 
		Tween(scale, { Scale = 0.94 }, 0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		Tween(dialog, { BackgroundTransparency = 1 }, 0.15)
		Tween(dialogStroke, { Transparency = 1 }, 0.15)
		Tween(backdrop, { BackgroundTransparency = 1 }, 0.15)
		Tween(titleLabel, { TextTransparency = 1 }, 0.12)
		if textLabel then Tween(textLabel, { TextTransparency = 1 }, 0.12) end
 
		task.delay(0.18, function()
			jan:Destroy()
			if backdrop then backdrop:Destroy() end
		end)
 
		if opts.Callback then
			task.spawn(opts.Callback, confirmed, confirmed and collectValues() or nil)
		end
	end
 
	jan:Add(backdrop.MouseButton1Click:Connect(function() close(false) end))
	jan:Add(cancelBtn.MouseButton1Click:Connect(function() close(false) end))
	jan:Add(confirmBtn.MouseButton1Click:Connect(function() close(true) end))
 
	jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or closed then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			close(false)
		end
	end))
 
	Tween(backdrop, { BackgroundTransparency = 0.5 }, 0.18)
	Tween(dialog, { BackgroundTransparency = ownerWindow and ownerWindow._interfaceTransparency or 0 }, 0.18)
	Tween(dialogStroke, { Transparency = 0.8 }, 0.18)
	Tween(titleLabel, { TextTransparency = 0 }, 0.2)
	if textLabel then Tween(textLabel, { TextTransparency = 0 }, 0.2) end
	Tween(scale, { Scale = 1 }, 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
	return { Close = close }
end
 
function Private.PlayEdgeBounce(guiObject)
	if not guiObject or not guiObject.Parent then return end
	local scale = guiObject:FindFirstChild("SilentEdgeBounceScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "SilentEdgeBounceScale"
		scale.Scale = 1
		scale.Parent = guiObject
	end
	scale.Scale = 0.975
	Tween(scale, { Scale = 1 }, 0.34, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
end

local DRAG_SMOOTH_SPEED = 22
 
function Private.SetupSmoothDrag(frame, handle, janitor)
	handle = handle or frame
 
	local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
	if detector then detector.Enabled = false end
 
	local dragging = false
	local settling = false
	local edgeFeedback = false
	local mouseOffset = Vector2.zero
	local activeInput = nil
 
	local function frameOffset()
		local pos = frame.Position
		local parentSize = Private.ViewportSize()
		if frame.Parent and frame.Parent:IsA("GuiObject") and frame.Parent.AbsoluteSize.X > 0 then
			parentSize = frame.Parent.AbsoluteSize
		end
		local s = GetUIScale()
		return Vector2.new(
			pos.X.Scale * parentSize.X + pos.X.Offset * s,
			pos.Y.Scale * parentSize.Y + pos.Y.Offset * s
		)
	end
 
	local currentPosition = frameOffset()
	local targetPosition = currentPosition
 
	local function clampToScreen(pos)
		local view = Private.ViewportSize()
		local size = frame.AbsoluteSize
		local anchor = frame.AnchorPoint
		local left = pos.X - size.X * anchor.X
		local top = pos.Y - size.Y * anchor.Y
		local maxLeft = math.max(0, view.X - size.X)
		local maxTop = math.max(0, view.Y - size.Y)
		left = SafeClamp(left, 0, maxLeft)
		top = SafeClamp(top, 0, maxTop)
		return Vector2.new(left + size.X * anchor.X, top + size.Y * anchor.Y)
	end
 
	local api = {}
 
	function api.Sync()
		currentPosition = frameOffset()
		targetPosition = currentPosition
		settling = false
	end
 
	janitor:Add(handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if dragging then return end
		dragging = true
		settling = true
		activeInput = input
		currentPosition = frameOffset()
		targetPosition = currentPosition
		mouseOffset = Vector2.new(input.Position.X, input.Position.Y) - currentPosition
	end))
 
	janitor:Add(UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch
			and activeInput and input ~= activeInput then
			return
		end
		local rawPosition = Vector2.new(input.Position.X, input.Position.Y) - mouseOffset
		local clampedPosition = clampToScreen(rawPosition)
		local outside = (rawPosition - clampedPosition).Magnitude > 1
		if outside and not edgeFeedback then
			edgeFeedback = true
			Private.PlayEdgeBounce(frame)
		elseif not outside then
			edgeFeedback = false
		end
		targetPosition = clampedPosition
	end))
 
	janitor:Add(UserInputService.InputEnded:Connect(function(input)
		if input == activeInput
			or (activeInput and activeInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = false
			activeInput = nil
			edgeFeedback = false
		end
	end))
 
	janitor:Add(RunService.RenderStepped:Connect(function(dt)
		if not dragging and not settling then return end
		if not frame.Parent then return end
 
		local alpha = 1 - math.exp(-DRAG_SMOOTH_SPEED * dt)
		currentPosition = currentPosition:Lerp(targetPosition, alpha)
 
		if not dragging and (currentPosition - targetPosition).Magnitude < 0.5 then
			currentPosition = targetPosition
			settling = false
		end
 
		local s = GetUIScale()
		frame.Position = UDim2.fromOffset(
			math.round(currentPosition.X / s),
			math.round(currentPosition.Y / s)
		)
	end))
 
	return api
end
 
function Private.SetupResize(frame, handle, janitor, opts)
	opts = opts or {}
	local minSize = opts.MinSize or Vector2.new(420, 300)
	local onResize = opts.OnResize
 
	local resizing = false
	local resizingEdgeFeedback = false
	local startSize, startTopLeft, startInput, activeInput
 
	janitor:Add(handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if resizing then return end
		resizing = true
		activeInput = input
		startSize = frame.AbsoluteSize
		startTopLeft = frame.AbsolutePosition
		startInput = Vector2.new(input.Position.X, input.Position.Y)
	end))
 
	janitor:Add(UserInputService.InputChanged:Connect(function(input)
		if not resizing then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch
			and activeInput and input ~= activeInput then
			return
		end
 
		local view = Private.ViewportSize()
		local delta = Vector2.new(input.Position.X, input.Position.Y) - startInput
		local maxW = math.max(1, view.X - startTopLeft.X - 2)
		local maxH = math.max(1, view.Y - startTopLeft.Y - 2)
		local rawW = startSize.X + delta.X
		local rawH = startSize.Y + delta.Y
		if (rawW > maxW or rawH > maxH) and not resizingEdgeFeedback then
			resizingEdgeFeedback = true
			Private.PlayEdgeBounce(frame)
		elseif rawW <= maxW and rawH <= maxH then
			resizingEdgeFeedback = false
		end
		local newW = SafeClamp(rawW, math.min(minSize.X, maxW), maxW)
		local newH = SafeClamp(rawH, math.min(minSize.Y, maxH), maxH)
 
		local s = GetUIScale()
		frame.Size = UDim2.fromOffset(math.round(newW / s), math.round(newH / s))
 
		local centerX = startTopLeft.X + newW / 2
		local centerY = startTopLeft.Y + newH / 2
		frame.Position = UDim2.fromOffset(math.round(centerX / s), math.round(centerY / s))
 
		if onResize then onResize(frame.Size, false) end
	end))
 
	janitor:Add(UserInputService.InputEnded:Connect(function(input)
		if not resizing then return end
		if input == activeInput
			or (activeInput and activeInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1) then
			resizing = false
			resizingEdgeFeedback = false
			activeInput = nil
			if onResize then onResize(frame.Size, true) end
		end
	end))
end
 
local DRAG_THRESHOLD = 6
 
local function BaseCard(parent, height)
	local windowId, interfaceTransparency
	local ancestor = parent
	while ancestor and not windowId do
		windowId = ancestor:GetAttribute("SilentWindowId")
		ancestor = ancestor.Parent
	end
	if windowId then
		for _, window in ipairs(SilentUI._Windows) do
			if window._id == windowId then
				interfaceTransparency = window._interfaceTransparency
				break
			end
		end
	end
	local card = Instance.new("Frame")
	card.BackgroundColor3 = SilentUI.Theme.Surface
	card.BackgroundTransparency = interfaceTransparency or 0.96
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, height or 44)
	card.ZIndex = Z.Content
	card.Parent = parent
	card:SetAttribute("SilentInterfacePanel", true)
	if windowId then card:SetAttribute("SilentWindowId", windowId) end
	Corner(card, SilentUI.Theme.CornerRadiusSm)
	Stroke(card, SilentUI.Theme.Border, 1, 0.95)
	return card
end
 
local function AddLeadingIcon(card, icon, height)
	local asset = icon and ResolveIcon(icon) or ""
	if asset == "" then return 14, nil end
 
	local img = Instance.new("ImageLabel")
	img.Name = "LeadingIcon"
	img.BackgroundTransparency = 1
	img.Image = asset
	img.ImageColor3 = SilentUI.Theme.TextDim
	img.Size = UDim2.fromOffset(16, 16)
	img.AnchorPoint = Vector2.new(0, 0.5)
	img.Position = UDim2.new(0, 14, 0.5, 0)
	img.ZIndex = Z.Content + 1
	img.Parent = card
	return 14 + 16 + 10, img
end
 
local function AddTitleDesc(card, x, rightReserve, title, description, baseHeight, extraBottom)
	extraBottom = extraBottom or 0
	local hasDesc = description ~= nil and description ~= ""
	local titleH, descH, gap = 16, 14, 3
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = SilentUI.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = SilentUI.Theme.Text
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Size = UDim2.new(1, -(x + (type(rightReserve) == "function" and rightReserve() or rightReserve)), 0, titleH)
	titleLabel.Position = UDim2.fromOffset(x, 0)
	titleLabel.ZIndex = Z.Content + 1
	titleLabel.Parent = card
 
	local descLabel
	if hasDesc then
		descLabel = Instance.new("TextLabel")
		descLabel.Name = "Description"
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = SilentUI.Theme.FontRegular
		descLabel.Text = description
		descLabel.TextColor3 = SilentUI.Theme.TextDim
		descLabel.TextSize = 12
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.Size = UDim2.new(1, -(x + (type(rightReserve) == "function" and rightReserve() or rightReserve)), 0, descH)
		descLabel.Position = UDim2.fromOffset(x, titleH + gap)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = card
	end
 
	local lastWidth = -1
	local lastReserve = -1
 
	local function relayout()
		local cardW = card.AbsoluteSize.X / GetUIScale()
		if cardW <= 0 then return end
		local reserve = type(rightReserve) == "function" and rightReserve() or rightReserve
		if math.abs(cardW - lastWidth) < 1 and reserve == lastReserve then return end
		lastReserve = reserve
		titleLabel.Size = UDim2.new(1, -(x + reserve), 0, titleH)
		lastWidth = cardW
 
		local avail = math.max(cardW - x - reserve, 1)
		local realDescH = descH
		if hasDesc then
			local _, h = MeasureText(descLabel.Text, 12, avail)
			realDescH = math.max(descH, h)
			descLabel.Size = UDim2.new(1, -(x + (type(rightReserve) == "function" and rightReserve() or rightReserve)), 0, realDescH)
		end
 
		local blockH = hasDesc and (titleH + gap + realDescH) or titleH
		local topPortion = math.max(baseHeight, blockH + 18)
		card.Size = UDim2.new(1, 0, 0, topPortion + extraBottom)
 
		local top = math.floor((topPortion - blockH) / 2)
		titleLabel.Position = UDim2.fromOffset(x, top)
		if hasDesc then
			descLabel.Position = UDim2.fromOffset(x, top + titleH + gap)
		end
	end
 
	card:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	if descLabel then
		descLabel:GetPropertyChangedSignal("Text"):Connect(function()
			lastWidth = -1
			relayout()
		end)
	end
	task.defer(relayout)
 
	return titleLabel, descLabel, relayout
end
 
function Private.AddEmptyState(scroll, overlayParent, janitor)
	local emptyState = Instance.new("Frame")
	emptyState.Name = "EmptyState"
	emptyState.BackgroundTransparency = 1
	emptyState.Size = UDim2.fromScale(1, 1)
	emptyState.ZIndex = (scroll.ZIndex or 0) + 5
	emptyState.Parent = overlayParent
 
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = emptyState
 
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = ResolveIcon("frown")
	icon.ImageColor3 = SilentUI.Theme.TextDim
	icon.Size = UDim2.fromOffset(26, 26)
	icon.LayoutOrder = 1
	icon.ZIndex = emptyState.ZIndex + 1
	icon.Parent = emptyState
 
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = SilentUI.Theme.FontRegular
	label.Text = "There's nothing here yet"
	label.TextColor3 = SilentUI.Theme.TextDim
	label.TextSize = 13
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 16)
	label.LayoutOrder = 2
	label.ZIndex = emptyState.ZIndex + 1
	label.Parent = emptyState
 
	local function update()
		local hasContent = false
		for _, child in ipairs(scroll:GetChildren()) do
			local cn = child.ClassName
			if cn ~= "UIListLayout" and cn ~= "UIPadding" then
				hasContent = true
				break
			end
		end
		emptyState.Visible = not hasContent
	end
 
	janitor:Add(scroll.ChildAdded:Connect(update))
	janitor:Add(scroll.ChildRemoved:Connect(update))
	update()
 
	return emptyState
end
 
local Window = {}
Window.__index = Window
 
local Tab = {}
Tab.__index = Tab

Private.NextWindowId = 0
 
function SilentUI:CreateWindow(opts)
	opts = opts or {}
	opts.Title = opts.Title or SilentUI.Defaults.Title or "SilentUI"
	opts.Subtitle = opts.Subtitle or SilentUI.Defaults.Subtitle or nil
	local backgroundDefaults = SilentUI.Defaults.Background or {}
	if opts.BackgroundImage == nil then opts.BackgroundImage = backgroundDefaults.Image end
	if type(opts.BackgroundImage) == "number" then
		opts.BackgroundImage = "rbxassetid://" .. tostring(opts.BackgroundImage)
	elseif type(opts.BackgroundImage) == "string" and opts.BackgroundImage:match("^%d+$") then
		opts.BackgroundImage = "rbxassetid://" .. opts.BackgroundImage
	end
	if opts.BackgroundImageTransparency == nil then
		opts.BackgroundImageTransparency = backgroundDefaults.ImageTransparency or 0.22
	end
	local initialBackgroundImage = opts.BackgroundImage
	if opts.RootMode ~= nil then
		local ok, err = self:SetRootMode(opts.RootMode)
		if not ok then error(err, 2) end
	end
	if self.SetConfigFolder then self:SetConfigFolder(opts.Folder) end
	if self.LoadAutoConfig then self:LoadAutoConfig() end
	local viewport = Private.ViewportSize()
	local initialScale = GetUIScale()
	local logicalViewport = viewport / initialScale
	local size = opts.Size or UDim2.fromOffset(605, 405)
	if IsMobileDevice and opts.Size == nil then
		size = UDim2.fromOffset(
			math.floor(logicalViewport.X * 0.94),
			math.floor(logicalViewport.Y * 0.90)
		)
	end
	local maxWindowWidth = math.max(1, logicalViewport.X - 20)
	local maxWindowHeight = math.max(1, logicalViewport.Y - 20)
	local requestedWidth = size.X.Scale == 0 and size.X.Offset
		or math.floor(logicalViewport.X * size.X.Scale + size.X.Offset)
	local requestedHeight = size.Y.Scale == 0 and size.Y.Offset
		or math.floor(logicalViewport.Y * size.Y.Scale + size.Y.Offset)
	size = UDim2.fromOffset(
		math.clamp(requestedWidth, math.min(240, maxWindowWidth), maxWindowWidth),
		math.clamp(requestedHeight, math.min(200, maxWindowHeight), maxWindowHeight)
	)
	local margin = SilentUI.Theme.Margin
 
	local root = SilentUI._Root
	local jan = Janitor.new()
	local windowPosition = UDim2.fromScale(0.5, IsMobileDevice and 0.5 or 0.55)
	-- Keep the shadow outside main because main clips its children.
	local shadow = Instance.new("ImageLabel")
	shadow.Name = "WindowShadow"
	shadow.BackgroundTransparency = 1
	shadow.BorderSizePixel = 0
	shadow.Image = "rbxassetid://112971167999062"
	shadow.ImageColor3 = Color3.new(0, 0, 0)
	shadow.ImageTransparency = 0
	shadow.ScaleType = Enum.ScaleType.Slice
	shadow.SliceCenter = Rect.new(Vector2.new(112, 112), Vector2.new(147, 147))
	shadow.SliceScale = 0.75
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = windowPosition
	shadow.Size = UDim2.new(size.X.Scale, size.X.Offset + 75, size.Y.Scale, size.Y.Offset + 75)
	shadow.ZIndex = Z.Window - 1
	shadow.Parent = root
	Corner(shadow, 5)
	jan:Add(shadow)
 
	local main = Instance.new("ImageLabel")
	main.Name = "Window"
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.Position = windowPosition
	main.Size = size
	main.Image = type(initialBackgroundImage) == "string" and initialBackgroundImage or ""
	main.ImageColor3 = Color3.new(1, 1, 1)
	main.ImageTransparency = main.Image ~= "" and math.clamp(tonumber(opts.BackgroundImageTransparency) or 0.22, 0, 1) or 1
	main.ScaleType = Enum.ScaleType.Crop
	main.BackgroundColor3 = SilentUI.Theme.Background
	main.BackgroundTransparency = 1
	main.BorderSizePixel = 0
	main.ClipsDescendants = true
	main.ZIndex = Z.Window
	main.Parent = root
	Corner(main, SilentUI.Theme.CornerRadius)
	Stroke(main, SilentUI.Theme.Border, 1, 0.92)
	Private.GlassLayer(main, SilentUI.Theme.CornerRadius, 0.985)
	local windowAnimationScale = Instance.new("UIScale")
	windowAnimationScale.Name = "SilentWindowAnimationScale"
	windowAnimationScale.Scale = 1
	windowAnimationScale.Parent = main

	Private.NextWindowId += 1
	local windowId = Private.NextWindowId
	main:SetAttribute("SilentWindowId", windowId)
	main:SetAttribute("SilentThemeImageColorExempt", true)

	local function syncShadow()
		shadow.AnchorPoint = main.AnchorPoint
		shadow.Position = main.Position
		shadow.Size = UDim2.new(
			main.Size.X.Scale, main.Size.X.Offset + 75,
			main.Size.Y.Scale, main.Size.Y.Offset + 75
		)
		shadow.Visible = main.Visible
	end
	syncShadow()
	jan:Add(main:GetPropertyChangedSignal("Position"):Connect(syncShadow))
	jan:Add(main:GetPropertyChangedSignal("Size"):Connect(syncShadow))
	jan:Add(main:GetPropertyChangedSignal("AnchorPoint"):Connect(syncShadow))
	jan:Add(main:GetPropertyChangedSignal("Visible"):Connect(syncShadow))
 
	local topbar = Instance.new("Frame")
	topbar.Name = "TopBar"
	topbar.BackgroundTransparency = 1
	topbar.Size = UDim2.new(1, 0, 0, 52)
	topbar.ZIndex = Z.Content
	topbar.Parent = main
 
	local controlsHolder = Instance.new("Frame")
	controlsHolder.Name = "WindowControls"
	controlsHolder.AnchorPoint = Vector2.new(1, 0.5)
	controlsHolder.Position = UDim2.new(1, -margin, 0.5, 0)
	controlsHolder.Size = UDim2.fromOffset(120, 26)
	controlsHolder.BackgroundTransparency = 1
	controlsHolder.ZIndex = Z.Content + 1
	controlsHolder.Parent = topbar
 
	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.FillDirection = Enum.FillDirection.Horizontal
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	controlsLayout.Padding = UDim.new(0, 4)
	controlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	controlsLayout.Parent = controlsHolder
 
	local function addControl(icon, name, order, hoverColor)
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = SilentUI.Theme.Surface
		btn.BackgroundTransparency = 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.fromOffset(26, 26)
		btn.LayoutOrder = order
		btn.ZIndex = Z.Content + 1
		btn.Parent = controlsHolder
		Corner(btn, 8)
 
		local ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Image = ResolveIcon(icon)
		ic.ImageColor3 = SilentUI.Theme.TextDim
		ic.Size = UDim2.fromOffset(14, 14)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.ZIndex = Z.Content + 2
		ic.Parent = btn
 
		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = 0.9 }, 0.12)
			Tween(ic, { ImageColor3 = hoverColor or SilentUI.Theme.Text }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = 1 }, 0.12)
			Tween(ic, { ImageColor3 = SilentUI.Theme.TextDim }, 0.12)
		end))
		return btn
	end
 
	local searchBtn = addControl("search",   "SearchButton",     1)
	local minBtn    = addControl("minus",    "MinimizeButton",   2)
	local fullBtn   = addControl("maximize", "FullscreenButton", 3)
	local closeBtn  = addControl("x",        "CloseButton",      4)
 
	local titleStartX  = margin + 5
	local titleTextPad = 146
 
	local hasIcon = opts.Icon and opts.Icon ~= ""
	if hasIcon then
		local windowIcon = Instance.new("ImageLabel")
		windowIcon.Name = "WindowIcon"
		windowIcon.BackgroundTransparency = 1
		windowIcon.Image = ResolveIcon(opts.Icon)
		windowIcon.ImageColor3 = SilentUI.Theme.Text
		windowIcon.Size = UDim2.fromOffset(20, 20)
		windowIcon.AnchorPoint = Vector2.new(0, 0.5)
		windowIcon.Position = UDim2.new(0, titleStartX, 0.5, 0)
		windowIcon.ZIndex = Z.Content
		windowIcon.Parent = topbar
		titleStartX += 20 + 8
	end
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = SilentUI.Theme.Font
	titleLabel.Text = opts.Title or "Window"
	titleLabel.TextColor3 = SilentUI.Theme.Text
	titleLabel.TextSize = 16
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Position = UDim2.fromOffset(titleStartX, opts.Subtitle and 8 or 0)
	titleLabel.Size = UDim2.new(1, -titleStartX - titleTextPad, 0, 20)
	titleLabel.ZIndex = Z.Content
	titleLabel.Parent = topbar
 
	local subLabel
	if opts.Subtitle then
		subLabel = Instance.new("TextLabel")
		subLabel.Name = "Subtitle"
		subLabel.BackgroundTransparency = 1
		subLabel.FontFace = SilentUI.Theme.FontRegular
		subLabel.Text = opts.Subtitle
		subLabel.TextColor3 = SilentUI.Theme.TextDim
		subLabel.TextSize = 13
		subLabel.TextXAlignment = Enum.TextXAlignment.Left
		subLabel.TextYAlignment = Enum.TextYAlignment.Center
		subLabel.TextTruncate = Enum.TextTruncate.AtEnd
		subLabel.Position = UDim2.fromOffset(titleStartX, 28)
		subLabel.Size = UDim2.new(1, -titleStartX - titleTextPad, 0, 14)
		subLabel.ZIndex = Z.Content
		subLabel.Parent = topbar
	end
 
	local tabBar = Instance.new("ScrollingFrame")
	tabBar.Name = "TabBar"
	tabBar.BackgroundTransparency = 1
	tabBar.BorderSizePixel = 0
	tabBar.Position = UDim2.fromOffset(margin, 58)
	tabBar.Size = UDim2.new(0, 130, 1, -(58 + margin))
	tabBar.ScrollBarThickness = 0
	tabBar.ScrollingDirection = Enum.ScrollingDirection.Y
	tabBar.AutomaticCanvasSize = Enum.AutomaticSize.Y
	tabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabBar.ZIndex = Z.Content
	tabBar.Parent = main
 
	local tabBarLayout = Instance.new("UIListLayout")
	tabBarLayout.Padding = UDim.new(0, 4)
	tabBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabBarLayout.Parent = tabBar
 
	AddScrollbar(tabBar)
 
	local tabIndicatorLayer = Instance.new("Frame")
	tabIndicatorLayer.Name = "TabIndicatorLayer"
	tabIndicatorLayer.BackgroundTransparency = 1
	tabIndicatorLayer.ClipsDescendants = true
	tabIndicatorLayer.ZIndex = Z.Window
	tabIndicatorLayer.Position = tabBar.Position
	tabIndicatorLayer.Size = tabBar.Size
	tabIndicatorLayer.Parent = main
 
	local tabIndicator = Instance.new("Frame")
	tabIndicator.Name = "Indicator"
	tabIndicator.BackgroundColor3 = SilentUI.Theme.Surface
	tabIndicator.BackgroundTransparency = 1
	tabIndicator.BorderSizePixel = 0
	tabIndicator.ZIndex = Z.Window
	tabIndicator.Size = UDim2.new(1, 0, 0, 34)
	tabIndicator.Position = UDim2.new(0, 0, 0, 0)
	tabIndicator.Parent = tabIndicatorLayer
	Corner(tabIndicator, 10)
 
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundColor3 = SilentUI.Theme.Surface
	divider.BackgroundTransparency = 0.94
	divider.BorderSizePixel = 0
	divider.Position = UDim2.new(0, margin + 144, 0, 58)
	divider.Size = UDim2.new(0, 1, 1, -(58 + margin))
	divider.ZIndex = Z.Content
	divider.Parent = main
 
	local contentX = margin + 144 + 16
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.new(0, contentX, 0, 58)
	content.Size = UDim2.new(1, -contentX - margin, 1, -(58 + margin))
	content.ZIndex = Z.Content
	content.Parent = main
 
	local resizeHandle = Instance.new("ImageButton")
	resizeHandle.Name = "ResizeHandle"
	resizeHandle.BackgroundTransparency = 1
	resizeHandle.AutoButtonColor = false
	resizeHandle.Image = "rbxassetid://120997033468887"
	resizeHandle.ImageColor3 = SilentUI.Theme.TextDim
	resizeHandle.ImageTransparency = 0.35
	resizeHandle.AnchorPoint = Vector2.new(1, 1)
	resizeHandle.Position = UDim2.new(1, -4, 1, -4)
	resizeHandle.Size = UDim2.fromOffset(16, 16)
	resizeHandle.ZIndex = Z.Content + 4
	resizeHandle.Parent = main
 
	jan:Add(resizeHandle.MouseEnter:Connect(function()
		Tween(resizeHandle, { ImageTransparency = 0 }, 0.12)
	end))
	jan:Add(resizeHandle.MouseLeave:Connect(function()
		Tween(resizeHandle, { ImageTransparency = 0.35 }, 0.12)
	end))
 
	Tween(main, { BackgroundTransparency = 0.15 }, 0.6, Enum.EasingStyle.Exponential)
	if main.Image ~= "" then
		task.defer(function()
			if main.Parent then
				Tween(main, {
					ImageTransparency = math.clamp(tonumber(opts.BackgroundImageTransparency) or 0.22, 0, 1),
				}, 0.52, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			end
		end)
	end
 
	local self = setmetatable({
		_id             = windowId,
		_gui            = main,
		_backgroundImage = main,
		_backgroundImageTransparency = math.clamp(tonumber(opts.BackgroundImageTransparency) or 0.22, 0, 1),
		_animationScale = windowAnimationScale,
		_shadow         = shadow,
		_content        = content,
		_tabBar         = tabBar,
		_tabIndicatorLayer = tabIndicatorLayer,
		_tabIndicator   = tabIndicator,
		_titleLabel     = titleLabel,
		_subLabel       = subLabel,
		_tabs           = {},
		_currentTab     = nil,
		_normalSize     = size,
		_fullscreen     = false,
		_janitor        = jan,
		_state          = "open",
		_busy           = false,
		_destroyed      = false,
		_destroyCallbacksFired = false,
		_destroyCallbacks = {},
		_interfaceTransparency = nil,
		_searchIndex    = {},
		_useBlur        = opts.UseBlur ~= false,
		_defaultTabName = opts.DefaultTab,
		_tabChangeListeners = {},
	}, Window)
 
	table.insert(SilentUI._Windows, self)

	local function fitWindowToViewport()
		if self._destroyed or not main.Parent then return end
		local view = Private.ViewportSize()
		local scale = math.max(GetUIScale(), 0.01)
		local maxW = math.max(1, view.X / scale - 20)
		local maxH = math.max(1, view.Y / scale - 20)
		local preferred = self._normalSize or main.Size
		local wantedW = preferred.X.Scale == 0 and preferred.X.Offset or (view.X / scale) * preferred.X.Scale + preferred.X.Offset
		local wantedH = preferred.Y.Scale == 0 and preferred.Y.Offset or (view.Y / scale) * preferred.Y.Scale + preferred.Y.Offset
		local fitted = UDim2.fromOffset(math.max(1, math.min(wantedW, maxW)), math.max(1, math.min(wantedH, maxH)))
		if math.abs(main.AbsoluteSize.X / scale - fitted.X.Offset) > 1
			or math.abs(main.AbsoluteSize.Y / scale - fitted.Y.Offset) > 1 then
			main.Size = fitted
		end
		main.Position = UDim2.fromOffset(view.X / scale * 0.5, view.Y / scale * 0.52)
		if self._drag then self._drag.Sync() end
	end
	jan:Add(root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitWindowToViewport))
	jan:Add(GlobalScale:GetPropertyChangedSignal("Scale"):Connect(fitWindowToViewport))
	task.defer(fitWindowToViewport)

		if opts.Draggable ~= false then
		self._drag = Private.SetupSmoothDrag(main, topbar, jan)
	end
 
	if opts.Resizable ~= false then
		Private.SetupResize(main, resizeHandle, jan, {
			-- No mobile o minimo nao pode ser maior que a janela ja clampada, senao um
			-- resize devolve a janela pro tamanho cortado.
			MinSize = Vector2.new(
				math.min((opts.MinSize or Vector2.new(420, 300)).X, size.X.Offset),
				math.min((opts.MinSize or Vector2.new(420, 300)).Y, size.Y.Offset)
			),
			OnResize = function(newSize, finished)
				if self._fullscreen then return end
				if finished then
					self._normalSize = newSize
					self._sizeBeforeMinimize = newSize
				end
			end,
		})
	else
		resizeHandle.Visible = false
	end
 
	if self._useBlur then
		self._acrylic = Private.CreateWindowAcrylic(main)
		jan:Add(self._acrylic)
	end
 
	jan:Add(closeBtn.MouseButton1Click:Connect(function()
		SilentUI:Confirm({
			Title = "Close Window",
			Text = "Do you want to close this window? You will not be able to open it again. "
				.. "If you just want to hide it, use the minimize button instead.",
			ConfirmText = "Close Window",
			CancelText = "Cancel",
			Danger = true,
			Window = self,
			Callback = function(confirmed)
				if confirmed then self:Destroy() end
			end,
		})
	end))
 
	jan:Add(minBtn.MouseButton1Click:Connect(function() self:Toggle() end))
	jan:Add(fullBtn.MouseButton1Click:Connect(function() self:ToggleFullscreen() end))
	jan:Add(searchBtn.MouseButton1Click:Connect(function() self:_OpenSearch() end))
 
	jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or KeybindCapturing then return end
		if self._state ~= "open" then return end
		local ctrlDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.LeftMeta)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightMeta)
		if ctrlDown and input.KeyCode == Enum.KeyCode.K then
			self:_OpenSearch()
		end
	end))
 
	local toggleKey = opts.ToggleKeybind
	if toggleKey == nil then
		toggleKey = Enum.KeyCode.RightShift
	end
 
	if toggleKey then
		jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or KeybindCapturing then return end
			if UserInputService:GetFocusedTextBox() then return end
			if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == toggleKey then
				self:Toggle()
			end
		end))
	end
 
	if opts.ShowFloatingButton ~= false then
		local launcherGui = Instance.new("ScreenGui")
		launcherGui.Name = "SilentUIFloatingLauncher"
		launcherGui.ResetOnSpawn = false
		launcherGui.IgnoreGuiInset = true
		launcherGui.DisplayOrder = math.max(10000, (tonumber(root.DisplayOrder) or 9999) + 1)
		launcherGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		launcherGui.Parent = root.Parent or PlayerGui
		jan:Add(launcherGui)

		local launcherSurface = Instance.new("Frame")
		launcherSurface.Name = "LauncherSurface"
		launcherSurface.BackgroundTransparency = 1
		launcherSurface.Size = UDim2.fromScale(1, 1)
		launcherSurface.Active = false
		launcherSurface.Parent = launcherGui

		local configuredSize = opts.FloatingButtonSize
		if configuredSize == nil then configuredSize = opts.MobileToggleSize or opts.ToggleSize end
		local buttonWidth = 146
		local buttonHeight = 44
		if typeof(configuredSize) == "UDim2" then
			buttonWidth = configuredSize.X.Scale == 0 and configuredSize.X.Offset or buttonWidth
			buttonHeight = configuredSize.Y.Scale == 0 and configuredSize.Y.Offset or buttonHeight
		elseif tonumber(configuredSize) then
			buttonWidth = math.max(112, tonumber(configuredSize))
		end

		local launcher = Instance.new("TextButton")
		launcher.Name = "SilentUIFloatingButton"
		launcher.Text = ""
		launcher.AutoButtonColor = false
		launcher.BackgroundColor3 = SilentUI.Theme.Surface
		launcher.BackgroundTransparency = 0.10
		launcher.BorderSizePixel = 0
		launcher.Size = UDim2.fromOffset(buttonWidth, buttonHeight)
		local configuredPosition = opts.FloatingButtonPosition
			or opts.MobileTogglePosition
			or opts.TogglePosition
		launcher.Position = configuredPosition
			or UDim2.new(0.5, -math.floor(buttonWidth / 2), 0, 16)
		launcher.ZIndex = Z.Toast + 1
		launcher.Visible = false
		launcher.Parent = launcherSurface
		launcher.ClipsDescendants = true
		Corner(launcher, 12)

		local launcherBackground = Instance.new("ImageLabel")
		launcherBackground.Name = "LauncherBackground"
		launcherBackground.BackgroundTransparency = 1
		launcherBackground.Image = type(initialBackgroundImage) == "string" and initialBackgroundImage or ""
		launcherBackground.ImageColor3 = Color3.new(1, 1, 1)
		launcherBackground.ImageTransparency = launcherBackground.Image ~= ""
			and math.clamp(tonumber(backgroundDefaults.LauncherTransparency) or 0.18, 0, 1) or 1
		launcherBackground.ScaleType = Enum.ScaleType.Crop
		launcherBackground.Size = UDim2.fromScale(1, 1)
		launcherBackground.ZIndex = launcher.ZIndex
		launcherBackground.Active = false
		launcherBackground.Parent = launcher

		local launcherShade = Instance.new("Frame")
		launcherShade.Name = "LauncherBackgroundShade"
		launcherShade.BackgroundColor3 = Color3.new(0, 0, 0)
		launcherShade.BackgroundTransparency = 0.48
		launcherShade.BorderSizePixel = 0
		launcherShade.Size = UDim2.fromScale(1, 1)
		launcherShade.ZIndex = launcher.ZIndex + 1
		launcherShade.Active = false
		launcherShade.Parent = launcher

		local launcherAnimationScale = Instance.new("UIScale")
		launcherAnimationScale.Name = "SilentLauncherAnimationScale"
		launcherAnimationScale.Scale = 1
		launcherAnimationScale.Parent = launcher
		local launcherStroke = Stroke(launcher, SilentUI.Theme.Border, 1, 0.28)

		local logoHolder = Instance.new("Frame")
		logoHolder.Name = "SilentUIMark"
		logoHolder.BackgroundTransparency = 1
		logoHolder.Position = UDim2.fromOffset(11, math.floor((buttonHeight - 24) / 2))
		logoHolder.Size = UDim2.fromOffset(24, 24)
		logoHolder.ZIndex = launcher.ZIndex + 2
		logoHolder.Parent = launcher

		local launcherLogoText
		local toggleImage = opts.FloatingButtonImage or opts.MobileToggleImage or opts.ToggleImage
		if type(toggleImage) == "string" and toggleImage ~= "" then
			local image = Instance.new("ImageLabel")
			image.Name = "LogoImage"
			image.BackgroundTransparency = 1
			image.Image = toggleImage
			image.ScaleType = Enum.ScaleType.Fit
			image.Size = UDim2.fromScale(1, 1)
			image.ZIndex = logoHolder.ZIndex + 1
			image.Parent = logoHolder
		else
			local logoText = Instance.new("TextLabel")
			logoText.Name = "LogoText"
			logoText.BackgroundTransparency = 1
			logoText.FontFace = SilentUI.Theme.Font
			logoText.Text = "S"
			logoText.TextColor3 = SilentUI.Theme.Accent
			logoText.TextSize = 23
			logoText.TextXAlignment = Enum.TextXAlignment.Center
			logoText.TextYAlignment = Enum.TextYAlignment.Center
			logoText.Size = UDim2.fromScale(1, 1)
			logoText.ZIndex = logoHolder.ZIndex + 1
			logoText.Parent = logoHolder
			launcherLogoText = logoText
		end
		self._launcherLogoText = launcherLogoText

		local launcherTitle = Instance.new("TextLabel")
		launcherTitle.Name = "LauncherTitle"
		launcherTitle.BackgroundTransparency = 1
		launcherTitle.FontFace = SilentUI.Theme.Font
		launcherTitle.Text = tostring(opts.FloatingButtonTitle or "SILENTUI")
		launcherTitle.TextColor3 = SilentUI.Theme.Text
		launcherTitle.TextSize = 11
		launcherTitle.TextXAlignment = Enum.TextXAlignment.Left
		launcherTitle.TextYAlignment = Enum.TextYAlignment.Center
		launcherTitle.TextTruncate = Enum.TextTruncate.AtEnd
		launcherTitle.Position = UDim2.fromOffset(45, 5)
		launcherTitle.Size = UDim2.new(1, -55, 0, 18)
		launcherTitle.ZIndex = launcher.ZIndex + 2
		launcherTitle.Parent = launcher
		self._launcherTitle = launcherTitle

		local launcherHint = Instance.new("TextLabel")
		launcherHint.Name = "LauncherHint"
		launcherHint.BackgroundTransparency = 1
		launcherHint.FontFace = SilentUI.Theme.FontRegular
		launcherHint.Text = tostring(opts.FloatingButtonSubtitle or "ABRIR PANEL")
		launcherHint.TextColor3 = SilentUI.Theme.TextDim
		launcherHint.TextSize = 8
		launcherHint.TextXAlignment = Enum.TextXAlignment.Left
		launcherHint.TextYAlignment = Enum.TextYAlignment.Center
		launcherHint.Position = UDim2.fromOffset(45, 23)
		launcherHint.Size = UDim2.new(1, -55, 0, 13)
		launcherHint.ZIndex = launcher.ZIndex + 2
		launcherHint.Parent = launcher

		self._launcher = launcher
		self._launcherBackground = launcherBackground
		self._launcherAnimationScale = launcherAnimationScale
		self._launcherGui = launcherGui
		self._launcherSurface = launcherSurface
		self._launcherStroke = launcherStroke

		local launcherMoved = configuredPosition ~= nil
		local function clampLauncher()
			local bounds = launcherSurface.AbsoluteSize
			local sizeNow = launcher.AbsoluteSize
			if bounds.X < 1 or bounds.Y < 1 or sizeNow.X < 1 or sizeNow.Y < 1 then return end
			local x = launcher.Position.X.Scale * bounds.X + launcher.Position.X.Offset
			local y = launcher.Position.Y.Scale * bounds.Y + launcher.Position.Y.Offset
			launcher.Position = UDim2.fromOffset(
				math.clamp(x, 0, math.max(0, bounds.X - sizeNow.X)),
				math.clamp(y, 0, math.max(0, bounds.Y - sizeNow.Y))
			)
		end

		local function fitLauncher()
			local bounds = launcherSurface.AbsoluteSize
			if bounds.X < 1 or bounds.Y < 1 then return end
			local availableWidth = math.max(1, bounds.X - 12)
			local availableHeight = math.max(1, bounds.Y - 12)
			local responsiveWidth = math.min(buttonWidth, availableWidth)
			local responsiveHeight = math.min(buttonHeight, availableHeight)
			launcher.Size = UDim2.fromOffset(responsiveWidth, responsiveHeight)
			local showText = responsiveWidth >= 118 and responsiveHeight >= 38
			launcherTitle.Visible = showText
			launcherHint.Visible = showText
			if showText then
				if launcherLogoText then launcherLogoText.TextSize = 23 end
				logoHolder.Position = UDim2.fromOffset(11, math.floor((responsiveHeight - 24) / 2))
				logoHolder.Size = UDim2.fromOffset(24, 24)
				launcherTitle.Position = UDim2.fromOffset(45, 5)
				launcherTitle.Size = UDim2.new(1, -55, 0, 18)
				launcherHint.Position = UDim2.fromOffset(45, 23)
				launcherHint.Size = UDim2.new(1, -55, 0, 13)
			else
				local iconSize = math.max(1, math.min(24, responsiveHeight - 6, responsiveWidth - 8))
				logoHolder.Size = UDim2.fromOffset(iconSize, iconSize)
				logoHolder.Position = UDim2.new(0.5, -iconSize / 2, 0.5, -iconSize / 2)
				if launcherLogoText then launcherLogoText.TextSize = math.max(8, iconSize * 0.92) end
				launcherTitle.Size = UDim2.fromOffset(0, 0)
				launcherHint.Size = UDim2.fromOffset(0, 0)
			end
			if not launcherMoved then
				launcher.Position = UDim2.new(0.5, -math.floor(responsiveWidth / 2), 0.5, -math.floor(responsiveHeight / 2))
			end
			clampLauncher()
		end
		jan:Add(launcherSurface:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitLauncher))
		task.defer(fitLauncher)

		local dragInput, dragStart, dragStartPosition, dragged
		local launcherEdgeFeedback = false
		jan:Add(launcher.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch
				and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			if dragInput then return end
			dragInput = input
			dragStart = input.Position
			dragStartPosition = launcher.Position
			dragged = false
		end))

		jan:Add(UserInputService.InputChanged:Connect(function(input)
			if not dragInput then return end
			local isTrackedInput = input == dragInput
				or (dragInput.UserInputType == Enum.UserInputType.MouseButton1
					and input.UserInputType == Enum.UserInputType.MouseMovement)
			if not isTrackedInput then return end

			local delta = input.Position - dragStart
			if not dragged and delta.Magnitude > 5 then
				dragged = true
				launcherMoved = true
			end
			if dragged then
				local bounds = launcherSurface.AbsoluteSize
				local sizeNow = launcher.AbsoluteSize
				local rawX = dragStartPosition.X.Scale * bounds.X + dragStartPosition.X.Offset + delta.X
				local rawY = dragStartPosition.Y.Scale * bounds.Y + dragStartPosition.Y.Offset + delta.Y
				local maxX = math.max(0, bounds.X - sizeNow.X)
				local maxY = math.max(0, bounds.Y - sizeNow.Y)
				local targetX = math.clamp(rawX, 0, maxX)
				local targetY = math.clamp(rawY, 0, maxY)
				local outside = math.abs(rawX - targetX) > 1 or math.abs(rawY - targetY) > 1
				if outside and not launcherEdgeFeedback then
					launcherEdgeFeedback = true
					Private.PlayEdgeBounce(launcher)
				elseif not outside then
					launcherEdgeFeedback = false
				end
				launcher.Position = UDim2.fromOffset(targetX, targetY)
			end
		end))

		jan:Add(UserInputService.InputEnded:Connect(function(input)
			if input ~= dragInput
				and not (dragInput and dragInput.UserInputType == Enum.UserInputType.MouseButton1
					and input.UserInputType == Enum.UserInputType.MouseButton1) then
				return
			end
			local shouldOpen = not dragged
			dragInput, dragStart, dragStartPosition, dragged = nil, nil, nil, nil
			launcherEdgeFeedback = false
			if shouldOpen and self._state == "closed" then
				self:Open()
			end
		end))

		jan:Add(launcher.MouseEnter:Connect(function()
			Tween(launcher, { BackgroundTransparency = 0.03 }, 0.12)
			if launcherStroke then Tween(launcherStroke, { Transparency = 0.08 }, 0.12) end
		end))
		jan:Add(launcher.MouseLeave:Connect(function()
			Tween(launcher, { BackgroundTransparency = 0.10 }, 0.12)
			if launcherStroke then Tween(launcherStroke, { Transparency = 0.28 }, 0.12) end
		end))
	end
	if initialBackgroundImage and initialBackgroundImage ~= "" and backgroundDefaults.UseImageAccent == true then
		task.defer(function()
			if not self._destroyed then
				local accentOk, accentError = SilentUI:SetBackgroundAccentFromImage(initialBackgroundImage)
				if not accentOk then warn("[SilentUI] initial background accent unavailable: " .. tostring(accentError)) end
			end
		end)
	end

    -- SilentUI's shortcuts are created automatically and stay isolated from
    -- AddDockButton calls made by scripts using the library.
    if opts.LibraryDock ~= false then
        self:AddSpotifyPanel(opts.Spotify or SilentUI.Defaults.Spotify or {})
        self:AddUserSettingsPanel(opts.UserSettings or SilentUI.Defaults.UserSettings or {})
        self:AddDiscordDockButton()
    end
	return self
end

function Window:SetTitle(title, subtitle)
	if self._titleLabel then self._titleLabel.Text = title or self._titleLabel.Text end
	if subtitle and self._subLabel then self._subLabel.Text = subtitle end
end
 
function Window:IsOpen()
	return self._state == "open"
end

function Window:CreateScope()
	local scope = SilentUI:CreateScope()
	self:OnDestroy(function() scope:Destroy() end)
	return scope
end

function Private.FireWindowDestroyCallbacks(window)
	if window._destroyCallbacksFired then return end
	window._destroyCallbacksFired = true
	local callbacks = window._destroyCallbacks or {}
	window._destroyCallbacks = {}
	for _, entry in ipairs(callbacks) do
		if entry.Connected then
			entry.Connected = false
			if entry.Connection then entry.Connection.Connected = false end
			local ok, err = pcall(entry.Callback, window)
			if not ok then warn("[SilentUI] OnDestroy callback error: " .. tostring(err)) end
		end
	end
end

function Window:OnDestroy(callback)
	assert(type(callback) == "function", "OnDestroy expects a callback")
	if self._destroyed then
		local ok, err = pcall(callback, self)
		if not ok then warn("[SilentUI] OnDestroy callback error: " .. tostring(err)) end
		return { Connected = false, Disconnect = function() end }
	end
	local entry = { Callback = callback, Connected = true }
	local callbacks = self._destroyCallbacks
	table.insert(callbacks, entry)
	local connection = { Connected = true }
	entry.Connection = connection
	function connection:Disconnect()
		if not self.Connected then return end
		self.Connected = false
		entry.Connected = false
		local index = table.find(callbacks, entry)
		if index then table.remove(callbacks, index) end
	end
	return connection
end

function Private.IsValidImageReference(image)
	return type(image) == "string"
		and (image == "" or image:match("^rbxassetid://%d+$") or image:match("^rbxasset://%S+$") or image:match("^https?://%S+$"))
end

function Private.SampleImageAccent(imageReference)
    if type(imageReference) == "number" then
        imageReference = "rbxassetid://" .. tostring(imageReference)
    elseif type(imageReference) == "string" and imageReference:match("^%d+$") then
        imageReference = "rbxassetid://" .. imageReference
    end
    if type(imageReference) ~= "string" or imageReference == "" then
        return nil, "No background image is configured"
    end

    local createOk, editableOrError = pcall(function()
        return AssetService:CreateEditableImageAsync(Content.fromUri(imageReference))
    end)
    if not createOk or not editableOrError then
        return nil, "EditableImage access may be denied by asset ownership or experience settings: "
            .. tostring(editableOrError)
    end

    local editable = editableOrError
    local readOk, pixelsOrError = pcall(function()
        local size = editable.Size
        return editable:ReadPixelsBuffer(Vector2.zero, size), size
    end)
    if not readOk then
        pcall(function() editable:Destroy() end)
        return nil, "EditableImage pixels could not be read: " .. tostring(pixelsOrError)
    end

    local pixels, size = pixelsOrError, editable.Size
    local width = math.max(1, math.floor(size.X))
    local height = math.max(1, math.floor(size.Y))
    local readPixelOk, colorOrError = pcall(function()
        local totalR, totalG, totalB, samples = 0, 0, 0, 0
        local stepX = math.max(1, math.floor(width / 24))
        local stepY = math.max(1, math.floor(height / 24))
        for y = math.floor(height * 0.15), math.floor(height * 0.85), stepY do
            for x = math.floor(width * 0.15), math.floor(width * 0.85), stepX do
                local offset = (y * width + x) * 4
                local r = buffer.readu8(pixels, offset)
                local g = buffer.readu8(pixels, offset + 1)
                local b = buffer.readu8(pixels, offset + 2)
                local a = buffer.readu8(pixels, offset + 3)
                if a > 48 then
                    totalR += r
                    totalG += g
                    totalB += b
                    samples += 1
                end
            end
        end
        if samples == 0 then error("image has no visible sample pixels") end
        return Color3.fromRGB(
            math.floor(totalR / samples + 0.5),
            math.floor(totalG / samples + 0.5),
            math.floor(totalB / samples + 0.5)
        )
    end)
    pcall(function() editable:Destroy() end)
    if not readPixelOk then return nil, tostring(colorOrError) end
    return colorOrError
end

function Private.ApplyBackgroundAccent(color)
    if typeof(color) ~= "Color3" then return false, "invalid accent color" end
    return SilentUI:SetTheme({ Accent = color })
end

function SilentUI:SetBackgroundAccentFromImage(imageReference)
    local color, err = Private.SampleImageAccent(imageReference)
    if not color then return false, err end
    local ok, setError = Private.ApplyBackgroundAccent(color)
    if not ok then return false, setError end
    self.BackgroundImageAccent = color
    return true, color
end

function Window:SetBackgroundImage(image)
    if self._destroyed then return false, "window has been destroyed" end

    if type(image) == "number" then
        image = "rbxassetid://" .. tostring(image)
    elseif type(image) == "string" and image:match("^%d+$") then
        image = "rbxassetid://" .. image
    end
    if image == "" then image = nil end
    if image ~= nil and not Private.IsValidImageReference(image) then
        return false, "background must be a Roblox asset ID or an HTTP(S) image URL"
    end

    local defaults = SilentUI.Defaults.Background or {}
    local windowTransparency = math.clamp(
        tonumber(self._backgroundImageTransparency or defaults.ImageTransparency) or 0.22, 0, 1
    )
    local launcherTransparency = math.clamp(
        tonumber(defaults.LauncherTransparency) or 0.18, 0, 1
    )

    if self._backgroundImage then
        self._backgroundImage.Image = image or ""
        self._backgroundImage.ImageTransparency = 1
        if image then
            Tween(self._backgroundImage, { ImageTransparency = windowTransparency }, 0.38,
                Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        end
    end

    if self._launcherBackground then
        self._launcherBackground.Image = image or ""
        self._launcherBackground.ImageTransparency = 1
        if image then
            Tween(self._launcherBackground, { ImageTransparency = launcherTransparency }, 0.38,
                Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        end
    end

    self._backgroundImageReference = image or ""
    local backgroundDefaults = SilentUI.Defaults.Background or {}
    if image and backgroundDefaults.UseImageAccent == true then
        task.defer(function()
            if not self._destroyed then
                local accentOk, accent = SilentUI:SetBackgroundAccentFromImage(image)
                if not accentOk then warn("[SilentUI] background accent extraction skipped: " .. tostring(accent)) end
            end
        end)
    end
    return true
end

function Window:SetBackgroundImageTransparency(value)
    if self._destroyed then return false, "window has been destroyed" end
    if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
        return false, "transparency must be a number between 0 and 1"
    end
    self._backgroundImageTransparency = value
    local defaults = SilentUI.Defaults.Background or {}
    local launcherTransparency = math.clamp(tonumber(defaults.LauncherTransparency) or 0.18, 0, 1)
    if self._backgroundImage then
        self._backgroundImage.ImageTransparency = value
    end
    if self._launcherBackground then
        self._launcherBackground.ImageTransparency = math.min(1, launcherTransparency + (value - (tonumber(defaults.ImageTransparency) or 0.22)))
    end
    return true
end

function Window:SetInterfaceTransparency(value)
	if self._destroyed then return false, "window has been destroyed" end
	if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
		return false, "transparency must be a number between 0 and 1"
	end
	self._interfaceTransparency = value
	self._gui.BackgroundTransparency = value
	local root = SilentUI._Root
	if root then
		for _, instance in ipairs(root:GetDescendants()) do
			if instance:GetAttribute("SilentWindowId") == self._id and instance:GetAttribute("SilentInterfacePanel") then
				instance.BackgroundTransparency = value
			end
		end
	end
	return true
end
 
function Window:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	if self._launcher then self._launcher.Visible = false end
	if self._launcherGui then self._launcherGui.Enabled = false end
	Private.FireWindowDestroyCallbacks(self)
 
	local idx = table.find(SilentUI._Windows, self)
	if idx then table.remove(SilentUI._Windows, idx) end
 
	Private.CloseAnyOpenPopup()
 
	local gui = self._gui
 
	Tween(gui, {
		Size = UDim2.new(gui.Size.X.Scale, gui.Size.X.Offset, 0, 0),
	}, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	Tween(gui, { BackgroundTransparency = 1 }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	if self._shadow then
		Tween(self._shadow, { ImageTransparency = 1 }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	end
 
	task.delay(0.34, function()
		self._janitor:Destroy()
		if gui then gui:Destroy() end
	end)
end
 
function Window:Toggle()
	if self._destroyed or self._busy then return end
	if self._state == "open" then
		self:Close()
	else
		self:Open()
	end
end
 
function Window:Close()
	if self._destroyed or self._busy or self._state ~= "open" then return end
	self._busy = true
	self._state = "closed"
	Private.CloseAnyOpenPopup()

	local gui = self._gui
	self._sizeBeforeMinimize = self._fullscreen
		and UDim2.new(0.94, 0, 0.9, 0)
		or (self._normalSize or gui.Size)

	if self._animationScale then
		self._animationScale.Scale = 1
		Tween(self._animationScale, { Scale = 0.94 }, 0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	end
	Tween(gui, { BackgroundTransparency = 1 }, 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	if self._backgroundImage then
		Tween(self._backgroundImage, { ImageTransparency = 1 }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	end
	if self._shadow then
		Tween(self._shadow, { ImageTransparency = 1 }, 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	end

	task.delay(0.27, function()
		if self._destroyed then return end
		if self._state == "closed" and gui and gui.Parent then
			gui.Visible = false
			if self._animationScale then self._animationScale.Scale = 1 end
			if self._launcher then
				self._launcher.Visible = true
				if self._launcherAnimationScale then
					self._launcherAnimationScale.Scale = 0.88
					Tween(self._launcherAnimationScale, { Scale = 1 }, 0.34,
						Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				end
			end
		end
		self._busy = false
	end)
end

function Window:Open()
	if self._destroyed or self._busy or self._state ~= "closed" then return end
	self._busy = true
	self._state = "open"
	if self._launcher then self._launcher.Visible = false end

	local gui = self._gui
	gui.Visible = true
	if self._animationScale then
		self._animationScale.Scale = 0.90
		Tween(self._animationScale, { Scale = 1 }, 0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	if self._shadow then
		self._shadow.Visible = true
		self._shadow.ImageTransparency = 1
		Tween(self._shadow, { ImageTransparency = 0 }, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end
	if self._backgroundImage and self._backgroundImage.Image ~= "" then
		self._backgroundImage.ImageTransparency = 1
		Tween(self._backgroundImage, {
			ImageTransparency = self._backgroundImageTransparency or 0.22,
		}, 0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end

	local targetSize = self._sizeBeforeMinimize or self._normalSize
	Tween(gui, {
		Size = targetSize,
		BackgroundTransparency = self._interfaceTransparency or 0.15,
	}, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	task.delay(0.35, function()
		self._busy = false
		if self._drag then self._drag.Sync() end
	end)
end

function Window:ToggleFullscreen()
	if self._destroyed then return end
	local gui = self._gui
	self._fullscreen = not self._fullscreen
 
	Private.CloseAnyOpenPopup()
 
	if self._fullscreen then
		self._preFullscreenPosition = gui.Position
		Tween(gui, {
			Size = UDim2.new(0.94, 0, 0.9, 0),
			Position = UDim2.fromScale(0.5, 0.5),
		}, 0.35, Enum.EasingStyle.Quint)
	else
		Tween(gui, {
			Size = self._normalSize,
			Position = self._preFullscreenPosition or UDim2.fromScale(0.5, 0.55),
		}, 0.35, Enum.EasingStyle.Quint)
	end
 
	task.delay(0.36, function()
		if self._drag then self._drag.Sync() end
	end)
end
 
function Window:AddTabLine()
	local holder = Instance.new("Frame")
	holder.Name = "TabLine"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 9)
	holder.ZIndex = Z.Content
	holder.Parent = self._tabBar
 
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.new(0, 4, 0.5, 0)
	line.Size = UDim2.new(1, -8, 0, 1)
	line.BackgroundColor3 = SilentUI.Theme.Surface
	line.BackgroundTransparency = 0.92
	line.BorderSizePixel = 0
	line.ZIndex = Z.Content
	line.Parent = holder
 
	return holder
end
 
Private.DOCK_ICON_SIZE = 28
Private.DOCK_HEIGHT    = 34
 
local function EnsureDockLayoutSpace(window)
    if window._dockLayoutApplied then return end
    local margin = SilentUI.Theme.Margin
    local shrunkSize = UDim2.new(0, 130, 1, -(58 + margin + Private.DOCK_HEIGHT + 10))
    window._tabBar.Size = shrunkSize
    window._tabIndicatorLayer.Size = shrunkSize
    window._dockLayoutApplied = true
end

local function CreateDockContainer(window, owner)
    local libraryOwned = owner == "library"
    local field = libraryOwned and "_libraryDock" or "_developerDock"
    if window[field] then return window[field] end

    EnsureDockLayoutSpace(window)

    local dock
    if libraryOwned then
        dock = Instance.new("Frame")
        dock.Name = "SilentUILibraryDock"
        dock.AnchorPoint = Vector2.new(0, 1)
        dock.Position = UDim2.new(0, SilentUI.Theme.Margin, 1, -SilentUI.Theme.Margin)
        dock.Size = UDim2.fromOffset(108, Private.DOCK_HEIGHT)
    else
        dock = Instance.new("ScrollingFrame")
        dock.Name = "ScriptDeveloperDock"
        dock.AnchorPoint = Vector2.new(1, 1)
        dock.Position = UDim2.new(1, -SilentUI.Theme.Margin, 1, -SilentUI.Theme.Margin)
        dock.Size = UDim2.new(0.42, 0, 0, Private.DOCK_HEIGHT)
        dock.CanvasSize = UDim2.new(0, 0, 0, 0)
        dock.AutomaticCanvasSize = Enum.AutomaticSize.X
        dock.ScrollingDirection = Enum.ScrollingDirection.X
        dock.ScrollBarThickness = 0
        dock.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
        dock.ClipsDescendants = true
    end

    dock.BackgroundTransparency = 1
    dock.BorderSizePixel = 0
    dock.ZIndex = Z.Content
    dock.Parent = window._gui

    local dockLayout = Instance.new("UIListLayout")
    dockLayout.FillDirection = Enum.FillDirection.Horizontal
    dockLayout.Padding = UDim.new(0, 6)
    dockLayout.SortOrder = Enum.SortOrder.LayoutOrder
    dockLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    dockLayout.Parent = dock

    window[field] = dock
    if libraryOwned then
        -- Compatibility alias for older internal code.
        window._dock = dock
    end
    return dock
end

function Window:AddDockButton(opts)
    opts = opts or {}
    local jan = self._janitor
    local owner = string.lower(tostring(opts.Owner or opts.Group or "script"))
    local libraryOwned = owner == "library" or owner == "silentui"
    local dock = CreateDockContainer(self, libraryOwned and "library" or "script")

    self._dockButtonSerial = (self._dockButtonSerial or 0) + 1
    local order = tonumber(opts.Order) or self._dockButtonSerial

    local btn = Instance.new("TextButton")
    btn.Name = opts.Name or (libraryOwned and "SilentUIDockButton" or "ScriptDockButton")
    local fallbackGlyph = tostring(opts.FallbackText or "")
    btn.Text = fallbackGlyph
    btn.TextTransparency = 0
    btn.AutoButtonColor = false
    btn.BackgroundColor3 = typeof(opts.BackgroundColor3) == "Color3"
        and opts.BackgroundColor3 or SilentUI.Theme.Surface
    btn.BackgroundTransparency = math.clamp(tonumber(opts.BackgroundTransparency) or 0.95, 0, 1)
    btn.BorderSizePixel = 0
    btn.Size = UDim2.fromOffset(Private.DOCK_ICON_SIZE, Private.DOCK_ICON_SIZE)
    btn.LayoutOrder = order
    btn.ZIndex = Z.Content + 1
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 16
    btn.TextColor3 = typeof(opts.FallbackTextColor3) == "Color3"
        and opts.FallbackTextColor3 or SilentUI.Theme.Text
    btn.Parent = dock
    Corner(btn, 8)

    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.BackgroundTransparency = 1
    local hasCustomImage = type(opts.Image) == "string" and opts.Image ~= ""
    local iconSource = opts.Icon
    local resolvedImage = hasCustomImage and opts.Image
        or (iconSource and ResolveIcon(iconSource) or "")
    icon.Image = resolvedImage
    icon.ImageColor3 = typeof(opts.IconColor3) == "Color3"
        and opts.IconColor3 or (hasCustomImage and Color3.new(1, 1, 1) or SilentUI.Theme.TextDim)
    icon.Size = UDim2.fromOffset(17, 17)
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    icon.Position = UDim2.fromScale(0.5, 0.5)
    icon.ZIndex = btn.ZIndex + 1
    icon.Visible = resolvedImage ~= ""
    icon.Parent = btn
    if hasCustomImage then icon:SetAttribute("SilentThemeColorExempt", true) end

    -- Some executors cannot load a valid Roblox image asset. Keep a text
    -- fallback ready, and only remove it when IsLoaded confirms the icon loaded.
    if icon.Image == "" then
        btn.Text = fallbackGlyph
        icon.Visible = false
    elseif fallbackGlyph ~= "" then
        task.spawn(function()
            local deadline = os.clock() + 5
            while icon.Parent and btn.Parent and os.clock() < deadline do
                local ok, loaded = pcall(function() return icon.IsLoaded end)
                if ok and loaded == true then
                    btn.Text = ""
                    return
                end
                task.wait(0.15)
            end
            if not icon.Parent or not btn.Parent then return end
            local ok, loaded = pcall(function() return icon.IsLoaded end)
            if not ok or loaded ~= true then
                icon.Visible = false
                btn.Text = fallbackGlyph
            else
                btn.Text = ""
            end
        end)
    end

    local active = false
    local normalTransparency = btn.BackgroundTransparency
    local activeTransparency = math.min(normalTransparency, 0.78)

    jan:Add(btn.MouseEnter:Connect(function()
        if active then return end
        Tween(btn, { BackgroundTransparency = math.min(normalTransparency, 0.84) }, 0.12)
        if not hasCustomImage then Tween(icon, { ImageColor3 = SilentUI.Theme.Text }, 0.12) end
    end))
    jan:Add(btn.MouseLeave:Connect(function()
        if active then return end
        Tween(btn, { BackgroundTransparency = normalTransparency }, 0.12)
        if not hasCustomImage then Tween(icon, { ImageColor3 = SilentUI.Theme.TextDim }, 0.12) end
    end))
    jan:Add(btn.Activated:Connect(function()
        if opts.Callback then task.spawn(opts.Callback) end
    end))

    return {
        Instance = btn,
        Icon = icon,
        Owner = libraryOwned and "library" or "script",
        SetActive = function(_, isActive)
            active = isActive and true or false
            Tween(btn, { BackgroundTransparency = active and activeTransparency or normalTransparency }, 0.12)
            if not hasCustomImage then
                Tween(icon, { ImageColor3 = active and SilentUI.Theme.Text or SilentUI.Theme.TextDim }, 0.12)
            end
        end,
        Destroy = function()
            if btn and btn.Parent then btn:Destroy() end
        end,
    }
end

Private.CHAT_CODE_FONT = "rbxasset://fonts/families/RobotoMono.json"
 
function Private.EscapeRichText(text)
	text = text:gsub("&", "&amp;")
	text = text:gsub("<", "&lt;")
	text = text:gsub(">", "&gt;")
	return text
end
 
function Private.MarkdownToRichText(text)
	text = Private.EscapeRichText(text)
 
	text = text:gsub("`([^`\n]+)`", "<font family=\"" .. CHAT_CODE_FONT .. "\">%1</font>")
 
	text = text:gsub("%*%*(.-)%*%*", "<b>%1</b>")
	text = text:gsub("__(.-)__", "<b>%1</b>")
 
	text = text:gsub("%*([^%s*][^*]-)%*", "<i>%1</i>")
	text = text:gsub("_([^%s_][^_]-)_", "<i>%1</i>")
 
	return text
end
 
function Private.SplitMessageSegments(text)
	local segments = {}
	local pos = 1
	while true do
		local s, e, lang, code = text:find("```(%w*)\n?(.-)```", pos)
		if not s then
			local rest = text:sub(pos)
			if rest ~= "" then table.insert(segments, { kind = "text", content = rest }) end
			break
		end
		if s > pos then
			local before = text:sub(pos, s - 1)
			if before:match("%S") then
				table.insert(segments, { kind = "text", content = before })
			end
		end
		code = code:gsub("^%s+", ""):gsub("%s+$", "")
		table.insert(segments, { kind = "code", lang = lang ~= "" and lang or "lua", content = code })
		pos = e + 1
	end
	if #segments == 0 then
		table.insert(segments, { kind = "text", content = text })
	end
	return segments
end
 
Private.LUA_KEYWORDS = {
	["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
	["end"] = true, ["false"] = true, ["for"] = true, ["function"] = true, ["if"] = true,
	["in"] = true, ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
	["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
	["until"] = true, ["while"] = true, ["continue"] = true,
}
 
function Private.HighlightLua(code)
	local out = {}
	local n = #code
	local i = 1
 
	while i <= n do
		local c = code:sub(i, i)
 
		if code:sub(i, i + 3) == "--[[" then
			local closeEnd = select(2, code:find("%]%]", i + 4))
			local stop = closeEnd or n
			out[#out + 1] = "<font color=\"#6A9955\">" .. code:sub(i, stop) .. "</font>"
			i = stop + 1
		elseif code:sub(i, i + 1) == "--" then
			local nl = code:find("\n", i, true)
			local stop = (nl or (n + 1)) - 1
			out[#out + 1] = "<font color=\"#6A9955\">" .. code:sub(i, stop) .. "</font>"
			i = stop + 1
		elseif c == '"' or c == "'" then
			local quote = c
			local j = i + 1
			while j <= n do
				local jc = code:sub(j, j)
				if jc == "\\" then
					j = j + 2
				elseif jc == quote or jc == "\n" then
					break
				else
					j = j + 1
				end
			end
			j = math.min(j, n)
			out[#out + 1] = "<font color=\"#CE9178\">" .. code:sub(i, j) .. "</font>"
			i = j + 1
		elseif c:match("%a") or c == "_" then
			local j = i
			while j <= n and code:sub(j, j):match("[%w_]") do j = j + 1 end
			local word = code:sub(i, j - 1)
			out[#out + 1] = Private.LUA_KEYWORDS[word] and ("<font color=\"#C586C0\">" .. word .. "</font>") or word
			i = j
		elseif c:match("%d") then
			local j = i
			while j <= n and code:sub(j, j):match("[%d%.]") do j = j + 1 end
			out[#out + 1] = "<font color=\"#B5CEA8\">" .. code:sub(i, j - 1) .. "</font>"
			i = j
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
 
	return table.concat(out)
end
 
function Window:AddPanelTab(opts)
	opts = opts or {}
	local self_ = self
	local tabObj = self:AddTab({
		Name   = opts.Name,
		Icon   = opts.Icon,
		Hidden = opts.Hidden ~= false,
	})
	tabObj._page.Visible = false
	local staleEmptyState = tabObj._group:FindFirstChild("EmptyState")
	if staleEmptyState then staleEmptyState.Visible = false end
 
	if opts.OnToggle then
		table.insert(self._tabChangeListeners, function(selected)
			task.spawn(opts.OnToggle, selected == tabObj)
		end)
	end
 
	local lastRealTab = nil
	local function openPanel()
		if self_._currentTab == tabObj then return end
		if self_._currentTab and not self_._currentTab.Hidden then
			lastRealTab = self_._currentTab
		end
		tabObj._select()
	end
	local function closePanel()
		if self_._currentTab ~= tabObj then return end
		if lastRealTab and not lastRealTab.Hidden then
			lastRealTab._select()
		elseif self_._tabs[1] and self_._tabs[1] ~= tabObj then
			self_._tabs[1]._select()
		end
	end
 
	return {
		Instance = tabObj._group,
		Tab = tabObj,
		Open = openPanel,
		Close = closePanel,
		Toggle = function()
			if self_._currentTab == tabObj then closePanel() else openPanel() end
		end,
		IsOpen = function() return self_._currentTab == tabObj end,
	}
end
 
function Window:AddBackgroundPanel(opts)
    opts = opts or {}
    if self._destroyed then return nil end

    local tabObj = self:AddTab({
        Name = opts.Name or "Background",
        Icon = opts.Icon or "image",
        Hidden = opts.Hidden == true,
    })

    local configured = SilentUI.Defaults.Background or {}
    local configuredImage = opts.Image
    if configuredImage == nil then configuredImage = configured.Image end
    local imageLabel = type(configuredImage) == "number" and ("rbxassetid://" .. tostring(configuredImage))
        or tostring(configuredImage or "")

    tabObj:AddParagraph({
        Title = opts.Title or "Background",
        Icon = "image",
        Text = opts.Description or (
            imageLabel ~= ""
                and "Imagen configurada desde SilentUI.Defaults.Background.Image."
                or "No hay imagen configurada. Define Background.Image en el bloque de distribución al inicio del archivo."
        ),
    })

    tabObj:AddInfoGrid({
        Title = "Configuración actual",
        Description = "Estos valores se controlan desde el bloque de distribución del código.",
        Columns = 2,
        Items = {
            { Label = "Imagen", Value = imageLabel ~= "" and "Configurada" or "Sin imagen" },
            { Label = "Acento", Value = configured.UseImageAccent and "Desde imagen" or "Tema actual" },
        },
    })

    tabObj:AddSlider({
        Text = "Transparencia del fondo",
        Description = "Ajusta la intensidad de la imagen en la ventana y en el botón flotante.",
        Min = 0,
        Max = 100,
        Increment = 1,
        Default = math.floor(math.clamp(tonumber(self._backgroundImage.ImageTransparency) or 0, 0, 1) * 100 + 0.5),
        Suffix = "%",
        Callback = function(value)
            self:SetBackgroundImageTransparency(math.clamp(value, 0, 100) / 100)
        end,
    })

    tabObj:AddToggle({
        Text = "Color de acento desde la imagen",
        Description = "Intenta extraer un color representativo del fondo. Requiere soporte EditableImage y permisos del asset.",
        Default = configured.UseImageAccent == true,
        Callback = function(enabled)
            configured.UseImageAccent = enabled == true
            if enabled then
                local ok, err = SilentUI:SetBackgroundAccentFromImage(imageLabel)
                SilentUI:Notify({
                    Title = "Background",
                    Text = ok and "Color de acento actualizado desde la imagen." or tostring(err),
                    Type = ok and "success" or "warning",
                    Duration = 7,
                })
            end
        end,
    })

    tabObj:AddButton({
        Text = "Restaurar fondo configurado",
        Description = "Vuelve a aplicar la imagen definida en SilentUI.Defaults.Background.Image.",
        Icon = "image",
        Callback = function()
            local ok, err = self:SetBackgroundImage(imageLabel)
            SilentUI:Notify({
                Title = "Background",
                Text = ok and "Fondo restaurado." or tostring(err),
                Type = ok and "success" or "warning",
                Duration = 5,
            })
        end,
    })

    tabObj:AddButton({
        Text = "Quitar fondo",
        Description = "Oculta la imagen en la ventana y el botón flotante.",
        Icon = "image-off",
        Callback = function()
            local ok, err = self:SetBackgroundImage("")
            SilentUI:Notify({
                Title = "Background",
                Text = ok and "Fondo eliminado." or tostring(err),
                Type = ok and "success" or "warning",
                Duration = 5,
            })
        end,
    })

    return {
        Instance = tabObj._group,
        Tab = tabObj,
        Destroy = function() tabObj._group:Destroy() end,
    }
end

function Private.OpenExternalURL(url)
    if type(url) ~= "string" or not url:match("^https?://") then
        return false, "invalid external URL"
    end

    local candidates = {}
    local environments = {}
    local seenEnvironment = {}
    local seenFunctions = {}

    local function addEnvironment(environment)
        if type(environment) ~= "table" or seenEnvironment[environment] then return end
        seenEnvironment[environment] = true
        table.insert(environments, environment)
    end

    -- Executors do not share a standard browser-opening API. Inspect the
    -- common execution environments instead of assuming getgenv is the only one.
    addEnvironment(Private.GetGlobalTable())
    addEnvironment(_G)
    pcall(function() if type(getgenv) == "function" then addEnvironment(getgenv()) end end)
    pcall(function() if type(getfenv) == "function" then addEnvironment(getfenv(0)); addEnvironment(getfenv(1)) end end)
    pcall(function() if type(getrenv) == "function" then addEnvironment(getrenv()) end end)
    pcall(function() if type(getrenv) == "table" then addEnvironment(getrenv) end end)

    local aliases = {
        "openurl", "open_url", "openUrl", "OpenURL", "OpenUrl", "openURL",
        "openlink", "open_link", "openLink", "OpenLink",
        "openexternalurl", "open_external_url", "openExternalURL", "openExternalUrl", "OpenExternalURL",
        "openexternallink", "open_external_link", "openExternalLink", "OpenExternalLink",
        "openbrowser", "open_browser", "openBrowser", "OpenBrowser",
        "openbrowserurl", "open_browser_url", "openBrowserUrl", "OpenBrowserUrl",
        "openbrowserwindow", "open_browser_window", "openBrowserWindow", "OpenBrowserWindow",
        "openexternal", "open_external", "openExternal", "OpenExternal",
        "openwebsite", "open_website", "openWebsite", "OpenWebsite",
        "launchurl", "launch_url", "launchURL", "LaunchURL",
        "launchbrowser", "launch_browser", "launchBrowser", "LaunchBrowser",
        "launchbrowserurl", "launch_browser_url", "LaunchBrowserUrl",
        "visiturl", "visit_url", "visitURL", "VisitURL",
        "browse", "Browse", "browser_open", "open_browser_url", "openInBrowser", "open_in_browser", "open_url_in_browser",
        "openuri", "open_uri", "openURI", "OpenURI", "urlopen", "url_open", "openUrlExternal",
    }

    local function addCandidate(fn, owner, name)
        if type(fn) ~= "function" then return end
        local owners = seenFunctions[fn]
        if not owners then owners = {}; seenFunctions[fn] = owners end
        if owners[owner or false] then return end
        owners[owner or false] = true
        table.insert(candidates, { Function = fn, Owner = owner, Name = name })
    end

    local namespaceNames = {
        "syn", "Syn", "synapse", "Synapse", "synapsez", "SynapseZ",
        "fluxus", "Fluxus", "xeno", "Xeno", "delta", "Delta", "krnl", "KRNL",
        "electron", "Electron", "wave", "Wave", "solara", "Solara", "hydrogen", "Hydrogen",
        "arceus", "Arceus", "arceusx", "ArceusX", "celery", "Celery", "comet", "Comet",
        "krampus", "Krampus", "scriptware", "ScriptWare", "swift", "Swift", "codex", "Codex",
        "evon", "Evon", "trigon", "Trigon", "oxygen", "Oxygen", "executor", "Executor",
        "browser", "Browser", "web", "Web", "http", "HTTP", "linking", "Linking",
        "platform", "Platform", "client", "Client", "native", "Native", "system", "System",
        "misc", "Misc", "ui", "UI", "os", "OS",
    }

    for _, environment in ipairs(environments) do
        for _, name in ipairs(aliases) do
            addCandidate(environment[name], nil, name)
        end
        for _, namespaceName in ipairs(namespaceNames) do
            local namespace = environment[namespaceName]
            if type(namespace) == "table" then
                for _, name in ipairs(aliases) do
                    addCandidate(namespace[name], namespace, namespaceName .. "." .. name)
                end
            end
        end
    end

    -- Some executor builds expose a LinkingService proxy. This is not a
    -- documented general Roblox browser API, so it is treated as best-effort.
    pcall(function()
        local linkingService = game:GetService("LinkingService")
        if linkingService then
            addCandidate(linkingService.OpenUrl, linkingService, "LinkingService.OpenUrl")
            addCandidate(linkingService.openUrl, linkingService, "LinkingService.openUrl")
        end
    end)

    -- Legacy Roblox browser entry points. These are RobloxScriptSecurity APIs
    -- (and deprecated), so ordinary LocalScripts cannot call them. Some executor
    -- contexts may expose them; pcall keeps this optional and non-fatal.
    pcall(function()
        local guiService = game:GetService("GuiService")
        if guiService then
            addCandidate(guiService.OpenBrowserWindow, guiService, "GuiService.OpenBrowserWindow (legacy)")
        end
    end)

    for _, candidate in ipairs(candidates) do
        local ok, result
        if candidate.Owner then
            -- Most executor globals are plain functions stored on a table, not
            -- colon methods. Try URL-first so the URL is not shifted into `self`.
            ok, result = pcall(candidate.Function, url)
            if not ok or result == false then
                ok, result = pcall(candidate.Function, candidate.Owner, url)
            end
        else
            ok, result = pcall(candidate.Function, url)
        end
        if ok and result ~= false then return true, candidate.Name end
    end

    return false, "no compatible external URL opener was exposed by this executor"
end

function Private.CopyToClipboard(text)
    if type(text) ~= "string" then return false end
    local globals = Private.GetGlobalTable()
    local aliases = { "setclipboard", "set_clipboard", "toclipboard", "to_clipboard", "writeclipboard", "write_clipboard" }
    for _, name in ipairs(aliases) do
        local fn = globals[name] or hasFn(name)
        if type(fn) == "function" then
            local ok, result = pcall(fn, text)
            if ok and result ~= false then return true end
        end
    end
    for _, namespaceName in ipairs({ "syn", "fluxus", "xeno", "delta", "krnl", "executor" }) do
        local namespace = globals[namespaceName]
        if type(namespace) == "table" then
            for _, name in ipairs(aliases) do
                local fn = namespace[name]
                if type(fn) == "function" then
                    local ok, result = pcall(fn, namespace, text)
                    if not ok or result == false then ok, result = pcall(fn, text) end
                    if ok and result ~= false then return true end
                end
            end
        end
    end
    return false
end

function Window:AddDiscordDockButton()
    if self._libraryDiscordDock then return self._libraryDiscordDock end
    local dock = self:AddDockButton({
        Name = "SilentUI_DiscordDockButton",
        Owner = "library",
        Order = 3,
        Icon = "messages-square",
        FallbackText = "D",
        BackgroundColor3 = Color3.fromRGB(88, 101, 242),
        BackgroundTransparency = 0.16,
        IconColor3 = Color3.new(1, 1, 1),
        FallbackTextColor3 = Color3.new(1, 1, 1),
        Callback = function()
            local fixedInvite = SILENTUI_DISCORD_INVITE
            local opened = Private.OpenExternalURL(fixedInvite)
            if opened then
                SilentUI:Notify({ Title = "Discord", Text = "Comunidad de SilentUI abierta.", Type = "success", Duration = 5 })
            else
                local copied = Private.CopyToClipboard(fixedInvite)
                SilentUI:Notify({
                    Title = "Discord",
                    Text = copied and "No se pudo abrir; invitación de SilentUI copiada." or ("Abre este enlace manualmente: " .. fixedInvite),
                    Type = copied and "info" or "warning",
                    Duration = 8,
                })
            end
        end,
    })
    self._libraryDiscordDock = dock
    return dock
end

function Window:AddDiscordPanel(opts)
    opts = opts or {}
    if self._libraryDiscordPanel then
        if opts.UserInvite ~= nil then
            self._libraryDiscordPanel:SetCustomInvite(opts.UserInvite)
        end
        return self._libraryDiscordPanel
    end
    local tabObj = self:AddTab({
        Name = opts.Name or "Discord",
        Icon = opts.Icon or "messages-square",
        Hidden = opts.Hidden == true,
    })

    tabObj:AddParagraph({
        Title = opts.Title or "Discord",
        Icon = "messages-square",
        Text = opts.Description or "Acceso a la comunidad de SilentUI y un enlace personal opcional.",
    })

    local customInvite = tostring(opts.UserInvite or "")
    tabObj:AddTextbox({
        Text = "Tu invitación de Discord",
        Description = "Opcional. Este enlace solo se usa desde este panel; no cambia el acceso fijo de SilentUI.",
        Placeholder = "https://discord.gg/tu-invitacion",
        Default = customInvite,
        Callback = function(value)
            customInvite = tostring(value or "")
        end,
    })

    local function validDiscordInvite(value)
        value = tostring(value or ""):match("^%s*(.-)%s*$")
        if value == "" then return false end
        return value:match("^https://discord%.gg/[A-Za-z0-9%-_]+/?$") ~= nil
            or value:match("^https://discord%.com/invite/[A-Za-z0-9%-_]+/?$") ~= nil
    end

    local customInviteButton = tabObj:AddButton({
        Text = "Abrir mi invitación",
        Description = "Abre el enlace personal que escribiste arriba.",
        Icon = "external-link",
        Callback = function()
            local invite = tostring(customInvite or ""):match("^%s*(.-)%s*$")
            if not validDiscordInvite(invite) then
                SilentUI:Notify({
                    Title = "Discord",
                    Text = "Introduce una invitación válida de discord.gg o discord.com/invite.",
                    Type = "warning",
                    Duration = 6,
                })
                return
            end
            local opened = Private.OpenExternalURL(invite)
            if opened then
                SilentUI:Notify({ Title = "Discord", Text = "Invitación personal abierta.", Type = "success", Duration = 5 })
            else
                local copied = Private.CopyToClipboard(invite)
                SilentUI:Notify({
                    Title = "Discord",
                    Text = copied and "No se pudo abrir; enlace personal copiado." or ("No se pudo abrir el enlace: " .. invite),
                    Type = copied and "info" or "warning",
                    Duration = 8,
                })
            end
        end,
    })

    -- The fixed shortcut is owned by SilentUI and is independent of the user's invite.
    local dock = self:AddDiscordDockButton()

    local panelHandle = {
        Instance = tabObj._group,
        Tab = tabObj,
        DockButton = dock,
        CustomInvite = customInviteButton,
        GetCustomInvite = function() return customInvite end,
        SetCustomInvite = function(_, value)
            customInvite = tostring(value or "")
            return validDiscordInvite(customInvite)
        end,
        FixedInvite = SILENTUI_DISCORD_INVITE,
        Destroy = function()
            if tabObj._group then tabObj._group:Destroy() end
        end,
    }
    self._libraryDiscordPanel = panelHandle
    return panelHandle
end

function Window:AddUserSettingsPanel(opts)
    opts = opts or {}
    if self._librarySettingsPanel then return self._librarySettingsPanel end
    local tabObj = self:AddTab({
        Name = opts.Name or "Configuración",
        Icon = "settings-2",
        Hidden = true,
    })

    tabObj:AddParagraph({
        Title = opts.Title or "Configuración",
        Icon = "settings-2",
        Text = opts.Description or "Ajusta cómo se ve y responde el panel.",
    })

    tabObj:AddSection("Panel", "settings-2")
    tabObj:AddToggle({
        Text = "Fondo desenfocado",
        Default = SilentUI.Config.Blur ~= false,
        Callback = function(value) SilentUI:SetBlurEnabled(value) end,
    })
    tabObj:AddDropdown({
        Text = "Idioma",
        Options = { "English", "Español" },
        Default = SilentUI:GetLanguage() == "es" and "Español" or "English",
        Callback = function(value)
            SilentUI:SetLanguage(value == "Español" and "es" or "en")
        end,
    })
    tabObj:AddButton({
        Text = "Pantalla completa",
        Icon = "maximize",
        Callback = function() self:ToggleFullscreen() end,
    })

    tabObj:AddSection("Botones flotantes", "app-window")
    tabObj:AddToggle({
        Text = "Mostrar botones flotantes",
        Default = SilentUI.UserSettings.ShowFloatingWidgets,
        Callback = function(value)
            SilentUI.UserSettings.ShowFloatingWidgets = value == true
            for widget in pairs(SilentUI._FloatingWidgets) do
                if widget._FloatingKind ~= "StateList" and widget.SetVisible then
                    widget:SetVisible(SilentUI.UserSettings.ShowFloatingWidgets)
                end
            end
        end,
    })

    tabObj:AddSection("Panel de estado", "list-checks")
    tabObj:AddToggle({
        Text = "Mostrar panel de estado",
        Default = SilentUI.UserSettings.ShowStatePanels,
        Callback = function(value)
            SilentUI.UserSettings.ShowStatePanels = value == true
            for list in pairs(SilentUI._StateLists) do
                if list.SetVisible then list:SetVisible(value) end
            end
        end,
    })
    tabObj:AddToggle({
        Text = "Mostrar estado ON/OFF",
        Default = SilentUI.UserSettings.ShowStateValues,
        Callback = function(value)
            SilentUI.UserSettings.ShowStateValues = value == true
            for list in pairs(SilentUI._StateLists) do
                if list.SetStatusVisible then list:SetStatusVisible(value) end
            end
        end,
    })
    tabObj:AddToggle({
        Text = "Bloquear paneles de estado",
        Default = SilentUI.UserSettings.LockStatePanels,
        Callback = function(value)
            SilentUI.UserSettings.LockStatePanels = value == true
            for list in pairs(SilentUI._StateLists) do
                if list.SetLocked then list:SetLocked(value) end
            end
        end,
    })
    tabObj:AddToggle({
        Text = "Permitir tocar detrás del panel",
        Default = SilentUI.UserSettings.StatePanelsPassThrough,
        Callback = function(value)
            SilentUI.UserSettings.StatePanelsPassThrough = value == true
            for list in pairs(SilentUI._StateLists) do
                if list.SetPassThrough then list:SetPassThrough(value) end
            end
        end,
    })

    tabObj:AddButton({
        Text = "Cerrar panel",
        Icon = "x",
        Callback = function() self:Close() end,
    })

    local dock = self:AddDockButton({
        Name = "PanelSettingsDockButton",
        Owner = "library",
        Order = 2,
        Icon = "settings-2",
        FallbackText = "⚙",
        Callback = function() tabObj._select() end,
    })
    local panelHandle = {
        Instance = tabObj._group,
        Tab = tabObj,
        DockButton = dock,
        Destroy = function()
            if dock and dock.Instance then dock.Instance:Destroy() end
            if tabObj._group then tabObj._group:Destroy() end
        end,
    }
    self._librarySettingsPanel = panelHandle
    return panelHandle
end

function Window:AddSpotifyPanel(opts)
	opts = opts or {}
    if self._librarySpotifyPanel then return self._librarySpotifyPanel end
	local jan = self._janitor
	local dockBtn
	local connectBridge
	local hasOpenedSpotify = false
	local panel
	panel = self:AddPanelTab({
		Name = opts.Name or "Spotify",
		Icon = opts.Icon or "Lucide:music-2",
		OnToggle = function(isOpen)
			if dockBtn then dockBtn:SetActive(isOpen) end
			if isOpen and not hasOpenedSpotify then
				hasOpenedSpotify = true
				if opts.AutoConnect == true and opts.BridgeUrl ~= "" then
					task.defer(function()
						if connectBridge then connectBridge() end
					end)
				end
			end
			if opts.OnToggle then task.spawn(opts.OnToggle, isOpen) end
		end,
	})
 
	local function websocketConnect()
		local candidates = {}
		pcall(function()
			if WebSocket and type(WebSocket.connect) == "function" then
				table.insert(candidates, WebSocket.connect)
			end
		end)
		pcall(function()
			if websocket and type(websocket.connect) == "function" then
				table.insert(candidates, websocket.connect)
			end
		end)
		pcall(function()
			if syn and syn.websocket and type(syn.websocket.connect) == "function" then
				table.insert(candidates, syn.websocket.connect)
			end
		end)
		return candidates[1]
	end
 
	local HEADER_H = 0
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.ZIndex = Z.Content + 1
	header.Parent = panel.Instance
	header.Visible = false
 
	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, 14)
	headerPad.PaddingRight = UDim.new(0, 8)
	headerPad.Parent = header
 
	local titleIcon = Instance.new("ImageLabel")
	titleIcon.BackgroundTransparency = 1
	titleIcon.Image = ResolveIcon(opts.Icon or "Lucide:music-2")
	titleIcon.ImageColor3 = Color3.fromRGB(30, 215, 96)
	titleIcon.AnchorPoint = Vector2.new(0, 0.5)
	titleIcon.Position = UDim2.new(0, 0, 0.5, 0)
	titleIcon.Size = UDim2.fromOffset(15, 15)
	titleIcon.ZIndex = Z.Content + 2
	titleIcon.Parent = header
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = SilentUI.Theme.Font
	titleLabel.Text = opts.Title or "Spotify Player"
	titleLabel.TextColor3 = SilentUI.Theme.Text
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.AnchorPoint = Vector2.new(0, 0.5)
	titleLabel.Position = UDim2.new(0, 22, 0.5, 0)
	titleLabel.Size = UDim2.new(1, -62, 0, 18)
	titleLabel.ZIndex = Z.Content + 2
	titleLabel.Parent = header
 
	local closeBtn = Instance.new("TextButton")
	closeBtn.Text = ""
	closeBtn.AutoButtonColor = false
	closeBtn.BackgroundTransparency = 1
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, 0, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(26, 26)
	closeBtn.ZIndex = Z.Content + 2
	closeBtn.Parent = header
 
	local closeIcon = Instance.new("ImageLabel")
	closeIcon.BackgroundTransparency = 1
	closeIcon.Image = ResolveIcon("x")
	closeIcon.ImageColor3 = SilentUI.Theme.TextDim
	closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	closeIcon.Position = UDim2.fromScale(0.5, 0.5)
	closeIcon.Size = UDim2.fromOffset(13, 13)
	closeIcon.ZIndex = Z.Content + 3
	closeIcon.Parent = closeBtn
	jan:Add(closeBtn.MouseButton1Click:Connect(function() panel.Close() end))
 
	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = SilentUI.Theme.Surface
	divider.BackgroundTransparency = 0.94
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromOffset(0, HEADER_H)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.ZIndex = Z.Content + 1
	divider.Parent = panel.Instance
	divider.Visible = false
 
	local subTabHost = Instance.new("ScrollingFrame")
	subTabHost.Name = "SpotifySubTabs"
	subTabHost.BackgroundTransparency = 1
	subTabHost.BorderSizePixel = 0
	subTabHost.Position = UDim2.fromOffset(0, HEADER_H)
	subTabHost.Size = UDim2.new(1, 0, 1, -HEADER_H)
	subTabHost.ScrollBarThickness = 0
	subTabHost.ZIndex = Z.Content + 1
	subTabHost.Parent = panel.Instance
 
	local subTabRoot = setmetatable({
		Name = "Spotify Player",
		_page = subTabHost,
		_window = self,
		_janitor = jan,
		_group = panel.Instance,
	}, Tab)
	local playerSubTab = subTabRoot:AddSubTab({ Name = "Spotify Player", Icon = "Lucide:music-2" })
	local favoritesSubTab = subTabRoot:AddSubTab({ Name = "Favorites", Icon = "Lucide:heart" })
	local scroll = playerSubTab._page
	local list = scroll:FindFirstChild("PageLayout")
	local scrollPad = scroll:FindFirstChild("PagePadding")
	if scrollPad then
		scrollPad.PaddingTop = UDim.new(0, 0)
		scrollPad.PaddingLeft = UDim.new(0, 0)
		scrollPad.PaddingRight = UDim.new(0, 12)
		scrollPad.PaddingBottom = UDim.new(0, 6)
	end
	local favoritesPad = favoritesSubTab._page:FindFirstChild("PagePadding")
	if favoritesPad then
		favoritesPad.PaddingTop = UDim.new(0, 0)
		favoritesPad.PaddingLeft = UDim.new(0, 0)
		favoritesPad.PaddingRight = UDim.new(0, 12)
		favoritesPad.PaddingBottom = UDim.new(0, 6)
	end
 
	local function makeCard(height, order, parent)
		local card = Instance.new("Frame")
		card.BackgroundColor3 = SilentUI.Theme.Surface
		card.BackgroundTransparency = 0.96
		card.BorderSizePixel = 0
		card.Size = UDim2.new(1, 0, 0, height)
		card.LayoutOrder = order
		card.ZIndex = Z.Content + 2
		card.Parent = parent or scroll
		Corner(card, 10)
		Stroke(card, SilentUI.Theme.Border, 1, 0.94)
		return card
	end
 
	local guideParagraph = playerSubTab:AddParagraph({
		Title = "Quick setup",
		Icon = "Lucide:link-2",
		Text = "Copy the player link, keep it open in your browser, load a playlist and press Play once.",
	})
	guideParagraph.Instance.LayoutOrder = 1
 
	local statusCard = makeCard(30, 6)
	local statusDot = Instance.new("Frame")
	statusDot.BackgroundColor3 = SilentUI.Theme.TextDim
	statusDot.BorderSizePixel = 0
	statusDot.AnchorPoint = Vector2.new(0, 0.5)
	statusDot.Position = UDim2.new(0, 11, 0.5, 0)
	statusDot.Size = UDim2.fromOffset(7, 7)
	statusDot.ZIndex = Z.Content + 3
	statusDot.Parent = statusCard
	Corner(statusDot, 4)
 
	local statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.FontFace = SilentUI.Theme.FontRegular
	statusLabel.Text = "Bridge disconnected"
	statusLabel.TextColor3 = SilentUI.Theme.TextDim
	statusLabel.TextSize = 12
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Position = UDim2.fromOffset(27, 0)
	statusLabel.Size = UDim2.new(1, -38, 1, 0)
	statusLabel.ZIndex = Z.Content + 3
	statusLabel.Parent = statusCard
 
	local nowCard = makeCard(164, 7)
	nowCard.ClipsDescendants = true
	local art = Instance.new("ImageLabel")
	art.BackgroundColor3 = Color3.fromRGB(30, 215, 96)
	art.BackgroundTransparency = 0.84
	art.BorderSizePixel = 0
	art.Image = ""
	art.ImageColor3 = SilentUI.Theme.Text
	art.ScaleType = Enum.ScaleType.Crop
	art.AnchorPoint = Vector2.new(0, 0)
	art.Position = UDim2.fromOffset(0, 12)
	art.Size = UDim2.fromOffset(88, 88)
	art.ZIndex = Z.Content + 3
	art.Parent = nowCard
	Corner(art, 12)
	Stroke(art, SilentUI.Theme.Border, 1, 0.9)
 
	local artIcon = Instance.new("ImageLabel")
	artIcon.BackgroundTransparency = 1
	artIcon.Image = ResolveIcon("music-2")
	artIcon.ImageColor3 = Color3.fromRGB(30, 215, 96)
	artIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	artIcon.Position = UDim2.fromScale(0.5, 0.5)
	artIcon.Size = UDim2.fromOffset(28, 28)
	artIcon.ZIndex = Z.Content + 4
	artIcon.Parent = art
 
	local coverToken = 0
	local coverCache = {}
	local function showCover(url)
		coverToken += 1
		local token = coverToken
		url = type(url) == "string" and url or ""
		if url == "" then
			art.BackgroundTransparency = 0.84
			art.Image = ""
			artIcon.Visible = true
			artIcon.Image = ResolveIcon("music-2")
			artIcon.ImageColor3 = Color3.fromRGB(30, 215, 96)
			artIcon.BackgroundTransparency = 1
			artIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			artIcon.Size = UDim2.fromOffset(28, 28)
			artIcon.Position = UDim2.fromScale(0.5, 0.5)
			return
		end
		task.spawn(function()
			local asset = coverCache[url]
			if not asset and Private.fn_customasset and fn_writefile and Private.EnsureAssetsFolder() then
				local hash = 7
				for index = 1, #url do hash = (hash * 31 + url:byte(index)) % 2147483647 end
				local path = ASSETS_FOLDER .. "/spotify-cover-" .. tostring(hash) .. ".jpg"
				if not (fn_isfile and fn_isfile(path)) then
					local ok, body = pcall(function() return game:HttpGet(url) end)
					if ok and type(body) == "string" and #body > 256 then pcall(fn_writefile, path, body) end
				end
				if not fn_isfile or fn_isfile(path) then
					local ok, result = pcall(Private.fn_customasset, path)
					if ok then asset = result; coverCache[url] = result end
				end
			end
			if token ~= coverToken or not asset then return end
			art.BackgroundTransparency = 1
			art.Image = asset
			artIcon.Visible = false
		end)
	end
 
	local nowPlayingTag = Instance.new("TextLabel")
	nowPlayingTag.BackgroundTransparency = 1
	nowPlayingTag.FontFace = SilentUI.Theme.Font
	nowPlayingTag.Text = "NOW PLAYING"
	nowPlayingTag.TextColor3 = Color3.fromRGB(30, 215, 96)
	nowPlayingTag.TextSize = 9
	nowPlayingTag.TextXAlignment = Enum.TextXAlignment.Left
	nowPlayingTag.Position = UDim2.fromOffset(100, 9)
	nowPlayingTag.Size = UDim2.new(1, -100, 0, 12)
	nowPlayingTag.ZIndex = Z.Content + 3
	nowPlayingTag.Parent = nowCard
 
	local trackLabel = Instance.new("TextLabel")
	trackLabel.BackgroundTransparency = 1
	trackLabel.FontFace = SilentUI.Theme.Font
	trackLabel.Text = "Nothing playing"
	trackLabel.TextColor3 = SilentUI.Theme.Text
	trackLabel.TextSize = 15
	trackLabel.TextXAlignment = Enum.TextXAlignment.Left
	trackLabel.TextTruncate = Enum.TextTruncate.AtEnd
	trackLabel.Position = UDim2.fromOffset(100, 25)
	trackLabel.Size = UDim2.new(1, -100, 0, 20)
	trackLabel.ZIndex = Z.Content + 3
	trackLabel.Parent = nowCard
 
	local artistLabel = Instance.new("TextLabel")
	artistLabel.BackgroundTransparency = 1
	artistLabel.FontFace = SilentUI.Theme.FontRegular
	artistLabel.Text = "Connect your Spotify bridge"
	artistLabel.TextColor3 = SilentUI.Theme.TextDim
	artistLabel.TextSize = 12
	artistLabel.TextXAlignment = Enum.TextXAlignment.Left
	artistLabel.TextTruncate = Enum.TextTruncate.AtEnd
	artistLabel.Position = UDim2.fromOffset(100, 47)
	artistLabel.Size = UDim2.new(1, -100, 0, 16)
	artistLabel.ZIndex = Z.Content + 3
	artistLabel.Parent = nowCard
 
	local progressTrack = Instance.new("Frame")
	progressTrack.BackgroundColor3 = SilentUI.Theme.SurfaceHover
	progressTrack.BackgroundTransparency = 0.45
	progressTrack.BorderSizePixel = 0
	progressTrack.Position = UDim2.fromOffset(100, 76)
	progressTrack.Size = UDim2.new(1, -100, 0, 5)
	progressTrack.ZIndex = Z.Content + 3
	progressTrack.Parent = nowCard
	Corner(progressTrack, 2)
 
	local progressFill = Instance.new("Frame")
	progressFill.BackgroundColor3 = Color3.fromRGB(30, 215, 96)
	progressFill.BorderSizePixel = 0
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.ZIndex = Z.Content + 4
	progressFill.Parent = progressTrack
	Corner(progressFill, 2)
 
	local progressKnob = Instance.new("Frame")
	progressKnob.BackgroundColor3 = SilentUI.Theme.Text
	progressKnob.BorderSizePixel = 0
	progressKnob.AnchorPoint = Vector2.new(0.5, 0.5)
	progressKnob.Position = UDim2.new(0, 0, 0.5, 0)
	progressKnob.Size = UDim2.fromOffset(9, 9)
	progressKnob.ZIndex = Z.Content + 6
	progressKnob.Parent = progressTrack
	Corner(progressKnob, 5)
 
	local seekBubble = Instance.new("Frame")
	seekBubble.BackgroundColor3 = SilentUI.Theme.Background
	seekBubble.BackgroundTransparency = 0.04
	seekBubble.BorderSizePixel = 0
	seekBubble.AnchorPoint = Vector2.new(0.5, 1)
	seekBubble.Position = UDim2.new(0, 0, 0, -8)
	seekBubble.Size = UDim2.fromOffset(48, 25)
	seekBubble.Visible = false
	seekBubble.ZIndex = Z.Content + 8
	seekBubble.Parent = progressTrack
	Corner(seekBubble, 7)
	Stroke(seekBubble, SilentUI.Theme.Border, 1, 0.9)
	local seekBubbleLabel = Instance.new("TextLabel")
	seekBubbleLabel.BackgroundTransparency = 1
	seekBubbleLabel.FontFace = SilentUI.Theme.Font
	seekBubbleLabel.Text = "0:00"
	seekBubbleLabel.TextColor3 = SilentUI.Theme.Text
	seekBubbleLabel.TextSize = 10
	seekBubbleLabel.Size = UDim2.fromScale(1, 1)
	seekBubbleLabel.ZIndex = Z.Content + 9
	seekBubbleLabel.Parent = seekBubble
 
	local progressHitbox = Instance.new("TextButton")
	progressHitbox.Text = ""
	progressHitbox.AutoButtonColor = false
	progressHitbox.BackgroundTransparency = 1
	progressHitbox.BorderSizePixel = 0
	progressHitbox.Position = UDim2.fromOffset(100, 68)
	progressHitbox.Size = UDim2.new(1, -100, 0, 21)
	progressHitbox.ZIndex = Z.Content + 7
	progressHitbox.Parent = nowCard
 
	local timeLabel = Instance.new("TextLabel")
	timeLabel.BackgroundTransparency = 1
	timeLabel.FontFace = SilentUI.Theme.FontRegular
	timeLabel.Text = "0:00"
	timeLabel.TextColor3 = SilentUI.Theme.TextDim
	timeLabel.TextSize = 10
	timeLabel.TextXAlignment = Enum.TextXAlignment.Left
	timeLabel.Position = UDim2.fromOffset(100, 87)
	timeLabel.Size = UDim2.new(0.5, -50, 0, 14)
	timeLabel.ZIndex = Z.Content + 3
	timeLabel.Parent = nowCard
 
	local durationLabel = Instance.new("TextLabel")
	durationLabel.BackgroundTransparency = 1
	durationLabel.FontFace = SilentUI.Theme.FontRegular
	durationLabel.Text = "0:00"
	durationLabel.TextColor3 = SilentUI.Theme.TextDim
	durationLabel.TextSize = 10
	durationLabel.TextXAlignment = Enum.TextXAlignment.Right
	durationLabel.Position = UDim2.new(0.5, 50, 0, 87)
	durationLabel.Size = UDim2.new(0.5, -50, 0, 14)
	durationLabel.ZIndex = Z.Content + 3
	durationLabel.Parent = nowCard
 
	local controlsDivider = Instance.new("Frame")
	controlsDivider.BackgroundColor3 = SilentUI.Theme.Surface
	controlsDivider.BackgroundTransparency = 0.93
	controlsDivider.BorderSizePixel = 0
	controlsDivider.Position = UDim2.fromOffset(0, 111)
	controlsDivider.Size = UDim2.new(1, 0, 0, 1)
	controlsDivider.ZIndex = Z.Content + 3
	controlsDivider.Parent = nowCard
 
	local controls = Instance.new("Frame")
	controls.BackgroundTransparency = 1
	controls.BorderSizePixel = 0
	controls.Position = UDim2.fromOffset(0, 114)
	controls.Size = UDim2.new(1, 0, 0, 44)
	controls.ZIndex = Z.Content + 3
	controls.Parent = nowCard
	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.FillDirection = Enum.FillDirection.Horizontal
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlsLayout.Padding = UDim.new(0, 12)
	controlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	controlsLayout.Parent = controls
 
	local controlRefs = {}
	local function makeControl(name, icon, order, primary)
		local button = Instance.new("TextButton")
		button.Name = name
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = primary and Color3.fromRGB(30, 215, 96) or SilentUI.Theme.Surface
		button.BackgroundTransparency = primary and 0.05 or 0.94
		button.BorderSizePixel = 0
		button.Size = UDim2.fromOffset(primary and 36 or 32, primary and 36 or 32)
		button.LayoutOrder = order
		button.ZIndex = Z.Content + 3
		button.Parent = controls
		Corner(button, primary and 18 or 10)
 
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = ResolveIcon(icon)
		image.ImageColor3 = primary and Color3.fromRGB(12, 28, 18) or SilentUI.Theme.TextDim
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromOffset(primary and 17 or 15, primary and 17 or 15)
		image.ZIndex = Z.Content + 4
		image.Parent = button
		controlRefs[name] = { Button = button, Icon = image }
		return button
	end
 
	local shuffleBtn = makeControl("Shuffle", "shuffle", 1, false)
	local previousBtn = makeControl("Previous", "skip-back", 2, false)
	local playBtn = makeControl("PlayPause", "play", 3, true)
	local nextBtn = makeControl("Next", "skip-forward", 4, false)
	local repeatBtn = makeControl("Repeat", "repeat", 5, false)
 
	local function makeInputCard(order, title, placeholder, buttonIcon)
		local card = makeCard(66, order)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.FontFace = SilentUI.Theme.Font
		label.Text = title
		label.TextColor3 = SilentUI.Theme.Text
		label.TextSize = 12
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Position = UDim2.fromOffset(11, 6)
		label.Size = UDim2.new(1, -22, 0, 16)
		label.ZIndex = Z.Content + 3
		label.Parent = card
 
		local pill = Instance.new("Frame")
		pill.BackgroundColor3 = SilentUI.Theme.Surface
		pill.BackgroundTransparency = 0.94
		pill.BorderSizePixel = 0
		pill.Position = UDim2.fromOffset(10, 27)
		pill.Size = UDim2.new(1, -20, 0, 30)
		pill.ZIndex = Z.Content + 3
		pill.Parent = card
		Corner(pill, 8)
 
		local button = Instance.new("TextButton")
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = SilentUI.Theme.Surface
		button.BackgroundTransparency = 0.91
		button.BorderSizePixel = 0
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -3, 0, 3)
		button.Size = UDim2.fromOffset(34, 24)
		button.ZIndex = Z.Content + 5
		button.Parent = pill
		Corner(button, 7)
		Stroke(button, SilentUI.Theme.Border, 1, 0.94)
		local buttonImage = Instance.new("ImageLabel")
		buttonImage.BackgroundTransparency = 1
		buttonImage.Image = ResolveIcon(buttonIcon)
		buttonImage.ImageColor3 = SilentUI.Theme.Text
		buttonImage.AnchorPoint = Vector2.new(0.5, 0.5)
		buttonImage.Position = UDim2.fromScale(0.5, 0.5)
		buttonImage.Size = UDim2.fromOffset(14, 14)
		buttonImage.ZIndex = Z.Content + 6
		buttonImage.Parent = button
 
		local box = Instance.new("TextBox")
		box.ClearTextOnFocus = false
		box.FontFace = SilentUI.Theme.FontRegular
		box.PlaceholderText = placeholder
		box.PlaceholderColor3 = SilentUI.Theme.TextDim
		box.Text = ""
		box.TextColor3 = SilentUI.Theme.Text
		box.TextSize = 11
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.BackgroundTransparency = 1
		box.Position = UDim2.fromOffset(9, 0)
		box.Size = UDim2.new(1, -52, 1, 0)
		box.ZIndex = Z.Content + 4
		box.Parent = pill
		return box, button, card, label, pill
	end
 
	local searchBox, searchBtn, searchCard, searchTitle, searchPill = makeInputCard(3, "", "Search this playlist...", "search")
	local pairBox, connectBtn, pairCard = makeInputCard(3, "Spotify Connect", "Pairing code", "link-2")
	local connectBtnIcon = connectBtn:FindFirstChildOfClass("ImageLabel")
	pairBox.TextEditable = false
	pairBox.Text = HttpService:GenerateGUID(false):gsub("%-", ""):sub(1, 8):upper()
	local playlistBox, loadBtn, playlistCard, playlistTitle, playlistPill = makeInputCard(4, "", "Paste a Spotify playlist link...", "play")
 
	local connectSection = playerSubTab:AddLineText("Spotify Connect")
	connectSection.Instance.LayoutOrder = 2
	local playerSection = playerSubTab:AddLineText("Player")
	playerSection.Instance.LayoutOrder = 4
	local playerShell = makeCard(286, 5)
	local function flattenIntoPlayer(card, y, height)
		card.Parent = playerShell
		card.BackgroundTransparency = 1
		card.Position = UDim2.fromOffset(12, y)
		card.Size = UDim2.new(1, -24, 0, height)
		for _, child in ipairs(card:GetChildren()) do
			if child:IsA("UIStroke") then child.Transparency = 1 end
		end
	end
	flattenIntoPlayer(searchCard, 12, 40)
	searchTitle.Visible = false
	searchPill.Position = UDim2.fromOffset(0, 0)
	searchPill.Size = UDim2.fromScale(1, 1)
	searchPill.BackgroundTransparency = 0.92
	searchBtn.AnchorPoint = Vector2.zero
	searchBtn.Position = UDim2.fromOffset(4, 4)
	searchBtn.Size = UDim2.fromOffset(32, 32)
	searchBtn.BackgroundTransparency = 1
	for _, child in ipairs(searchBtn:GetChildren()) do
		if child:IsA("UIStroke") then child.Transparency = 1 end
	end
	searchBox.Position = UDim2.fromOffset(38, 0)
	searchBox.Size = UDim2.new(1, -46, 1, 0)
	searchBox.TextSize = 13
 
	flattenIntoPlayer(playlistCard, 60, 40)
	playlistTitle.Visible = false
	playlistPill.Position = UDim2.fromOffset(0, 0)
	playlistPill.Size = UDim2.fromScale(1, 1)
	playlistPill.BackgroundTransparency = 0.92
	loadBtn.Position = UDim2.new(1, -4, 0, 4)
	loadBtn.Size = UDim2.fromOffset(32, 32)
	playlistBox.Position = UDim2.fromOffset(12, 0)
	playlistBox.Size = UDim2.new(1, -56, 1, 0)
 
	statusCard.Parent = playerShell
	statusCard.Position = UDim2.fromOffset(12, 108)
	statusCard.Size = UDim2.new(1, -24, 0, 30)
	statusCard.Visible = false
	nowCard.Parent = playerShell
	nowCard.Position = UDim2.fromOffset(12, 108)
	nowCard.Size = UDim2.new(1, -24, 0, 164)
	nowCard.BackgroundTransparency = 1
	for _, child in ipairs(nowCard:GetChildren()) do
		if child:IsA("UIStroke") then child.Transparency = 1 end
	end
 
	local favoritesSection = favoritesSubTab:AddLineText("Saved Playlists")
	favoritesSection.Instance.LayoutOrder = 1
	local favoritesHeader = makeCard(137, 2, favoritesSubTab._page)
	local favoritesTitle = Instance.new("TextLabel")
	favoritesTitle.BackgroundTransparency = 1
	favoritesTitle.FontFace = SilentUI.Theme.Font
	favoritesTitle.Text = "Favorite playlists"
	favoritesTitle.TextColor3 = SilentUI.Theme.Text
	favoritesTitle.TextSize = 14
	favoritesTitle.TextXAlignment = Enum.TextXAlignment.Left
	favoritesTitle.Position = UDim2.fromOffset(12, 8)
	favoritesTitle.Size = UDim2.new(1, -112, 0, 20)
	favoritesTitle.ZIndex = Z.Content + 3
	favoritesTitle.Parent = favoritesHeader
	favoritesTitle.Visible = false
	local favoritesHint = Instance.new("TextLabel")
	favoritesHint.BackgroundTransparency = 1
	favoritesHint.FontFace = SilentUI.Theme.FontRegular
	favoritesHint.Text = "Save and load your playlists with one tap"
	favoritesHint.TextColor3 = SilentUI.Theme.TextDim
	favoritesHint.TextSize = 10
	favoritesHint.TextXAlignment = Enum.TextXAlignment.Left
	favoritesHint.Position = UDim2.fromOffset(12, 29)
	favoritesHint.Size = UDim2.new(1, -112, 0, 16)
	favoritesHint.ZIndex = Z.Content + 3
	favoritesHint.Parent = favoritesHeader
	favoritesHint.Visible = false
	local favoritesSearchPill = Instance.new("Frame")
	favoritesSearchPill.BackgroundColor3 = SilentUI.Theme.Surface
	favoritesSearchPill.BackgroundTransparency = 0.94
	favoritesSearchPill.BorderSizePixel = 0
	favoritesSearchPill.Position = UDim2.fromOffset(8, 7)
	favoritesSearchPill.Size = UDim2.new(1, -16, 0, 36)
	favoritesSearchPill.ZIndex = Z.Content + 3
	favoritesSearchPill.Parent = favoritesHeader
	Corner(favoritesSearchPill, 9)
	local favoritesSearchIcon = Instance.new("ImageLabel")
	favoritesSearchIcon.BackgroundTransparency = 1
	favoritesSearchIcon.Image = ResolveIcon("search")
	favoritesSearchIcon.ImageColor3 = SilentUI.Theme.TextDim
	favoritesSearchIcon.AnchorPoint = Vector2.new(0, 0.5)
	favoritesSearchIcon.Position = UDim2.new(0, 11, 0.5, 0)
	favoritesSearchIcon.Size = UDim2.fromOffset(15, 15)
	favoritesSearchIcon.ZIndex = Z.Content + 4
	favoritesSearchIcon.Parent = favoritesSearchPill
	local favoritesSearchBox = Instance.new("TextBox")
	favoritesSearchBox.BackgroundTransparency = 1
	favoritesSearchBox.ClearTextOnFocus = false
	favoritesSearchBox.FontFace = SilentUI.Theme.FontRegular
	favoritesSearchBox.PlaceholderText = "Search favorite playlists..."
	favoritesSearchBox.PlaceholderColor3 = SilentUI.Theme.TextDim
	favoritesSearchBox.Text = ""
	favoritesSearchBox.TextColor3 = SilentUI.Theme.Text
	favoritesSearchBox.TextSize = 11
	favoritesSearchBox.TextXAlignment = Enum.TextXAlignment.Left
	favoritesSearchBox.Position = UDim2.fromOffset(36, 0)
	favoritesSearchBox.Size = UDim2.new(1, -44, 1, 0)
	favoritesSearchBox.ZIndex = Z.Content + 4
	favoritesSearchBox.Parent = favoritesSearchPill
	local addFavoriteBtn = Instance.new("TextButton")
	addFavoriteBtn.Text = ""
	addFavoriteBtn.AutoButtonColor = false
	addFavoriteBtn.BackgroundColor3 = SilentUI.Theme.Surface
	addFavoriteBtn.BackgroundTransparency = 0.96
	addFavoriteBtn.BorderSizePixel = 0
	addFavoriteBtn.Position = UDim2.fromOffset(8, 113)
	addFavoriteBtn.Size = UDim2.new(1, -16, 0, 56)
	addFavoriteBtn.ZIndex = Z.Content + 4
	addFavoriteBtn.Parent = favoritesHeader
	Corner(addFavoriteBtn, 10)
	Stroke(addFavoriteBtn, SilentUI.Theme.Border, 1, 0.94)
	local addFavoriteIcon = Instance.new("ImageLabel")
	addFavoriteIcon.BackgroundTransparency = 1
	addFavoriteIcon.Image = ResolveIcon("heart-plus")
	addFavoriteIcon.ImageColor3 = SilentUI.Theme.Text
	addFavoriteIcon.AnchorPoint = Vector2.new(0, 0.5)
	addFavoriteIcon.Position = UDim2.new(0, 16, 0.5, 0)
	addFavoriteIcon.Size = UDim2.fromOffset(17, 17)
	addFavoriteIcon.ZIndex = Z.Content + 5
	addFavoriteIcon.Parent = addFavoriteBtn
	local saveFavoriteTitle = Instance.new("TextLabel")
	saveFavoriteTitle.BackgroundTransparency = 1
	saveFavoriteTitle.FontFace = SilentUI.Theme.Font
	saveFavoriteTitle.Text = "Save current playlist"
	saveFavoriteTitle.TextColor3 = SilentUI.Theme.Text
	saveFavoriteTitle.TextSize = 12
	saveFavoriteTitle.TextXAlignment = Enum.TextXAlignment.Left
	saveFavoriteTitle.Position = UDim2.fromOffset(44, 7)
	saveFavoriteTitle.Size = UDim2.new(1, -84, 0, 20)
	saveFavoriteTitle.ZIndex = Z.Content + 5
	saveFavoriteTitle.Parent = addFavoriteBtn
	local saveFavoriteHint = Instance.new("TextLabel")
	saveFavoriteHint.BackgroundTransparency = 1
	saveFavoriteHint.FontFace = SilentUI.Theme.FontRegular
	saveFavoriteHint.Text = "Add the playlist loaded in the player to Favorites"
	saveFavoriteHint.TextColor3 = SilentUI.Theme.TextDim
	saveFavoriteHint.TextSize = 9
	saveFavoriteHint.TextXAlignment = Enum.TextXAlignment.Left
	saveFavoriteHint.Position = UDim2.fromOffset(44, 27)
	saveFavoriteHint.Size = UDim2.new(1, -84, 0, 17)
	saveFavoriteHint.ZIndex = Z.Content + 5
	saveFavoriteHint.Parent = addFavoriteBtn
	local saveFavoriteChevron = Instance.new("ImageLabel")
	saveFavoriteChevron.BackgroundTransparency = 1
	saveFavoriteChevron.Image = ResolveIcon("chevron-right")
	saveFavoriteChevron.ImageColor3 = SilentUI.Theme.TextDim
	saveFavoriteChevron.AnchorPoint = Vector2.new(1, 0.5)
	saveFavoriteChevron.Position = UDim2.new(1, -16, 0.5, 0)
	saveFavoriteChevron.Size = UDim2.fromOffset(14, 14)
	saveFavoriteChevron.ZIndex = Z.Content + 5
	saveFavoriteChevron.Parent = addFavoriteBtn
	local saveFavoriteDivider = Instance.new("Frame")
	saveFavoriteDivider.BackgroundColor3 = SilentUI.Theme.Surface
	saveFavoriteDivider.BackgroundTransparency = 0.92
	saveFavoriteDivider.BorderSizePixel = 0
	saveFavoriteDivider.Position = UDim2.fromOffset(8, 103)
	saveFavoriteDivider.Size = UDim2.new(1, -16, 0, 1)
	saveFavoriteDivider.ZIndex = Z.Content + 3
	saveFavoriteDivider.Parent = favoritesHeader
 
	local favoritesList = Instance.new("Frame")
	favoritesList.BackgroundTransparency = 1
	favoritesList.BorderSizePixel = 0
	favoritesList.Position = UDim2.fromOffset(8, 51)
	favoritesList.Size = UDim2.new(1, -16, 0, 78)
	favoritesList.ZIndex = Z.Content + 2
	favoritesList.Parent = favoritesHeader
	local favoriteRows = {}
	local favorites = {}
	local currentPlaylistName = "Spotify playlist"
	local favoritesPath = ASSETS_FOLDER .. "/spotify-favorites.json"
	if fn_readfile and fn_isfile then
		local existsOk, exists = pcall(fn_isfile, favoritesPath)
		if existsOk and exists then
			local readOk, raw = pcall(fn_readfile, favoritesPath)
			if readOk then
				local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
				if decodeOk and type(decoded) == "table" then favorites = decoded end
			end
		end
	end
	local function saveFavorites()
		if not (fn_writefile and Private.EnsureAssetsFolder()) then return end
		pcall(fn_writefile, favoritesPath, HttpService:JSONEncode(favorites))
	end
 
	local socket
	local socketConnections = {}
	local isConnected = false
	local isPlaying = false
	local shuffle = false
	local repeatMode = "off"
	local durationMs = 0
	local progressMs = 0
	local lastStateClock = os.clock()
	local seekDragging = false
	local seekPreviewMs = 0
 
	local function setStatus(text, color)
		statusLabel.Text = tostring(text or "")
	statusDot.BackgroundColor3 = color or SilentUI.Theme.TextDim
	end
 
	local notifyTimes = {}
	local function spotifyNotify(key, title, text, notifyType, icon, duration, actions)
		if not panel.IsOpen() then return end
		local now = os.clock()
		if notifyTimes[key] and now - notifyTimes[key] < 2.5 then return end
		notifyTimes[key] = now
		SilentUI:Notify({
			Title = title,
			Text = text,
			Type = notifyType or "info",
			Icon = icon,
			Duration = duration or 5,
			Actions = actions,
		})
	end
 
	local function formatTime(ms)
		local seconds = math.max(0, math.floor((tonumber(ms) or 0) / 1000))
		return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
	end
 
	local function renderProgress()
		local shownProgress = progressMs
		if isPlaying and durationMs > 0 then
			shownProgress = math.min(durationMs, progressMs + (os.clock() - lastStateClock) * 1000)
		end
		local alpha = durationMs > 0 and math.clamp(shownProgress / durationMs, 0, 1) or 0
		if not seekDragging then
			progressFill.Size = UDim2.new(alpha, 0, 1, 0)
			progressKnob.Position = UDim2.new(alpha, 0, 0.5, 0)
			timeLabel.Text = formatTime(shownProgress)
		end
		durationLabel.Text = formatTime(durationMs)
	end
	jan:Add(RunService.Heartbeat:Connect(renderProgress))
 
	local function send(action, extra)
		if not (isConnected and socket) then
			setStatus("Connect the bridge first", Color3.fromRGB(255, 190, 90))
			return false
		end
		local payload = extra or {}
		payload.type = "command"
		payload.action = action
		local ok, err = pcall(function()
			socket:Send(HttpService:JSONEncode(payload))
		end)
		if not ok then
			setStatus("Could not send command: " .. tostring(err), Color3.fromRGB(255, 105, 105))
		end
		return ok
	end
 
	local function setView(name)
		subTabRoot:SelectSubTabByName(name)
	end
 
	local function renderFavorites()
		for _, row in ipairs(favoriteRows) do row:Destroy() end
		table.clear(favoriteRows)
		local query = favoritesSearchBox.Text:lower():gsub("^%s+", ""):gsub("%s+$", "")
		local filtered = {}
		for originalIndex, favorite in ipairs(favorites) do
			local searchable = (tostring(favorite.name or "") .. " " .. tostring(favorite.url or "")):lower()
			if query == "" or searchable:find(query, 1, true) then
				table.insert(filtered, { Favorite = favorite, Index = originalIndex })
			end
		end
		local count = math.min(#filtered, 8)
		local listHeight = count == 0 and 52 or count * 64
		favoritesList.Size = UDim2.new(1, -16, 0, listHeight)
		local dividerY = 51 + listHeight + 7
		saveFavoriteDivider.Position = UDim2.fromOffset(8, dividerY)
		addFavoriteBtn.Position = UDim2.fromOffset(8, dividerY + 10)
		favoritesHeader.Size = UDim2.new(1, 0, 0, dividerY + 74)
		if count == 0 then
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.FontFace = SilentUI.Theme.FontRegular
			empty.Text = query ~= "" and "No saved playlist matches your search" or "No saved playlists yet"
			empty.TextColor3 = SilentUI.Theme.TextDim
			empty.TextSize = 11
			empty.Size = UDim2.fromScale(1, 1)
			empty.ZIndex = Z.Content + 3
			empty.Parent = favoritesList
			table.insert(favoriteRows, empty)
		else
		for visibleIndex = 1, count do
			local entry = filtered[visibleIndex]
			local favorite = entry.Favorite
			local originalIndex = entry.Index
			local row = Instance.new("Frame")
			row.BackgroundColor3 = SilentUI.Theme.Surface
			row.BackgroundTransparency = 0.96
			row.BorderSizePixel = 0
			row.Position = UDim2.fromOffset(0, (visibleIndex - 1) * 64)
			row.Size = UDim2.new(1, 0, 0, 58)
			row.ZIndex = Z.Content + 3
			row.Parent = favoritesList
			Corner(row, 10)
			Stroke(row, SilentUI.Theme.Border, 1, 0.94)
			local playlistIconBox = Instance.new("Frame")
			playlistIconBox.BackgroundColor3 = SilentUI.Theme.Surface
			playlistIconBox.BackgroundTransparency = 0.91
			playlistIconBox.BorderSizePixel = 0
			playlistIconBox.Position = UDim2.fromOffset(10, 9)
			playlistIconBox.Size = UDim2.fromOffset(40, 40)
			playlistIconBox.ZIndex = Z.Content + 4
			playlistIconBox.Parent = row
			Corner(playlistIconBox, 8)
			local playlistIcon = Instance.new("ImageLabel")
			playlistIcon.BackgroundTransparency = 1
			playlistIcon.Image = ResolveIcon("list-music")
			playlistIcon.ImageColor3 = SilentUI.Theme.Text
			playlistIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			playlistIcon.Position = UDim2.fromScale(0.5, 0.5)
			playlistIcon.Size = UDim2.fromOffset(15, 15)
			playlistIcon.ZIndex = Z.Content + 5
			playlistIcon.Parent = playlistIconBox
			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.FontFace = SilentUI.Theme.Font
			name.Text = tostring(favorite.name or "Spotify playlist")
			name.TextColor3 = SilentUI.Theme.Text
			name.TextSize = 11
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Position = UDim2.fromOffset(60, 8)
			name.Size = UDim2.new(1, -152, 0, 20)
			name.ZIndex = Z.Content + 4
			name.Parent = row
			local subtitle = Instance.new("TextLabel")
			subtitle.BackgroundTransparency = 1
			subtitle.FontFace = SilentUI.Theme.FontRegular
			subtitle.Text = "Spotify playlist"
			subtitle.TextColor3 = SilentUI.Theme.TextDim
			subtitle.TextSize = 9
			subtitle.TextXAlignment = Enum.TextXAlignment.Left
			subtitle.Position = UDim2.fromOffset(60, 30)
			subtitle.Size = UDim2.new(1, -152, 0, 16)
			subtitle.ZIndex = Z.Content + 4
			subtitle.Parent = row
			local loadFavorite = Instance.new("TextButton")
			loadFavorite.Text = ""
			loadFavorite.AutoButtonColor = false
			loadFavorite.BackgroundColor3 = SilentUI.Theme.Surface
			loadFavorite.BackgroundTransparency = 0.91
			loadFavorite.BorderSizePixel = 0
			loadFavorite.Position = UDim2.new(1, -76, 0, 13)
			loadFavorite.Size = UDim2.fromOffset(32, 32)
			loadFavorite.ZIndex = Z.Content + 5
			loadFavorite.Parent = row
			Corner(loadFavorite, 8)
			local loadFavoriteIcon = Instance.new("ImageLabel")
			loadFavoriteIcon.BackgroundTransparency = 1
			loadFavoriteIcon.Image = ResolveIcon("play")
			loadFavoriteIcon.ImageColor3 = SilentUI.Theme.Text
			loadFavoriteIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			loadFavoriteIcon.Position = UDim2.fromScale(0.5, 0.5)
			loadFavoriteIcon.Size = UDim2.fromOffset(13, 13)
			loadFavoriteIcon.ZIndex = Z.Content + 6
			loadFavoriteIcon.Parent = loadFavorite
			local removeFavorite = Instance.new("TextButton")
			removeFavorite.Text = ""
			removeFavorite.BackgroundColor3 = SilentUI.Theme.Surface
			removeFavorite.BackgroundTransparency = 0.94
			removeFavorite.Position = UDim2.new(1, -38, 0, 13)
			removeFavorite.Size = UDim2.fromOffset(30, 32)
			removeFavorite.ZIndex = Z.Content + 5
			removeFavorite.Parent = row
			Corner(removeFavorite, 8)
			local removeFavoriteIcon = Instance.new("ImageLabel")
			removeFavoriteIcon.BackgroundTransparency = 1
			removeFavoriteIcon.Image = ResolveIcon("trash-2")
			removeFavoriteIcon.ImageColor3 = Color3.fromRGB(220, 125, 125)
			removeFavoriteIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			removeFavoriteIcon.Position = UDim2.fromScale(0.5, 0.5)
			removeFavoriteIcon.Size = UDim2.fromOffset(13, 13)
			removeFavoriteIcon.ZIndex = Z.Content + 6
			removeFavoriteIcon.Parent = removeFavorite
			jan:Add(loadFavorite.MouseButton1Click:Connect(function()
				playlistBox.Text = tostring(favorite.url or "")
				setView("Spotify Player")
				if send("load_playlist", { url = playlistBox.Text }) then
					setStatus("Loading favorite playlist...", Color3.fromRGB(30, 215, 96))
					spotifyNotify("favorite_load", "Open Spotify Bridge", "Open the browser site, wait for the playlist and press Play once. Then return to Roblox to control it here.", "warning", "external-link", 8)
				end
			end))
			jan:Add(removeFavorite.MouseButton1Click:Connect(function()
				local removedName = tostring(favorite.name or "Spotify playlist")
				table.remove(favorites, originalIndex)
				saveFavorites()
				renderFavorites()
				spotifyNotify("favorite_removed", "Favorite removed", removedName, "success", "trash-2", 3)
			end))
			table.insert(favoriteRows, row)
		end
		end
	end
	jan:Add(favoritesSearchBox:GetPropertyChangedSignal("Text"):Connect(renderFavorites))
 
	jan:Add(addFavoriteBtn.MouseButton1Click:Connect(function()
		local url = playlistBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if url == "" then
			spotifyNotify("favorite_missing", "Nothing to save", "Paste or load a Spotify playlist first.", "warning", "heart", 4)
			return
		end
		for _, favorite in ipairs(favorites) do
			if favorite.url == url then
				spotifyNotify("favorite_duplicate", "Already saved", "This playlist is already in your favorites.", "warning", "heart", 4)
				return
			end
		end
		table.insert(favorites, 1, { name = currentPlaylistName, url = url })
		saveFavorites()
		renderFavorites()
		spotifyNotify("favorite_saved", "Playlist saved", currentPlaylistName .. " was added to Favorites.", "success", "heart", 4)
	end))
	renderFavorites()
 
	local function paintModes()
		controlRefs.PlayPause.Icon.Image = ResolveIcon(isPlaying and "pause" or "play")
		controlRefs.Shuffle.Icon.ImageColor3 = shuffle and Color3.fromRGB(30, 215, 96) or SilentUI.Theme.TextDim
		controlRefs.Repeat.Icon.ImageColor3 = repeatMode ~= "off" and Color3.fromRGB(30, 215, 96) or SilentUI.Theme.TextDim
	end
 
	local function applyState(data)
		local track = data.track or data.item or {}
		local artists = track.artist or track.artists or data.artist
		if type(artists) == "table" then
			local names = {}
			for _, artist in ipairs(artists) do
				table.insert(names, type(artist) == "table" and tostring(artist.name or "") or tostring(artist))
			end
			artists = table.concat(names, ", ")
		end
		trackLabel.Text = tostring(track.name or data.trackName or "Nothing playing")
		artistLabel.Text = tostring(artists or "Spotify")
		showCover(track.image or track.imageUrl or track.albumArt or data.image or data.imageUrl)
		isPlaying = data.isPlaying == true or data.playing == true
		shuffle = data.shuffle == true or data.shuffleState == true
		repeatMode = tostring(data.repeatMode or data.repeat_state or "off")
		durationMs = tonumber(track.durationMs or track.duration_ms or data.durationMs or data.duration_ms) or 0
		progressMs = tonumber(data.progressMs or data.progress_ms or data.positionMs or data.position_ms) or 0
		lastStateClock = os.clock()
		paintModes()
		renderProgress()
		if trackLabel.Text ~= "Playlist ready" and trackLabel.Text ~= "Nothing playing" then
			setStatus(isPlaying and "Playing — controls synced" or "Paused — controls synced", Color3.fromRGB(30, 215, 96))
		end
	end
 
	local function clearSocketConnections()
		for _, connection in ipairs(socketConnections) do
			pcall(function() connection:Disconnect() end)
		end
		table.clear(socketConnections)
	end
 
	local function disconnectBridge(silent)
		clearSocketConnections()
		local oldSocket = socket
		socket = nil
		isConnected = false
		if connectBtnIcon then connectBtnIcon.Image = ResolveIcon("link-2") end
		if oldSocket then pcall(function() oldSocket:Close() end) end
		if not silent then setStatus("Bridge disconnected", SilentUI.Theme.TextDim) end
	end
 
	local function bindSocketEvent(event, callback)
		if event and type(event.Connect) == "function" then
			local ok, connection = pcall(function() return event:Connect(callback) end)
			if ok and connection then table.insert(socketConnections, connection) end
		end
	end
 
	connectBridge = function()
		if isConnected then
			local pageUrl = tostring(opts.ConnectUrl or "")
			local pairUrl = pageUrl .. (pageUrl:find("?", 1, true) and "&" or "?") .. "code=" .. pairBox.Text
			local copy = hasFn("setclipboard")
			if copy then
				pcall(copy, pairUrl)
				setStatus("Player link copied — open it in your browser", Color3.fromRGB(30, 215, 96))
				spotifyNotify("link_copied", "Player link copied", "Open the link in your browser and keep that tab running.", "success", "external-link", 6, {
					{ Text = "Copy again", Callback = function() pcall(copy, pairUrl) end },
				})
			else
				setStatus("Open the player page and enter code " .. pairBox.Text, Color3.fromRGB(255, 190, 90))
				spotifyNotify("manual_code", "Open Spotify Bridge", "Clipboard is unavailable. Open the player page and enter code " .. pairBox.Text .. ".", "warning", "monitor-up", 7)
			end
			return
		end
		local bridgeUrl = tostring(opts.BridgeUrl or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if not bridgeUrl:match("^wss?://") then
			setStatus("Spotify bridge is not configured by the script owner", Color3.fromRGB(255, 105, 105))
			return
		end
		local url = bridgeUrl
			.. (bridgeUrl:find("?", 1, true) and "&" or "?")
			.. "code=" .. pairBox.Text .. "&role=game"
		local connect = websocketConnect()
		if not connect then
			setStatus("This executor has no WebSocket support", Color3.fromRGB(255, 105, 105))
			return
		end
		setStatus("Connecting...", Color3.fromRGB(255, 190, 90))
		if connectBtnIcon then connectBtnIcon.Image = ResolveIcon("loader-circle") end
		task.spawn(function()
			local ok, result = pcall(connect, url)
			if not ok or not result then
				if connectBtnIcon then connectBtnIcon.Image = ResolveIcon("link-2") end
				setStatus("Connection failed: " .. tostring(result), Color3.fromRGB(255, 105, 105))
				return
			end
			socket = result
			isConnected = true
			if connectBtnIcon then connectBtnIcon.Image = ResolveIcon("copy") end
			local pageUrl = tostring(opts.ConnectUrl or "")
			local pairUrl = pageUrl .. (pageUrl:find("?", 1, true) and "&" or "?") .. "code=" .. pairBox.Text
			local copy = hasFn("setclipboard")
			if copy then pcall(copy, pairUrl) end
			setStatus(copy and "Player link copied — open it in your browser" or ("Open player page; code " .. pairBox.Text), Color3.fromRGB(30, 215, 96))
			if copy then
				spotifyNotify("initial_link", "Spotify Connect ready", "The player link was copied. Open it now and keep the browser tab running.", "success", "copy-check", 7, {
					{ Text = "Copy again", Callback = function() pcall(copy, pairUrl) end },
				})
			else
				spotifyNotify("manual_code", "Open Spotify Bridge", "Enter pairing code " .. pairBox.Text .. " on the player page.", "warning", "monitor-up", 7)
			end
 
			bindSocketEvent(socket.OnMessage, function(raw)
				local decoded
				local decodedOk = pcall(function() decoded = HttpService:JSONDecode(tostring(raw)) end)
				if not decodedOk or type(decoded) ~= "table" then return end
				if decoded.type == "state" or decoded.event == "state" then
					applyState(decoded)
				elseif decoded.type == "queue" then
					local playlist = decoded.playlist or {}
					currentPlaylistName = tostring(playlist.name or "Spotify playlist")
					local trackCount = tonumber(decoded.count) or 0
					setStatus(string.format("%s — %d tracks ready", currentPlaylistName, trackCount), Color3.fromRGB(30, 215, 96))
					spotifyNotify("queue_ready_" .. currentPlaylistName, "Playlist ready", string.format("%s loaded with %d tracks.", currentPlaylistName, trackCount), "success", "list-music", 4)
				elseif decoded.type == "ready" or decoded.event == "ready" then
					local message = tostring(decoded.message or "Spotify ready")
					setStatus(message, Color3.fromRGB(30, 215, 96))
					local lower = message:lower()
					if lower:find("press", 1, true) or lower:find("open", 1, true) or lower:find("tap", 1, true) then
						spotifyNotify("browser_action", "Browser action needed", "Open Spotify Bridge and press Play once to unlock remote controls.", "warning", "monitor-play", 7)
					end
				elseif decoded.type == "needs_browser" then
					local message = tostring(decoded.message or "Open the Spotify player tab once to continue playback")
					setStatus(message, Color3.fromRGB(255, 190, 90))
					spotifyNotify("browser_attention", "Spotify needs attention", message, "warning", "external-link", 7)
				elseif decoded.type == "error" or decoded.event == "error" then
					local message = tostring(decoded.message or decoded.error or "Spotify bridge error")
					setStatus(message, Color3.fromRGB(255, 105, 105))
					spotifyNotify("spotify_error_" .. message, "Spotify error", message, "error", "circle-x", 6)
				end
			end)
			bindSocketEvent(socket.OnClose, function()
				disconnectBridge(false)
			end)
			send("hello", { client = "SilentUI", protocol = 1 })
		end)
	end
 
	jan:Add(connectBtn.MouseButton1Click:Connect(connectBridge))
	jan:Add(loadBtn.MouseButton1Click:Connect(function()
		local url = playlistBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if url == "" then
			setStatus("Paste a Spotify playlist link", Color3.fromRGB(255, 190, 90))
			return
		end
		if send("load_playlist", { url = url }) then
			setStatus("Playlist sent to Spotify", Color3.fromRGB(30, 215, 96))
			spotifyNotify("playlist_sent", "Open Spotify Bridge", "Open the browser site, wait for the playlist and press Play once. Then return to Roblox to control it here.", "warning", "external-link", 8)
		end
	end))
	local function searchPlaylist()
		local query = searchBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if query == "" then setStatus("Type a song or artist to search", Color3.fromRGB(255, 190, 90)); return end
		if send("search", { query = query }) then setStatus("Searching this playlist...", Color3.fromRGB(30, 215, 96)) end
	end
	jan:Add(searchBtn.MouseButton1Click:Connect(searchPlaylist))
	jan:Add(searchBox.FocusLost:Connect(function(enterPressed) if enterPressed then searchPlaylist() end end))
	jan:Add(shuffleBtn.MouseButton1Click:Connect(function() send("toggle_shuffle") end))
	jan:Add(previousBtn.MouseButton1Click:Connect(function() send("previous") end))
	jan:Add(playBtn.MouseButton1Click:Connect(function() send("play_pause") end))
	jan:Add(nextBtn.MouseButton1Click:Connect(function() send("next") end))
	jan:Add(repeatBtn.MouseButton1Click:Connect(function() send("cycle_repeat") end))
	local seekInput
	local function updateSeekPreview(screenX)
		if durationMs <= 0 or progressTrack.AbsoluteSize.X <= 0 then return end
		local alpha = math.clamp((screenX - progressTrack.AbsolutePosition.X) / progressTrack.AbsoluteSize.X, 0, 1)
		seekPreviewMs = math.floor(durationMs * alpha)
		progressFill.Size = UDim2.new(alpha, 0, 1, 0)
		progressKnob.Position = UDim2.new(alpha, 0, 0.5, 0)
		seekBubble.Position = UDim2.new(math.clamp(alpha, 0.04, 0.96), 0, 0, -8)
		seekBubbleLabel.Text = formatTime(seekPreviewMs)
		timeLabel.Text = formatTime(seekPreviewMs)
	end
	jan:Add(progressHitbox.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if durationMs <= 0 then return end
		seekDragging = true
		seekInput = input
		seekBubble.Visible = true
		updateSeekPreview(input.Position.X)
	end))
	jan:Add(UserInputService.InputChanged:Connect(function(input)
		if not seekDragging then return end
		if input == seekInput or input.UserInputType == Enum.UserInputType.MouseMovement then
			updateSeekPreview(input.Position.X)
		end
	end))
	jan:Add(UserInputService.InputEnded:Connect(function(input)
		if not seekDragging then return end
		if input ~= seekInput and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		updateSeekPreview(input.Position.X)
		seekDragging = false
		seekInput = nil
		seekBubble.Visible = false
		if send("seek", { positionMs = seekPreviewMs }) then
			progressMs = seekPreviewMs
			lastStateClock = os.clock()
		end
		renderProgress()
	end))
 
	jan:Add(function() disconnectBridge(true) end)
	dockBtn = self:AddDockButton({
		Owner = "library",
		Order = 1,
		Icon = opts.Icon or "Lucide:music-2",
		FallbackText = "♫",
		Callback = function() panel.Toggle() end,
	})
 
	panel.Connect = connectBridge
	panel.Disconnect = disconnectBridge
	panel.Send = send
	panel.SetState = applyState
	if opts.BridgeUrl == nil or opts.BridgeUrl == "" then
		setStatus("Spotify bridge is not configured by the script owner", Color3.fromRGB(255, 190, 90))
	else
		setStatus("Tap Connect, then open the copied browser link", SilentUI.Theme.TextDim)
	end
    self._librarySpotifyPanel = panel
	return panel
end
 
function Window:AddCloudPanel(opts)
	opts = opts or {}
	local service = opts.Service
 
	local tabObj = self:AddTab({
		Name   = opts.Name or "Cloud",
		Icon   = opts.Icon or "cloud",
		Hidden = opts.Hidden ~= false,
	})
 
	table.insert(self._tabChangeListeners, function(selected)
		if opts.OnToggle then task.spawn(opts.OnToggle, selected == tabObj) end
	end)
 
	local mineGrid, publicGrid, localGrid
	local function relativeTime(timestamp)
		local seconds = math.max(0, os.time() - tonumber(timestamp or os.time()))
		if seconds < 60 then return "updated just now" end
		if seconds < 3600 then return "updated " .. math.floor(seconds / 60) .. "m ago" end
		if seconds < 86400 then return "updated " .. math.floor(seconds / 3600) .. "h ago" end
		return "updated " .. math.floor(seconds / 86400) .. "d ago"
	end
 
	local CloudTabs = {
		Local = tabObj:AddSubTab({ Name = "Local Configs", Icon = "Lucide:hard-drive" }),
		Mine = tabObj:AddSubTab({ Name = "Publish Public Config", Icon = "Lucide:cloud-cog" }),
		Explore = tabObj:AddSubTab({ Name = "Public Configs", Icon = "Lucide:cloud" }),
	}
 
	CloudTabs.Local:AddParagraph({
		Title = "Local Library",
		Icon = "Lucide:hard-drive",
		Text = "Private presets saved only on this device. Load, create and manage them without uploading anything.",
	})
 
	CloudTabs.Local:AddSection("Quick Actions", "Lucide:zap")
	CloudTabs.Local:AddButton({
		Text = "Save Current Settings Locally",
		Description = "Stays on this device only",
		Icon = "Lucide:save",
		Callback = function()
			SilentUI:Modal({
				Title = "Save Config Locally",
				Text  = "Stays only on this device -- never sent anywhere.",
				ConfirmText = "Save",
				CancelText  = "Cancel",
				Window = self,
				Fields = {
					{ Key = "Name", Label = "Name", Placeholder = "Enter a name...", MaxLength = 60 },
					{ Key = "Description", Label = "Description (optional)", Type = "textarea",
						Placeholder = "What's different about this one?", MaxLength = 280 },
				},
				Callback = function(confirmed, values)
					if not confirmed then return end
					if not values.Name or values.Name:gsub("%s+", "") == "" then
						SilentUI:Notify({ Title = "Local Save", Text = "Name can't be empty.", Type = "warning", Duration = 3 })
						return
					end
					local function saveNow()
						local ok, err = SilentUI:SaveConfig(values.Name, { Description = values.Description })
						SilentUI:Notify({
							Title = ok and "Saved" or "Could not save", Text = ok and "Saved locally." or tostring(err),
							Type = ok and "success" or "error", Duration = 3,
						})
						if ok and localGrid then localGrid.Refresh() end
					end
					if SilentUI:GetConfigMeta(values.Name) then
						SilentUI:Confirm({
							Title = "Overwrite \"" .. tostring(values.Name) .. "\"?",
							Text = "A local config already uses this name.", ConfirmText = "Overwrite", CancelText = "Cancel",
							Danger = true, Window = self,
							Callback = function(overwrite) if overwrite then saveNow() end end,
						})
					else
						saveNow()
					end
				end,
			})
		end,
	})
 
	localGrid = CloudTabs.Local:AddCardGrid({
		Title = "Local Configs",
		Height = 224,
		FixedHeight = true,
		Search = true,
		SearchPlaceholder = "Search local configs...",
		CardHeight = 68,
		AutoCardHeight = false,
		CardMinWidth = 180,
		Columns = 2,
		MaxColumns = 2,
		OuterPadding = 12,
		CardPadding = 8,
		ShowScrollbar = true,
		EmptyText = "No local configs saved yet.",
		ErrorText = "Your executor doesn't support local file access.",
		Fetch = function(state)
			local items, err = SilentUI:ListConfigs()
			if err and #items == 0 then return nil, err end
			local query = string.lower(tostring(state and state.Query or ""))
			local out = {}
			for _, cfg in ipairs(items) do
				local searchable = string.lower(table.concat({
					tostring(cfg.Name or ""),
					tostring(cfg.Description or ""),
					table.concat(cfg.Tags or {}, " "),
				}, " "))
				if query ~= "" and not string.find(searchable, query, 1, true) then continue end
 
				local function loadLocalConfig()
					SilentUI:Confirm({
						Title = "Load \"" .. tostring(cfg.Name) .. "\"?",
						Text = "This overwrites your current settings. A snapshot is kept for instant undo.",
						ConfirmText = "Load", CancelText = "Cancel", Window = self,
						Callback = function(confirmedLoad)
							if not confirmedLoad then return end
							local snapshot = SilentUI:CreateSnapshot()
							local ok, loadErr = SilentUI:LoadConfig(cfg.Name, false)
							if not ok then
								SilentUI:Notify({ Title = "Could not load", Text = tostring(loadErr), Type = "error", Duration = 4 })
								return
							end
							SilentUI:Notify({
								Title = "Loaded", Text = tostring(cfg.Name) .. " is now active.", Type = "success", Duration = 6,
								Actions = {{ Text = "Undo", Callback = function() SilentUI:RestoreSnapshot(snapshot, false) end }},
							})
						end,
					})
				end
 
				local function renameLocalConfig()
					SilentUI:Modal({
						Title = "Rename Config", Text = "Choose a new name for \"" .. tostring(cfg.Name) .. "\".",
						ConfirmText = "Rename", CancelText = "Cancel", Window = self,
						Fields = {{ Key = "Name", Label = "New name", Default = cfg.Name, MaxLength = 60 }},
						Callback = function(confirmed, values)
							if not confirmed then return end
							local newName = tostring(values.Name or ""):match("^%s*(.-)%s*$")
							if newName == "" then return end
							local existing = SilentUI:GetConfigMeta(newName)
							if existing and newName ~= cfg.Name then
								SilentUI:Notify({ Title = "Name already used", Text = "Choose another config name.", Type = "warning", Duration = 3 })
								return
							end
							local ok, renameErr = SilentUI:RenameConfig(cfg.Name, newName)
							SilentUI:Notify({ Title = ok and "Renamed" or "Could not rename", Text = ok and "Config name updated." or tostring(renameErr), Type = ok and "success" or "error", Duration = 3 })
							if ok and localGrid then localGrid.Refresh() end
						end,
					})
				end
 
				local function publishLocalConfig()
					if not service then
						SilentUI:Notify({ Title = "Cloud", Text = "No cloud service configured.", Type = "warning", Duration = 3 })
						return
					end
					local saved, savedErr = SilentUI:GetSavedConfig(cfg.Name)
					if not saved then
						SilentUI:Notify({ Title = "Could not read config", Text = tostring(savedErr), Type = "error", Duration = 3 })
						return
					end
					local result, publishErr = service:Publish({ Name = cfg.Name, Description = cfg.Description, Tags = cfg.Tags }, saved.Data)
					SilentUI:Notify({ Title = result and "Published" or "Could not publish", Text = result and "Config published successfully." or tostring(publishErr), Type = result and "success" or "error", Duration = 4 })
					if result then
						if mineGrid then mineGrid.Refresh() end
						if publicGrid then publicGrid.Refresh() end
					end
				end
 
				local function deleteLocalConfig()
					SilentUI:Confirm({
						Title = "Delete \"" .. tostring(cfg.Name) .. "\"?", Text = "This local config will be permanently removed.",
						ConfirmText = "Delete", CancelText = "Cancel", Danger = true, Window = self,
						Callback = function(confirmed)
							if not confirmed then return end
							local ok, deleteErr = SilentUI:DeleteConfig(cfg.Name)
							SilentUI:Notify({ Title = ok and "Deleted" or "Could not delete", Text = ok and "Config removed." or tostring(deleteErr), Type = ok and "success" or "error", Duration = 3 })
							if ok and localGrid then localGrid.Refresh() end
						end,
					})
				end
 
				table.insert(out, {
					Title = cfg.Name,
					Description = cfg.Description,
					Byline = relativeTime(cfg.CreatedAt)
						.. ((cfg.Tags and #cfg.Tags > 0) and ("  •  " .. table.concat(cfg.Tags, ", ")) or ""),
					Icon = "Lucide:file-text",
					ActionIcon = "download",
					Callback = loadLocalConfig,
					SecondaryIcon = "trash-2",
					SecondaryCallback = deleteLocalConfig,
					SecondaryDanger = true,
				})
			end
			return out
		end,
	})
 
	local function publishFlow()
		if not service then
			SilentUI:Notify({ Title = "Cloud", Text = "No cloud service configured.", Type = "warning", Duration = 3 })
			return
		end
		SilentUI:Modal({
			Title = "New Config",
			ConfirmText = "Publish",
			CancelText = "Cancel",
			Window = self,
			Fields = {
				{ Key = "Name", Label = "Name", Placeholder = "Enter profile name...", MaxLength = 60 },
				{ Key = "Description", Label = "Description", Type = "textarea",
					Placeholder = "Enter profile's description...", MaxLength = 280 },
				{ Key = "Tags", Label = "Tags (optional)", Type = "tags",
					Placeholder = "Enter tags separated by commas..." },
			},
			Callback = function(confirmed, values)
				if not confirmed then return end
				local result, err = service:Publish({
					Name = values.Name,
					Description = values.Description,
					Tags = values.Tags,
				})
				SilentUI:Notify({
					Title = result and "Published" or "Could not publish",
					Text  = result and "Your config is now public." or tostring(err),
					Type  = result and "success" or "error",
					Duration = 4,
				})
				if result then
					if mineGrid then mineGrid.Refresh() end
					if publicGrid then publicGrid.Refresh() end
				end
			end,
		})
	end
 
	CloudTabs.Mine:AddParagraph({
		Title = "My Cloud Library",
		Icon = "Lucide:cloud",
		Text = "Publish your current setup, review what you shared and remove old uploads from one place.",
	})
 
	CloudTabs.Mine:AddSection("Publishing", "Lucide:upload-cloud")
	CloudTabs.Mine:AddButton({
		Text = "Publish Current Settings",
		Description = "Share your current config publicly",
		Icon = "Lucide:upload-cloud",
		Callback = publishFlow,
	})
 
	mineGrid = CloudTabs.Mine:AddCardGrid({
		Title = "Your Configs",
		Height = 210,
		FixedHeight = true,
		Search = false,
		CardHeight = 104,
		AutoCardHeight = false,
		DescriptionHeight = 24,
		CardMinWidth = 180,
		Columns = 2,
		MaxColumns = 2,
		OuterPadding = 12,
		CardPadding = 8,
		ShowScrollbar = true,
		EmptyText = service and "You haven't published anything yet." or "No cloud service configured.",
		ErrorText = "Couldn't load your configs.",
		Fetch = function()
			if not service then
				return {}, nil
			end
			local items, err = service:ListMine()
			if not items then return nil, err end
			local out = {}
			for _, cfg in ipairs(items) do
				local function deletePublishedConfig()
					SilentUI:Confirm({
						Title = "Delete \"" .. tostring(cfg.Name) .. "\"?",
						Text = "This removes it from the public library. This cannot be undone.",
						ConfirmText = "Delete", CancelText = "Cancel", Danger = true, Window = self,
						Callback = function(confirmedDelete)
							if not confirmedDelete then return end
							local ok, delErr = service:Delete(cfg.Id)
							SilentUI:Notify({ Title = ok and "Deleted" or "Could not delete", Text = ok and "Config removed." or tostring(delErr), Type = ok and "success" or "error", Duration = 3 })
							if ok then
								if mineGrid then mineGrid.Refresh() end
								if publicGrid then publicGrid.Refresh() end
							end
						end,
					})
				end
				table.insert(out, {
					Title = cfg.Name,
					Description = cfg.Description,
					Byline = cfg.CreatedAtText or "",
					Icon = "Lucide:cloud",
					Stats = {
						{ Icon = "thumbs-up", Text = tostring(cfg.Likes or 0) },
						{ Icon = "download", Text = tostring(cfg.Downloads or 0) },
					},
					Menu = {
						{ Text = "Delete publication", Icon = "trash-2", Danger = true, Callback = deletePublishedConfig },
					},
				})
			end
			return out
		end,
	})
 
	CloudTabs.Explore:AddParagraph({
		Title = "Community Library",
		Icon = "Lucide:compass",
		Text = "Discover public configs, compare popularity and apply a setup with an instant undo snapshot.",
	})
 
	CloudTabs.Explore:AddSection("Browse Configs", "Lucide:layout-grid")
 
	local SORT_MAP = { ["Top Rated"] = "top", ["Most Downloaded"] = "downloads", ["Newest"] = "new" }
 
	publicGrid = CloudTabs.Explore:AddCardGrid({
		Title = "Public Configs",
		Height = 230,
		FixedHeight = true,
		Sorts = { "Top Rated", "Most Downloaded", "Newest" },
		SearchPlaceholder = "Search config by name / tags...",
		CardHeight = 112,
		AutoCardHeight = false,
		DescriptionHeight = 24,
		CardMinWidth = 180,
		Columns = 2,
		MaxColumns = 2,
		OuterPadding = 12,
		CardPadding = 8,
		ShowScrollbar = true,
		EmptyText = "No public configs match your search.",
		ErrorText = "Couldn't reach the cloud service.",
		Fetch = function(state)
			if not service then return nil, "No cloud service configured." end
			local items, err = service:List({
				Query = state.Query,
				Sort = SORT_MAP[state.Sort] or "top",
				PageSize = state.PageSize,
			})
			if not items then return nil, err end
			local out = {}
			for _, cfg in ipairs(items) do
				local byline = cfg.OwnerName or "anonymous"
				if cfg.CreatedAtText then byline = byline .. " \226\128\162 " .. cfg.CreatedAtText end
				table.insert(out, {
					Title = cfg.Name,
					Description = cfg.Description,
					Byline = byline,
					Icon = "Lucide:cloud-download",
					ActionIcon = "download",
					Stats = {
						{
							Icon = "thumbs-up",
							Text = tostring(cfg.Likes or 0),
							Callback = function()
								local liked, likeErr = service:Like(cfg.Id)
								if not liked then
									SilentUI:Notify({
										Title = "Could not like",
										Text  = tostring(likeErr),
										Type  = "error",
										Duration = 3,
									})
									return
								end
								if publicGrid then publicGrid.Refresh() end
							end,
						},
						{ Icon = "download", Text = tostring(cfg.Downloads or 0) },
					},
					Callback = function()
						SilentUI:Confirm({
							Title = "Apply \"" .. tostring(cfg.Name) .. "\"?",
							Text  = "This overwrites your current settings. A snapshot of what you have now "
								.. "is kept so you can undo it right after.",
							ConfirmText = "Apply",
							CancelText  = "Cancel",
							Window = self,
							Callback = function(confirmedApply)
								if not confirmedApply then return end
								local result, dlErr = service:Download(cfg.Id)
								if not result or not result.Data then
									SilentUI:Notify({
										Title = "Could not apply",
										Text  = tostring(dlErr),
										Type  = "error",
										Duration = 4,
									})
									return
								end
 
								local snapshot = SilentUI:CreateSnapshot()
								local applied, applyErr = SilentUI:SetConfig(result.Data, false)
								if not applied then
									SilentUI:Notify({
										Title = "Could not apply",
										Text = tostring(applyErr),
										Type = "error",
										Duration = 5,
									})
									return
								end
								SilentUI:Notify({
									Title = "Applied",
									Text  = tostring(cfg.Name) .. " is now active.",
									Type  = "success",
									Duration = 6,
									Actions = {
										{
											Text = "Undo",
											Callback = function()
												SilentUI:RestoreSnapshot(snapshot, false)
												SilentUI:Notify({
													Title = "Reverted",
													Text  = "Your previous settings are back.",
													Type  = "info",
													Duration = 3,
												})
											end,
										},
									},
								})
 
								if publicGrid then publicGrid.Refresh() end
								if opts.OnApplied then task.spawn(opts.OnApplied, cfg) end
							end,
						})
					end,
				})
			end
			return out
		end,
	})
 
	local lastRealTab = nil
	local function openPanel()
		if self._currentTab == tabObj then return end
		if self._currentTab and not self._currentTab.Hidden then
			lastRealTab = self._currentTab
		end
		tabObj._select()
	end
	local function closePanel()
		if self._currentTab ~= tabObj then return end
		if lastRealTab and not lastRealTab.Hidden then
			lastRealTab._select()
		elseif self._tabs[1] and self._tabs[1] ~= tabObj then
			self._tabs[1]._select()
		end
	end
 
	return {
		Instance = tabObj._group,
		Tab = tabObj,
		Open = openPanel,
		Close = closePanel,
		Toggle = function()
			if self._currentTab == tabObj then closePanel() else openPanel() end
		end,
		IsOpen = function() return self._currentTab == tabObj end,
		RefreshMine = function() if mineGrid then mineGrid.Refresh() end end,
		RefreshPublic = function() if publicGrid then publicGrid.Refresh() end end,
	}
end
 
function Window:AddGlobalChatPanel(opts)
	opts = opts or {}
	local service = opts.Service
	local jan = self._janitor
 
	local tabObj = self:AddTab({
		Name   = opts.Name or "Chat",
		Icon   = opts.Icon or "messages-square",
		Hidden = opts.Hidden ~= false,
	})
	tabObj._page.Visible = false
	local staleEmptyState = tabObj._group:FindFirstChild("EmptyState")
	if staleEmptyState then staleEmptyState.Visible = false end
 
	table.insert(self._tabChangeListeners, function(selected)
		if opts.OnToggle then task.spawn(opts.OnToggle, selected == tabObj) end
	end)
 
	local INPUT_H, HEADER_H = 38, 38
 
	local panel = Instance.new("Frame")
	panel.Name = "GlobalChatPanel"
	panel.BackgroundTransparency = 1
	panel.ClipsDescendants = true
	panel.Size = UDim2.fromScale(1, 1)
	panel.ZIndex = Z.Content
	panel.Parent = tabObj._group
 
	local BASE_Z = panel.ZIndex + 1
 
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = panel.ZIndex
	content.Parent = panel
 
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Active = true
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.ZIndex = BASE_Z
	header.Parent = content
 
	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, 14)
	headerPad.PaddingRight = UDim.new(0, 8)
	headerPad.Parent = header
 
	local titleRow = Instance.new("Frame")
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, -136, 1, 0)
	titleRow.ZIndex = BASE_Z + 1
	titleRow.Parent = header
 
	local titleLayout = Instance.new("UIListLayout")
	titleLayout.FillDirection = Enum.FillDirection.Horizontal
	titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleLayout.Padding = UDim.new(0, 7)
	titleLayout.Parent = titleRow
 
	local titleIcon = Instance.new("ImageLabel")
	titleIcon.BackgroundTransparency = 1
	titleIcon.Image = ResolveIcon(opts.Icon or "messages-square")
	titleIcon.ImageColor3 = SilentUI.Theme.Text
	titleIcon.Size = UDim2.fromOffset(14, 14)
	titleIcon.LayoutOrder = 1
	titleIcon.ZIndex = BASE_Z + 2
	titleIcon.Parent = titleRow
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = SilentUI.Theme.Font
	titleLabel.Text = opts.Title or "Chat"
	titleLabel.TextColor3 = SilentUI.Theme.Text
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.AutomaticSize = Enum.AutomaticSize.X
	titleLabel.Size = UDim2.fromOffset(0, 16)
	titleLabel.LayoutOrder = 2
	titleLabel.ZIndex = BASE_Z + 2
	titleLabel.Parent = titleRow
 
	local controls = Instance.new("Frame")
	controls.BackgroundTransparency = 1
	controls.AnchorPoint = Vector2.new(1, 0.5)
	controls.Position = UDim2.new(1, 0, 0.5, 0)
	controls.Size = UDim2.fromOffset(126, 22)
	controls.ZIndex = BASE_Z + 1
	controls.Parent = header
 
	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.FillDirection = Enum.FillDirection.Horizontal
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlsLayout.Padding = UDim.new(0, 4)
	controlsLayout.Parent = controls
 
	local function headerIconButton(icon, layoutOrder)
		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = SilentUI.Theme.Surface
		btn.BackgroundTransparency = 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.fromOffset(22, 22)
		btn.LayoutOrder = layoutOrder
		btn.ZIndex = BASE_Z + 1
		btn.Parent = controls
		Corner(btn, 6)
 
		local ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Image = ResolveIcon(icon)
		ic.ImageColor3 = SilentUI.Theme.TextDim
		ic.Size = UDim2.fromOffset(13, 13)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.ZIndex = BASE_Z + 2
		ic.Parent = btn
 
		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = 0.9 }, 0.12)
			Tween(ic, { ImageColor3 = SilentUI.Theme.Text }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = 1 }, 0.12)
			Tween(ic, { ImageColor3 = SilentUI.Theme.TextDim }, 0.12)
		end))
 
		return btn, ic
	end
 
	local anonymousMode = opts.AnonymousByDefault ~= false
	local showTimestamps = true
	local notifySound = false
	local pollInterval = opts.PollInterval or 2.5
 
	local copyBtn, copyIcon = headerIconButton("copy", 1)
	local anonBtn, anonIcon = headerIconButton(anonymousMode and "eye-off" or "eye", 2)
	local clearBtn, clearIcon = headerIconButton("trash-2", 3)
	local settingsBtn, settingsIcon = headerIconButton("settings", 4)
	local closeBtn, closeIcon = headerIconButton("x", 5)
 
	local headerDivider = Instance.new("Frame")
	headerDivider.BackgroundColor3 = SilentUI.Theme.Surface
	headerDivider.BackgroundTransparency = 0.94
	headerDivider.BorderSizePixel = 0
	headerDivider.Position = UDim2.fromOffset(0, HEADER_H)
	headerDivider.Size = UDim2.new(1, 0, 0, 1)
	headerDivider.ZIndex = BASE_Z
	headerDivider.Parent = content
 
	local contentPad = Instance.new("UIPadding")
	contentPad.PaddingLeft = UDim.new(0, 14)
	contentPad.PaddingRight = UDim.new(0, 14)
	contentPad.PaddingBottom = UDim.new(0, 12)
	contentPad.Parent = content
 
	local inputRow = Instance.new("Frame")
	inputRow.BackgroundTransparency = 1
	inputRow.Active = true
	inputRow.AnchorPoint = Vector2.new(0, 1)
	inputRow.Position = UDim2.new(0, 0, 1, 0)
	inputRow.Size = UDim2.new(1, 0, 0, INPUT_H)
	inputRow.ZIndex = BASE_Z
	inputRow.Parent = content
 
	local pill = Instance.new("Frame")
	pill.BackgroundColor3 = SilentUI.Theme.Surface
	pill.BackgroundTransparency = 0.95
	pill.BorderSizePixel = 0
	pill.Size = UDim2.new(1, -(INPUT_H + 6), 1, 0)
	pill.ZIndex = BASE_Z + 1
	pill.Parent = inputRow
	Corner(pill, 9)
	local pillStroke = Stroke(pill, SilentUI.Theme.Border, 1, 0.9)
 
	local pillPad = Instance.new("UIPadding")
	pillPad.PaddingLeft = UDim.new(0, 10)
	pillPad.PaddingRight = UDim.new(0, 10)
	pillPad.Parent = pill
 
	local inputBox = Instance.new("TextBox")
	inputBox.BackgroundTransparency = 1
	inputBox.ClearTextOnFocus = false
	inputBox.FontFace = SilentUI.Theme.FontRegular
	inputBox.PlaceholderText = opts.Placeholder or "Message everyone using this script..."
	inputBox.PlaceholderColor3 = SilentUI.Theme.TextDim
	inputBox.Text = ""
	inputBox.TextColor3 = SilentUI.Theme.Text
	inputBox.TextSize = 13
	inputBox.TextXAlignment = Enum.TextXAlignment.Left
	inputBox.TextYAlignment = Enum.TextYAlignment.Center
	inputBox.ClipsDescendants = true
	inputBox.Size = UDim2.fromScale(1, 1)
	inputBox.ZIndex = BASE_Z + 2
	inputBox.Parent = pill
 
	jan:Add(inputBox.Focused:Connect(function()
		Tween(pillStroke, { Color = SilentUI.Theme.Accent, Transparency = 0.3 }, 0.15)
	end))
	jan:Add(inputBox.FocusLost:Connect(function()
		Tween(pillStroke, { Color = SilentUI.Theme.Border, Transparency = 0.9 }, 0.15)
	end))
 
	local sendBtn = Instance.new("TextButton")
	sendBtn.Text = ""
	sendBtn.AutoButtonColor = false
	sendBtn.BackgroundColor3 = SilentUI.Theme.Surface
	sendBtn.BackgroundTransparency = 0.9
	sendBtn.BorderSizePixel = 0
	sendBtn.AnchorPoint = Vector2.new(1, 0)
	sendBtn.Position = UDim2.new(1, 0, 0, 0)
	sendBtn.Size = UDim2.fromOffset(INPUT_H, INPUT_H)
	sendBtn.ZIndex = BASE_Z + 1
	sendBtn.Parent = inputRow
	Corner(sendBtn, 9)
 
	local sendIcon = Instance.new("ImageLabel")
	sendIcon.BackgroundTransparency = 1
	sendIcon.Image = ResolveIcon("send")
	sendIcon.ImageColor3 = SilentUI.Theme.Text
	sendIcon.Size = UDim2.fromOffset(14, 14)
	sendIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	sendIcon.Position = UDim2.fromScale(0.5, 0.5)
	sendIcon.ZIndex = BASE_Z + 2
	sendIcon.Parent = sendBtn
 
	jan:Add(sendBtn.MouseEnter:Connect(function() Tween(sendBtn, { BackgroundTransparency = 0.8 }, 0.12) end))
	jan:Add(sendBtn.MouseLeave:Connect(function() Tween(sendBtn, { BackgroundTransparency = 0.9 }, 0.12) end))
 
	local msgScroll = Instance.new("ScrollingFrame")
	msgScroll.BackgroundTransparency = 1
	msgScroll.BorderSizePixel = 0
	msgScroll.Position = UDim2.fromOffset(0, HEADER_H + 9)
	msgScroll.Size = UDim2.new(1, 0, 1, -(HEADER_H + 9 + INPUT_H + 10))
	msgScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	msgScroll.ScrollBarThickness = 0
	msgScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	msgScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	msgScroll.ZIndex = BASE_Z
	msgScroll.Parent = content
 
	local msgPad = Instance.new("UIPadding")
	msgPad.PaddingRight = UDim.new(0, 18)
	msgPad.Parent = msgScroll
 
	local msgLayout = Instance.new("UIListLayout")
	msgLayout.Padding = UDim.new(0, 8)
	msgLayout.SortOrder = Enum.SortOrder.LayoutOrder
	msgLayout.Parent = msgScroll
 
	AddScrollbar(msgScroll)
	Private.AddContentScrollThumb(msgScroll, msgLayout, panel, jan)
 
	local order = 0
	local transcript = {}
	local timestampLabels = {}
	local pinnedToBottom = true
	jan:Add(msgScroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
		if pinnedToBottom then
			msgScroll.CanvasPosition = Vector2.new(0, msgScroll.AbsoluteCanvasSize.Y)
		end
	end))
	jan:Add(msgScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local atBottom = msgScroll.CanvasPosition.Y
			>= msgScroll.AbsoluteCanvasSize.Y - msgScroll.AbsoluteWindowSize.Y - 20
		pinnedToBottom = atBottom
	end))
 
	local function scrollToBottom()
		pinnedToBottom = true
		task.defer(function()
			if msgScroll and msgScroll.Parent then
				msgScroll.CanvasPosition = Vector2.new(0, msgScroll.AbsoluteCanvasSize.Y)
			end
		end)
	end
 
	local AVATAR = 26
 
	local function addBubble(msg, isOwn)
		order = order + 1
		local text = tostring(msg.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if text == "" then return end
 
		local row = Instance.new("Frame")
		row.Name = "ChatRow"
		row.BackgroundTransparency = 1
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Size = UDim2.new(1, 0, 0, 0)
		row.LayoutOrder = order
		row.ZIndex = BASE_Z + 1
		row.Parent = msgScroll
 
		local rowScale = Instance.new("UIScale")
		rowScale.Scale = 0.92
		rowScale.Parent = row
 
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.HorizontalAlignment = isOwn and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		rowLayout.Padding = UDim.new(0, 8)
		rowLayout.Parent = row
 
		local isAnon = not msg.UserId or msg.UserId == 0
 
		local avatar = Instance.new("Frame")
		avatar.Name = "Avatar"
 
		avatar.BackgroundColor3 = isAnon and Color3.fromRGB(196, 143, 105) or SilentUI.Theme.Accent
		avatar.BackgroundTransparency = 1
		avatar.BorderSizePixel = 0
		avatar.Size = UDim2.fromOffset(AVATAR, AVATAR)
		avatar.LayoutOrder = isOwn and 2 or 1
		avatar.ZIndex = BASE_Z + 2
		avatar.Parent = row
		Corner(avatar, AVATAR / 2)
 
		if isAnon then
			local anonIconImg = Instance.new("ImageLabel")
			anonIconImg.BackgroundTransparency = 1
			anonIconImg.ImageTransparency = 1
			anonIconImg.Image = ResolveIcon("user-round")
			anonIconImg.ImageColor3 = Color3.fromRGB(90, 61, 40)
			anonIconImg.Size = UDim2.fromOffset(15, 15)
			anonIconImg.AnchorPoint = Vector2.new(0.5, 0.5)
			anonIconImg.Position = UDim2.fromScale(0.5, 0.5)
			anonIconImg.ZIndex = BASE_Z + 3
			anonIconImg.Parent = avatar
			Tween(anonIconImg, { ImageTransparency = 0 }, 0.16)
		else
			local avatarImg = Instance.new("ImageLabel")
			avatarImg.BackgroundTransparency = 1
			avatarImg.ImageTransparency = 1
			avatarImg.ScaleType = Enum.ScaleType.Crop
			avatarImg.Size = UDim2.fromScale(1, 1)
			avatarImg.ZIndex = BASE_Z + 3
			avatarImg.Parent = avatar
			Corner(avatarImg, AVATAR / 2)
			Tween(avatarImg, { ImageTransparency = 0 }, 0.16)
			task.spawn(function()
				local ok, content = pcall(
					Players.GetUserThumbnailAsync,
					Players,
					msg.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size100x100
				)
				if ok and content and avatarImg.Parent then
					avatarImg.Image = content
				end
			end)
		end
 
		local H_PAD, V_PAD = 10, 8
		local BUBBLE_MAX_WIDTH = 240
 
		local MIN_BUBBLE_WIDTH = 64
		local naturalW = MeasureText(text, 13, 10000)
		local bubbleWidth = math.min(naturalW, BUBBLE_MAX_WIDTH - H_PAD * 2) + H_PAD * 2
		bubbleWidth = math.max(bubbleWidth, MIN_BUBBLE_WIDTH)
		if msgScroll.AbsoluteSize.X > 0 then
			bubbleWidth = math.min(bubbleWidth, math.max(160, msgScroll.AbsoluteSize.X - 20))
		end
 
		local bubble = Instance.new("Frame")
		bubble.Name = "Bubble"
		bubble.BackgroundColor3 = isOwn and SilentUI.Theme.Accent or SilentUI.Theme.Surface
		bubble.BackgroundTransparency = 1
		bubble.BorderSizePixel = 0
		bubble.ClipsDescendants = true
		bubble.AutomaticSize = Enum.AutomaticSize.Y
		bubble.Size = UDim2.fromOffset(bubbleWidth, 0)
		bubble.LayoutOrder = isOwn and 1 or 2
		bubble.ZIndex = BASE_Z + 2
		bubble.Parent = row
		Corner(bubble, 12)
		local bubbleStroke = Stroke(bubble, SilentUI.Theme.Border, 1, 1)
 
		local bubblePad = Instance.new("UIPadding")
		bubblePad.PaddingTop = UDim.new(0, V_PAD)
		bubblePad.PaddingBottom = UDim.new(0, V_PAD)
		bubblePad.PaddingLeft = UDim.new(0, H_PAD)
		bubblePad.PaddingRight = UDim.new(0, H_PAD)
		bubblePad.Parent = bubble
 
		local bubbleLayout = Instance.new("UIListLayout")
		bubbleLayout.SortOrder = Enum.SortOrder.LayoutOrder
		bubbleLayout.Parent = bubble
 
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.FontFace = SilentUI.Theme.FontRegular
		label.Text = text
		label.TextColor3 = SilentUI.Theme.Text
		label.TextTransparency = 1
		label.TextSize = 13
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.LineHeight = 1.3
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Size = UDim2.new(1, 0, 0, 16)
		label.LayoutOrder = 1
		label.ZIndex = BASE_Z + 3
		label.Parent = bubble
 
		if msg.CreatedAt then
			local timeLbl = Instance.new("TextLabel")
			timeLbl.BackgroundTransparency = 1
			timeLbl.FontFace = SilentUI.Theme.FontRegular
			timeLbl.Text = os.date("%H:%M", math.floor(msg.CreatedAt / 1000))
			timeLbl.TextColor3 = isOwn and SilentUI.Theme.Text or SilentUI.Theme.TextDim
			timeLbl.TextTransparency = isOwn and 0.5 or 0.4
			timeLbl.TextSize = 10
			timeLbl.TextXAlignment = Enum.TextXAlignment.Left
			timeLbl.AutomaticSize = Enum.AutomaticSize.Y
			timeLbl.Size = UDim2.new(1, 0, 0, 12)
			timeLbl.LayoutOrder = 2
			timeLbl.ZIndex = BASE_Z + 3
 
			timeLbl.Visible = showTimestamps
			timeLbl.Parent = bubble
			table.insert(timestampLabels, timeLbl)
		end
 
		if not isOwn and msg.Id and service then
			local reportBtn = Instance.new("TextButton")
			reportBtn.Text = ""
			reportBtn.AutoButtonColor = false
			reportBtn.BackgroundColor3 = SilentUI.Theme.Surface
			reportBtn.BackgroundTransparency = 1
			reportBtn.BorderSizePixel = 0
			reportBtn.Size = UDim2.fromOffset(20, 20)
			reportBtn.LayoutOrder = 3
			reportBtn.ZIndex = BASE_Z + 2
			reportBtn.Parent = row
			Corner(reportBtn, 6)
 
			local reportIcon = Instance.new("ImageLabel")
			reportIcon.BackgroundTransparency = 1
			reportIcon.ImageTransparency = 1
			reportIcon.Image = ResolveIcon("flag")
			reportIcon.ImageColor3 = SilentUI.Theme.TextDim
			reportIcon.Size = UDim2.fromOffset(11, 11)
			reportIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			reportIcon.Position = UDim2.fromScale(0.5, 0.5)
			reportIcon.ZIndex = BASE_Z + 3
			reportIcon.Parent = reportBtn
 
			jan:Add(row.MouseEnter:Connect(function()
				Tween(reportIcon, { ImageTransparency = 0.3 }, 0.12)
			end))
			jan:Add(row.MouseLeave:Connect(function()
				Tween(reportIcon, { ImageTransparency = 1 }, 0.12)
			end))
			jan:Add(reportBtn.MouseEnter:Connect(function()
				Tween(reportBtn, { BackgroundTransparency = 0.88 }, 0.1)
				Tween(reportIcon, { ImageColor3 = SilentUI.Theme.Danger, ImageTransparency = 0 }, 0.1)
			end))
			jan:Add(reportBtn.MouseLeave:Connect(function()
				Tween(reportBtn, { BackgroundTransparency = 1 }, 0.1)
				Tween(reportIcon, { ImageColor3 = SilentUI.Theme.TextDim }, 0.1)
			end))
			jan:Add(reportBtn.MouseButton1Click:Connect(function()
				SilentUI:Confirm({
					Title = "Report this message?",
					Text  = "Hides it for everyone once enough people report it.",
					ConfirmText = "Report",
					CancelText  = "Cancel",
					Danger = true,
					Window = self,
					Callback = function(confirmed)
						if not confirmed then return end
						local ok, err = service:ReportChatMessage(msg.Id)
						SilentUI:Notify({
							Title = ok and "Reported" or "Could not report",
							Text  = ok and "Thanks -- our filters will take it from here." or tostring(err),
							Type  = ok and "success" or "error",
							Duration = 3,
						})
					end,
				})
			end))
		end
 
		local avatarFinalTransparency = isOwn and 0.85 or 0.82
		local bubbleFinalTransparency = isOwn and 0.72 or 0.9
		local strokeFinalTransparency = isOwn and 0.8 or 0.9
		Tween(avatar, { BackgroundTransparency = avatarFinalTransparency }, 0.16)
		Tween(bubble, { BackgroundTransparency = bubbleFinalTransparency }, 0.16)
		Tween(bubbleStroke, { Transparency = strokeFinalTransparency }, 0.16)
		Tween(label, { TextTransparency = 0 }, 0.16)
		Tween(rowScale, { Scale = 1 }, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
 
		scrollToBottom()
		table.insert(transcript, (isOwn and "You" or "Someone") .. ": " .. text)
	end
 
	jan:Add(copyBtn.MouseButton1Click:Connect(function()
		local setclipboard = hasFn("setclipboard")
		if not setclipboard or #transcript == 0 then return end
		pcall(setclipboard, table.concat(transcript, "\n"))
		Tween(copyIcon, { ImageColor3 = Color3.fromRGB(120, 220, 140) }, 0.1)
		task.delay(0.4, function()
			if copyIcon.Parent then
				Tween(copyIcon, { ImageColor3 = SilentUI.Theme.TextDim }, 0.15)
			end
		end)
	end))
 
	local seenIds = { [0] = true }
	local lastSeenId = 0
 
	local function trySend()
		local text = inputBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if text == "" or not service then return end
		inputBox.Text = ""
		local localUserId = anonymousMode and 0 or LocalPlayer.UserId
		task.spawn(function()
			local result, err = service:SendChatMessage(text)
			if not result then
				SilentUI:Notify({ Title = "Chat", Text = tostring(err), Type = "error", Duration = 3 })
				return
			end
			seenIds[result.Id] = true
			if result.Id > lastSeenId then lastSeenId = result.Id end
			addBubble({ UserId = localUserId, Text = text, CreatedAt = os.time() * 1000 }, true)
		end)
	end
 
	jan:Add(sendBtn.MouseButton1Click:Connect(trySend))
	jan:Add(inputBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then trySend() end
	end))
	jan:Add(anonBtn.MouseButton1Click:Connect(function()
		anonymousMode = not anonymousMode
		anonIcon.Image = ResolveIcon(anonymousMode and "eye-off" or "eye")
		SilentUI:Notify({
			Title = "Chat",
			Text  = anonymousMode
				and "Anonymous view on -- your local message hides your avatar."
				or "Anonymous view off -- your local message shows your avatar on this device.",
			Type  = "info",
			Duration = 3,
		})
	end))
	jan:Add(clearBtn.MouseButton1Click:Connect(function()
 
		for _, child in ipairs(msgScroll:GetChildren()) do
			if child.Name == "ChatRow" then child:Destroy() end
		end
		table.clear(transcript)
		table.clear(timestampLabels)
	end))
	jan:Add(closeBtn.MouseButton1Click:Connect(function()
		if self._currentTab == tabObj then
			if self._tabs[1] and self._tabs[1] ~= tabObj then self._tabs[1]._select() end
		end
	end))
 
	local settingsPopup
	local function closeSettingsPopup()
		if settingsPopup then
			settingsPopup:Destroy()
			settingsPopup = nil
		end
	end
 
	local function openSettingsPopup()
		if settingsPopup then closeSettingsPopup(); return end
 
		local popup = Instance.new("Frame")
		popup.Name = "ChatSettingsPopup"
		popup.BackgroundColor3 = SilentUI.Theme.Surface
		popup.BackgroundTransparency = self._interfaceTransparency or 0.05
		popup.BorderSizePixel = 0
		popup.AnchorPoint = Vector2.new(1, 0)
		popup.Position = UDim2.new(1, 0, 0, HEADER_H + 4)
		popup.Size = UDim2.new(0, 190, 0, 0)
		popup.AutomaticSize = Enum.AutomaticSize.Y
		popup.ClipsDescendants = true
		popup.ZIndex = BASE_Z + 10
		popup.Parent = panel
		popup:SetAttribute("SilentInterfacePanel", true)
		popup:SetAttribute("SilentWindowId", self._id)
		Corner(popup, 10)
		local popupStroke = Stroke(popup, SilentUI.Theme.Border, 1, 0.88)
 
		local popupPad = Instance.new("UIPadding")
		popupPad.PaddingTop = UDim.new(0, 10)
		popupPad.PaddingBottom = UDim.new(0, 10)
		popupPad.PaddingLeft = UDim.new(0, 12)
		popupPad.PaddingRight = UDim.new(0, 12)
		popupPad.Parent = popup
 
		local popupLayout = Instance.new("UIListLayout")
		popupLayout.Padding = UDim.new(0, 8)
		popupLayout.SortOrder = Enum.SortOrder.LayoutOrder
		popupLayout.Parent = popup
 
		local function toggleRow(order, label, getValue, onToggle)
			local row = Instance.new("Frame")
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, 20)
			row.LayoutOrder = order
			row.ZIndex = BASE_Z + 11
			row.Parent = popup
 
			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.FontFace = SilentUI.Theme.FontRegular
			lbl.Text = label
			lbl.TextColor3 = SilentUI.Theme.Text
			lbl.TextSize = 12
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.Size = UDim2.new(1, -30, 1, 0)
			lbl.ZIndex = BASE_Z + 12
			lbl.Parent = row
 
			local check = Instance.new("TextButton")
			check.Text = ""
			check.AutoButtonColor = false
			check.BackgroundColor3 = SilentUI.Theme.Surface
			check.BackgroundTransparency = getValue() and 0.7 or 0.92
			check.BorderSizePixel = 0
			check.AnchorPoint = Vector2.new(1, 0.5)
			check.Position = UDim2.new(1, 0, 0.5, 0)
			check.Size = UDim2.fromOffset(20, 20)
			check.ZIndex = BASE_Z + 12
			check.Parent = row
			Corner(check, 6)
 
			local checkIcon = Instance.new("ImageLabel")
			checkIcon.BackgroundTransparency = 1
			checkIcon.Image = ResolveIcon("check")
			checkIcon.ImageColor3 = SilentUI.Theme.Accent
			checkIcon.ImageTransparency = getValue() and 0 or 1
			checkIcon.Size = UDim2.fromOffset(11, 11)
			checkIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			checkIcon.Position = UDim2.fromScale(0.5, 0.5)
			checkIcon.ZIndex = BASE_Z + 13
			checkIcon.Parent = check
 
			jan:Add(check.MouseButton1Click:Connect(function()
				local newValue = onToggle()
				Tween(check, { BackgroundTransparency = newValue and 0.7 or 0.92 }, 0.12)
				Tween(checkIcon, { ImageTransparency = newValue and 0 or 1 }, 0.12)
			end))
		end
 
		toggleRow(1, "Show timestamps", function() return showTimestamps end, function()
			showTimestamps = not showTimestamps
			for _, lbl in ipairs(timestampLabels) do
				if lbl.Parent then lbl.Visible = showTimestamps end
			end
			return showTimestamps
		end)
		toggleRow(2, "Sound on new message", function() return notifySound end, function()
			notifySound = not notifySound
			return notifySound
		end)
		toggleRow(3, "Fast updates (1s)", function() return pollInterval <= 1 end, function()
			pollInterval = (pollInterval <= 1) and (opts.PollInterval or 2.5) or 1
			return pollInterval <= 1
		end)
 
		settingsPopup = popup
	end
 
	jan:Add(settingsBtn.MouseButton1Click:Connect(function()
		if settingsPopup then closeSettingsPopup() else openSettingsPopup() end
	end))
 
	local notifySoundInstance = Instance.new("Sound")
	notifySoundInstance.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	notifySoundInstance.Volume = 0.5
	notifySoundInstance.Parent = panel
 
	if service then
		task.spawn(function()
			local backlog = service:PollChatMessages(0)
			if backlog then
				local historyLimit = opts.HistoryLimit or 3
				local startIdx = math.max(1, #backlog - historyLimit + 1)
				for i = startIdx, #backlog do
					local m = backlog[i]
					if not seenIds[m.Id] then
						seenIds[m.Id] = true
						addBubble(m, m.UserId == LocalPlayer.UserId)
					end
					if m.Id > lastSeenId then lastSeenId = m.Id end
				end
			end
			while panel and panel.Parent do
				task.wait(pollInterval)
				local newMsgs = service:PollChatMessages(lastSeenId)
				if newMsgs then
					for _, m in ipairs(newMsgs) do
						if not seenIds[m.Id] then
							seenIds[m.Id] = true
							local isOwn = m.UserId == LocalPlayer.UserId
							addBubble(m, isOwn)
 
							if notifySound and not isOwn and notifySoundInstance.Parent then
								notifySoundInstance:Play()
							end
						end
						if m.Id > lastSeenId then lastSeenId = m.Id end
					end
				end
			end
		end)
	end
 
	local lastRealTab = nil
	local function openPanel()
		if self._currentTab == tabObj then return end
		if self._currentTab and not self._currentTab.Hidden then
			lastRealTab = self._currentTab
		end
		tabObj._select()
	end
	local function closePanel()
		if self._currentTab ~= tabObj then return end
		if lastRealTab and not lastRealTab.Hidden then
			lastRealTab._select()
		elseif self._tabs[1] and self._tabs[1] ~= tabObj then
			self._tabs[1]._select()
		end
	end
 
	return {
		Instance = panel,
		Tab = tabObj,
		Open = openPanel,
		Close = closePanel,
		Toggle = function()
			if self._currentTab == tabObj then closePanel() else openPanel() end
		end,
		IsOpen = function() return self._currentTab == tabObj end,
		Destroy = function() panel:Destroy() end,
	}
end
 
Private.TRANSITION_EXIT  = 0.18
Private.TRANSITION_GAP   = 0.08
Private.TRANSITION_ENTER = 0.32
 
function Window:AddTab(nameOrOpts)
	local opts = type(nameOrOpts) == "table" and nameOrOpts or { Name = nameOrOpts }
	local name = opts.Name or opts.Title or "Tab"
	local iconAsset = opts.Icon and ResolveIcon(opts.Icon) or nil
	local hasIcon = iconAsset ~= nil and iconAsset ~= ""
	local jan = self._janitor
 
	local hidden = opts.Hidden == true
 
	local tabButton = Instance.new("TextButton")
	tabButton.Name = name
	tabButton.Text = ""
	tabButton.AutoButtonColor = false
	tabButton.BackgroundColor3 = SilentUI.Theme.Surface
	tabButton.BackgroundTransparency = 1
	tabButton.BorderSizePixel = 0
	tabButton.Size = UDim2.new(1, 0, 0, 34)
	tabButton.ZIndex = Z.Content
	if not hidden then
		tabButton.Parent = self._tabBar
	end
	Corner(tabButton, 10)
 
	local isPrivate = opts.Password ~= nil and opts.Password ~= ""
	local remembered = isPrivate and Private.IsPrivateTabRemembered(name)
	local unlocked = not isPrivate or remembered
	local glowColor = opts.GlowColor or SilentUI.Theme.Accent
	local glowStroke, lockBadge, glowPulse
 
	if isPrivate then
		glowStroke = Stroke(tabButton, glowColor, 1, remembered and 0.9 or 0.82)
 
		if not remembered then
			glowPulse = TweenService:Create(
				glowStroke,
				TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.94 }
			)
			glowPulse:Play()
		end
	end
 
	if isPrivate and not remembered then
		lockBadge = Instance.new("Frame")
		lockBadge.Name = "LockBadge"
		lockBadge.BackgroundColor3 = SilentUI.Theme.Background
		lockBadge.BackgroundTransparency = 0
		lockBadge.BorderSizePixel = 0
		lockBadge.Size = UDim2.fromOffset(13, 13)
		lockBadge.AnchorPoint = Vector2.new(1, 0)
		lockBadge.Position = UDim2.new(1, -2, 0, -3)
		lockBadge.ZIndex = Z.Content + 3
		lockBadge.Parent = tabButton
		Corner(lockBadge, 7)
		Stroke(lockBadge, glowColor, 1, 0.7)
 
		local lockIcon = Instance.new("ImageLabel")
		lockIcon.BackgroundTransparency = 1
		lockIcon.Image = ResolveIcon("lock")
		lockIcon.ImageColor3 = glowColor
		lockIcon.Size = UDim2.fromOffset(7, 7)
		lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		lockIcon.Position = UDim2.fromScale(0.5, 0.5)
		lockIcon.ZIndex = Z.Content + 4
		lockIcon.Parent = lockBadge
	end
 
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.ZIndex = Z.Content
	row.Parent = tabButton
 
	local rowPad = Instance.new("UIPadding")
	rowPad.PaddingLeft = UDim.new(0, 12)
	rowPad.PaddingRight = UDim.new(0, 12)
	rowPad.Parent = row
 
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row
 
	local iconLabel
	if hasIcon then
		iconLabel = Instance.new("ImageLabel")
		iconLabel.Name = "Icon"
		iconLabel.BackgroundTransparency = 1
		iconLabel.Image = iconAsset
		iconLabel.ImageColor3 = SilentUI.Theme.TextDim
		iconLabel.Size = UDim2.fromOffset(16, 16)
		iconLabel.LayoutOrder = 1
		iconLabel.ZIndex = Z.Content + 1
		iconLabel.Parent = row
	end
 
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Label"
	textLabel.BackgroundTransparency = 1
	textLabel.FontFace = SilentUI.Theme.Font
	textLabel.Text = name
	textLabel.TextColor3 = SilentUI.Theme.TextDim
	textLabel.TextSize = 14
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextTruncate = Enum.TextTruncate.AtEnd
	textLabel.Size = UDim2.new(1, hasIcon and -26 or 0, 1, 0)
	textLabel.LayoutOrder = 2
	textLabel.ZIndex = Z.Content + 1
	textLabel.Parent = row
	if opts.NameKey or opts.TitleKey then SilentUI:Localize(textLabel, opts.NameKey or opts.TitleKey) end
 
	local pageGroup = Instance.new("CanvasGroup")
	pageGroup.Name = name .. "Group"
	pageGroup.BackgroundTransparency = 1
	pageGroup.Size = UDim2.fromScale(1, 1)
	pageGroup.GroupTransparency = 0
	pageGroup.Visible = false
	pageGroup.ZIndex = Z.Content
	pageGroup.Parent = self._content
 
	local page = Instance.new("ScrollingFrame")
	page.Name = name .. "Page"
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Size = UDim2.fromScale(1, 1)
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.ScrollBarThickness = 0
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.ZIndex = Z.Content
	page.Parent = pageGroup
 
	local pagePad = Instance.new("UIPadding")
	pagePad.Name = "PagePadding"
	pagePad.PaddingRight = UDim.new(0, 12)
	pagePad.PaddingBottom = UDim.new(0, 6)
	pagePad.Parent = page
 
	local pageLayout = Instance.new("UIListLayout")
	pageLayout.Name = "PageLayout"
	pageLayout.Padding = UDim.new(0, 8)
	pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pageLayout.Parent = page
 
	AddScrollbar(page)
	Private.AddContentScrollThumb(page, pageLayout, pageGroup, jan)
	Private.AddEmptyState(page, pageGroup, jan)
 
	local tabObj = setmetatable({
		Name      = name,
		_page     = page,
		_group    = pageGroup,
		_button   = tabButton,
		_icon     = iconLabel,
		_label    = textLabel,
		_window   = self,
		_janitor  = jan,
		_password = opts.Password,
	}, Tab)
 
	local myIndex = #self._tabs + 1
 
	local function indicatorY()
		return (tabButton.AbsolutePosition.Y - self._tabBar.AbsolutePosition.Y) / GetUIScale()
	end
 
	local function selectTab()
		if self._currentTab == tabObj then return end
 
		self._tabSwitchToken = (self._tabSwitchToken or 0) + 1
		local myToken = self._tabSwitchToken
 
		local direction = 0
		if self._currentIndex then
			direction = (myIndex > self._currentIndex) and 1 or -1
		end
		self._currentIndex = myIndex
 
		local previousTab = self._currentTab
		self._currentTab = tabObj
		for _, fn in ipairs(self._tabChangeListeners) do
			task.spawn(fn, tabObj)
		end
 
		for _, t in pairs(self._tabs) do
			local isSelected = (t == tabObj)
			Tween(t._label, { TextColor3 = isSelected and SilentUI.Theme.Text or SilentUI.Theme.TextDim }, 0.22)
			if t._icon then
				Tween(t._icon, { ImageColor3 = isSelected and SilentUI.Theme.Text or SilentUI.Theme.TextDim }, 0.22)
			end
			if not isSelected then
				Tween(t._button, { BackgroundTransparency = 1 }, 0.15)
			end
		end
 
		if hidden then
			Tween(self._tabIndicator, { BackgroundTransparency = 1 }, 0.15)
		else
			Tween(self._tabIndicator, {
				Position = UDim2.new(0, 0, 0, indicatorY()),
				BackgroundTransparency = 0.88,
			}, 0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		end
 
		for _, t in pairs(self._tabs) do
			if t ~= tabObj and t ~= previousTab and t._group.Visible then
				t._group.Visible = false
			end
		end
 
		local function playEnter()
			if self._tabSwitchToken ~= myToken then return end
			pageGroup.Visible = true
			pageGroup.GroupTransparency = 1
			pageGroup.Position = UDim2.fromOffset(direction * 20, 0)
			Tween(pageGroup, {
				GroupTransparency = 0,
				Position = UDim2.fromOffset(0, 0),
			}, Private.TRANSITION_ENTER, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		end
 
		if previousTab and previousTab._group.Visible then
			local g = previousTab._group
			Tween(g, {
				GroupTransparency = 1,
				Position = UDim2.fromOffset(-direction * 20, 0),
			}, Private.TRANSITION_EXIT, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(Private.TRANSITION_EXIT, function()
				if g then g.Visible = false end
				task.delay(Private.TRANSITION_GAP, playEnter)
			end)
		else
			playEnter()
		end
	end
 
	local promptOpen = false
	local function guardedSelect()
		if isPrivate and not unlocked then
			if promptOpen then return end
			promptOpen = true
			self:_PromptTabPassword(tabObj, function(success, remember)
				promptOpen = false
				if not success then return end
				Private.SetPrivateTabRemembered(tabObj.Name, remember == true)
				unlocked = true
				tabObj.Unlocked = true
				if glowPulse then glowPulse:Cancel() end
				if glowStroke then Tween(glowStroke, { Transparency = 0.9 }, 0.4) end
				if lockBadge then
					Tween(lockBadge, { BackgroundTransparency = 1 }, 0.25)
					task.delay(0.25, function()
						if lockBadge then lockBadge:Destroy(); lockBadge = nil end
					end)
				end
				selectTab()
			end)
			return
		end
		selectTab()
	end
 
	tabObj._select = guardedSelect
	tabObj.IsPrivate = isPrivate
	tabObj.Unlocked = unlocked
	tabObj.Hidden = hidden
 
	if not hidden then
		jan:Add(tabButton:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			if self._currentTab == tabObj then
				self._tabIndicator.Position = UDim2.new(0, 0, 0, indicatorY())
			end
		end))
 
		jan:Add(tabButton.MouseButton1Click:Connect(guardedSelect))
 
		jan:Add(tabButton.MouseEnter:Connect(function()
			if self._currentTab ~= tabObj then
				Tween(tabButton, { BackgroundTransparency = 0.95 }, 0.15)
			end
		end))
		jan:Add(tabButton.MouseLeave:Connect(function()
			if self._currentTab ~= tabObj then
				Tween(tabButton, { BackgroundTransparency = 1 }, 0.15)
			end
		end))
	end
 
	table.insert(self._tabs, tabObj)
	if not hidden then
 
		self._visibleTabCount = (self._visibleTabCount or 0) + 1
		if self._visibleTabCount == 1 then
			guardedSelect()
		end
		if self._defaultTabName and name == self._defaultTabName then
			guardedSelect()
		end
	end
 
	return tabObj
end
 
function Window:AddPrivateTab(opts)
	opts = type(opts) == "table" and opts or { Name = opts }
	assert(opts.Password and opts.Password ~= "", "AddPrivateTab requires opts.Password")
	return self:AddTab(opts)
end
 
function Window:_PromptTabPassword(tabObj, callback)
	local root = SilentUI._Root
	local jan = Janitor.new()
	local closed = false
	local settled = false
 
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "TabPasswordBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = Z.Modal
	backdrop.Parent = root
 
	local dialog = Instance.new("Frame")
	dialog.Name = "TabPasswordDialog"
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	do
		local cx, cy = Private.ComputeDialogCenter(self._gui)
		local s = GetUIScale()
		dialog.Position = UDim2.fromOffset(math.round(cx / s), math.round(cy / s))
	end
	dialog.BackgroundColor3 = SilentUI.Theme.Background
	dialog.BackgroundTransparency = 1
	dialog.BorderSizePixel = 0
	dialog.ClipsDescendants = true
	dialog.AutomaticSize = Enum.AutomaticSize.Y
	dialog.Size = UDim2.new(0, 300, 0, 0)
	dialog.ZIndex = Z.ModalTop
	dialog.Parent = backdrop
	dialog:SetAttribute("SilentInterfacePanel", true)
	dialog:SetAttribute("SilentWindowId", self._id)
	Corner(dialog, 14)
	local dialogStroke = Stroke(dialog, SilentUI.Theme.Border, 1, 0.9)
 
	local scale = Instance.new("UIScale")
	scale.Scale = 0.94
	scale.Parent = dialog
 
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 18)
	pad.PaddingBottom = UDim.new(0, 18)
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = dialog
 
	local dialogLayout = Instance.new("UIListLayout")
	dialogLayout.Padding = UDim.new(0, 8)
	dialogLayout.SortOrder = Enum.SortOrder.LayoutOrder
	dialogLayout.Parent = dialog
 
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 20)
	header.LayoutOrder = 1
	header.ZIndex = Z.ModalTop + 1
	header.Parent = dialog
 
	local lockIcon = Instance.new("ImageLabel")
	lockIcon.BackgroundTransparency = 1
	lockIcon.Image = ResolveIcon("lock")
	lockIcon.ImageColor3 = SilentUI.Theme.TextDim
	lockIcon.Size = UDim2.fromOffset(18, 18)
	lockIcon.Position = UDim2.fromOffset(0, 0)
	lockIcon.ZIndex = Z.ModalTop + 2
	lockIcon.Parent = header
 
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.FontFace = SilentUI.Theme.Font
	title.Text = "Private Tab"
	title.TextColor3 = SilentUI.Theme.Text
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, -26, 1, 0)
	title.Position = UDim2.fromOffset(26, 0)
	title.ZIndex = Z.ModalTop + 2
	title.Parent = header
 
	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.FontFace = SilentUI.Theme.FontRegular
	subtitle.Text = ("Enter the password to unlock \"%s\""):format(tabObj.Name or "")
	subtitle.TextColor3 = SilentUI.Theme.TextDim
	subtitle.TextSize = 12
	subtitle.TextWrapped = true
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitle.AutomaticSize = Enum.AutomaticSize.Y
	subtitle.Size = UDim2.new(1, 0, 0, 0)
	subtitle.LayoutOrder = 2
	subtitle.ZIndex = Z.ModalTop + 1
	subtitle.Parent = dialog
 
	local fieldHolder = Instance.new("Frame")
	fieldHolder.BackgroundColor3 = SilentUI.Theme.Surface
	fieldHolder.BackgroundTransparency = 0.94
	fieldHolder.BorderSizePixel = 0
	fieldHolder.ClipsDescendants = true
	fieldHolder.Size = UDim2.new(1, 0, 0, 36)
	fieldHolder.LayoutOrder = 3
	fieldHolder.ZIndex = Z.ModalTop + 1
	fieldHolder.Parent = dialog
	Corner(fieldHolder, 8)
	local fieldStroke = Stroke(fieldHolder, SilentUI.Theme.Border, 1, 0.88)
 
	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.FontFace = SilentUI.Theme.FontRegular
	box.PlaceholderText = ""
	box.Text = ""
	box.TextColor3 = SilentUI.Theme.Text
	box.TextTransparency = 1
	box.TextSize = 14
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Position = UDim2.fromOffset(10, 0)
	box.Size = UDim2.new(1, -20, 1, 0)
	box.ZIndex = Z.ModalTop + 2
	box.Parent = fieldHolder
 
	local maskLabel = Instance.new("TextLabel")
	maskLabel.BackgroundTransparency = 1
	maskLabel.FontFace = SilentUI.Theme.FontRegular
	maskLabel.Text = ""
	maskLabel.TextColor3 = SilentUI.Theme.Text
	maskLabel.TextSize = 14
	maskLabel.TextXAlignment = Enum.TextXAlignment.Left
	maskLabel.Position = box.Position
	maskLabel.Size = box.Size
	maskLabel.ZIndex = box.ZIndex + 1
	maskLabel.Parent = fieldHolder
 
	local placeholderLabel = Instance.new("TextLabel")
	placeholderLabel.BackgroundTransparency = 1
	placeholderLabel.FontFace = SilentUI.Theme.FontRegular
	placeholderLabel.Text = "Password"
	placeholderLabel.TextColor3 = SilentUI.Theme.TextDim
	placeholderLabel.TextSize = 14
	placeholderLabel.TextXAlignment = Enum.TextXAlignment.Left
	placeholderLabel.Position = box.Position
	placeholderLabel.Size = box.Size
	placeholderLabel.ZIndex = box.ZIndex + 1
	placeholderLabel.Parent = fieldHolder
 
	jan:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
		maskLabel.Text = string.rep("\226\128\162", #box.Text)
		placeholderLabel.Visible = (#box.Text == 0)
	end))
 
	local rememberRow = Instance.new("Frame")
	rememberRow.BackgroundTransparency = 1
	rememberRow.Size = UDim2.new(1, 0, 0, 18)
	rememberRow.LayoutOrder = 4
	rememberRow.ZIndex = Z.ModalTop + 1
	rememberRow.Parent = dialog
 
	local remember = Private.IsPrivateTabRemembered(tabObj.Name)
 
	local rememberSwitch = Instance.new("Frame")
	rememberSwitch.AnchorPoint = Vector2.new(0, 0.5)
	rememberSwitch.Position = UDim2.new(0, 0, 0.5, 0)
	rememberSwitch.Size = UDim2.fromOffset(32, 18)
	rememberSwitch.BackgroundColor3 = remember and SilentUI.Theme.Accent or SilentUI.Theme.Surface
	rememberSwitch.BorderSizePixel = 0
	rememberSwitch.ZIndex = Z.ModalTop + 2
	rememberSwitch.Parent = rememberRow
	Corner(rememberSwitch, 9)
 
	local rememberLabel = Instance.new("TextLabel")
	rememberLabel.BackgroundTransparency = 1
	rememberLabel.FontFace = SilentUI.Theme.FontRegular
	rememberLabel.Text = "Remember me"
	rememberLabel.TextColor3 = SilentUI.Theme.TextDim
	rememberLabel.TextSize = 12
	rememberLabel.TextXAlignment = Enum.TextXAlignment.Left
	rememberLabel.AnchorPoint = Vector2.new(0, 0.5)
	rememberLabel.Position = UDim2.new(0, 42, 0.5, 0)
	rememberLabel.Size = UDim2.new(1, -42, 1, 0)
	rememberLabel.ZIndex = Z.ModalTop + 2
	rememberLabel.Parent = rememberRow
 
	local rememberKnob = Instance.new("Frame")
	rememberKnob.Size = UDim2.fromOffset(14, 14)
	rememberKnob.AnchorPoint = Vector2.new(0, 0.5)
	rememberKnob.Position = remember and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
	rememberKnob.BackgroundColor3 = remember and SilentUI.Theme.Background or SilentUI.Theme.Text
	rememberKnob.BorderSizePixel = 0
	rememberKnob.ZIndex = Z.ModalTop + 3
	rememberKnob.Parent = rememberSwitch
	Corner(rememberKnob, 7)
 
	local rememberClick = Instance.new("TextButton")
	rememberClick.Text = ""
	rememberClick.AutoButtonColor = false
	rememberClick.BackgroundTransparency = 1
	rememberClick.Size = UDim2.fromScale(1, 1)
	rememberClick.ZIndex = Z.ModalTop + 3
	rememberClick.Parent = rememberRow
 
	jan:Add(rememberClick.MouseButton1Click:Connect(function()
		remember = not remember
		Tween(rememberSwitch, {
			BackgroundColor3 = remember and SilentUI.Theme.Accent or SilentUI.Theme.Surface,
		}, 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		Tween(rememberKnob, {
			BackgroundColor3 = remember and SilentUI.Theme.Background or SilentUI.Theme.Text,
			Position = remember and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
		}, 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	end))
 
	local buttonsRow = Instance.new("Frame")
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.Size = UDim2.new(1, 0, 0, 34)
	buttonsRow.LayoutOrder = 5
	buttonsRow.ZIndex = Z.ModalTop + 1
	buttonsRow.Parent = dialog
 
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = buttonsRow
 
	local function makeButton(text_, order, filled)
		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = SilentUI.Theme.Surface
		btn.BackgroundTransparency = filled and 0.82 or 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(0.5, -4, 1, 0)
		btn.LayoutOrder = order
		btn.ZIndex = Z.ModalTop + 1
		btn.Parent = buttonsRow
		Corner(btn, 10)
		local btnStroke = Stroke(btn, SilentUI.Theme.Border, 1, filled and 0.7 or 0.85)
 
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.FontFace = SilentUI.Theme.Font
		lbl.Text = text_
		lbl.TextColor3 = SilentUI.Theme.Text
		lbl.TextSize = 13
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.ZIndex = Z.ModalTop + 2
		lbl.Parent = btn
 
		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = math.max((filled and 0.82 or 1) - 0.1, 0) }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = filled and 0.82 or 1 }, 0.12)
		end))
 
		return btn
	end
 
	local cancelBtn  = makeButton("Cancel", 1, false)
	local unlockBtn  = makeButton("Unlock", 2, true)
 
	local function close(success)
		if closed then return end
		closed = true
 
		Tween(scale, { Scale = 0.94 }, 0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		Tween(dialog, { BackgroundTransparency = 1 }, 0.15)
		Tween(dialogStroke, { Transparency = 1 }, 0.15)
		Tween(backdrop, { BackgroundTransparency = 1 }, 0.15)
		task.delay(0.16, function()
			jan:Destroy()
			backdrop:Destroy()
		end)
 
		task.spawn(callback, success, remember)
	end
 
	local function shakeError()
		Tween(fieldStroke, { Color = SilentUI.Theme.Danger, Transparency = 0.4 }, 0.12)
		placeholderLabel.Text = "Incorrect password"
		Tween(placeholderLabel, { TextColor3 = SilentUI.Theme.Danger }, 0.12)
 
		local baseX = dialog.Position.X.Offset
		local seq = { 8, -7, 5, -4, 0 }
		local t = 0
		for _, dx in ipairs(seq) do
			t = t + 0.05
			task.delay(t, function()
				if closed then return end
				Tween(dialog, {
					Position = UDim2.fromOffset(baseX + dx, dialog.Position.Y.Offset),
				}, 0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			end)
		end
 
		task.delay(1.4, function()
			if closed then return end
			Tween(fieldStroke, { Color = SilentUI.Theme.Border, Transparency = 0.88 }, 0.3)
			Tween(placeholderLabel, { TextColor3 = SilentUI.Theme.TextDim }, 0.3)
			task.delay(0.3, function()
				if not closed then placeholderLabel.Text = "Password" end
			end)
		end)
	end
 
	local function attempt()
		if closed or settled then return end
		if box.Text == tabObj._password then
			settled = true
			close(true)
		else
			shakeError()
			box.Text = ""
		end
	end
 
	jan:Add(cancelBtn.MouseButton1Click:Connect(function() close(false) end))
	jan:Add(unlockBtn.MouseButton1Click:Connect(attempt))
	jan:Add(backdrop.MouseButton1Click:Connect(function() close(false) end))
 
	jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if closed then return end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			attempt()
		elseif input.KeyCode == Enum.KeyCode.Escape and not gameProcessed then
			close(false)
		end
	end))
 
	Tween(backdrop, { BackgroundTransparency = 0.5 }, 0.18)
	Tween(dialog, { BackgroundTransparency = self._interfaceTransparency or 0 }, 0.18)
	Tween(dialogStroke, { Transparency = 0.8 }, 0.18)
	Tween(scale, { Scale = 1 }, 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
	task.defer(function()
		if box.Parent then box:CaptureFocus() end
	end)
end
 
function Window:SelectTab(nameOrIndex)
	if type(nameOrIndex) == "number" then
		local t = self._tabs[nameOrIndex]
		if t then t._select() end
		return t
	end
	for _, t in ipairs(self._tabs) do
		if t.Name == nameOrIndex then
			t._select()
			return t
		end
	end
	return nil
end
 
function Window:_RegisterSearchable(tabObj, title, instance)
	if not title or title == "" or not instance then return end
	table.insert(self._searchIndex, { title = title, instance = instance, tabObj = tabObj })
end
 
function Private.SearchEntryPath(tabObj)
	if not tabObj then return "" end
	if tabObj._parentTabName then
		return tabObj._parentTabName .. " \226\128\186 " .. tabObj.Name
	end
	return tabObj.Name or ""
end
 
function Window:_JumpToSearchable(entry)
	local tabObj = entry.tabObj
	local inst = entry.instance
	if not tabObj or not inst or not inst.Parent then return end
 
	if tabObj._parentTab then
		tabObj._parentTab._select()
		tabObj._parentTab:SelectSubTab(tabObj._subTabIdx)
	elseif tabObj._select then
		tabObj._select()
	end
 
	task.delay(0.6, function()
		if not inst.Parent then return end
		local page = tabObj._page
		if not page then return end
		local targetY = math.max(
			0,
			(inst.AbsolutePosition.Y - page.AbsolutePosition.Y) + page.CanvasPosition.Y - 40
		)
		page.CanvasPosition = Vector2.new(page.CanvasPosition.X, targetY)
 
		local baseColor = inst.BackgroundColor3
		local baseBg = inst.BackgroundTransparency
 
		inst.BackgroundColor3 = SilentUI.Theme.Accent
		Tween(inst, { BackgroundTransparency = 0.85 }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
		task.delay(0.5, function()
			if not inst.Parent then return end
			Tween(inst, { BackgroundTransparency = baseBg }, 0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
			task.delay(0.7, function()
				if inst.Parent then inst.BackgroundColor3 = baseColor end
			end)
		end)
	end)
end
 
function Window:JumpToElement(query)
	query = tostring(query or "")
	if query == "" then return false, "No element name given" end
 
	local q = query:lower()
	local best, bestScore = nil, 0
	for _, entry in ipairs(self._searchIndex) do
		local title = tostring(entry.title or ""):lower()
		if title == q then
			best, bestScore = entry, math.huge
			break
		elseif title:find(q, 1, true) then
			local score = 1000 - math.abs(#title - #q)
			if score > bestScore then best, bestScore = entry, score end
		end
	end
 
	if not best then
		return false, "No element found matching '" .. query .. "'"
	end
 
	self:_JumpToSearchable(best)
	return true, best.title
end
 
function Window:_OpenSearch()
	local self_ = self
	local root = SilentUI._Root
	local panelW = math.min(440, Private.ViewportSize().X / GetUIScale() - 40)
	local HEADER_H = 50
	local MAX_RESULTS_H = 280
	local ROW_H = 40
 
	local open = true
	local backdrop, panel, scale
	local heartbeatConn, textConn, focusConn
	local lastMatches = {}
 
	local restY
 
	local function closeSearch()
		if not open then return end
		open = false
		Private.RegisterPopupClose(closeSearch)
		if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn = nil end
		if textConn then textConn:Disconnect(); textConn = nil end
		if focusConn then focusConn:Disconnect(); focusConn = nil end
 
		local b, p = backdrop, panel
		backdrop, panel = nil, nil
		if p then
			Tween(p, { Size = UDim2.new(p.Size.X.Scale, p.Size.X.Offset, 0, 0) }, 0.32,
				Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			Tween(p, { GroupTransparency = 1 }, 0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		end
		if b then Tween(b, { BackgroundTransparency = 1 }, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.In) end
		task.delay(0.32, function()
			if b then b:Destroy() end
			if p then p:Destroy() end
		end)
	end
 
	Private.RegisterPopupOpen(closeSearch)
	backdrop = Private.MakePopupBackdrop(closeSearch)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	Tween(backdrop, { BackgroundTransparency = 0.4 }, 0.36, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
	panel = Instance.new("CanvasGroup")
	panel.Name = "SearchPalette"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	do
		local cx, cy = Private.ComputeDialogCenter(self_._gui)
		local s = GetUIScale()
		local px, py = math.round(cx / s), math.round(cy / s)
		restY = py
		panel.Position = UDim2.fromOffset(px, py - 18)
	end
	panel.Size = UDim2.new(0, panelW, 0, HEADER_H)
	panel.BackgroundColor3 = SilentUI.Theme.Background
	panel.BackgroundTransparency = self_._interfaceTransparency or 0.05
	panel.GroupTransparency = 1
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.ZIndex = Z.Modal
	panel.Parent = root
	panel:SetAttribute("SilentInterfacePanel", true)
	panel:SetAttribute("SilentWindowId", self_._id)
	Corner(panel, 14)
	Stroke(panel, SilentUI.Theme.Border, 1, 0.8)
	Private.GlassLayer(panel, 14, 0.985)
 
	scale = Instance.new("UIScale")
	scale.Scale = 0.94
	scale.Parent = panel
 
	local searchIcon = Instance.new("ImageLabel")
	searchIcon.BackgroundTransparency = 1
	searchIcon.Image = ResolveIcon("search")
	searchIcon.ImageColor3 = SilentUI.Theme.TextDim
	searchIcon.Size = UDim2.fromOffset(16, 16)
	searchIcon.AnchorPoint = Vector2.new(0, 0.5)
	searchIcon.Position = UDim2.new(0, 16, 0, HEADER_H / 2)
	searchIcon.ZIndex = Z.Modal + 2
	searchIcon.Parent = panel
 
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Text = ""
	closeBtn.AutoButtonColor = false
	closeBtn.BackgroundColor3 = SilentUI.Theme.Surface
	closeBtn.BackgroundTransparency = 1
	closeBtn.BorderSizePixel = 0
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Size = UDim2.fromOffset(24, 24)
	closeBtn.Position = UDim2.new(1, -10, 0, HEADER_H / 2)
	closeBtn.ZIndex = Z.Modal + 2
	closeBtn.Parent = panel
	Corner(closeBtn, 7)
 
	local closeIcon = Instance.new("ImageLabel")
	closeIcon.BackgroundTransparency = 1
	closeIcon.Image = ResolveIcon("x")
	closeIcon.ImageColor3 = SilentUI.Theme.TextDim
	closeIcon.Size = UDim2.fromOffset(12, 12)
	closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	closeIcon.Position = UDim2.fromScale(0.5, 0.5)
	closeIcon.ZIndex = Z.Modal + 3
	closeIcon.Parent = closeBtn
 
	closeBtn.MouseEnter:Connect(function()
		Tween(closeBtn, { BackgroundTransparency = 0.9 }, 0.12)
		Tween(closeIcon, { ImageColor3 = SilentUI.Theme.Text }, 0.12)
	end)
	closeBtn.MouseLeave:Connect(function()
		Tween(closeBtn, { BackgroundTransparency = 1 }, 0.12)
		Tween(closeIcon, { ImageColor3 = SilentUI.Theme.TextDim }, 0.12)
	end)
	closeBtn.MouseButton1Click:Connect(closeSearch)
 
	local box = Instance.new("TextBox")
	box.Name = "SearchBox"
	box.BackgroundTransparency = 1
	box.FontFace = SilentUI.Theme.FontRegular
	box.PlaceholderText = "Search everything..."
	box.Text = ""
	box.TextColor3 = SilentUI.Theme.Text
	box.PlaceholderColor3 = SilentUI.Theme.TextDim
	box.TextSize = 15
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Position = UDim2.new(0, 40, 0, 0)
	box.Size = UDim2.new(1, -78, 0, HEADER_H)
	box.ZIndex = Z.Modal + 2
	box.Parent = panel
 
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundColor3 = SilentUI.Theme.Surface
	divider.BackgroundTransparency = 0.92
	divider.BorderSizePixel = 0
	divider.Position = UDim2.new(0, 0, 0, HEADER_H)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.Visible = false
	divider.ZIndex = Z.Modal + 1
	divider.Parent = panel
 
	local resultsHolder = Instance.new("ScrollingFrame")
	resultsHolder.Name = "Results"
	resultsHolder.BackgroundTransparency = 1
	resultsHolder.BorderSizePixel = 0
	resultsHolder.Position = UDim2.new(0, 0, 0, HEADER_H + 1)
	resultsHolder.Size = UDim2.new(1, 0, 0, 0)
	resultsHolder.Visible = false
	resultsHolder.ScrollingDirection = Enum.ScrollingDirection.Y
	resultsHolder.ScrollBarThickness = 0
	resultsHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
	resultsHolder.CanvasSize = UDim2.new(0, 0, 0, 0)
	resultsHolder.ZIndex = Z.Modal + 1
	resultsHolder.Parent = panel
 
	local resultsPad = Instance.new("UIPadding")
	resultsPad.PaddingTop = UDim.new(0, 6)
	resultsPad.PaddingBottom = UDim.new(0, 6)
	resultsPad.PaddingLeft = UDim.new(0, 6)
	resultsPad.PaddingRight = UDim.new(0, 16)
	resultsPad.Parent = resultsHolder
 
	local resultsLayout = Instance.new("UIListLayout")
	resultsLayout.Padding = UDim.new(0, 2)
	resultsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	resultsLayout.Parent = resultsHolder
 
	AddScrollbar(resultsHolder)
	Private.AddContentScrollThumb(resultsHolder, resultsLayout, panel, {
		Add = function(_, conn) heartbeatConn = conn end,
	})
 
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.FontFace = SilentUI.Theme.FontRegular
	emptyLabel.Text = "No results"
	emptyLabel.TextColor3 = SilentUI.Theme.TextDim
	emptyLabel.TextSize = 13
	emptyLabel.Visible = false
	emptyLabel.Position = UDim2.new(0, 0, 0, HEADER_H + 9)
	emptyLabel.Size = UDim2.new(1, 0, 0, 26)
	emptyLabel.ZIndex = Z.Modal + 1
	emptyLabel.Parent = panel
 
	local function activate(entry)
		closeSearch()
		self_:_JumpToSearchable(entry)
	end
 
	local function rebuild(query)
		for _, child in ipairs(resultsHolder:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
 
		local q = query:lower():match("^%s*(.-)%s*$")
		local matches = {}
		for _, entry in ipairs(self_._searchIndex) do
			if entry.instance and entry.instance.Parent then
				if q == "" or entry.title:lower():find(q, 1, true) then
					table.insert(matches, entry)
					if #matches >= 15 then break end
				end
			end
		end
		lastMatches = matches
 
		local showEmpty = (#matches == 0 and q ~= "")
		emptyLabel.Visible = showEmpty
		resultsHolder.Visible = (#matches > 0)
		divider.Visible = (#matches > 0) or showEmpty
 
		for i, entry in ipairs(matches) do
			local row = Instance.new("TextButton")
			row.Text = ""
			row.AutoButtonColor = false
			row.BackgroundColor3 = SilentUI.Theme.Surface
			row.BackgroundTransparency = 1
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, 0, 0, ROW_H)
			row.LayoutOrder = i
			row.ZIndex = Z.Modal + 2
			row.Parent = resultsHolder
			Corner(row, 8)
 
			local titleLbl = Instance.new("TextLabel")
			titleLbl.BackgroundTransparency = 1
			titleLbl.FontFace = SilentUI.Theme.Font
			titleLbl.Text = entry.title
			titleLbl.TextColor3 = SilentUI.Theme.Text
			titleLbl.TextSize = 13
			titleLbl.TextXAlignment = Enum.TextXAlignment.Left
			titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
			titleLbl.Position = UDim2.fromOffset(12, 5)
			titleLbl.Size = UDim2.new(1, -24, 0, 16)
			titleLbl.ZIndex = Z.Modal + 3
			titleLbl.Parent = row
 
			local pathLbl = Instance.new("TextLabel")
			pathLbl.BackgroundTransparency = 1
			pathLbl.FontFace = SilentUI.Theme.FontRegular
			pathLbl.Text = Private.SearchEntryPath(entry.tabObj)
			pathLbl.TextColor3 = SilentUI.Theme.TextDim
			pathLbl.TextSize = 11
			pathLbl.TextXAlignment = Enum.TextXAlignment.Left
			pathLbl.TextTruncate = Enum.TextTruncate.AtEnd
			pathLbl.Position = UDim2.fromOffset(12, 21)
			pathLbl.Size = UDim2.new(1, -24, 0, 12)
			pathLbl.ZIndex = Z.Modal + 3
			pathLbl.Parent = row
 
			row.MouseEnter:Connect(function()
				Tween(row, { BackgroundTransparency = 0.92 }, 0.1)
			end)
			row.MouseLeave:Connect(function()
				Tween(row, { BackgroundTransparency = 1 }, 0.1)
			end)
			row.MouseButton1Click:Connect(function()
				activate(entry)
			end)
		end
 
		local resultsH = math.min(#matches * (ROW_H + 2), MAX_RESULTS_H)
 
		local extraH = 0
		if resultsH > 0 then
			extraH = resultsH + 1
		elseif showEmpty then
			extraH = 36
		end
 
		Tween(resultsHolder, { Size = UDim2.new(1, 0, 0, resultsH) }, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		Tween(panel, { Size = UDim2.new(0, panelW, 0, HEADER_H + extraH) }, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	end
 
	local rebuildToken = 0
	textConn = box:GetPropertyChangedSignal("Text"):Connect(function()
		rebuildToken = rebuildToken + 1
		local myToken = rebuildToken
		local text = box.Text
		task.delay(0.12, function()
			if rebuildToken == myToken and box.Parent then
				rebuild(text)
			end
		end)
	end)
 
	focusConn = box.FocusLost:Connect(function(enterPressed)
		if enterPressed and lastMatches[1] then
			activate(lastMatches[1])
		end
	end)
 
	rebuild("")
 
	scale.Scale = 0.94
	Tween(panel, {
		GroupTransparency = 0,
		Position = UDim2.fromOffset(panel.Position.X.Offset, restY),
	}, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	Tween(scale, { Scale = 1 }, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
	task.defer(function()
		if box.Parent then box:CaptureFocus() end
	end)
end
 
Private.SUBTAB_EXIT  = 0.18
Private.SUBTAB_GAP   = 0.08
Private.SUBTAB_ENTER = 0.30
 
function Tab:AddSubTab(nameOrOpts)
	local opts = type(nameOrOpts) == "table" and nameOrOpts or { Name = nameOrOpts }
	local title = opts.Name or "SubTab"
	local iconAsset = opts.Icon and ResolveIcon(opts.Icon) or nil
	local jan = self._janitor
 
	self._subTabCount = (self._subTabCount or 0) + 1
	local idx = self._subTabCount
 
	if not self._subTabHolder then
		local page = self._page
		page.ScrollingEnabled = false
		page.AutomaticCanvasSize = Enum.AutomaticSize.None
		page.CanvasSize = UDim2.new(0, 0, 0, 0)
 
		local pl = page:FindFirstChildOfClass("UIListLayout")
		if pl then pl:Destroy() end
		local pp = page:FindFirstChildOfClass("UIPadding")
		if pp then pp:Destroy() end
		local oldTrack = page:FindFirstChild("ScrollTrack")
		if oldTrack then oldTrack:Destroy() end
 
		self._subTabHolder = Instance.new("ScrollingFrame")
		self._subTabHolder.Name = "SubTabBar"
		self._subTabHolder.Size = UDim2.new(1, -12, 0, 40)
		self._subTabHolder.Position = UDim2.fromOffset(2, 6)
		self._subTabHolder.BackgroundTransparency = 1
		self._subTabHolder.BorderSizePixel = 0
		self._subTabHolder.ScrollingDirection = Enum.ScrollingDirection.X
		self._subTabHolder.ScrollBarThickness = 0
		self._subTabHolder.AutomaticCanvasSize = Enum.AutomaticSize.X
		self._subTabHolder.CanvasSize = UDim2.new(0, 0, 0, 40)
		self._subTabHolder.ZIndex = Z.Content
		self._subTabHolder.Parent = page
		AddScrollbar(self._subTabHolder)
 
		self._subTabIndicatorLayer = Instance.new("Frame")
		self._subTabIndicatorLayer.Name = "SubTabIndicatorLayer"
		self._subTabIndicatorLayer.BackgroundTransparency = 1
		self._subTabIndicatorLayer.ClipsDescendants = true
		self._subTabIndicatorLayer.ZIndex = Z.Window
		self._subTabIndicatorLayer.Position = self._subTabHolder.Position
		self._subTabIndicatorLayer.Size = self._subTabHolder.Size
		self._subTabIndicatorLayer.Parent = page
 
		self._subTabIndicator = Instance.new("Frame")
		self._subTabIndicator.Name = "Indicator"
		self._subTabIndicator.BackgroundColor3 = SilentUI.Theme.Surface
		self._subTabIndicator.BackgroundTransparency = 1
		self._subTabIndicator.BorderSizePixel = 0
		self._subTabIndicator.ZIndex = Z.Window
		self._subTabIndicator.Size = UDim2.fromOffset(0, 32)
		self._subTabIndicator.Position = UDim2.fromOffset(0, 4)
		self._subTabIndicator.Parent = self._subTabIndicatorLayer
		Corner(self._subTabIndicator, 8)
 
		local sl = Instance.new("UIListLayout")
		sl.FillDirection = Enum.FillDirection.Horizontal
		sl.VerticalAlignment = Enum.VerticalAlignment.Center
		sl.Padding = UDim.new(0, 6)
		sl.SortOrder = Enum.SortOrder.LayoutOrder
		sl.Parent = self._subTabHolder
 
		self._subTabBody = Instance.new("Frame")
		self._subTabBody.Name = "SubTabBody"
		-- Keep a clear visual gutter below the subtab bar and its scroll track.
		-- This prevents the first card/paragraph text from visually touching the tab labels on small screens.
		self._subTabBody.Size = UDim2.new(1, -4, 1, -70)
		self._subTabBody.Position = UDim2.fromOffset(2, 64)
		self._subTabBody.BackgroundTransparency = 1
		self._subTabBody.BorderSizePixel = 0
		self._subTabBody.ClipsDescendants = true
		self._subTabBody.ZIndex = Z.Content
		self._subTabBody.Parent = page
 
		self._subTabScrollTrack = Instance.new("Frame")
		self._subTabScrollTrack.Name = "SubTabScrollTrack"
		self._subTabScrollTrack.BackgroundColor3 = SilentUI.Theme.TextDim
		self._subTabScrollTrack.BackgroundTransparency = 0.85
		self._subTabScrollTrack.BorderSizePixel = 0
		self._subTabScrollTrack.Position = UDim2.new(0, 2, 0, 48)
		self._subTabScrollTrack.Size = UDim2.new(1, -12, 0, 3)
		self._subTabScrollTrack.Visible = false
		self._subTabScrollTrack.ZIndex = Z.Content
		self._subTabScrollTrack.Parent = page
		Corner(self._subTabScrollTrack, 2)
 
		self._subTabScrollThumb = Instance.new("Frame")
		self._subTabScrollThumb.Name = "Thumb"
		self._subTabScrollThumb.BackgroundColor3 = SilentUI.Theme.TextDim
		self._subTabScrollThumb.BackgroundTransparency = 0.35
		self._subTabScrollThumb.BorderSizePixel = 0
		self._subTabScrollThumb.Size = UDim2.new(0, 40, 1, 0)
		self._subTabScrollThumb.ZIndex = Z.Content + 1
		self._subTabScrollThumb.Parent = self._subTabScrollTrack
		Corner(self._subTabScrollThumb, 2)
 
		function self._updateSubTabScrollbar()
			local holder = self._subTabHolder
			local track = self._subTabScrollTrack
			if not holder or not track then return end
			if not self._group or not self._group.Visible then
				track.Visible = false
				return
			end
			local windowW = holder.AbsoluteWindowSize.X
			local canvasW = holder.AbsoluteCanvasSize.X
			local overflow = canvasW - windowW
			if overflow <= 1 or windowW <= 0 then
				track.Visible = false
				return
			end
			track.Visible = true
			local trackW = track.AbsoluteSize.X
			if trackW <= 0 then return end
			local thumbW = math.min(trackW, math.max(30, trackW * (windowW / canvasW)))
			local maxThumbX = trackW - thumbW
			local ratio = math.clamp(holder.CanvasPosition.X / overflow, 0, 1)
			self._subTabScrollThumb.Size = UDim2.new(thumbW / trackW, 0, 1, 0)
			self._subTabScrollThumb.Position = UDim2.new((maxThumbX / trackW) * ratio, 0, 0, 0)
		end
 
		jan:Add(RunService.Heartbeat:Connect(self._updateSubTabScrollbar))
 
		self._subTabs = {}
		self._subTabWidthUpdaters = {}
		jan:Add(self._subTabHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			for _, updateWidth in pairs(self._subTabWidthUpdaters or {}) do
				updateWidth()
			end
		end))
 
		function self._syncSubIndicator(animated)
			local sel = self._subTabs and self._subTabs[self.SelectedSubTab]
			if not sel or not sel.Button.Parent then return end
			local holder = self._subTabHolder
			local s = GetUIScale()
			local relX = (sel.Button.AbsolutePosition.X - holder.AbsolutePosition.X) / s
			local w = sel.Button.AbsoluteSize.X / s
			if w <= 0 then return end
			local goal = {
				Position = UDim2.fromOffset(math.round(relX), 4),
				Size = UDim2.fromOffset(math.round(w), 32),
				BackgroundTransparency = 0.86,
			}
			if animated then
				Tween(self._subTabIndicator, goal, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			else
				self._subTabIndicator.Position = goal.Position
				self._subTabIndicator.Size = goal.Size
				self._subTabIndicator.BackgroundTransparency = goal.BackgroundTransparency
			end
		end
 
		jan:Add(self._subTabHolder:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			self._syncSubIndicator(false)
			self._updateSubTabScrollbar()
		end))
	end
 
	local btn = Instance.new("TextButton")
	btn.Name = "SubTab_" .. title:gsub("%s", "")
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = SilentUI.Theme.Surface
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.AutomaticSize = Enum.AutomaticSize.None
	btn.Size = UDim2.fromOffset(72, 32)
	btn.LayoutOrder = idx
	btn.ZIndex = Z.Content
	btn.Parent = self._subTabHolder
	Corner(btn, 8)
 
	local bl = Instance.new("UIListLayout")
	bl.FillDirection = Enum.FillDirection.Horizontal
	bl.VerticalAlignment = Enum.VerticalAlignment.Center
	bl.SortOrder = Enum.SortOrder.LayoutOrder
	bl.Padding = UDim.new(0, 6)
	bl.Parent = btn
 
	local bpad = Instance.new("UIPadding")
	bpad.PaddingLeft = UDim.new(0, 12)
	bpad.PaddingRight = UDim.new(0, 12)
	bpad.Parent = btn
 
	local ic = nil
	if iconAsset and iconAsset ~= "" then
		ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Image = iconAsset
		ic.ImageColor3 = SilentUI.Theme.TextDim
		ic.Size = UDim2.fromOffset(16, 16)
		ic.LayoutOrder = 1
		ic.ZIndex = Z.Content + 1
		ic.Parent = btn
	end
 
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.FontFace = SilentUI.Theme.Font
	lbl.Text = title
	lbl.TextColor3 = SilentUI.Theme.TextDim
	lbl.TextSize = 13
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.TextWrapped = false
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Size = UDim2.fromOffset(48, 32)
	lbl.AutomaticSize = Enum.AutomaticSize.None
	lbl.LayoutOrder = 2
	lbl.ZIndex = Z.Content + 1
	lbl.Parent = btn
	if opts.NameKey then SilentUI:Localize(lbl, opts.NameKey) end

	local function updateSubTabButtonWidth()
		if not btn.Parent or not lbl.Parent then return end
		local scale = math.max(GetUIScale(), 0.01)
		local viewportWidth = self._subTabHolder and self._subTabHolder.AbsoluteSize.X / scale or 0
		local maxLabelWidth = math.max(48, math.min(220, viewportWidth > 0 and viewportWidth - 48 or 220))
		local measuredWidth = MeasureText(lbl.Text, lbl.TextSize, 10000)
		local labelWidth = math.clamp(measuredWidth, 48, maxLabelWidth)
		lbl.Size = UDim2.fromOffset(labelWidth, 32)
		local iconWidth = ic and 22 or 0
		local buttonWidth = math.max(64, math.ceil(labelWidth + iconWidth + 24))
		btn.Size = UDim2.fromOffset(buttonWidth, 32)
	end

	self._subTabWidthUpdaters = self._subTabWidthUpdaters or {}
	self._subTabWidthUpdaters[idx] = updateSubTabButtonWidth
	jan:Add(lbl:GetPropertyChangedSignal("Text"):Connect(updateSubTabButtonWidth))
	jan:Add(lbl:GetPropertyChangedSignal("TextSize"):Connect(updateSubTabButtonWidth))
	jan:Add(btn.AncestryChanged:Connect(function(_, parent)
		if parent == nil and self._subTabWidthUpdaters then
			self._subTabWidthUpdaters[idx] = nil
		end
	end))
	updateSubTabButtonWidth()
 
	local group = Instance.new("Frame")
	group.Name = title .. "Group"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.Visible = false
	group.ZIndex = Z.Content
	group.Parent = self._subTabBody
 
	local container = Instance.new("ScrollingFrame")
	container.Name = title .. "Page"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ScrollingDirection = Enum.ScrollingDirection.Y
	container.ScrollBarThickness = 0
	container.AutomaticCanvasSize = Enum.AutomaticSize.Y
	container.CanvasSize = UDim2.new(0, 0, 0, 0)
	container.ZIndex = Z.Content
	container.Parent = group
 
	local cpad = Instance.new("UIPadding")
	cpad.Name = "PagePadding"
	cpad.PaddingRight = UDim.new(0, 12)
	cpad.PaddingBottom = UDim.new(0, 6)
	cpad.Parent = container
 
	local clayout = Instance.new("UIListLayout")
	clayout.Name = "PageLayout"
	clayout.Padding = UDim.new(0, 8)
	clayout.SortOrder = Enum.SortOrder.LayoutOrder
	clayout.Parent = container
 
	AddScrollbar(container)
	Private.AddContentScrollThumb(container, clayout, group, jan)
	Private.AddEmptyState(container, group, jan)
 
	local sub = setmetatable({
		Name           = title,
		_page          = container,
		_window        = self._window,
		_janitor       = jan,
		_parentTab     = self,
		_parentTabName = self.Name,
		_subTabIdx     = idx,
		Button    = btn,
		Label     = lbl,
		Icon      = ic,
		Container = container,
		Group     = group,
		Selected  = false,
	}, Tab)
 
	self._subTabs[idx] = sub
 
	jan:Add(btn:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		if self.SelectedSubTab == idx then
			self._syncSubIndicator(false)
		end
	end))
	jan:Add(btn:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if self.SelectedSubTab == idx then
			self._syncSubIndicator(false)
		end
	end))
 
	jan:Add(btn.MouseEnter:Connect(function()
		if idx ~= self.SelectedSubTab then
			Tween(btn, { BackgroundTransparency = 0.94 }, 0.15)
		end
	end))
	jan:Add(btn.MouseLeave:Connect(function()
		if idx ~= self.SelectedSubTab then
			Tween(btn, { BackgroundTransparency = 1 }, 0.15)
		end
	end))
 
	local downPos = nil
	jan:Add(btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			downPos = input.Position
		end
	end))
	jan:Add(btn.InputEnded:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch) and downPos then
			if (input.Position - downPos).Magnitude < DRAG_THRESHOLD then
				self:SelectSubTab(idx)
			end
			downPos = nil
		end
	end))
 
	task.defer(updateSubTabButtonWidth)
	if not self.SelectedSubTab then
		self:SelectSubTab(idx)
	end
 
	return sub
end
 
function Tab:SelectSubTab(idx)
	if not self._subTabs then return end
	local previous = self.SelectedSubTab
	if previous == idx then return end
 
	self._subTabSwitchToken = (self._subTabSwitchToken or 0) + 1
	local myToken = self._subTabSwitchToken
 
	local direction = 0
	if previous then
		direction = (idx > previous) and 1 or -1
	end
 
	self.SelectedSubTab = idx
	local target = self._subTabs[idx]
	local previousSub = previous and self._subTabs[previous]
	if not target then return end
 
	self._syncSubIndicator(previous ~= nil)
 
	for i, st in pairs(self._subTabs) do
		local sel = (i == idx)
		st.Selected = sel
		if not sel then
			Tween(st.Button, { BackgroundTransparency = 1 }, 0.15)
		end
		Tween(st.Label, { TextColor3 = sel and SilentUI.Theme.Text or SilentUI.Theme.TextDim }, 0.22)
		if st.Icon then
			Tween(st.Icon, { ImageColor3 = sel and SilentUI.Theme.Text or SilentUI.Theme.TextDim }, 0.22)
		end
	end
 
	for _, st in pairs(self._subTabs) do
		if st ~= target and st ~= previousSub and st.Group.Visible then
			st.Group.Visible = false
		end
	end
 
	local function playEnter()
		if self._subTabSwitchToken ~= myToken then return end
		target.Group.Visible = true
		target.Group.Position = UDim2.fromOffset(direction * 20, 0)
		Tween(target.Group, {
			Position = UDim2.fromOffset(0, 0),
		}, Private.SUBTAB_ENTER, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end
 
	if previousSub and previousSub.Group.Visible then
		local g = previousSub.Group
		Tween(g, {
			Position = UDim2.fromOffset(-direction * 20, 0),
		}, Private.SUBTAB_EXIT, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(Private.SUBTAB_EXIT, function()
			if g then g.Visible = false end
			task.delay(Private.SUBTAB_GAP, playEnter)
		end)
	else
		playEnter()
	end
end
 
function Tab:SelectSubTabByName(name)
	if not self._subTabs then return nil end
	for idx, st in pairs(self._subTabs) do
		if st.Name == name then
			self:SelectSubTab(idx)
			return st
		end
	end
	return nil
end
 
function Private.ValidateConfigFlag(api, value)
	local kind = api.Kind
	if kind == "Toggle" then return type(value) == "boolean", value, "expected a boolean" end
	if kind == "Slider" then
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge, value, "expected a finite number"
	end
	if kind == "Textbox" then return type(value) == "string", value, "expected a string" end
	if kind == "ColorPicker" then return typeof(value) == "Color3", value, "expected a Color3" end
	if kind == "Keybind" then
		if type(value) == "table" then
			local keyValue = value.key
			if keyValue == nil then keyValue = value.Key end
			if keyValue == nil and type(api.Get) == "function" then
				local ok, current = pcall(api.Get, api)
				if ok then keyValue = current end
			end
			local key, keyErr = Private.ResolveKeybindKey(keyValue)
			if keyErr then return false, nil, keyErr end
			local mode = value.mode or value.Mode or api.Mode or "Toggle"
			local legacyPress = mode == "Press"
			if legacyPress then mode = "Toggle" end
			if mode ~= "Toggle" and mode ~= "Hold" and mode ~= "Always" then
				return false, nil, "mode must be Toggle, Hold, or Always"
			end
			local active
			if legacyPress then
				active = false
			else
				active = value.active
				if active == nil then active = value.Active end
				if active == nil and type(api.GetActive) == "function" then
					local ok, current = pcall(api.GetActive, api)
					if ok then active = current end
				end
				if active ~= nil and type(active) ~= "boolean" then return false, nil, "active must be a boolean" end
			end
			local context = value.context or value.Context or api.Context or "global"
			if type(context) ~= "string" or context:gsub("%s", "") == "" then
				return false, nil, "context must be a non-empty string"
			end
			if mode == "Always" then active = true end
			if mode == "Hold" then active = false end
			return true, { key = key or "NONE", mode = mode, context = context, active = active == true }
		end
		local key, keyErr = Private.ResolveKeybindKey(value)
		if keyErr then return false, nil, keyErr end
		return true, key
	end
	if kind == "Dropdown" then
		local ok, current = pcall(api.Get)
		if not ok then return false, nil, "could not read current dropdown value" end
		if type(current) == "table" then
			if type(value) ~= "table" then return false, nil, "expected a selection list" end
			for key, item in pairs(value) do
				if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or (type(item) ~= "string" and type(item) ~= "number") then
					return false, nil, "dropdown selections must be an array of strings or numbers"
				end
			end
			return true, value
		end
		if value == nil then return true, value end
		if current ~= nil and type(value) ~= type(current) then return false, nil, "expected a " .. type(current) end
		if current == nil and type(value) ~= "string" and type(value) ~= "number" then return false, nil, "expected a string or number" end
		return true, value
	end
	return true, value
end


local function CopyInitialFlagValue(value, seen)
	if type(value) ~= "table" then return value end
	seen = seen or {}
	if seen[value] then return seen[value] end
	local copy = {}
	seen[value] = copy
	for key, item in pairs(value) do
		copy[CopyInitialFlagValue(key, seen)] = CopyInitialFlagValue(item, seen)
	end
	return copy
end

local EnabledBindings = {}
function Private.ResolveEnabledCondition(spec)
	if type(spec) == "function" then
		local ok, result = pcall(spec, function(flag)
			local api = SilentUI.Flags[flag]
			return api and api.Get and api:Get() or nil
		end)
		return ok and not not result
	end
	if type(spec) == "string" then spec = { Flag = spec } end
	if type(spec) ~= "table" then return false end
	if type(spec.All) == "table" then
		for _, item in ipairs(spec.All) do
			if not Private.ResolveEnabledCondition(item) then return false end
		end
		return true
	end
	if type(spec.Any) == "table" then
		for _, item in ipairs(spec.Any) do
			if Private.ResolveEnabledCondition(item) then return true end
		end
		return false
	end
	local api = SilentUI.Flags[spec.Flag]
	local ok, current = false, nil
	if api and type(api.Get) == "function" then
		ok, current = pcall(api.Get, api)
	end
	local matched = false
	if ok then
		if spec.Equals ~= nil then
			matched = current == spec.Equals
		else
			matched = not not current
		end
	end
	if spec.Not then return not matched end
	return matched
end

function SilentUI:RefreshEnabledConditions()
	for control, binding in pairs(EnabledBindings) do
		if control._SilentDependencyDestroyed then
			EnabledBindings[control] = nil
		else
			local enabled = Private.ResolveEnabledCondition(binding.Condition)
			if enabled ~= binding.Enabled then
				binding.Enabled = enabled
				if type(control.SetLocked) == "function" then
					control:SetLocked(not enabled)
				else
					binding.Guard.Visible = not enabled
				end
				if type(binding.OnChanged) == "function" then
					task.spawn(binding.OnChanged, enabled)
				end
			end
		end
	end
end

function SilentUI:BindEnabledWhen(control, condition, onChanged)
	assert(type(control) == "table" and typeof(control.Instance) == "Instance",
		"BindEnabledWhen expects a UI control with an Instance")
	assert(type(condition) == "string" or type(condition) == "table" or type(condition) == "function",
		"EnabledWhen expects a flag, condition table or function")
	local oldBinding = EnabledBindings[control]
	if oldBinding then
		if oldBinding.Connection then oldBinding.Connection:Disconnect() end
		oldBinding.Guard:Destroy()
	end
	local guard = Instance.new("TextButton")
	guard.Name = "SilentDisabledGuard"
	guard.Text = ""
	guard.AutoButtonColor = false
	guard.BackgroundColor3 = SilentUI.Theme.Background
	guard.BackgroundTransparency = 0.87
	guard.BorderSizePixel = 0
	guard.Size = UDim2.fromScale(1, 1)
	guard.ZIndex = 100
	guard.Visible = false
	guard.Parent = control.Instance
	local guardConnection = control.Instance.Destroying:Connect(function()
		EnabledBindings[control] = nil
	end)
	EnabledBindings[control] = {
		Condition = condition, Guard = guard, OnChanged = onChanged, Connection = guardConnection
	}
	local originalDestroy = control.Destroy
	control.Destroy = function(self, ...)
		self._SilentDependencyDestroyed = true
		EnabledBindings[self] = nil
		guardConnection:Disconnect()
		guard:Destroy()
		if originalDestroy then return originalDestroy(self, ...) end
	end
	self:RefreshEnabledConditions()
	return control
end

-- Controls may share one persisted Flag only when the additional control opts in.
-- SilentUI.Flags continues to expose the canonical controller; replicas are UI views.
local SharedFlagGroups = {}

function Private.ReadSharedFlagValue(api)
	local getter = api.Kind == "Keybind" and api.GetState or api.Get
	assert(type(getter) == "function", "SharedFlag requires a readable control")
	return getter(api)
end

function Private.SyncSharedFlag(group, origin, silent)
	if group.Syncing or origin._SharedFlagDestroyed then return end
	group.Syncing = true
	local ok, err = pcall(function()
		local value = CopyInitialFlagValue(Private.ReadSharedFlagValue(origin))
		if origin ~= group.Primary then
			assert(group.Primary, "SharedFlag has no primary controller")
			group.Primary:Set(CopyInitialFlagValue(value), silent == true)
			value = CopyInitialFlagValue(Private.ReadSharedFlagValue(group.Primary))
		end
		for _, peer in ipairs(group.Controls) do
			if peer ~= origin and peer ~= group.Primary and not peer._SharedFlagDestroyed then
				peer:Set(CopyInitialFlagValue(value), true)
			end
		end
	end)
	group.Syncing = false
	if not ok then warn("[SilentUI] shared flag '" .. group.Flag .. "' could not synchronize: " .. tostring(err)) end
end

local function RegisterFlag(opts, api, kind, validator)
	if opts.Flag ~= nil then
		local flag = opts.Flag
		if type(flag) ~= "string" or flag:gsub("%s", "") == "" then
			error("Control Flag must be a non-empty string", 2)
		end
		local existing = SilentUI.Flags[flag]
		if existing and opts.SharedFlag ~= true then
			error("duplicate flag '" .. flag .. "' (use SharedFlag = true to mirror it)", 2)
		end
		if existing and existing.Kind ~= kind then
			error("shared flag '" .. flag .. "' must use the same control kind", 2)
		end
		if existing and kind == "Keybind" and existing.ToggleFlag ~= api.ToggleFlag then
			error("shared keybind '" .. flag .. "' must use the same ToggleFlag", 2)
		end

		local group = SharedFlagGroups[flag]
		if not group then
			group = { Flag = flag, Primary = api, Controls = { api }, Syncing = false }
			SharedFlagGroups[flag] = group
		end

		api.Flag = flag
		api.Kind = kind
		api.Label = opts.Text or opts.Label or flag
		local initialGetter = kind == "Keybind" and api.GetState or api.Get
		if type(initialGetter) == "function" then
			local initialOk, initialValue = pcall(initialGetter, api)
			if initialOk then
				api._HasInitialValue = true
				api._InitialValue = CopyInitialFlagValue(initialValue)
			end
		end
		if not existing and kind ~= "Keybind" and type(opts.Callback) == "function" then
			SilentUI._NextControlRegistration += 1
			api._InitializationCallback = opts.Callback
			api._RegistrationOrder = SilentUI._NextControlRegistration
		end
		api.ValidateConfig = validator or function(value) return Private.ValidateConfigFlag(api, value) end

		local function wrapSetter(method)
			local setter = api[method]
			if type(setter) ~= "function" then return end
			api[method] = function(control, ...)
				local previousSource = SilentUI._ChangeSource
				if previousSource == nil then SilentUI._ChangeSource = "code" end
				local arguments = table.pack(...)
				local results = table.pack(pcall(setter, control, ...))
				SilentUI._ChangeSource = previousSource
				if not results[1] then error(results[2], 2) end
				if not group.Syncing then Private.SyncSharedFlag(group, api, arguments[2]) end
				return table.unpack(results, 2, results.n)
			end
		end
		wrapSetter("Set")
		if kind == "Keybind" then
			wrapSetter("SetMode")
			wrapSetter("SetContext")
			wrapSetter("SetActive")
		end

		if existing then
			local snapshotOk, snapshot = pcall(Private.ReadSharedFlagValue, group.Primary)
			if not snapshotOk then error("shared flag '" .. flag .. "' cannot read its primary: " .. tostring(snapshot), 2) end
			group.Syncing = true
			local applied, applyErr = pcall(api.Set, api, CopyInitialFlagValue(snapshot), true)
			group.Syncing = false
			if not applied then error("shared flag '" .. flag .. "' cannot initialize its mirror: " .. tostring(applyErr), 2) end
			table.insert(group.Controls, api)
		else
			SilentUI.Flags[flag] = api
			SilentUI.ConfigFlags[flag] = api.Set
			SilentUI.ConfigValidators[flag] = api.ValidateConfig
			group.InitialValue = CopyInitialFlagValue(api._InitialValue)
			group.HasInitialValue = api._HasInitialValue
		end

		local configChangeHook = api.OnStateChanged or api.OnChanged
		if type(configChangeHook) == "function" then
			local ok, connection = pcall(configChangeHook, api, function()
				if api._SharedFlagDestroyed then return end
				Private.SyncSharedFlag(group, api, false)
				SilentUI:RefreshEnabledConditions()
				if group.Primary == api and not SilentUI._ApplyingConfig and SilentUI.QueueAutoConfigSave then
					SilentUI:QueueAutoConfigSave(flag)
				end
			end)
			if ok then api._ConfigChangeConnection = connection end
		end

		local originalDestroy = api.Destroy
		if type(originalDestroy) == "function" then
			api.Destroy = function(self, ...)
				if self._SharedFlagDestroyed then return end
				self._SharedFlagDestroyed = true
				local connection = self._ConfigChangeConnection
				if connection and type(connection.Disconnect) == "function" then
					pcall(function() connection:Disconnect() end)
				end
				self._ConfigChangeConnection = nil
				local index = table.find(group.Controls, self)
				if index then table.remove(group.Controls, index) end
				if group.Primary == self then
					local replacement = group.Controls[1]
					group.Primary = replacement
					SilentUI.Flags[flag] = replacement
					SilentUI.ConfigFlags[flag] = replacement and replacement.Set or nil
					SilentUI.ConfigValidators[flag] = replacement and replacement.ValidateConfig or nil
					if replacement then
						replacement._HasInitialValue = group.HasInitialValue
						replacement._InitialValue = CopyInitialFlagValue(group.InitialValue)
					end
				end
				if #group.Controls == 0 then SharedFlagGroups[flag] = nil end
				return originalDestroy(self, ...)
			end
		end

		if not existing and SilentUI.ApplyAutoConfigFlag then SilentUI:ApplyAutoConfigFlag(flag) end
		if opts.TextKey or opts.DescriptionKey then SilentUI:LocalizeControl(api, opts) end
		if opts.EnabledWhen then SilentUI:BindEnabledWhen(api, opts.EnabledWhen, opts.OnEnabledChanged) end
		SilentUI:RefreshEnabledConditions()
		if SilentUI._RefreshFloatingBindings then SilentUI:_RefreshFloatingBindings() end
	end
	return api
end

function Tab:AddLabel(textOrOptions)
	local opts = type(textOrOptions) == "table" and textOrOptions or { Text = textOrOptions }
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = SilentUI.Theme.FontRegular
	label.Text = tostring(opts.Text or "")
	label.RichText = opts.RichText == true
	label.TextColor3 = typeof(opts.Color) == "Color3" and opts.Color or SilentUI.Theme.TextDim
	label.TextSize = 13
	label.TextWrapped = opts.TextWrapped ~= false
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, 0, 0, 16)
	label.ZIndex = Z.Content
	label.Parent = self._page
	if opts.TextKey then SilentUI:Localize(label, opts.TextKey) end
	if typeof(opts.Color) == "Color3" then label:SetAttribute("SilentThemeColorExempt", true) end
	local function set(value)
		if type(value) == "table" then
			if value.Text ~= nil then label.Text = tostring(value.Text) end
			if value.RichText ~= nil then label.RichText = value.RichText == true end
			if value.TextWrapped ~= nil then label.TextWrapped = value.TextWrapped == true end
			if typeof(value.Color) == "Color3" then
				label.TextColor3 = value.Color
				label:SetAttribute("SilentThemeColorExempt", true)
			end
		else
			label.Text = tostring(value or "")
		end
	end
 
	return {
		Instance = label,
		Set = function(_, value) set(value) end,
		Get = function() return label.Text end,
		SetColor = function(_, color)
			if typeof(color) == "Color3" then
				label.TextColor3 = color
				label:SetAttribute("SilentThemeColorExempt", true)
			end
		end,
		Destroy = function() label:Destroy() end,
	}
end
 
function Tab:AddSection(textOrOpts, maybeIcon)
    local opts = type(textOrOpts) == "table" and textOrOpts or { Text = textOrOpts, Icon = maybeIcon }
    local text = tostring(opts.Text or "Section")
    local iconAsset = opts.Icon and ResolveIcon(opts.Icon) or ""
    local columnCount = (opts.Columns == true and 2) or math.clamp(tonumber(opts.Columns) or 1, 1, 2)
    local stackAtWidth = math.clamp(tonumber(opts.StackAtWidth) or 560, 360, 900)
    local windowId = self._window and self._window._id

    local holder = Instance.new("Frame")
    holder.Name = "Section"
    holder.BackgroundColor3 = SilentUI.Theme.Surface
    holder.BackgroundTransparency = self._window and self._window._interfaceTransparency or 0.72
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.Size = UDim2.new(1, 0, 0, 0)
    holder.ZIndex = Z.Content
    holder.Parent = self._page
    holder:SetAttribute("SilentInterfacePanel", true)
    if windowId then holder:SetAttribute("SilentWindowId", windowId) end
    Corner(holder, SilentUI.Theme.CornerRadiusSm)
    Stroke(holder, SilentUI.Theme.Border, 1, 0.92)

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 7)
    padding.PaddingBottom = UDim.new(0, 9)
    padding.PaddingLeft = UDim.new(0, 10)
    padding.PaddingRight = UDim.new(0, 10)
    padding.Parent = holder

    local holderLayout = Instance.new("UIListLayout")
    holderLayout.Padding = UDim.new(0, 7)
    holderLayout.SortOrder = Enum.SortOrder.LayoutOrder
    holderLayout.Parent = holder

    local header = Instance.new("TextButton")
    header.Name = "Header"
    header.AutoButtonColor = false
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1, 0, 0, 22)
    header.Text = ""
    header.LayoutOrder = 1
    header.ZIndex = Z.Content + 1
    header.Parent = holder

    local x = 0
    if iconAsset ~= "" then
        local img = Instance.new("ImageLabel")
        img.BackgroundTransparency = 1
        img.Image = iconAsset
        img.ImageColor3 = SilentUI.Theme.TextDim
        img.Size = UDim2.fromOffset(13, 13)
        img.Position = UDim2.fromOffset(0, 4)
        img.ZIndex = Z.Content + 2
        img.Parent = header
        x = 20
    end

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.FontFace = SilentUI.Theme.Font
    label.Text = string.upper(text)
    label.TextColor3 = SilentUI.Theme.TextDim
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.Position = UDim2.fromOffset(x, 4)
    label.Size = UDim2.new(1, -(x + 22), 0, 14)
    label.ZIndex = Z.Content + 2
    label.Parent = header
    if opts.TextKey then SilentUI:Localize(label, opts.TextKey) end

    local collapseIcon
    if opts.Collapsible then
        collapseIcon = Instance.new("ImageLabel")
        collapseIcon.Name = "CollapseIcon"
        collapseIcon.BackgroundTransparency = 1
        collapseIcon.Image = ResolveIcon("chevron-down")
        collapseIcon.ImageColor3 = SilentUI.Theme.TextDim
        collapseIcon.Size = UDim2.fromOffset(13, 13)
        collapseIcon.AnchorPoint = Vector2.new(1, 0.5)
        collapseIcon.Position = UDim2.new(1, 0, 0.5, 0)
        collapseIcon.ZIndex = Z.Content + 2
        collapseIcon.Parent = header
    end

    local body = Instance.new("Frame")
    body.Name = "SectionContent"
    body.BackgroundTransparency = 1
    body.AutomaticSize = Enum.AutomaticSize.Y
    body.Size = UDim2.new(1, 0, 0, 0)
    body.LayoutOrder = 2
    body.ZIndex = Z.Content + 1
    body.Parent = holder

    local columns, columnLayouts = {}, {}
    for i = 1, columnCount do
        local column = Instance.new("Frame")
        column.Name = "Column" .. i
        column.BackgroundTransparency = 1
        column.AutomaticSize = Enum.AutomaticSize.Y
        column.ZIndex = Z.Content + 1
        if columnCount == 1 then
            column.Size = UDim2.new(1, 0, 0, 0)
        else
            column.Size = UDim2.new(0.5, -4, 0, 0)
            column.Position = UDim2.new((i - 1) * 0.5, (i - 1) * 8, 0, 0)
        end
        column.Parent = body

        local columnLayout = Instance.new("UIListLayout")
        columnLayout.Padding = UDim.new(0, 7)
        columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
        columnLayout.Parent = column
        columns[i] = column
        columnLayouts[i] = columnLayout
    end

    local collapsed = opts.Collapsible == true and opts.Collapsed == true
    local stacked = false
    body.Visible = not collapsed
    if collapseIcon and collapsed then collapseIcon.Rotation = -90 end

    local section = {
        Instance = holder,
        Name = text,
        _page = self._page,
        _columns = columns,
        _columnLayouts = columnLayouts,
        _controls = {},
        _columnOrders = {},
        _columnCount = columnCount,
        _nextColumn = 1,
        _manualColumn = false,
        _window = self._window,
        _janitor = self._janitor,
        _group = self._group,
        _button = self._button,
        _select = self._select,
        _parentTab = self._parentTab,
        _parentTabName = self._parentTabName,
        _subTabIdx = self._subTabIdx,
        Collapsed = collapsed,
        Set = function(_, value) label.Text = string.upper(tostring(value or "")) end,
        SetColumn = function(self, index)
            index = math.floor(tonumber(index) or 1)
            if index < 1 or index > self._columnCount then return false end
            self._nextColumn = index
            self._manualColumn = true
            return true
        end,
        SetCollapsed = function(self, value)
            self.Collapsed = value == true
            body.Visible = not self.Collapsed
            if self.Collapsed then
                holder.AutomaticSize = Enum.AutomaticSize.None
                holder.Size = UDim2.new(1, 0, 0, 38)
            else
                holder.AutomaticSize = Enum.AutomaticSize.Y
                holder.Size = UDim2.new(1, 0, 0, 0)
                task.defer(function() section.responsiveRelayout() end)
            end
            if collapseIcon then collapseIcon.Rotation = self.Collapsed and -90 or 0 end
        end,
        ToggleCollapsed = function(self)
            self:SetCollapsed(not self.Collapsed)
        end,
        Destroy = function(self)
            for index = #self._controls, 1, -1 do
                local control = self._controls[index]
                if control and type(control.Destroy) == "function" then pcall(control.Destroy, control) end
            end
            table.clear(self._controls)
            holder:Destroy()
        end,
    }

    function section.responsiveRelayout()
        if not holder.Parent or section.Collapsed then return end
        local width = holder.AbsoluteSize.X / GetUIScale()
        if width <= 0 then return end
        local shouldStack = columnCount > 1 and width < stackAtWidth
        if shouldStack == stacked and not shouldStack then return end
        stacked = shouldStack

        if stacked then
            body.AutomaticSize = Enum.AutomaticSize.None
            body.Size = UDim2.new(1, 0, 0, 0)
            local cursorY = 0
            for index, column in ipairs(columns) do
                local contentHeight = columnLayouts[index].AbsoluteContentSize.Y / GetUIScale()
                if contentHeight <= 0 then contentHeight = 1 end
                column.AutomaticSize = Enum.AutomaticSize.None
                column.Position = UDim2.fromOffset(0, cursorY)
                column.Size = UDim2.new(1, 0, 0, contentHeight)
                cursorY += contentHeight + (index < #columns and 7 or 0)
            end
            body.Size = UDim2.new(1, 0, 0, math.max(0, cursorY - 7))
        else
            body.AutomaticSize = Enum.AutomaticSize.Y
            body.Size = UDim2.new(1, 0, 0, 0)
            for index, column in ipairs(columns) do
                column.AutomaticSize = Enum.AutomaticSize.Y
                column.Size = UDim2.new(0.5, -4, 0, 0)
                column.Position = UDim2.new((index - 1) * 0.5, (index - 1) * 8, 0, 0)
            end
        end
    end

    if collapsed then section:SetCollapsed(true) end
    setmetatable(section, {
        __index = function(self, key)
            if key == "AddSection" then return nil end
            local method = Tab[key]
            if type(method) ~= "function" then return method end
            return function(sectionSelf, ...)
                local oldPage = sectionSelf._page
                local columnIndex
                if sectionSelf._manualColumn then
                    columnIndex = sectionSelf._nextColumn
                    sectionSelf._manualColumn = false
                elseif sectionSelf._columnCount > 1 and not stacked then
                    local heights = sectionSelf._columnLayouts
                    columnIndex = 1
                    for index = 2, #heights do
                        if heights[index].AbsoluteContentSize.Y < heights[columnIndex].AbsoluteContentSize.Y then
                            columnIndex = index
                        end
                    end
                else
                    columnIndex = sectionSelf._nextColumn or 1
                    if sectionSelf._columnCount == 1 then columnIndex = 1 end
                end
                sectionSelf._nextColumn = columnIndex % sectionSelf._columnCount + 1
                sectionSelf._page = sectionSelf._columns[columnIndex] or sectionSelf._columns[1]
                local arguments = table.pack(...)
                local results = table.pack(pcall(method, sectionSelf, table.unpack(arguments, 1, arguments.n)))
                sectionSelf._page = oldPage
                if not results[1] then error(results[2], 2) end
                local control = results[2]
                if type(control) == "table" and type(control.Destroy) == "function" then
                    table.insert(sectionSelf._controls, control)
                    local columnOrders = sectionSelf._columnOrders
                    columnOrders[columnIndex] = (columnOrders[columnIndex] or 0) + 1
                    if typeof(control.Instance) == "Instance" then
                        pcall(function() control.Instance.LayoutOrder = columnOrders[columnIndex] end)
                    end
                end
                task.defer(function() sectionSelf.responsiveRelayout() end)
                return table.unpack(results, 2, results.n)
            end
        end,
    })

    holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(section.responsiveRelayout)
    for _, columnLayout in ipairs(columnLayouts) do
        columnLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            task.defer(function() section.responsiveRelayout() end)
        end)
    end
    if opts.Collapsible then
        header.MouseButton1Click:Connect(function() section:ToggleCollapsed() end)
    end
    task.defer(section.responsiveRelayout)
    return section
end

function Tab:AddDivider()
	local holder = Instance.new("Frame")
	holder.Name = "Divider"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 13)
	holder.ZIndex = Z.Content
	holder.Parent = self._page
 
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.new(0, 0, 0.5, 0)
	line.Size = UDim2.new(1, 0, 0, 1)
	line.BackgroundColor3 = SilentUI.Theme.Surface
	line.BackgroundTransparency = 0.92
	line.BorderSizePixel = 0
	line.ZIndex = Z.Content
	line.Parent = holder
 
	return { Instance = holder, Destroy = function() holder:Destroy() end }
end
 
Tab.AddLine = Tab.AddDivider
 
function Tab:AddLineText(text)
	text = tostring(text or "")
 
	local holder = Instance.new("Frame")
	holder.Name = "LineText"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 20)
	holder.ZIndex = Z.Content
	holder.Parent = self._page
 
	local left = Instance.new("Frame")
	left.Name = "Left"
	left.AnchorPoint = Vector2.new(0, 0.5)
	left.Position = UDim2.fromScale(0, 0.5)
	left.Size = UDim2.new(0.5, -10, 0, 1)
	left.BackgroundColor3 = SilentUI.Theme.Surface
	left.BackgroundTransparency = 0.92
	left.BorderSizePixel = 0
	left.ZIndex = Z.Content
	left.Parent = holder
 
	local right = Instance.new("Frame")
	right.Name = "Right"
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Position = UDim2.fromScale(1, 0.5)
	right.Size = UDim2.new(0.5, -10, 0, 1)
	right.BackgroundColor3 = SilentUI.Theme.Surface
	right.BackgroundTransparency = 0.92
	right.BorderSizePixel = 0
	right.ZIndex = Z.Content
	right.Parent = holder
 
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.FontFace = SilentUI.Theme.FontRegular
	label.Text = text
	label.TextColor3 = SilentUI.Theme.TextDim
	label.TextSize = 12
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 16)
	label.ZIndex = Z.Content + 1
	label.Parent = holder
 
	local gap = 10
	local minSide = 6
	local lastW = -1
 
	local function relayout()
		local w = holder.AbsoluteSize.X / GetUIScale()
		if w <= 0 or math.abs(w - lastW) < 1 then return end
		lastW = w
 
		local textW = MeasureText(text, 12, w)
		local sideW = math.max((w - textW) / 2 - gap, minSide)
		left.Size = UDim2.new(0, sideW, 0, 1)
		right.Size = UDim2.new(0, sideW, 0, 1)
	end
 
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	task.defer(relayout)
 
	return {
		Instance = holder,
		Set = function(_, v)
			text = tostring(v or "")
			label.Text = text
			lastW = -1
			relayout()
		end,
		Destroy = function() holder:Destroy() end,
	}
end
 
function Tab:AddParagraph(opts)
	opts = opts or {}
 
	local card = BaseCard(self._page, 10)
	card.AutomaticSize = Enum.AutomaticSize.Y
 
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = card
 
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card
 
	local titleLabel
	if opts.Title then
		local titleRow = Instance.new("Frame")
		titleRow.BackgroundTransparency = 1
		titleRow.Size = UDim2.new(1, 0, 0, 18)
		titleRow.AutomaticSize = Enum.AutomaticSize.Y
		titleRow.LayoutOrder = 1
		titleRow.ZIndex = Z.Content + 1
		titleRow.Parent = card
 
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Padding = UDim.new(0, 7)
		rowLayout.Parent = titleRow
 
		local iconAsset = opts.Icon and ResolveIcon(opts.Icon) or ""
		if iconAsset ~= "" then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Image = iconAsset
			img.ImageColor3 = SilentUI.Theme.Text
			img.Size = UDim2.fromOffset(15, 15)
			img.LayoutOrder = 1
			img.ZIndex = Z.Content + 2
			img.Parent = titleRow
		end
 
		titleLabel = Instance.new("TextLabel")
		titleLabel.BackgroundTransparency = 1
		titleLabel.FontFace = SilentUI.Theme.Font
		titleLabel.Text = opts.Title
		titleLabel.TextColor3 = SilentUI.Theme.Text
		titleLabel.TextSize = 14
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.TextYAlignment = Enum.TextYAlignment.Center
		titleLabel.AutomaticSize = Enum.AutomaticSize.X
		titleLabel.Size = UDim2.fromOffset(0, 18)
		titleLabel.LayoutOrder = 2
		titleLabel.ZIndex = Z.Content + 2
		titleLabel.Parent = titleRow
 
		local titlePadding = Instance.new("UIPadding")
		titlePadding.PaddingTop = UDim.new(0, 2)
		titlePadding.Parent = titleLabel
	end
 
	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.FontFace = SilentUI.Theme.FontRegular
	textLabel.Text = opts.Text or ""
	textLabel.RichText = opts.RichText == true
	textLabel.TextColor3 = typeof(opts.Color) == "Color3" and opts.Color or SilentUI.Theme.TextDim
	textLabel.TextSize = 13
	textLabel.TextWrapped = opts.TextWrapped ~= false
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.AutomaticSize = Enum.AutomaticSize.Y
	textLabel.Size = UDim2.new(1, 0, 0, 16)
	textLabel.LayoutOrder = 2
	textLabel.ZIndex = Z.Content + 1
	textLabel.Parent = card
	if opts.TitleKey and titleLabel then SilentUI:Localize(titleLabel, opts.TitleKey) end
	if opts.TextKey then SilentUI:Localize(textLabel, opts.TextKey) end
	if typeof(opts.Color) == "Color3" then textLabel:SetAttribute("SilentThemeColorExempt", true) end

	local function update(value)
		if type(value) == "table" then
			if value.Text ~= nil then textLabel.Text = tostring(value.Text) end
			if value.Title ~= nil and titleLabel then titleLabel.Text = tostring(value.Title) end
			if value.RichText ~= nil then textLabel.RichText = value.RichText == true end
			if value.TextWrapped ~= nil then textLabel.TextWrapped = value.TextWrapped == true end
			if typeof(value.Color) == "Color3" then
				textLabel.TextColor3 = value.Color
				textLabel:SetAttribute("SilentThemeColorExempt", true)
			end
		else
			textLabel.Text = tostring(value or "")
		end
	end
	return {
		Instance = card,
		Set = function(_, value) update(value) end,
		Get = function() return textLabel.Text end,
		SetTitle = function(_, v) if titleLabel then titleLabel.Text = v end end,
		SetColor = function(_, color)
			if typeof(color) == "Color3" then
				textLabel.TextColor3 = color
				textLabel:SetAttribute("SilentThemeColorExempt", true)
			end
		end,
		Destroy = function() card:Destroy() end,
	}
end
 
function Private.BuildStarRow(parent, layoutOrder, maxStars, starColor, starSize, default)
	local starOutline = ResolveIcon("Phosphor:star")
	local starFilled = ResolveIcon("Material:star")
 
	local row = Instance.new("Frame")
	row.Name = "Stars"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, starSize)
	row.LayoutOrder = layoutOrder
	row.ZIndex = Z.Content + 1
	row.Parent = parent
 
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row
 
	local stars = {}
	local selected = math.clamp(default or 0, 0, maxStars)
 
	local function paint(previewCount)
		local count = previewCount or selected
		for i, button in ipairs(stars) do
			local on = i <= count
			button.Image = on and starFilled or starOutline
			Tween(button, { ImageColor3 = on and starColor or SilentUI.Theme.TextDim }, 0.12)
		end
	end
 
	for i = 1, maxStars do
		local button = Instance.new("ImageButton")
		button.Name = "Star" .. i
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		button.Image = starOutline
		button.ImageColor3 = SilentUI.Theme.TextDim
		button.Size = UDim2.fromOffset(starSize, starSize)
		button.LayoutOrder = i
		button.ZIndex = Z.Content + 2
		button.Parent = row
 
		button.MouseEnter:Connect(function() paint(i) end)
		button.MouseLeave:Connect(function() paint() end)
		button.MouseButton1Click:Connect(function()
			selected = i
			paint()
		end)
 
		stars[i] = button
	end
	paint()
 
	return {
		Row = row,
		Get = function() return selected end,
		Set = function(v)
			selected = math.clamp(v or 0, 0, maxStars)
			paint()
		end,
		Nudge = function()
			for _, button in ipairs(stars) do Tween(button, { Rotation = 8 }, 0.06) end
			task.delay(0.06, function()
				for _, button in ipairs(stars) do Tween(button, { Rotation = 0 }, 0.12) end
			end)
		end,
	}
end
 
function Private.NormalizeFeedbackText(text)
	local invisibleChars = {
		["\226\128\139"] = "", ["\226\128\142"] = "", ["\226\128\143"] = "",
		["\239\187\191"] = "", ["\194\173"] = "",
	}
	for char, replacement in pairs(invisibleChars) do
		text = text:gsub(char, replacement)
	end
	text = text:gsub("%s+", " ")
	text = text:gsub("^%s+", "")
	text = text:gsub("%s+$", "")
	return text
end
 
Private.FeedbackEvasionPatterns = {
	{pattern = "t%s*e%s*l%s*e%s*g%s*r%s*a%s*m", name = "telegram"},
	{pattern = "h%s*t%s*t%s*p", name = "http"},
	{pattern = "h%s*t%s*t%s*p%s*s", name = "https"},
	{pattern = "w%s*w%s*w", name = "www"},
	{pattern = "c%s*o%s*m", name = "com"},
	{pattern = "o%s*r%s*g", name = "org"},
	{pattern = "n%s*e%s*t", name = "net"},
	{pattern = ".%s*g%s*g", name = ".gg"},
	{pattern = ".%s*c%s*o%s*m", name = ".com"},
	{pattern = "/%s*i%s*n%s*v%s*i%s*t%s*e", name = "/invite"},
	{pattern = "d%s*o%s*t%s*%s*c%s*o%s*m", name = "dot com"},
	{pattern = "a%s*t%s*%s*%s*h%s*e%s*r%s*e", name = "@here"},
	{pattern = "a%s*t%s*%s*%s*e%s*v%s*e%s*r%s*y%s*o%s*n%s*e", name = "@everyone"},
}
 
function Private.DetectFeedbackEvasion(text)
	for _, evasion in ipairs(Private.FeedbackEvasionPatterns) do
		if text:match(evasion.pattern) then
			return true, evasion.name
		end
	end
	local dotCount, slashCount = 0, 0
	for i = 1, #text do
		local char = text:sub(i, i)
		if char == "." then dotCount = dotCount + 1 end
		if char == "/" then slashCount = slashCount + 1 end
	end
	if dotCount >= 3 or slashCount >= 3 then
		return true, "suspicious link/invite"
	end
	return false, nil
end
 
Private.FeedbackAsciiMap = {
	["á"] = "a", ["à"] = "a", ["ã"] = "a", ["â"] = "a", ["ä"] = "a",
	["Á"] = "A", ["À"] = "A", ["Ã"] = "A", ["Â"] = "A", ["Ä"] = "A",
	["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
	["É"] = "E", ["È"] = "E", ["Ê"] = "E", ["Ë"] = "E",
	["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i",
	["Í"] = "I", ["Ì"] = "I", ["Î"] = "I", ["Ï"] = "I",
	["ó"] = "o", ["ò"] = "o", ["õ"] = "o", ["ô"] = "o", ["ö"] = "o",
	["Ó"] = "O", ["Ò"] = "O", ["Õ"] = "O", ["Ô"] = "O", ["Ö"] = "O",
	["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
	["Ú"] = "U", ["Ù"] = "U", ["Û"] = "U", ["Ü"] = "U",
	["ç"] = "c", ["Ç"] = "C", ["ñ"] = "n", ["Ñ"] = "N",
	["°"] = " ", ["º"] = " ", ["ª"] = " ",
}
 
Private.FeedbackAllowedChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,!?;:()[]{}@#%&*+-=/_\"'"
 
function Private.SanitizeFeedbackText(text)
	if not text or text == "" then
		return "_No message_"
	end
 
	text = Private.NormalizeFeedbackText(text)
 
	local hasEvasion, evasionType = Private.DetectFeedbackEvasion(text)
	if hasEvasion then
		return "[Message blocked - " .. evasionType .. "]"
	end
 
	text = text:gsub("@everyone", "@\226\128\139everyone")
	text = text:gsub("@here", "@\226\128\139here")
	text = text:gsub("<@!?(%d+)>", "[user]")
	text = text:gsub("<@&(%d+)>", "[role]")
 
	text = text:gsub("https?%s*:%s*//%s*[%w%-%.]+%s*%.%s*[%w]+[%w%-%./?=&%%]*", "[link removed]")
	text = text:gsub("www%s*%.%s*[%w%-]+%s*%.%s*[%w]+", "[link removed]")
	text = text:gsub("t[eE][lL][eE][gG][rR][aA][mM]%.?%s*[mM][eE]%s*/%s*[%w%-_]+", "[invite removed]")
 
	for old, new in pairs(Private.FeedbackAsciiMap) do
		text = text:gsub(old, new)
	end
 
	local cleaned = ""
	for i = 1, #text do
		local char = text:sub(i, i)
		if Private.FeedbackAllowedChars:find(char, 1, true) then
			cleaned = cleaned .. char
		else
			cleaned = cleaned .. " "
		end
	end
	text = cleaned
 
	text = text:gsub("%s+", " ")
	text = text:gsub("^%s+", "")
	text = text:gsub("%s+$", "")
 
	local hasEvasionAfter = Private.DetectFeedbackEvasion(text)
	if hasEvasionAfter then
		return "[Message blocked - suspicious content]"
	end
 
	if #text > 500 then
		text = text:sub(1, 500) .. "..."
	end
 
	return text
end
 
function SilentUI:SanitizeText(text, opts)
	opts = opts or {}
	local maxLength = opts.MaxLength or 500
 
	if not text or text == "" then
		return "", false, nil
	end
 
	local normalized = Private.NormalizeFeedbackText(tostring(text))
	local hasEvasion, evasionType = Private.DetectFeedbackEvasion(normalized)
	if hasEvasion then
		return "", true, evasionType
	end
 
	local cleaned = Private.SanitizeFeedbackText(text)
	if cleaned == "_No message_" then
		return "", false, nil
	end
	if cleaned:find("^%[Message blocked") then
		return "", true, "blocked content"
	end
 
	if #cleaned > maxLength then
		cleaned = cleaned:sub(1, maxLength)
	end
 
	return cleaned, false, nil
end
 
function Private.BuildFeedbackRow(parent, layoutOrder, rowH, placeholder, buttonIcon)
	local row = Instance.new("Frame")
	row.Name = "Feedback"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, rowH)
	row.LayoutOrder = layoutOrder
	row.ZIndex = Z.Content + 1
	row.Parent = parent
 
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.BackgroundColor3 = SilentUI.Theme.Surface
	pill.BackgroundTransparency = 0.95
	pill.BorderSizePixel = 0
	pill.Size = UDim2.new(1, -(rowH + 6), 1, 0)
	pill.ZIndex = Z.Content + 1
	pill.Parent = row
	Corner(pill, 9)
	local pillStroke = Stroke(pill, SilentUI.Theme.Border, 1, 0.9)
 
	local pillPad = Instance.new("UIPadding")
	pillPad.PaddingLeft = UDim.new(0, 10)
	pillPad.PaddingRight = UDim.new(0, 10)
	pillPad.Parent = pill
 
	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.ClearTextOnFocus = false
	box.FontFace = SilentUI.Theme.FontRegular
	box.PlaceholderText = placeholder or "Give us some feedback!"
	box.PlaceholderColor3 = SilentUI.Theme.TextDim
	box.Text = ""
	box.TextColor3 = SilentUI.Theme.Text
	box.TextSize = 13
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Center
	box.TextTruncate = Enum.TextTruncate.AtEnd
	box.ClipsDescendants = true
	box.Size = UDim2.fromScale(1, 1)
	box.ZIndex = Z.Content + 2
	box.Parent = pill
 
	box.Focused:Connect(function()
		Tween(pillStroke, { Color = SilentUI.Theme.Accent, Transparency = 0.3 }, 0.15)
	end)
	box.FocusLost:Connect(function()
		Tween(pillStroke, { Color = SilentUI.Theme.Border, Transparency = 0.9 }, 0.15)
	end)
 
	local sendBtn = Instance.new("TextButton")
	sendBtn.Name = "Send"
	sendBtn.Text = ""
	sendBtn.AutoButtonColor = false
	sendBtn.BackgroundColor3 = SilentUI.Theme.Surface
	sendBtn.BackgroundTransparency = 0.9
	sendBtn.BorderSizePixel = 0
	sendBtn.AnchorPoint = Vector2.new(1, 0)
	sendBtn.Position = UDim2.new(1, 0, 0, 0)
	sendBtn.Size = UDim2.fromOffset(rowH, rowH)
	sendBtn.ZIndex = Z.Content + 1
	sendBtn.Parent = row
	Corner(sendBtn, 9)
 
	local sendIcon = Instance.new("ImageLabel")
	sendIcon.BackgroundTransparency = 1
	sendIcon.Image = ResolveIcon(buttonIcon or "send")
	sendIcon.ImageColor3 = SilentUI.Theme.Text
	sendIcon.Size = UDim2.fromOffset(12, 12)
	sendIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	sendIcon.Position = UDim2.fromScale(0.5, 0.5)
	sendIcon.ZIndex = Z.Content + 2
	sendIcon.Parent = sendBtn
 
	sendBtn.MouseEnter:Connect(function() Tween(sendBtn, { BackgroundTransparency = 0.8 }, 0.12) end)
	sendBtn.MouseLeave:Connect(function() Tween(sendBtn, { BackgroundTransparency = 0.9 }, 0.12) end)
 
	return { Row = row, Box = box, SendBtn = sendBtn }
end
 
function Tab:AddRating(opts)
	opts = opts or {}
	local maxStars = math.max(1, opts.MaxStars or 5)
	local starColor = opts.StarColor or Color3.fromRGB(255, 196, 64)
	local hasTitle = opts.Title and opts.Title ~= ""
 
	local card = BaseCard(self._page, 10)
	card.AutomaticSize = Enum.AutomaticSize.Y
 
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = card
 
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card
 
	if hasTitle then
		local titleLabel = Instance.new("TextLabel")
		titleLabel.BackgroundTransparency = 1
		titleLabel.FontFace = SilentUI.Theme.Font
		titleLabel.Text = opts.Title
		titleLabel.TextColor3 = SilentUI.Theme.Text
		titleLabel.TextSize = 14
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.Size = UDim2.new(1, 0, 0, 16)
		titleLabel.LayoutOrder = 1
		titleLabel.ZIndex = Z.Content + 1
		titleLabel.Parent = card
 
		self._window:_RegisterSearchable(self, opts.Title, card)
	end
 
	local starBar = Private.BuildStarRow(card, 2, maxStars, starColor, 20, opts.Default)
	local feedback = Private.BuildFeedbackRow(card, 3, 26, opts.Placeholder, opts.ButtonIcon)
 
	local clearOnSubmit = opts.ClearOnSubmit ~= false
	feedback.SendBtn.MouseButton1Click:Connect(function()
		local selected = starBar.Get()
		if selected <= 0 then
			starBar.Nudge()
			return
		end
		if opts.Callback then task.spawn(opts.Callback, selected, feedback.Box.Text) end
		if clearOnSubmit then
			feedback.Box.Text = ""
			starBar.Set(opts.Default or 0)
		end
	end)
 
	return {
		Instance = card,
		Get = function() return starBar.Get(), feedback.Box.Text end,
		Set = function(_, newStars, newText)
			starBar.Set(newStars)
			if newText ~= nil then feedback.Box.Text = newText end
		end,
		Destroy = function() card:Destroy() end,
	}
end
 
function Tab:AddButton(opts)
	opts = opts or {}
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local card = BaseCard(self._page, height)
 
	local textX = AddLeadingIcon(card, opts.Icon, height)
	AddTitleDesc(card, textX, 44, opts.Text or "Button", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Button", card)
 
	local chev = Instance.new("ImageLabel")
	chev.BackgroundTransparency = 1
	chev.Image = ResolveIcon("chevron-right")
	chev.ImageColor3 = SilentUI.Theme.TextDim
	chev.Size = UDim2.fromOffset(14, 14)
	chev.AnchorPoint = Vector2.new(1, 0.5)
	chev.Position = UDim2.new(1, -16, 0.5, 0)
	chev.ZIndex = Z.Content + 1
	chev.Parent = card
 
	local click = Instance.new("TextButton")
	click.Text = ""
	click.AutoButtonColor = false
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.ZIndex = Z.Content + 3
	click.Parent = card
 
	click.MouseEnter:Connect(function()
		Tween(card, { BackgroundTransparency = 0.9 }, 0.15)
		Tween(chev, { ImageColor3 = SilentUI.Theme.Text, Position = UDim2.new(1, -12, 0.5, 0) }, 0.15)
	end)
	click.MouseLeave:Connect(function()
		Tween(card, { BackgroundTransparency = 0.96 }, 0.15)
		Tween(chev, { ImageColor3 = SilentUI.Theme.TextDim, Position = UDim2.new(1, -16, 0.5, 0) }, 0.15)
	end)
	click.MouseButton1Click:Connect(function()
		Tween(card, { BackgroundTransparency = 0.8 }, 0.08)
		Tween(chev, { ImageColor3 = SilentUI.Theme.Accent }, 0.08)
		task.delay(0.08, function()
			if not card.Parent then return end
			Tween(card, { BackgroundTransparency = 0.9 }, 0.15)
			Tween(chev, { ImageColor3 = SilentUI.Theme.Text }, 0.15)
		end)
		if opts.Callback then task.spawn(opts.Callback) end
	end)
 
	local result = {
		Instance = card,
		Destroy = function() card:Destroy() end,
	}
	if opts.TextKey or opts.DescriptionKey then SilentUI:LocalizeControl(result, opts) end
	if opts.EnabledWhen then SilentUI:BindEnabledWhen(result, opts.EnabledWhen, opts.OnEnabledChanged) end
	return result
end
 
function Tab:AddCard(opts)
	opts = opts or {}
	local hasDesc = opts.Description and opts.Description ~= ""
	local hasImage = (opts.Image and opts.Image ~= "") or opts.UserId ~= nil
	local hasButton = opts.ButtonText ~= nil and opts.ButtonText ~= ""
	local BUTTON_H, BUTTON_GAP, BUTTON_MARGIN = 32, 6, 4
	local buttonReserve = hasButton and (BUTTON_GAP + BUTTON_H + BUTTON_MARGIN) or 0
 
	local hasRating = type(opts.Rating) == "table"
	local RATING_LABEL_H, RATING_STAR_H, RATING_INPUT_H = 14, 20, 26
	local RATING_ROW_GAP, RATING_TOP_GAP, RATING_BOTTOM_MARGIN = 6, 10, 8
	local ratingHasTitle = hasRating and opts.Rating.Title and opts.Rating.Title ~= ""
	local ratingBlockH = 0
	if hasRating then
		local bodyH = (ratingHasTitle and (RATING_LABEL_H + RATING_ROW_GAP) or 0)
			+ RATING_STAR_H + RATING_ROW_GAP + RATING_INPUT_H
		ratingBlockH = RATING_TOP_GAP + bodyH + RATING_BOTTOM_MARGIN
	end
 
	local extraBottom = buttonReserve + ratingBlockH
	local topHeight = hasDesc and 56 or 44
	local height = topHeight + extraBottom
	local imgSize, imgPad = 34, 10
 
	local card = BaseCard(self._page, height)
	local textX = 14
 
	if hasImage then
		local imgHolder = Instance.new("Frame")
		imgHolder.Name = "Image"
		imgHolder.AnchorPoint = Vector2.new(0, 0.5)
		imgHolder.Position = UDim2.fromOffset(10, topHeight / 2)
		imgHolder.Size = UDim2.fromOffset(imgSize, imgSize)
		imgHolder.BackgroundTransparency = 1
		imgHolder.BorderSizePixel = 0
		imgHolder.ClipsDescendants = true
		imgHolder.ZIndex = Z.Content + 1
		imgHolder.Parent = card
		Corner(imgHolder, SilentUI.Theme.CornerRadiusSm)
		Stroke(imgHolder, SilentUI.Theme.Border, 1, 0.85)
 
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.ScaleType = Enum.ScaleType.Crop
		img.Size = UDim2.fromScale(1, 1)
		img.ZIndex = Z.Content + 2
		img.Parent = imgHolder
		Corner(img, SilentUI.Theme.CornerRadiusSm)
 
		if opts.UserId then
			task.spawn(function()
				local ok, content = pcall(
					Players.GetUserThumbnailAsync,
					Players,
					opts.UserId,
					opts.ThumbnailType or Enum.ThumbnailType.HeadShot,
					opts.ThumbnailSize or Enum.ThumbnailSize.Size100x100
				)
				if ok and content and img.Parent then
					img.Image = content
				end
			end)
		else
			img.Image = ResolveIcon(opts.Image)
		end
 
		textX = 10 + imgSize + imgPad
	end
 
	local rightReserve = opts.Callback and 44 or 14
	AddTitleDesc(card, textX, rightReserve, opts.Title or "Card", opts.Description, topHeight, extraBottom)
	self._window:_RegisterSearchable(self, opts.Title or "Card", card)
 
	if opts.Callback then
		local chev = Instance.new("ImageLabel")
		chev.BackgroundTransparency = 1
		chev.Image = ResolveIcon("chevron-right")
		chev.ImageColor3 = SilentUI.Theme.TextDim
		chev.Size = UDim2.fromOffset(14, 14)
		chev.AnchorPoint = Vector2.new(1, 0.5)
		chev.Position = UDim2.new(1, -16, 0.5, 0)
		chev.ZIndex = Z.Content + 1
		chev.Parent = card
 
		local click = Instance.new("TextButton")
		click.Text = ""
		click.AutoButtonColor = false
		click.BackgroundTransparency = 1
		click.Size = UDim2.fromScale(1, 1)
		click.ZIndex = Z.Content + 3
		click.Parent = card
 
		click.MouseEnter:Connect(function()
			Tween(card, { BackgroundTransparency = 0.9 }, 0.15)
			Tween(chev, { ImageColor3 = SilentUI.Theme.Text, Position = UDim2.new(1, -12, 0.5, 0) }, 0.15)
		end)
		click.MouseLeave:Connect(function()
			Tween(card, { BackgroundTransparency = 0.96 }, 0.15)
			Tween(chev, { ImageColor3 = SilentUI.Theme.TextDim, Position = UDim2.new(1, -16, 0.5, 0) }, 0.15)
		end)
		click.MouseButton1Click:Connect(function()
			Tween(card, { BackgroundTransparency = 0.8 }, 0.08)
			task.delay(0.08, function()
				if card.Parent then Tween(card, { BackgroundTransparency = 0.9 }, 0.15) end
			end)
			task.spawn(opts.Callback)
		end)
	end
 
	if hasButton then
		local footerBtn = Instance.new("TextButton")
		footerBtn.Name = "FooterButton"
		footerBtn.Text = ""
		footerBtn.AutoButtonColor = false
		footerBtn.BackgroundColor3 = SilentUI.Theme.Surface
		footerBtn.BackgroundTransparency = 0.85
		footerBtn.BorderSizePixel = 0
		footerBtn.Position = UDim2.new(0, 10, 1, -(BUTTON_H + BUTTON_MARGIN))
		footerBtn.Size = UDim2.new(1, -20, 0, BUTTON_H)
		footerBtn.ZIndex = Z.Content + 1
		footerBtn.Parent = card
		Corner(footerBtn, 8)
		local footerStroke = Stroke(footerBtn, SilentUI.Theme.Border, 1, 0.85)
 
		local footerLabel = Instance.new("TextLabel")
		footerLabel.BackgroundTransparency = 1
		footerLabel.FontFace = SilentUI.Theme.Font
		footerLabel.Text = opts.ButtonText
		footerLabel.TextColor3 = SilentUI.Theme.Text
		footerLabel.TextSize = 13
		footerLabel.Size = UDim2.fromScale(1, 1)
		footerLabel.ZIndex = Z.Content + 2
		footerLabel.Parent = footerBtn
 
		footerBtn.MouseEnter:Connect(function()
			Tween(footerBtn, { BackgroundTransparency = 0.7 }, 0.12)
			Tween(footerStroke, { Transparency = 0.7 }, 0.12)
		end)
		footerBtn.MouseLeave:Connect(function()
			Tween(footerBtn, { BackgroundTransparency = 0.85 }, 0.12)
			Tween(footerStroke, { Transparency = 0.85 }, 0.12)
		end)
		footerBtn.MouseButton1Click:Connect(function()
			Tween(footerBtn, { BackgroundTransparency = 0.55 }, 0.08)
			task.delay(0.08, function()
				if footerBtn.Parent then Tween(footerBtn, { BackgroundTransparency = 0.7 }, 0.15) end
			end)
			if opts.ButtonCallback then task.spawn(opts.ButtonCallback) end
		end)
	end
 
	local ratingBar
	if hasRating then
		local ratingOpts = opts.Rating
 
		local ratingHolder = Instance.new("Frame")
		ratingHolder.Name = "Rating"
		ratingHolder.BackgroundTransparency = 1
		ratingHolder.Position = UDim2.new(0, 10, 1, -(ratingBlockH + buttonReserve))
		ratingHolder.Size = UDim2.new(1, -20, 0, ratingBlockH - RATING_BOTTOM_MARGIN)
		ratingHolder.ZIndex = Z.Content + 1
		ratingHolder.Parent = card
 
		local divider = Instance.new("Frame")
		divider.Name = "Divider"
		divider.BackgroundColor3 = SilentUI.Theme.Surface
		divider.BackgroundTransparency = 0.94
		divider.BorderSizePixel = 0
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.ZIndex = Z.Content + 1
		divider.Parent = ratingHolder
 
		local ratingBody = Instance.new("Frame")
		ratingBody.BackgroundTransparency = 1
		ratingBody.Position = UDim2.new(0, 0, 0, RATING_TOP_GAP)
		ratingBody.Size = UDim2.new(1, 0, 1, -RATING_TOP_GAP)
		ratingBody.ZIndex = Z.Content + 1
		ratingBody.Parent = ratingHolder
 
		local ratingLayout = Instance.new("UIListLayout")
		ratingLayout.Padding = UDim.new(0, RATING_ROW_GAP)
		ratingLayout.SortOrder = Enum.SortOrder.LayoutOrder
		ratingLayout.Parent = ratingBody
 
		if ratingHasTitle then
			local ratingLabel = Instance.new("TextLabel")
			ratingLabel.BackgroundTransparency = 1
			ratingLabel.FontFace = SilentUI.Theme.Font
			ratingLabel.Text = ratingOpts.Title
			ratingLabel.TextColor3 = SilentUI.Theme.Text
			ratingLabel.TextSize = 13
			ratingLabel.TextXAlignment = Enum.TextXAlignment.Left
			ratingLabel.Size = UDim2.new(1, 0, 0, RATING_LABEL_H)
			ratingLabel.LayoutOrder = 1
			ratingLabel.ZIndex = Z.Content + 1
			ratingLabel.Parent = ratingBody
			if ratingOpts.TitleKey then SilentUI:Localize(ratingLabel, ratingOpts.TitleKey) end
		end
 
		local starBar = Private.BuildStarRow(ratingBody, 2, math.max(1, ratingOpts.MaxStars or 5),
			ratingOpts.StarColor or Color3.fromRGB(255, 196, 64), RATING_STAR_H, ratingOpts.Default)
		local feedback = Private.BuildFeedbackRow(ratingBody, 3, RATING_INPUT_H, ratingOpts.Placeholder, ratingOpts.ButtonIcon)
 
		local clearOnSubmit = ratingOpts.ClearOnSubmit ~= false
		feedback.SendBtn.MouseButton1Click:Connect(function()
			local sel = starBar.Get()
			if sel <= 0 then
				starBar.Nudge()
				return
			end
			if ratingOpts.Callback then task.spawn(ratingOpts.Callback, sel, feedback.Box.Text) end
			if clearOnSubmit then
				feedback.Box.Text = ""
				starBar.Set(ratingOpts.Default or 0)
			end
		end)
 
		ratingBar = {
			Get = function() return starBar.Get(), feedback.Box.Text end,
			Set = function(newStars, newText)
				starBar.Set(newStars)
				if newText ~= nil then feedback.Box.Text = newText end
			end,
		}
	end
 
	local result = {
		Instance = card,
		Rating = ratingBar,
		Destroy = function() card:Destroy() end,
	}
	if opts.TitleKey or opts.DescriptionKey then
		SilentUI:LocalizeControl(result, { TextKey = opts.TitleKey, DescriptionKey = opts.DescriptionKey })
	end
	if opts.EnabledWhen then SilentUI:BindEnabledWhen(result, opts.EnabledWhen, opts.OnEnabledChanged) end
	return result
end
 
Private.CHANGELOG_TYPES = {
	Added   = { Color = Color3.fromRGB(120, 210, 140), Icon = "plus" },
	Fixed   = { Color = Color3.fromRGB(120, 170, 255), Icon = "wrench" },
	Changed = { Color = Color3.fromRGB(255, 190, 90),  Icon = "refresh-cw" },
	Removed = { Color = Color3.fromRGB(230, 120, 120), Icon = "minus" },
}
 
function Tab:AddChangelogEntry(opts)
	opts = opts or {}
	local version = opts.Version or "Update"
	local date = opts.Date
	local changes = opts.Changes or {}
 
	local PAD = 12
	local HEADER_H = 18
	local ROW_H = 22
	local ROW_GAP = 2
	local height = PAD * 2 + HEADER_H + (#changes > 0 and 8 or 0)
 
	local card = BaseCard(self._page, height)
	card.AutomaticSize = Enum.AutomaticSize.Y
	self._window:_RegisterSearchable(self, version, card)
 
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, PAD)
	pad.PaddingBottom = UDim.new(0, PAD)
	pad.PaddingLeft = UDim.new(0, PAD)
	pad.PaddingRight = UDim.new(0, PAD)
	pad.Parent = card
 
	local versionLabel = Instance.new("TextLabel")
	versionLabel.BackgroundTransparency = 1
	versionLabel.FontFace = SilentUI.Theme.Font
	versionLabel.Text = version
	versionLabel.TextColor3 = SilentUI.Theme.Text
	versionLabel.TextSize = 14
	versionLabel.TextXAlignment = Enum.TextXAlignment.Left
	versionLabel.TextTruncate = Enum.TextTruncate.AtEnd
	versionLabel.Size = UDim2.new(1, date and -90 or 0, 0, HEADER_H)
	versionLabel.ZIndex = Z.Content + 1
	versionLabel.Parent = card
 
	if date then
		local dateLabel = Instance.new("TextLabel")
		dateLabel.BackgroundTransparency = 1
		dateLabel.FontFace = SilentUI.Theme.FontRegular
		dateLabel.Text = date
		dateLabel.TextColor3 = SilentUI.Theme.TextDim
		dateLabel.TextSize = 12
		dateLabel.TextXAlignment = Enum.TextXAlignment.Right
		dateLabel.AnchorPoint = Vector2.new(1, 0)
		dateLabel.Position = UDim2.new(1, 0, 0, 2)
		dateLabel.Size = UDim2.fromOffset(90, HEADER_H)
		dateLabel.ZIndex = Z.Content + 1
		dateLabel.Parent = card
	end
 
	local rowsHolder = Instance.new("Frame")
	rowsHolder.Name = "Rows"
	rowsHolder.BackgroundTransparency = 1
	rowsHolder.Position = UDim2.fromOffset(0, HEADER_H + 8)
	rowsHolder.Size = UDim2.new(1, 0, 0, 0)
	rowsHolder.AutomaticSize = Enum.AutomaticSize.Y
	rowsHolder.ZIndex = Z.Content + 1
	rowsHolder.Parent = card
 
	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.FillDirection = Enum.FillDirection.Vertical
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Padding = UDim.new(0, ROW_GAP)
	rowsLayout.Parent = rowsHolder
 
	for i, change in ipairs(changes) do
		local kind = Private.CHANGELOG_TYPES[change.Type] and change.Type or "Changed"
		local meta = Private.CHANGELOG_TYPES[kind]
 
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = i * 2 - 1
		row.ZIndex = Z.Content + 1
		row.Parent = rowsHolder
 
		local pill = Instance.new("Frame")
		pill.BackgroundColor3 = meta.Color
		pill.BackgroundTransparency = 0.85
		pill.BorderSizePixel = 0
		pill.AnchorPoint = Vector2.zero
		pill.Position = UDim2.fromOffset(0, 1)
		pill.Size = UDim2.fromOffset(66, 18)
		pill.ZIndex = Z.Content + 2
		pill.Parent = row
		Corner(pill, 5)
 
		local pillLayout = Instance.new("UIListLayout")
		pillLayout.FillDirection = Enum.FillDirection.Horizontal
		pillLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		pillLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		pillLayout.Padding = UDim.new(0, 3)
		pillLayout.Parent = pill
 
		local pillIcon = Instance.new("ImageLabel")
		pillIcon.BackgroundTransparency = 1
		pillIcon.Image = ResolveIcon(meta.Icon)
		pillIcon.ImageColor3 = meta.Color
		pillIcon.Size = UDim2.fromOffset(9, 9)
		pillIcon.LayoutOrder = 1
		pillIcon.ZIndex = Z.Content + 3
		pillIcon.Parent = pill
 
		local pillLabel = Instance.new("TextLabel")
		pillLabel.BackgroundTransparency = 1
		pillLabel.FontFace = SilentUI.Theme.Font
		pillLabel.Text = string.upper(kind)
		pillLabel.TextColor3 = meta.Color
		pillLabel.TextSize = 9
		pillLabel.AutomaticSize = Enum.AutomaticSize.X
		pillLabel.Size = UDim2.fromOffset(0, 12)
		pillLabel.LayoutOrder = 2
		pillLabel.ZIndex = Z.Content + 3
		pillLabel.Parent = pill
 
		local changeLabel = Instance.new("TextLabel")
		changeLabel.BackgroundTransparency = 1
		changeLabel.FontFace = SilentUI.Theme.FontRegular
		changeLabel.Text = tostring(change.Text or "")
		changeLabel.TextColor3 = SilentUI.Theme.TextDim
		changeLabel.TextSize = 12
		changeLabel.TextXAlignment = Enum.TextXAlignment.Left
		changeLabel.TextYAlignment = Enum.TextYAlignment.Top
		changeLabel.TextWrapped = true
		changeLabel.TextTruncate = Enum.TextTruncate.None
		changeLabel.AutomaticSize = Enum.AutomaticSize.Y
		changeLabel.Position = UDim2.fromOffset(76, 0)
		changeLabel.Size = UDim2.new(1, -76, 0, ROW_H)
		changeLabel.ZIndex = Z.Content + 2
		changeLabel.Parent = row
 
		local function alignChangelogRow()
			local isMultiline = changeLabel.TextBounds.Y > 18
			if isMultiline then
				pill.AnchorPoint = Vector2.zero
				pill.Position = UDim2.fromOffset(0, 1)
				changeLabel.TextYAlignment = Enum.TextYAlignment.Top
			else
				pill.AnchorPoint = Vector2.new(0, 0.5)
				pill.Position = UDim2.new(0, 0, 0.5, 0)
				changeLabel.TextYAlignment = Enum.TextYAlignment.Center
			end
		end
		changeLabel:GetPropertyChangedSignal("TextBounds"):Connect(alignChangelogRow)
		task.defer(alignChangelogRow)
 
		if i < #changes then
			local separator = Instance.new("Frame")
			separator.Name = "Separator" .. i
			separator.BackgroundColor3 = SilentUI.Theme.Surface
			separator.BackgroundTransparency = 0.93
			separator.BorderSizePixel = 0
			separator.Size = UDim2.new(1, 0, 0, 1)
			separator.LayoutOrder = i * 2
			separator.ZIndex = Z.Content + 1
			separator.Parent = rowsHolder
		end
	end
 
	return { Instance = card, Destroy = function() card:Destroy() end }
end
 
function Tab:AddLoadoutGroup(opts)
	opts = opts or {}
	local title = opts.Title or "Loadout"
	local color = opts.Color or SilentUI.Theme.Accent
	local icons = opts.Icons or {}
	local buttonText = opts.ButtonText or "Equip"
 
	local PAD = 12
	local HEADER_H = 16
	local ICON_SIZE = 44
	local ROW_GAP = 8
	local BUTTON_H = 30
	local GAP1, GAP2 = 8, 10
	local height = PAD * 2 + HEADER_H + GAP1 + ICON_SIZE + GAP2 + BUTTON_H
 
	local card = BaseCard(self._page, height)
	self._window:_RegisterSearchable(self, title, card)
 
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, PAD)
	pad.PaddingBottom = UDim.new(0, PAD)
	pad.PaddingLeft = UDim.new(0, PAD)
	pad.PaddingRight = UDim.new(0, PAD)
	pad.Parent = card
 
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(0, 0)
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.ZIndex = Z.Content + 1
	header.Parent = card
 
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.new(0, 1, 0.5, 0)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	dot.ZIndex = Z.Content + 2
	dot.Parent = header
	Corner(dot, 3)
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = SilentUI.Theme.Font
	titleLabel.Text = string.upper(title)
	titleLabel.TextColor3 = SilentUI.Theme.TextDim
	titleLabel.TextSize = 12
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Position = UDim2.fromOffset(15, 0)
	titleLabel.Size = UDim2.new(1, -15, 1, 0)
	titleLabel.ZIndex = Z.Content + 2
	titleLabel.Parent = header
 
	local iconsRow = Instance.new("Frame")
	iconsRow.Name = "Icons"
	iconsRow.BackgroundTransparency = 1
	iconsRow.Position = UDim2.fromOffset(0, HEADER_H + GAP1)
	iconsRow.Size = UDim2.new(1, 0, 0, ICON_SIZE)
	iconsRow.ZIndex = Z.Content + 1
	iconsRow.Parent = card
 
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, ROW_GAP)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = iconsRow
 
	for i, iconAsset in ipairs(icons) do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. i
		slot.BackgroundColor3 = SilentUI.Theme.Surface
		slot.BackgroundTransparency = 0.95
		slot.BorderSizePixel = 0
		slot.ClipsDescendants = true
		slot.Size = UDim2.new(1 / 3, -ROW_GAP * 2 / 3, 1, 0)
		slot.LayoutOrder = i
		slot.ZIndex = Z.Content + 2
		slot.Parent = iconsRow
		Corner(slot, SilentUI.Theme.CornerRadiusSm)
		Stroke(slot, SilentUI.Theme.Border, 1, 0.94)
 
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = ResolveIcon(iconAsset)
		img.ImageColor3 = color
		img.ScaleType = Enum.ScaleType.Fit
		img.Position = UDim2.fromOffset(8, 8)
		img.Size = UDim2.new(1, -16, 1, -16)
		img.ZIndex = Z.Content + 3
		img.Parent = slot
	end
 
	local btn = Instance.new("TextButton")
	btn.Name = "EquipButton"
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = SilentUI.Theme.Surface
	btn.BackgroundTransparency = 0.92
	btn.BorderSizePixel = 0
	btn.Position = UDim2.fromOffset(0, HEADER_H + GAP1 + ICON_SIZE + GAP2)
	btn.Size = UDim2.new(1, 0, 0, BUTTON_H)
	btn.ZIndex = Z.Content + 1
	btn.Parent = card
	Corner(btn, 8)
 
	local btnLabel = Instance.new("TextLabel")
	btnLabel.BackgroundTransparency = 1
	btnLabel.FontFace = SilentUI.Theme.Font
	btnLabel.Text = buttonText
	btnLabel.TextColor3 = SilentUI.Theme.Text
	btnLabel.TextSize = 12
	btnLabel.Size = UDim2.fromScale(1, 1)
	btnLabel.ZIndex = Z.Content + 2
	btnLabel.Parent = btn
 
	btn.MouseEnter:Connect(function()
		Tween(btn, { BackgroundTransparency = 0.85 }, 0.12)
	end)
	btn.MouseLeave:Connect(function()
		Tween(btn, { BackgroundTransparency = 0.92 }, 0.12)
	end)
	btn.MouseButton1Click:Connect(function()
		Tween(btn, { BackgroundTransparency = 0.7 }, 0.08)
		task.delay(0.08, function()
			if btn.Parent then Tween(btn, { BackgroundTransparency = 0.85 }, 0.15) end
		end)
		if opts.Callback then task.spawn(opts.Callback) end
	end)
 
	return { Instance = card, Destroy = function() card:Destroy() end }
end
 
function Tab:AddInfoGrid(opts)
    opts = opts or {}
    local title = opts.Title or "Info"
    local description = opts.Description
    local hasDesc = description ~= nil and description ~= ""
    local items = opts.Items or {}
    local color = opts.Color
    local preferredColumns = math.clamp(math.floor(tonumber(opts.Columns) or 2), 1, 4)

    local PAD = 12
    local CHIP_H = 42
    local GRID_GAP = 8
    local MIN_CELL_WIDTH = math.clamp(tonumber(opts.MinCellWidth) or 132, 96, 220)
    local HEADER_H = hasDesc and 38 or 18
    local card = BaseCard(self._page, PAD * 2 + HEADER_H)
    self._window:_RegisterSearchable(self, title, card)
    card.AutomaticSize = Enum.AutomaticSize.None

    local leftInset = 0
    if color then
        local accent = Instance.new("Frame")
        accent.Name = "Accent"
        accent.BackgroundColor3 = color
        accent.BorderSizePixel = 0
        accent.Size = UDim2.new(0, 3, 1, -12)
        accent.Position = UDim2.fromOffset(0, 6)
        accent.ZIndex = Z.Content + 1
        accent.Parent = card
        Corner(accent, 1.5)
        leftInset = 6
    end

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, PAD)
    pad.PaddingBottom = UDim.new(0, PAD)
    pad.PaddingLeft = UDim.new(0, PAD + leftInset)
    pad.PaddingRight = UDim.new(0, PAD)
    pad.Parent = card

    local titleLabel = Instance.new("TextLabel")
    titleLabel.BackgroundTransparency = 1
    titleLabel.FontFace = SilentUI.Theme.Font
    titleLabel.Text = title
    titleLabel.TextColor3 = SilentUI.Theme.Text
    titleLabel.TextSize = 14
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextYAlignment = Enum.TextYAlignment.Center
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Position = UDim2.fromOffset(0, 0)
    titleLabel.Size = UDim2.new(1, 0, 0, 17)
    titleLabel.ZIndex = Z.Content + 1
    titleLabel.Parent = card

    local descLabel
    if hasDesc then
        descLabel = Instance.new("TextLabel")
        descLabel.BackgroundTransparency = 1
        descLabel.FontFace = SilentUI.Theme.FontRegular
        descLabel.Text = description
        descLabel.TextColor3 = SilentUI.Theme.TextDim
        descLabel.TextSize = 12
        descLabel.TextWrapped = true
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextYAlignment = Enum.TextYAlignment.Top
        descLabel.Position = UDim2.fromOffset(0, 20)
        descLabel.Size = UDim2.new(1, 0, 0, 16)
        descLabel.ZIndex = Z.Content + 1
        descLabel.Parent = card
    end

    local chipValues = {}
    local grid, gridLayout
    if #items > 0 then
        grid = Instance.new("Frame")
        grid.Name = "Grid"
        grid.BackgroundTransparency = 1
        grid.Position = UDim2.fromOffset(0, HEADER_H + 10)
        grid.Size = UDim2.new(1, 0, 0, 0)
        grid.ZIndex = Z.Content + 1
        grid.Parent = card

        gridLayout = Instance.new("UIGridLayout")
        gridLayout.CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP)
        gridLayout.FillDirectionMaxCells = preferredColumns
        gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
        gridLayout.Parent = grid

        for i, item in ipairs(items) do
            local chip = Instance.new("Frame")
            chip.Name = "Chip" .. i
            chip.BackgroundColor3 = SilentUI.Theme.Surface
            chip.BackgroundTransparency = 0.95
            chip.BorderSizePixel = 0
            chip.LayoutOrder = i
            chip.ZIndex = Z.Content + 2
            chip.Parent = grid
            Corner(chip, 6)

            local chipPad = Instance.new("UIPadding")
            chipPad.PaddingTop = UDim.new(0, 6)
            chipPad.PaddingLeft = UDim.new(0, 8)
            chipPad.PaddingRight = UDim.new(0, 8)
            chipPad.Parent = chip

            local labelLabel = Instance.new("TextLabel")
            labelLabel.BackgroundTransparency = 1
            labelLabel.FontFace = SilentUI.Theme.Font
            labelLabel.Text = tostring(item.Label or "")
            labelLabel.TextColor3 = SilentUI.Theme.Text
            labelLabel.TextSize = 12
            labelLabel.TextXAlignment = Enum.TextXAlignment.Left
            labelLabel.TextTruncate = Enum.TextTruncate.AtEnd
            labelLabel.Size = UDim2.new(1, 0, 0, 15)
            labelLabel.ZIndex = Z.Content + 3
            labelLabel.Parent = chip

            local valueLabel = Instance.new("TextLabel")
            valueLabel.Name = "Value"
            valueLabel.BackgroundTransparency = 1
            valueLabel.FontFace = SilentUI.Theme.FontRegular
            valueLabel.Text = tostring(item.Value or "")
            valueLabel.TextColor3 = SilentUI.Theme.TextDim
            valueLabel.TextSize = 11
            valueLabel.TextXAlignment = Enum.TextXAlignment.Left
            valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
            valueLabel.Position = UDim2.fromOffset(0, 15)
            valueLabel.Size = UDim2.new(1, 0, 0, 14)
            valueLabel.ZIndex = Z.Content + 3
            valueLabel.Parent = chip
            if item.Label then chipValues[item.Label] = valueLabel end
        end
    end

    local currentColumns = preferredColumns
    local function responsiveRelayout()
        if not card.Parent then return end
        local width = card.AbsoluteSize.X / GetUIScale() - PAD * 2 - leftInset
        if width <= 0 then return end

        local headerHeight = 18
        if descLabel then
            local _, measured = MeasureText(descLabel.Text, 12, math.max(80, width))
            headerHeight = 20 + math.max(16, measured) + 3
            descLabel.Size = UDim2.new(1, 0, 0, math.max(16, measured))
        end
        HEADER_H = headerHeight

        if grid and gridLayout then
            currentColumns = math.clamp(
                math.floor((width + GRID_GAP) / (MIN_CELL_WIDTH + GRID_GAP)),
                1,
                math.min(preferredColumns, #items)
            )
            local cellWidth = math.max(1, (width - GRID_GAP * (currentColumns - 1)) / currentColumns)
            local rows = math.ceil(#items / currentColumns)
            local gridHeight = rows > 0 and (rows * CHIP_H + (rows - 1) * GRID_GAP) or 0
            gridLayout.FillDirectionMaxCells = currentColumns
            gridLayout.CellSize = UDim2.fromOffset(cellWidth, CHIP_H)
            grid.Position = UDim2.fromOffset(0, HEADER_H + 8)
            grid.Size = UDim2.new(1, 0, 0, gridHeight)
            card.Size = UDim2.new(1, 0, 0, PAD * 2 + HEADER_H + 8 + gridHeight)
        else
            card.Size = UDim2.new(1, 0, 0, PAD * 2 + HEADER_H)
        end
    end

    if grid then grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(responsiveRelayout) end
    card:GetPropertyChangedSignal("AbsoluteSize"):Connect(responsiveRelayout)
    task.defer(responsiveRelayout)

    return {
        Instance = card,
        SetValue = function(_, label, value)
            local lbl = chipValues[label]
            if lbl then lbl.Text = tostring(value) end
        end,
        GetColumns = function() return currentColumns end,
        Destroy = function() card:Destroy() end,
    }
end

function Tab:AddSystemInfoGrid(opts)
	opts = opts or {}
	local Stats = game:GetService("Stats")
	local LocalPlayer = Players.LocalPlayer
 
	local grid = self:AddInfoGrid({
		Title       = opts.Title or "System Info",
		Description = opts.Description,
		Color       = opts.Color,
		Columns     = opts.Columns or 2,
		Items = {
			{ Label = "FPS",           Value = "--" },
			{ Label = "Ping",          Value = "-- ms" },
			{ Label = "Executor",      Value = Private.GetExecutorName() },
			{ Label = "Server Region", Value = "Unknown" },
			{ Label = "Time of Day",   Value = "--:--" },
		},
	})
 
	local frames = 0
	local lastFpsUpdate = os.clock()
	self._janitor:Add(RunService.Heartbeat:Connect(function()
		frames = frames + 1
		local now = os.clock()
		local elapsed = now - lastFpsUpdate
		if elapsed >= 1 then
			grid:SetValue("FPS", math.floor(frames / elapsed + 0.5))
			frames = 0
			lastFpsUpdate = now
		end
	end))
 
	local alive = true
	self._janitor:Add(function() alive = false end)
 
	task.spawn(function()
		while alive and grid.Instance.Parent do
			pcall(function()
				local ping = 0
				pcall(function()
					ping = math.clamp(Stats.Network.ServerStatsItem["Data Ping"]:GetValue(), 0, 9999)
				end)
				grid:SetValue("Ping", math.floor(ping) .. " ms")
 
				local h = tonumber(os.date("%H"))
				local m = tonumber(os.date("%M"))
				grid:SetValue("Time of Day", Private.FormatClock(h * 60 + m))
			end)
			task.wait(1)
		end
	end)
 
	task.spawn(function()
		local ok, region = pcall(function()
			return game:GetService("LocalizationService"):GetCountryRegionForPlayerAsync(LocalPlayer)
		end)
		if ok and region and alive then grid:SetValue("Server Region", region) end
	end)
 
	return grid
end
 
function Tab:AddGradientCard(opts)
	opts = opts or {}
	local title = opts.Title or "Card"
	local hasDesc = opts.Description and opts.Description ~= ""
	local colorA = opts.ColorA or Color3.fromRGB(88, 101, 242)
	local colorB = opts.ColorB or Color3.fromRGB(52, 58, 138)
	local height = hasDesc and 56 or 44
 
	local card = Instance.new("Frame")
	card.Name = title .. "GradientCard"
	card.BackgroundColor3 = colorA
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, height)
	card.ZIndex = Z.Content
	card.Parent = self._page
	Corner(card, SilentUI.Theme.CornerRadiusSm)
 
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(colorA, colorB)
	gradient.Rotation = 100
	gradient.Parent = card
 
	self._window:_RegisterSearchable(self, title, card)
 
	local PAD = 14
	local rightReserve = opts.Callback and 32 or PAD
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = SilentUI.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = SilentUI.Theme.Text
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Position = UDim2.fromOffset(PAD, hasDesc and 9 or 0)
	titleLabel.Size = UDim2.new(1, -(PAD + rightReserve), 0, 18)
	titleLabel.ZIndex = Z.Content + 1
	titleLabel.Parent = card
 
	if hasDesc then
		local descLabel = Instance.new("TextLabel")
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = SilentUI.Theme.FontRegular
		descLabel.Text = opts.Description
		descLabel.TextColor3 = SilentUI.Theme.Text
		descLabel.TextTransparency = 0.3
		descLabel.TextSize = 12
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextTruncate = Enum.TextTruncate.AtEnd
		descLabel.Position = UDim2.fromOffset(PAD, 29)
		descLabel.Size = UDim2.new(1, -(PAD + rightReserve), 0, 14)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = card
	end
 
	if opts.Callback then
		local chev = Instance.new("ImageLabel")
		chev.BackgroundTransparency = 1
		chev.Image = ResolveIcon("chevron-right")
		chev.ImageColor3 = SilentUI.Theme.Text
		chev.ImageTransparency = 0.2
		chev.Size = UDim2.fromOffset(14, 14)
		chev.AnchorPoint = Vector2.new(1, 0.5)
		chev.Position = UDim2.new(1, -14, 0.5, 0)
		chev.ZIndex = Z.Content + 1
		chev.Parent = card
 
		local veil = Instance.new("Frame")
		veil.Name = "HoverVeil"
		veil.BackgroundColor3 = SilentUI.Theme.Surface
		veil.BackgroundTransparency = 1
		veil.BorderSizePixel = 0
		veil.Size = UDim2.fromScale(1, 1)
		veil.ZIndex = Z.Content + 2
		veil.Parent = card
		Corner(veil, SilentUI.Theme.CornerRadiusSm)
 
		local click = Instance.new("TextButton")
		click.Text = ""
		click.AutoButtonColor = false
		click.BackgroundTransparency = 1
		click.Size = UDim2.fromScale(1, 1)
		click.ZIndex = Z.Content + 3
		click.Parent = card
 
		click.MouseEnter:Connect(function()
			Tween(veil, { BackgroundTransparency = 0.9 }, 0.15)
			Tween(chev, { Position = UDim2.new(1, -10, 0.5, 0) }, 0.15)
		end)
		click.MouseLeave:Connect(function()
			Tween(veil, { BackgroundTransparency = 1 }, 0.15)
			Tween(chev, { Position = UDim2.new(1, -14, 0.5, 0) }, 0.15)
		end)
		click.MouseButton1Click:Connect(function()
			Tween(veil, { BackgroundTransparency = 0.8 }, 0.08)
			task.delay(0.08, function()
				if veil.Parent then Tween(veil, { BackgroundTransparency = 0.9 }, 0.15) end
			end)
			task.spawn(opts.Callback)
		end)
	end
 
	return { Instance = card, Destroy = function() card:Destroy() end }
end
 
function Tab:AddToggle(opts)
	opts = opts or {}
	local state = opts.Default == true
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local card = BaseCard(self._page, height)
 
	local textX = AddLeadingIcon(card, opts.Icon, height)
	AddTitleDesc(card, textX, 66, opts.Text or "Toggle", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Toggle", card)
 
	local switchBg = Instance.new("Frame")
	switchBg.AnchorPoint = Vector2.new(1, 0.5)
	switchBg.Position = UDim2.new(1, -14, 0.5, 0)
	switchBg.Size = UDim2.fromOffset(40, 22)
	switchBg.BackgroundColor3 = state and SilentUI.Theme.Accent or SilentUI.Theme.Surface
	switchBg.BackgroundTransparency = state and 0 or 0.32
	switchBg.BorderSizePixel = 0
	switchBg.ZIndex = Z.Content + 1
	switchBg.Parent = card
	Corner(switchBg, 11)
 
	-- The disabled state stays translucent so the window background remains visible
	-- through the control instead of turning into a flat gray pill.
	local switchStroke = Stroke(
		switchBg,
		state and SilentUI.Theme.Accent or SilentUI.Theme.Border,
		1,
		state and 0.88 or 0.72
	)
 
	local switchGradient = Instance.new("UIGradient")
	switchGradient.Rotation = 90
	switchGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, SilentUI.Theme.Accent),
		ColorSequenceKeypoint.new(1, SilentUI.Theme.TextDim),
	})
	switchGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, state and 0 or 0.76),
		NumberSequenceKeypoint.new(1, state and 0 or 0.94),
	})
	switchGradient.Parent = switchBg
 
	local switchScale = Instance.new("UIScale")
	switchScale.Scale = 1
	switchScale.Parent = switchBg
 
	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(16, 16)
	knob.Position = state and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.BackgroundColor3 = state and SilentUI.Theme.Background or SilentUI.Theme.Text
	knob.BackgroundTransparency = state and 0 or 0.06
	knob.BorderSizePixel = 0
	knob.ZIndex = Z.Content + 2
	knob.Parent = switchBg
	Corner(knob, 8)
 
	local click = Instance.new("TextButton")
	click.Text = ""
	click.AutoButtonColor = false
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.ZIndex = Z.Content + 3
	click.Parent = card
 
	local function render()
		local anim = 0.28
		local style, dir = Enum.EasingStyle.Quint, Enum.EasingDirection.InOut
		Tween(switchBg, {
			BackgroundColor3 = state and SilentUI.Theme.Accent or SilentUI.Theme.Surface,
			BackgroundTransparency = state and 0 or 0.32,
		}, anim, style, dir)
		Tween(switchStroke, {
			Color = state and SilentUI.Theme.Accent or SilentUI.Theme.Border,
			Transparency = state and 0.88 or 0.72,
		}, anim, style, dir)
		switchGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, state and 0 or 0.76),
			NumberSequenceKeypoint.new(1, state and 0 or 0.94),
		})
		Tween(knob, {
			BackgroundColor3 = state and SilentUI.Theme.Background or SilentUI.Theme.Text,
			BackgroundTransparency = state and 0 or 0.06,
			Position = state and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
		}, anim, style, dir)
	end
 
	local signal = MakeSignal()
	local function fireChanged(newState)
		local info = ChangeInfo()
		if opts.Callback then task.spawn(opts.Callback, newState, info) end
		signal.Fire(newState, info)
	end
 
	local locked = opts.Locked == true
	click.MouseButton1Click:Connect(function()
		if locked then return end
		Tween(switchScale, { Scale = 0.91 }, 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(0.08, function()
			if switchScale.Parent then
				Tween(switchScale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			end
		end)
		state = not state
		render()
		fireChanged(state)
	end)
 
	card.MouseEnter:Connect(function()
		if not locked then
			Tween(card, { BackgroundTransparency = 0.93 }, 0.15)
			if not state then
				Tween(switchStroke, { Transparency = 0.55 }, 0.15)
				Tween(switchBg, { BackgroundTransparency = 0.24 }, 0.15)
			end
		end
	end)
	card.MouseLeave:Connect(function()
		Tween(card, { BackgroundTransparency = 0.96 }, 0.15)
		if not state then
			Tween(switchStroke, { Transparency = 0.72 }, 0.15)
			Tween(switchBg, { BackgroundTransparency = 0.32 }, 0.15)
		end
	end)
 
	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, value, silent)
			state = value == true
			render()
			if not silent then fireChanged(state) end
		end,
		Get = function() return state end,
		SetLocked = function(_, v)
			locked = v == true
			card.BackgroundTransparency = locked and 0.98 or 0.96
		end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() signal.Clear(); card:Destroy() end,
	}, "Toggle")
end
 
local ActiveSliderOwner = nil
 
function Tab:AddSlider(opts)
	opts = opts or {}
	local min = tonumber(opts.Min) or 0
	local max = tonumber(opts.Max) or 100
	if max < min then min, max = max, min end
	local increment = tonumber(opts.Increment) or 1
	local value = math.clamp(tonumber(opts.Default) or min, min, max)
 
	local hasDesc = opts.Description and opts.Description ~= ""
	local jan = self._janitor
 
	local card = BaseCard(self._page, hasDesc and 76 or 56)
	local textX = AddLeadingIcon(card, opts.Icon, 24)
	local leadingIcon = card:FindFirstChild("LeadingIcon")
	if leadingIcon then
		leadingIcon.AnchorPoint = Vector2.new(0, 0)
		leadingIcon.Position = UDim2.fromOffset(14, 9)
	end
 
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = SilentUI.Theme.Font
	label.Text = opts.Text or "Slider"
	label.TextColor3 = SilentUI.Theme.Text
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Position = UDim2.fromOffset(textX, 8)
	label.Size = UDim2.new(1, -(textX + 76), 0, 18)
	label.ZIndex = Z.Content + 1
	label.Parent = card
	self._window:_RegisterSearchable(self, opts.Text or "Slider", card)
 
	local descLabel
	if hasDesc then
		descLabel = Instance.new("TextLabel")
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = SilentUI.Theme.FontRegular
		descLabel.Text = opts.Description
		descLabel.TextColor3 = SilentUI.Theme.TextDim
		descLabel.TextSize = 12
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.AutomaticSize = Enum.AutomaticSize.Y
		descLabel.Position = UDim2.fromOffset(textX, 26)
		descLabel.Size = UDim2.new(1, -(textX + 14), 0, 14)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = card
	end
 
	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.FontFace = SilentUI.Theme.FontRegular
	valueLabel.Text = FormatNumber(value) .. (opts.Suffix or "")
	valueLabel.TextColor3 = SilentUI.Theme.TextDim
	valueLabel.TextSize = 13
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.AnchorPoint = Vector2.new(1, 0)
	valueLabel.Position = UDim2.new(1, -14, 0, 8)
	valueLabel.Size = UDim2.fromOffset(62, 18)
	valueLabel.ZIndex = Z.Content + 1
	valueLabel.Parent = card
 
	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 14, 1, -20)
	track.Size = UDim2.new(1, -28, 0, 6)
	-- Nearly transparent white overlay: no gray tint, so the window background
	-- remains visible through the unfilled portion of the slider.
	track.BackgroundColor3 = SilentUI.Theme.Surface
	track.BackgroundTransparency = 0.91
	track.BorderSizePixel = 0
	track.ZIndex = Z.Content + 1
	track.Parent = card
	Corner(track, 3)
 
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = SilentUI.Theme.Accent
	fill.BackgroundTransparency = 0
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(SafeAlpha(value, min, max), 0, 1, 0)
	fill.ZIndex = Z.Content + 2
	fill.Parent = track
	Corner(fill, 3)
 
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(SafeAlpha(value, min, max), 0, 0.5, 0)
	knob.Size = UDim2.fromOffset(12, 12)
	knob.BackgroundColor3 = SilentUI.Theme.Text
	knob.BackgroundTransparency = 0
	knob.BorderSizePixel = 0
	knob.ZIndex = Z.Content + 3
	knob.Parent = track
	Corner(knob, 6)
	Stroke(knob, SilentUI.Theme.Background, 2, 0)
 
	if hasDesc then
		local lastW = -1
		local function relayout()
			local w = card.AbsoluteSize.X / GetUIScale()
			if w <= 0 or math.abs(w - lastW) < 1 then return end
			lastW = w
			local _, h = MeasureText(opts.Description, 12, math.max(w - textX - 14, 40))
			card.Size = UDim2.new(1, 0, 0, math.max(76, 26 + h + 8 + 20))
		end
		card:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
		task.defer(relayout)
	end
 
	local function setVisual(alpha, animated, duration)
		if animated then
			Tween(fill, { Size = UDim2.new(alpha, 0, 1, 0) }, duration or 0.16)
			Tween(knob, { Position = UDim2.new(alpha, 0, 0.5, 0) }, duration or 0.16)
		else
			fill.Size = UDim2.new(alpha, 0, 1, 0)
			knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		end
	end
 
	local targetAlpha = SafeAlpha(value, min, max)
	local visualAlpha = targetAlpha
 
	local signal = MakeSignal()
	local function fireChanged(v)
		local info = ChangeInfo()
		if opts.Callback then task.spawn(opts.Callback, v, info) end
		signal.Fire(v, info)
	end
 
	local function setValueLabel()
		valueLabel.Text = FormatNumber(value) .. (opts.Suffix or "")
	end
 
	local function moveTo(newValue, animated)
		value = math.clamp(newValue, min, max)
		local alpha = SafeAlpha(value, min, max)
		targetAlpha = alpha
		visualAlpha = alpha
		setValueLabel()
		setVisual(alpha, animated ~= false, 0.18)
	end
 
	local dragging = false
	local sliderInput = nil
	local sliderOwner = {}
	local followConn = nil
 
	local function updateFromX(xPos)
		if track.AbsoluteSize.X <= 0 then return end
		targetAlpha = math.clamp((xPos - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local raw = min + targetAlpha * (max - min)
		local newValue = SnapToIncrement(raw, min, max, increment)
		if newValue ~= value then
			value = newValue
			setValueLabel()
			fireChanged(value)
		end
	end
 
	local SLIDER_SMOOTH = 22
 
	local function stopFollow()
		if followConn then
			followConn:Disconnect()
			followConn = nil
		end
	end
 
	local function releaseSlider()
		if ActiveSliderOwner == sliderOwner then ActiveSliderOwner = nil end
		dragging = false
		sliderInput = nil
		stopFollow()
	end
	jan:Add(releaseSlider)
	jan:Add(card.Destroying:Connect(releaseSlider))
	jan:Add(UserInputService.WindowFocusReleased:Connect(releaseSlider))
 
	local hitBox = Instance.new("TextButton")
	hitBox.Name = "SliderHitBox"
	hitBox.Text = ""
	hitBox.AutoButtonColor = false
	hitBox.BackgroundTransparency = 1
	hitBox.AnchorPoint = Vector2.new(0.5, 0.5)
	hitBox.Position = UDim2.fromScale(0.5, 0.5)
	hitBox.Size = UDim2.new(1, 8, 0, 26)
	hitBox.ZIndex = Z.Content + 4
	hitBox.Parent = track
 
	jan:Add(hitBox.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if dragging or ActiveSliderOwner ~= nil then return end
		ActiveSliderOwner = sliderOwner
		dragging = true
		sliderInput = input
		updateFromX(input.Position.X)
 
		stopFollow()
		followConn = RunService.RenderStepped:Connect(function(dt)
			if not track.Parent then stopFollow() return end
			local a = 1 - math.exp(-SLIDER_SMOOTH * dt)
			visualAlpha = visualAlpha + (targetAlpha - visualAlpha) * a
			if math.abs(targetAlpha - visualAlpha) < 0.001 then
				visualAlpha = targetAlpha
			end
			setVisual(visualAlpha, false)
		end)
		jan:Add(followConn)
	end))
 
	jan:Add(UserInputService.InputChanged:Connect(function(input)
		if not dragging or ActiveSliderOwner ~= sliderOwner then return end
		if input == sliderInput
			or (sliderInput and sliderInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement) then
			updateFromX(input.Position.X)
		end
	end))
 
	jan:Add(UserInputService.InputEnded:Connect(function(input)
		if not dragging or ActiveSliderOwner ~= sliderOwner then return end
		if input ~= sliderInput
			and not (sliderInput and sliderInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1) then
			return
		end
		releaseSlider()
		targetAlpha = SafeAlpha(value, min, max)
		visualAlpha = targetAlpha
		setVisual(targetAlpha, true, 0.12)
	end))
 
	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, v, silent)
			moveTo(SnapToIncrement(tonumber(v) or min, min, max, increment), true)
			if not silent then fireChanged(value) end
		end,
		Get = function() return value end,
		SetRange = function(_, newMin, newMax)
			min, max = newMin, newMax
			moveTo(math.clamp(value, min, max), true)
		end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() stopFollow(); signal.Clear(); card:Destroy() end,
	}, "Slider", function(v)
		if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
			return false, nil, "expected a finite number"
		end
		return true, SnapToIncrement(math.clamp(v, min, max), min, max, increment)
	end)
end
 
function Private.ComputePopupPosition(window, card, w, h)
	local s = GetUIScale()
	local realW, realH = w * s, h * s
 
	local view = Private.ViewportSize()
	local winPos = window.AbsolutePosition
	local winSize = window.AbsoluteSize
	local cardPos = card.AbsolutePosition
 
	local px = winPos.X + winSize.X + 12
	if px + realW > view.X - 8 then
		px = winPos.X - realW - 12
	end
	px = SafeClamp(px, 8, view.X - realW - 8)
 
	local py = cardPos.Y - realH - 8
	py = SafeClamp(py, winPos.Y + 8, winPos.Y + winSize.Y - realH - 8)
	py = SafeClamp(py, 8, view.Y - realH - 8)
 
	return math.round(px / s), math.round(py / s)
end
 

-- Asset previews are deliberately independent of window backgrounds.
function Tab:AddAssetGrid(opts)
	opts = opts or {}

	local function normalizeImage(reference)
		if reference == nil or reference == "" then return "" end
		if type(reference) == "number" then
			assert(reference > 0 and reference % 1 == 0 and reference < math.huge,
				"AssetGrid image IDs must be positive integers")
			return "rbxassetid://" .. tostring(reference)
		end
		assert(type(reference) == "string", "AssetGrid images must be asset IDs or image URLs")
		if reference:match("^%d+$") then return "rbxassetid://" .. reference end
		assert(Private.IsValidImageReference(reference),
			"AssetGrid image must be an asset ID, rbxasset:// path, or HTTP(S) image URL")
		return reference
	end

	local function normalizeOptions(list)
		assert(type(list) == "table", "AssetGrid Options must be an array")
		local normalized, seen = {}, {}
		for index, item in ipairs(list) do
			local value, image, label, labelKey
			if type(item) == "table" then
				image = item.AssetId
				if image == nil then image = item.Image end
				value = item.Value
				if value == nil then value = image end
				label, labelKey = item.Label, item.LabelKey
			else
				value, image = item, item
			end
			assert(type(value) == "string" or type(value) == "number",
				"AssetGrid option Value must be a string or number")
			assert(not seen[value], "AssetGrid option Values must be unique")
			seen[value] = true
			if type(labelKey) == "string" then label = SilentUI:Translate(labelKey) end
			table.insert(normalized, {
				Value = value,
				Image = normalizeImage(image),
				Label = tostring(label ~= nil and label or value),
				Index = index,
			})
		end
		return normalized
	end

	local rawOptions = opts.Options or opts.Items or {}
	local options = normalizeOptions(rawOptions)
	local function findOption(value)
		for _, option in ipairs(options) do
			if option.Value == value then return option end
		end
		return nil
	end
	local selected = findOption(opts.Default) and opts.Default or (options[1] and options[1].Value)
	local locked = opts.Locked == true
	local signal = MakeSignal()

	local headerHeight = opts.Description and opts.Description ~= "" and 56 or 44
	local card = BaseCard(self._page, headerHeight + 12)
	card.Name = "AssetGrid"
	self._window:_RegisterSearchable(self, opts.Text or "Assets", card)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, headerHeight)
	header.ZIndex = Z.Content + 1
	header.Parent = card
	local titleX = AddLeadingIcon(header, opts.Icon, headerHeight)
	AddTitleDesc(header, titleX, 14, opts.Text or "Assets", opts.Description, headerHeight)

	local grid = Instance.new("Frame")
	grid.Name = "Previews"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(12, headerHeight)
	grid.Size = UDim2.new(1, -24, 0, 0)
	grid.ZIndex = Z.Content + 1
	grid.Parent = card

	local layout = Instance.new("UIGridLayout")
	local gap = math.max(2, tonumber(opts.Gap) or 8)
	local columns = math.clamp(math.floor(tonumber(opts.Columns) or 2), 1, 6)
	local minCellWidth = math.max(65, tonumber(opts.MinCellWidth) or 110)
	local cellHeight = math.max(60, tonumber(opts.CellHeight) or 98)
	layout.CellPadding = UDim2.fromOffset(gap, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local emptyOverlay = Instance.new("Frame")
	emptyOverlay.Name = "EmptyOverlay"
	emptyOverlay.BackgroundTransparency = 1
	emptyOverlay.Position = grid.Position
	emptyOverlay.Size = grid.Size
	emptyOverlay.ZIndex = Z.Content + 1
	emptyOverlay.Parent = card

	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "Empty"
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.FontFace = SilentUI.Theme.FontRegular
	emptyLabel.Text = opts.EmptyText or "No assets available"
	emptyLabel.TextColor3 = SilentUI.Theme.TextDim
	emptyLabel.TextSize = 12
	emptyLabel.Size = UDim2.fromScale(1, 1)
	emptyLabel.ZIndex = Z.Content + 2
	emptyLabel.Parent = emptyOverlay

	local entries = {}
	local visibleColumns = columns
	local cellWidth = -1
	local function updateGridHeight()
		if not card.Parent then return end
		local rows = math.ceil(#options / visibleColumns)
		local expectedHeight = rows > 0 and (rows * cellHeight + (rows - 1) * gap) or 40
		local measuredHeight = layout.AbsoluteContentSize.Y / GetUIScale()
		local height = math.max(expectedHeight, measuredHeight)
		local top = header.Size.Y.Offset
		grid.Position = UDim2.fromOffset(12, top)
		grid.Size = UDim2.new(1, -24, 0, height)
		emptyOverlay.Position = grid.Position
		emptyOverlay.Size = grid.Size
		card.Size = UDim2.new(1, 0, 0, top + height + 12)
		emptyOverlay.Visible = #options == 0
	end

	local function relayout()
		if not card.Parent then return end
		local width = grid.AbsoluteSize.X / GetUIScale()
		local availableWidth = math.max(1, width - 4)
		local nextColumns = columns
		if width > 0 then
			nextColumns = math.min(columns,
				math.max(1, math.floor((availableWidth + gap) / (minCellWidth + gap))))
		end
		local nextCellWidth = width > 0
			and math.max(1, math.floor((availableWidth - (nextColumns - 1) * gap) / nextColumns))
			or minCellWidth
		if nextColumns ~= visibleColumns or nextCellWidth ~= cellWidth then
			visibleColumns = nextColumns
			cellWidth = nextCellWidth
			layout.FillDirectionMaxCells = visibleColumns
			layout.CellSize = UDim2.fromOffset(cellWidth, cellHeight)
		end
		updateGridHeight()
	end

	local function renderSelection()
		for _, entry in ipairs(entries) do
			local active = entry.Option.Value == selected
			entry.Stroke.Color = active and SilentUI.Theme.Accent or SilentUI.Theme.Border
			entry.Stroke.Transparency = active and 0.08 or 0.68
			entry.Stroke.Thickness = active and 2 or 1
			entry.Check.Visible = active
			entry.Button.BackgroundTransparency = active and 0.78 or 0.91
			entry.Button.Active = not locked
		end
	end

	local function fireChanged()
		local option = findOption(selected)
		local info = ChangeInfo()
		local snapshot = option and table.clone(option) or nil
		if opts.Callback then task.spawn(opts.Callback, selected, info, snapshot) end
		signal.Fire(selected, info, snapshot)
	end

	local function buildOptions()
		for _, entry in ipairs(entries) do entry.Button:Destroy() end
		table.clear(entries)
		for index, option in ipairs(options) do
			local button = Instance.new("TextButton")
			button.Name = "Asset_" .. tostring(index)
			button.Text = ""
			button.AutoButtonColor = false
			button.BackgroundColor3 = SilentUI.Theme.Surface
			button.BackgroundTransparency = 0.91
			button.BorderSizePixel = 0
			button.ClipsDescendants = false
			button.LayoutOrder = index
			button.ZIndex = Z.Content + 2
			button.Parent = grid
			Corner(button, 10)
			local border = Stroke(button, SilentUI.Theme.Border, 1, 0.68)

			if option.Image ~= "" then
				local preview = Instance.new("ImageLabel")
				preview.Name = "Preview"
				preview.BackgroundTransparency = 1
				preview.Image = option.Image
				preview.ImageColor3 = Color3.new(1, 1, 1)
				preview:SetAttribute("SilentThemeImageColorExempt", true)
				preview.ScaleType = Enum.ScaleType.Crop
				preview.Size = UDim2.fromScale(1, 1)
				preview.ZIndex = Z.Content + 3
				preview.Parent = button
				Corner(preview, 10)

				local labelShade = Instance.new("Frame")
				labelShade.Name = "CaptionBackdrop"
				labelShade.BackgroundColor3 = Color3.fromRGB(12, 13, 17)
				labelShade.BackgroundTransparency = 0.25
				labelShade:SetAttribute("SilentThemeColorExempt", true)
				labelShade.BorderSizePixel = 0
				labelShade.AnchorPoint = Vector2.new(0.5, 1)
				labelShade.Position = UDim2.new(0.5, 0, 1, -5)
				labelShade.Size = UDim2.new(1, -10, 0, 23)
				labelShade.ZIndex = Z.Content + 4
				labelShade.Parent = button
				Corner(labelShade, 6)
			end

			local label = Instance.new("TextLabel")
			label.Name = "AssetName"
			label.BackgroundTransparency = 1
			label.FontFace = SilentUI.Theme.Font
			label.Text = option.Label
			label.TextColor3 = SilentUI.Theme.Text
			label.TextSize = 12
			label.TextTruncate = Enum.TextTruncate.AtEnd
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.TextYAlignment = Enum.TextYAlignment.Center
			label.AnchorPoint = Vector2.new(0.5, option.Image == "" and 0.5 or 1)
			label.Position = option.Image == "" and UDim2.fromScale(0.5, 0.5)
				or UDim2.new(0.5, 0, 1, -6)
			label.Size = UDim2.new(1, -20, 0, option.Image == "" and cellHeight - 12 or 21)
			label.ZIndex = Z.Content + 5
			label.Parent = button

			local check = Instance.new("ImageLabel")
			check.Name = "Selected"
			check.BackgroundColor3 = SilentUI.Theme.Accent
			check.BackgroundTransparency = 0.06
			check.BorderSizePixel = 0
			check.Image = ResolveIcon("check")
			check.ImageColor3 = SilentUI.Theme.Background
			check.AnchorPoint = Vector2.new(1, 0)
			check.Position = UDim2.new(1, -7, 0, 7)
			check.Size = UDim2.fromOffset(22, 22)
			check.ZIndex = Z.Content + 6
			check.Parent = button
			Corner(check, 7)

			table.insert(entries, { Button = button, Stroke = border, Check = check, Option = option })
			button.Activated:Connect(function()
				if locked or selected == option.Value then return end
				selected = option.Value
				renderSelection()
				fireChanged()
			end)
			button.MouseEnter:Connect(function()
				if not locked and selected ~= option.Value then
					Tween(border, { Transparency = 0.35 }, 0.12)
				end
			end)
			button.MouseLeave:Connect(function()
				if selected ~= option.Value then
					Tween(border, { Transparency = 0.68 }, 0.12)
				end
			end)
		end
		renderSelection()
		relayout()
	end

	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	header:GetPropertyChangedSignal("Size"):Connect(relayout)
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateGridHeight)
	buildOptions()
	task.defer(relayout)

	local localeConnection = SilentUI:RegisterLocaleCallback(function()
		if not card.Parent then return end
		options = normalizeOptions(rawOptions)
		buildOptions()
	end)

	return RegisterFlag(opts, {
		Instance = card,
		Get = function() return selected end,
		GetOption = function()
			local option = findOption(selected)
			return option and table.clone(option) or nil
		end,
		Set = function(_, value, silent)
			assert(value == nil and #options == 0 or findOption(value),
				"AssetGrid selection is not an available option")
			local changed = value ~= selected
			selected = value
			renderSelection()
			if changed and not silent then fireChanged() end
		end,
		SetOptions = function(_, newOptions)
			local nextRaw = newOptions or {}
			local nextOptions = normalizeOptions(nextRaw)
			local before = findOption(selected)
			local beforeValue, beforeImage = selected, before and before.Image
			rawOptions, options = nextRaw, nextOptions
			if not findOption(selected) then
				selected = findOption(opts.Default) and opts.Default
					or (options[1] and options[1].Value)
			end
			buildOptions()
			local after = findOption(selected)
			if beforeValue ~= selected or beforeImage ~= (after and after.Image) then fireChanged() end
		end,
		Refresh = function(self, newOptions)
			if newOptions ~= nil then self:SetOptions(newOptions) else
				options = normalizeOptions(rawOptions)
				buildOptions()
			end
		end,
		SetLocked = function(_, value)
			locked = value == true
			renderSelection()
		end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function()
			localeConnection:Disconnect()
			signal.Clear()
			card:Destroy()
		end,
	}, "AssetGrid", function(value)
		if value == nil and #options == 0 then return true, nil end
		if findOption(value) then return true, value end
		return false, nil, "selection is not an available asset"
	end)
end

function Tab:AddDropdown(opts)
	opts = opts or {}
	local function normalizeOptions(list)
		assert(type(list) == "table", "Dropdown Options must be an array")
		local normalized, seen = {}, {}
		for index, option in ipairs(list) do
			local value, label
			if type(option) == "table" then
				value = option.Value
				label = option.Label
			else
				value = option
			end
			assert(type(value) == "string" or type(value) == "number", "Dropdown option Value must be a string or number")
			assert(not seen[value], "Dropdown option values must be unique")
			seen[value] = true
			local key = type(option) == "table" and option.LabelKey
			if type(key) == "string" then label = SilentUI:Translate(key) end
			table.insert(normalized, { Value = value, Label = tostring(label ~= nil and label or value), Index = index })
		end
		return normalized
	end
	local rawOptions = opts.Options or {}
	local options = normalizeOptions(rawOptions)
	local isMulti = opts.MultiSelect == true
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local jan = self._janitor
	local function optionValue(option) return option.Value end
	local function findOption(value)
		for _, option in ipairs(options) do
			if option.Value == value then return option end
		end
	end
	local function hasOption(value) return findOption(value) ~= nil end
 
	local selected
	if isMulti then
		selected = {}
		if type(opts.Default) == "table" then
			for _, v in ipairs(opts.Default) do if hasOption(v) then selected[v] = true end end
		end
	else
		selected = hasOption(opts.Default) and opts.Default or (options[1] and optionValue(options[1]))
	end
 
	local signal = MakeSignal()
	local function fireChanged(newValue, source)
		local info = ChangeInfo()
		if source then info.Source = source end
		if opts.Callback then task.spawn(opts.Callback, newValue, info) end
		signal.Fire(newValue, info)
	end
 
	local function getSelectedList()
		local list = {}
		for _, option in ipairs(options) do
			local value = optionValue(option)
			if isMulti and selected[value] then table.insert(list, value) end
		end
		return list
	end
 
	local function isOptionSelected(value)
		if isMulti then return selected[value] == true end
		return value == selected
	end

	local function displayValue(value)
		local option = findOption(value)
		return option and option.Label or tostring(value or "None")
	end
 
	local function formatValue()
		if isMulti then
			local list = getSelectedList()
			if #list == 0 then return "None" end
		if #list == 1 then return displayValue(list[1]) end
			return #list .. " selected"
		end
		return displayValue(selected)
	end
 
	local card = BaseCard(self._page, height)
	local textX = AddLeadingIcon(card, opts.Icon, height)
 
	AddTitleDesc(card, textX, 166, opts.Text or "Dropdown", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Dropdown", card)
 
	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.FontFace = SilentUI.Theme.FontRegular
	valueLabel.Text = formatValue()
	valueLabel.TextColor3 = SilentUI.Theme.TextDim
	valueLabel.TextSize = 13
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.AnchorPoint = Vector2.new(1, 0.5)
	valueLabel.Position = UDim2.new(1, -34, 0.5, 0)
	valueLabel.Size = UDim2.fromOffset(120, height)
	valueLabel.ZIndex = Z.Content + 1
	valueLabel.Parent = card
 
	local chevron = Instance.new("ImageLabel")
	chevron.BackgroundTransparency = 1
	chevron.Image = ResolveIcon("chevron-down")
	chevron.ImageColor3 = SilentUI.Theme.TextDim
	chevron.Size = UDim2.fromOffset(14, 14)
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.new(1, -14, 0.5, 0)
	chevron.ZIndex = Z.Content + 1
	chevron.Parent = card
 
	local click = Instance.new("TextButton")
	click.Text = ""
	click.AutoButtonColor = false
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.ZIndex = Z.Content + 3
	click.Parent = card
 
	local popupOpen = false
	local popupFrame, popupBackdrop, followConn, scrollConn, searchConn
	local optionButtons = {}
 
	local function closePopup()
		if not popupOpen then return end
		popupOpen = false
		Private.RegisterPopupClose(closePopup)
		Tween(chevron, { Rotation = 0 }, 0.15)
 
		if followConn then followConn:Disconnect(); followConn = nil end
		if scrollConn then scrollConn:Disconnect(); scrollConn = nil end
		if searchConn then searchConn:Disconnect(); searchConn = nil end
		table.clear(optionButtons)
 
		if popupBackdrop then popupBackdrop:Destroy(); popupBackdrop = nil end
 
		if popupFrame then
			local pf = popupFrame
			popupFrame = nil
			Tween(pf, { Size = UDim2.new(0, pf.Size.X.Offset, 0, 0) }, 0.4,
				Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			Tween(pf, { BackgroundTransparency = 1 }, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(0.4, function() if pf then pf:Destroy() end end)
		end
	end
 
	local function refreshOptionVisual(value)
		local entry = optionButtons[value]
		if not entry then return end
		local sel = isOptionSelected(value)
		Tween(entry.button, { BackgroundTransparency = sel and 0.9 or 1 }, 0.1)
		Tween(entry.label, { TextColor3 = sel and SilentUI.Theme.Text or SilentUI.Theme.TextDim }, 0.1)
		if entry.check then
			Tween(entry.check, { BackgroundTransparency = sel and 0.05 or 0.9 }, 0.1)
		end
		if entry.checkIcon then
			Tween(entry.checkIcon, { ImageTransparency = sel and 0 or 1 }, 0.1)
		end
		if entry.singleCheck then entry.singleCheck.Visible = sel end
	end
 
	local function openPopup()
		if popupOpen then return end
		popupOpen = true
		Private.RegisterPopupOpen(closePopup)
		Tween(chevron, { Rotation = 180 }, 0.15)
 
		local root = SilentUI._Root
		local mainWindow = self._window and self._window._gui or root
 
		local rowH, padV = 30, 12
		local searchable = opts.Searchable == true or (opts.Searchable ~= false and #options >= 8)
		local searchHeight = searchable and 36 or 0
		local contentH = #options * rowH + math.max(#options - 1, 0) * 2 + padV + searchHeight
		local targetHeight = math.min(contentH, 220, math.max(1, (Private.ViewportSize().Y - 16) / GetUIScale()))
 
		local popupW = 140
		for _, option in ipairs(options) do
			local w = MeasureText(option.Label, 13, 1000)
			popupW = math.max(popupW, w + 66)
		end
		if searchable then popupW = math.max(popupW, 180) end
		popupW = math.min(popupW, Private.ViewportSize().X / GetUIScale() - 24)
 
		popupBackdrop = Private.MakePopupBackdrop(closePopup)
 
		popupFrame = Instance.new("CanvasGroup")
		popupFrame.Name = "DropdownPopup"
		popupFrame.Active = true
		popupFrame.BackgroundColor3 = SilentUI.Theme.Background
		popupFrame.BackgroundTransparency = 1
		popupFrame.BorderSizePixel = 0
		popupFrame.ZIndex = Z.Popup
		popupFrame.Size = UDim2.new(0, popupW, 0, 0)
		popupFrame.Parent = root
		popupFrame:SetAttribute("SilentInterfacePanel", true)
		if self._window then popupFrame:SetAttribute("SilentWindowId", self._window._id) end
		Corner(popupFrame, 10)
		local popupStroke = Stroke(popupFrame, SilentUI.Theme.Border, 1, 0.92)
		Private.GlassLayer(popupFrame, 10, 0.985)
 
		local px, py = Private.ComputePopupPosition(mainWindow, card, popupW, targetHeight)
		popupFrame.Position = UDim2.fromOffset(px, py)
 
		local optionsHolder = Instance.new("ScrollingFrame")
		optionsHolder.Name = "Options"
		optionsHolder.BackgroundTransparency = 1
		optionsHolder.BorderSizePixel = 0
		optionsHolder.Position = UDim2.fromOffset(0, searchHeight)
		optionsHolder.Size = UDim2.new(1, 0, 1, -searchHeight)
		optionsHolder.ScrollingDirection = Enum.ScrollingDirection.Y
		optionsHolder.ScrollBarThickness = 0
		optionsHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
		optionsHolder.CanvasSize = UDim2.new(0, 0, 0, 0)
		optionsHolder.ZIndex = Z.Popup + 1
		optionsHolder.Parent = popupFrame
 
		local optPad = Instance.new("UIPadding")
		optPad.PaddingTop = UDim.new(0, 6)
		optPad.PaddingBottom = UDim.new(0, 6)
		optPad.PaddingLeft = UDim.new(0, 6)
		optPad.PaddingRight = UDim.new(0, 16)
		optPad.Parent = optionsHolder
 
		local optLayout = Instance.new("UIListLayout")
		optLayout.Padding = UDim.new(0, 2)
		optLayout.SortOrder = Enum.SortOrder.LayoutOrder
		optLayout.Parent = optionsHolder
 
		AddScrollbar(optionsHolder)
		Private.AddContentScrollThumb(optionsHolder, optLayout, popupFrame, {
			Add = function(_, conn) scrollConn = conn end,
		})
		local searchBox
		if searchable then
			local searchField = Instance.new("TextBox")
			searchField.Name = "Search"
			searchField.ClearTextOnFocus = false
			searchField.PlaceholderText = opts.SearchPlaceholder or "Search options..."
			searchField.Text = ""
			searchField.FontFace = SilentUI.Theme.FontRegular
			searchField.TextColor3 = SilentUI.Theme.Text
			searchField.PlaceholderColor3 = SilentUI.Theme.TextDim
			searchField.TextSize = 13
			searchField.TextXAlignment = Enum.TextXAlignment.Left
			searchField.BackgroundColor3 = SilentUI.Theme.Surface
			searchField.BackgroundTransparency = 0.2
			searchField.BorderSizePixel = 0
			searchField.Position = UDim2.fromOffset(6, 5)
			searchField.Size = UDim2.new(1, -12, 0, 26)
			searchField.ZIndex = Z.Popup + 2
			searchField.Parent = popupFrame
			Corner(searchField, 7)
			searchBox = searchField
		end

		local function applySearch()
			local query = searchBox and searchBox.Text:lower() or ""
			for value, entry in pairs(optionButtons) do
				local option = findOption(value)
				local matches = query == "" or (option and (
					option.Label:lower():find(query, 1, true) ~= nil
					or tostring(option.Value):lower():find(query, 1, true) ~= nil
				))
				entry.button.Visible = matches == true
			end
			optionsHolder.CanvasPosition = Vector2.new(0, 0)
		end
		if searchBox then searchConn = searchBox:GetPropertyChangedSignal("Text"):Connect(applySearch) end
 
		for i, option in ipairs(options) do
			local optionName = option.Value
			local optBtn = Instance.new("TextButton")
			optBtn.Text = ""
			optBtn.AutoButtonColor = false
			optBtn.BackgroundColor3 = SilentUI.Theme.Surface
			optBtn.BackgroundTransparency = isOptionSelected(optionName) and 0.9 or 1
			optBtn.BorderSizePixel = 0
			optBtn.Size = UDim2.new(1, 0, 0, rowH)
			optBtn.LayoutOrder = i
			optBtn.ZIndex = Z.Popup + 2
			optBtn.Parent = optionsHolder
			Corner(optBtn, 8)
 
			local optLabel = Instance.new("TextLabel")
			optLabel.BackgroundTransparency = 1
			optLabel.FontFace = SilentUI.Theme.FontRegular
			optLabel.Text = option.Label
			optLabel.TextColor3 = isOptionSelected(optionName) and SilentUI.Theme.Text or SilentUI.Theme.TextDim
			optLabel.TextSize = 13
			optLabel.TextXAlignment = Enum.TextXAlignment.Left
			optLabel.TextTruncate = Enum.TextTruncate.AtEnd
			optLabel.Position = UDim2.fromOffset(10, 0)
			optLabel.Size = UDim2.new(1, -34, 1, 0)
			optLabel.ZIndex = Z.Popup + 3
			optLabel.Parent = optBtn
 
			local entry = { button = optBtn, label = optLabel }
 
			if isMulti then
				local check = Instance.new("Frame")
				check.Name = "Check"
				check.AnchorPoint = Vector2.new(1, 0.5)
				check.Position = UDim2.new(1, -10, 0.5, 0)
				check.Size = UDim2.fromOffset(14, 14)
				check.BackgroundColor3 = SilentUI.Theme.Accent
				check.BackgroundTransparency = isOptionSelected(optionName) and 0.05 or 0.9
				check.BorderSizePixel = 0
				check.ZIndex = Z.Popup + 3
				check.Parent = optBtn
				Corner(check, 4)
				Stroke(check, SilentUI.Theme.Border, 1, 0.75)
 
				local checkIcon = Instance.new("ImageLabel")
				checkIcon.Name = "Icon"
				checkIcon.BackgroundTransparency = 1
				checkIcon.Image = ResolveIcon("check")
				checkIcon.ImageColor3 = SilentUI.Theme.Background
				checkIcon.ImageTransparency = isOptionSelected(optionName) and 0 or 1
				checkIcon.Size = UDim2.fromOffset(10, 10)
				checkIcon.AnchorPoint = Vector2.new(0.5, 0.5)
				checkIcon.Position = UDim2.fromScale(0.5, 0.5)
				checkIcon.ZIndex = Z.Popup + 4
				checkIcon.Parent = check
 
				entry.check = check
				entry.checkIcon = checkIcon
			else
				local check = Instance.new("ImageLabel")
				check.Name = "SingleCheck"
				check.BackgroundTransparency = 1
				check.Image = ResolveIcon("check")
				check.ImageColor3 = SilentUI.Theme.Text
				check.Size = UDim2.fromOffset(14, 14)
				check.AnchorPoint = Vector2.new(1, 0.5)
				check.Position = UDim2.new(1, -10, 0.5, 0)
				check.ZIndex = Z.Popup + 3
				check.Visible = isOptionSelected(optionName)
				check.Parent = optBtn
				entry.singleCheck = check
			end
 
			optionButtons[optionName] = entry
 
			optBtn.MouseEnter:Connect(function()
				if not isOptionSelected(optionName) then
					Tween(optBtn, { BackgroundTransparency = 0.85 }, 0.1)
				end
			end)
			optBtn.MouseLeave:Connect(function()
				if not isOptionSelected(optionName) then
					Tween(optBtn, { BackgroundTransparency = 1 }, 0.1)
				end
			end)
 
			optBtn.MouseButton1Click:Connect(function()
				if isMulti then
					selected[optionName] = (not selected[optionName]) or nil
					refreshOptionVisual(optionName)
					valueLabel.Text = formatValue()
					fireChanged(getSelectedList())
				else
					selected = optionName
					valueLabel.Text = formatValue()
					fireChanged(optionName)
					closePopup()
				end
			end)
		end
		applySearch()
 
		Tween(popupFrame, {
			Size = UDim2.new(0, popupW, 0, targetHeight),
			BackgroundTransparency = self._window and self._window._interfaceTransparency or 0.15,
		}, 0.44, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		Tween(popupStroke, { Transparency = 0.85 }, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
		followConn = RunService.RenderStepped:Connect(function()
			if not popupFrame or not card.Parent then return end
			local nx, ny = Private.ComputePopupPosition(mainWindow, card, popupW, targetHeight)
			popupFrame.Position = UDim2.fromOffset(nx, ny)
		end)
		jan:Add(followConn)
	end
 
	click.MouseButton1Click:Connect(function()
		if popupOpen then closePopup() else openPopup() end
	end)
 
	card.MouseEnter:Connect(function() Tween(card, { BackgroundTransparency = 0.93 }, 0.15) end)
	card.MouseLeave:Connect(function() Tween(card, { BackgroundTransparency = 0.96 }, 0.15) end)
 
	local function cloneSelection()
		if not isMulti then return selected end
		local copy = {}
		for value, enabled in pairs(selected) do if enabled then copy[value] = true end end
		return copy
	end
	local function selectionEquals(first, second)
		if type(first) ~= type(second) then return false end
		if type(first) ~= "table" then return first == second end
		for value, enabled in pairs(first) do if enabled ~= second[value] then return false end end
		for value, enabled in pairs(second) do if enabled ~= first[value] then return false end end
		return true
	end
	local function setOptions(newOptions)
		local before = cloneSelection()
		rawOptions = newOptions or {}
		options = normalizeOptions(rawOptions)
		if isMulti then
			local filtered = {}
			for value, enabled in pairs(before) do if enabled and hasOption(value) then filtered[value] = true end end
			selected = filtered
		elseif not hasOption(selected) then
			selected = hasOption(opts.Default) and opts.Default or (options[1] and optionValue(options[1]))
		end
		closePopup()
		valueLabel.Text = formatValue()
		local after = cloneSelection()
		if not selectionEquals(before, after) then fireChanged(isMulti and getSelectedList() or selected, "code") end
	end

	local localeConnection = SilentUI:RegisterLocaleCallback(function()
		if card.Parent then setOptions(rawOptions) end
	end)
	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, v, silent)
			if isMulti then
				selected = {}
				if type(v) == "table" then
					for _, name in ipairs(v) do if hasOption(name) then selected[name] = true end end
				end
			else
				selected = v
			end
			valueLabel.Text = formatValue()
			for name in pairs(optionButtons) do refreshOptionVisual(name) end
			if not silent then
				fireChanged(isMulti and getSelectedList() or selected)
			end
		end,
		Get = function()
			if isMulti then return getSelectedList() end
			return selected
		end,
		SetOptions = function(_, newOptions)
			setOptions(newOptions)
		end,
		Refresh = function(_, newOptions)
			if newOptions ~= nil then setOptions(newOptions) end
		end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function()
			localeConnection:Disconnect()
			closePopup()
			signal.Clear()
			card:Destroy()
		end,
	}, "Dropdown", function(v)
		if isMulti then
			if type(v) ~= "table" then return false, nil, "expected a selection list" end
			for key, value in pairs(v) do
				if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or not hasOption(value) then
					return false, nil, "selection contains an invalid option"
				end
			end
			return true, v
		end
		if v == nil or hasOption(v) then return true, v end
		return false, nil, "selection is not an available option"
	end)
end
 
function Tab:AddTextbox(opts)
	opts = opts or {}
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local card = BaseCard(self._page, height)
 
	local textX = AddLeadingIcon(card, opts.Icon, height)
 
	local iconGap, rightPad, pillMinW = 29, 12, 90
	local titleReserve = pillMinW + 26
 
	local _, _, refreshTextLayout = AddTitleDesc(card, textX, function() return titleReserve end, opts.Text or "Textbox", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Textbox", card)
 
	local pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(1, 0.5)
	pill.Position = UDim2.new(1, -14, 0.5, 0)
	pill.Size = UDim2.fromOffset(pillMinW, 26)
	pill.BackgroundColor3 = SilentUI.Theme.Surface
	pill.BackgroundTransparency = 0.9
	pill.BorderSizePixel = 0
	pill.ZIndex = Z.Content + 2
	pill.Parent = card
	Corner(pill, 8)
	local pillStroke = Stroke(pill, SilentUI.Theme.Border, 1, 0.88)
 
	local penIcon = Instance.new("ImageLabel")
	penIcon.BackgroundTransparency = 1
	penIcon.Image = ResolveIcon("pencil")
	penIcon.ImageColor3 = SilentUI.Theme.TextDim
	penIcon.Size = UDim2.fromOffset(13, 13)
	penIcon.AnchorPoint = Vector2.new(0, 0.5)
	penIcon.Position = UDim2.new(0, 10, 0.5, 0)
	penIcon.ZIndex = Z.Content + 3
	penIcon.Parent = pill
 
	local box = Instance.new("TextBox")
	box.ClearTextOnFocus = false
	box.FontFace = SilentUI.Theme.FontRegular
	box.PlaceholderText = opts.Placeholder or ""
	box.PlaceholderColor3 = SilentUI.Theme.TextDim
	box.Text = opts.Default or ""
	box.TextColor3 = SilentUI.Theme.Text
	box.TextSize = 13
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Center
	box.TextTruncate = Enum.TextTruncate.AtEnd
	box.ClipsDescendants = true
	box.BackgroundTransparency = 1
	box.Position = UDim2.fromOffset(iconGap, 0)
	box.Size = UDim2.new(1, -(iconGap + 10), 1, 0)
	box.ZIndex = Z.Content + 3
	box.Parent = pill
 
	local currentPillW = pillMinW
 
	local function resizePill(animated)
		local sample = box.Text ~= "" and box.Text or box.PlaceholderText
		local textW = MeasureText(sample, 13, 2000)
		local desiredW = iconGap + textW + rightPad
 
		local realCardW = card.AbsoluteSize.X > 0 and card.AbsoluteSize.X or 400
		local cardW = realCardW / GetUIScale()
		local maxW = math.max(pillMinW, math.floor(cardW * 0.5))
		local targetW = math.clamp(desiredW, pillMinW, maxW)
 
		if math.abs(targetW - currentPillW) < 1 then return end
		currentPillW = targetW
		titleReserve = targetW + 26
		refreshTextLayout()
 
		if animated == false then
			pill.Size = UDim2.fromOffset(targetW, 26)
		else
			Tween(pill, { Size = UDim2.fromOffset(targetW, 26) }, 0.16,
				Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		end
	end
 
	box:GetPropertyChangedSignal("Text"):Connect(function() resizePill(true) end)
	card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() resizePill(false) end)
	task.defer(function() resizePill(false) end)
 
	box.Focused:Connect(function()
		Tween(pillStroke, { Color = SilentUI.Theme.Accent, Transparency = 0.3 }, 0.15)
		Tween(pill, { BackgroundTransparency = 0.82 }, 0.15)
	end)
 
	local signal = MakeSignal()
	local function fireChanged(text, enterPressed)
		local info = ChangeInfo(enterPressed and "submit" or "change")
		if opts.Callback then task.spawn(opts.Callback, text, enterPressed, info) end
		signal.Fire(text, enterPressed, info)
	end
 
	box.FocusLost:Connect(function(enterPressed)
		Tween(pillStroke, { Color = SilentUI.Theme.Border, Transparency = 0.88 }, 0.15)
		Tween(pill, { BackgroundTransparency = 0.9 }, 0.15)
		fireChanged(box.Text, enterPressed)
	end)
 
	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, v, silent)
			box.Text = tostring(v or "")
			resizePill()
			if not silent then fireChanged(box.Text, false) end
		end,
		Get = function() return box.Text end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() signal.Clear(); card:Destroy() end,
	}, "Textbox")
end
 
function Private.MiniField(parent, label, width, zBase)
	zBase = zBase or Z.Popup
 
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(width, 36)
	holder.ZIndex = zBase + 1
	holder.Parent = parent
 
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.FontFace = SilentUI.Theme.FontRegular
	lbl.Text = label
	lbl.TextColor3 = SilentUI.Theme.TextDim
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Size = UDim2.new(1, 0, 0, 12)
	lbl.ZIndex = zBase + 2
	lbl.Parent = holder
 
	local field = Instance.new("Frame")
	field.Position = UDim2.fromOffset(0, 12)
	field.Size = UDim2.new(1, 0, 0, 24)
	field.BackgroundColor3 = SilentUI.Theme.Surface
	field.BackgroundTransparency = 0.92
	field.BorderSizePixel = 0
	field.ZIndex = zBase + 2
	field.Parent = holder
	Corner(field, 7)
	local fieldStroke = Stroke(field, SilentUI.Theme.Border, 1, 0.88)
 
	local box = Instance.new("TextBox")
	box.ClearTextOnFocus = false
	box.FontFace = SilentUI.Theme.FontRegular
	box.Text = ""
	box.TextColor3 = SilentUI.Theme.Text
	box.TextSize = 13
	box.TextXAlignment = Enum.TextXAlignment.Center
	box.TextYAlignment = Enum.TextYAlignment.Center
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromScale(1, 1)
	box.ZIndex = zBase + 3
	box.Parent = field
 
	box.Focused:Connect(function()
		Tween(fieldStroke, { Color = SilentUI.Theme.Accent, Transparency = 0.3 }, 0.15)
		Tween(field, { BackgroundTransparency = 0.84 }, 0.15)
	end)
	box.FocusLost:Connect(function()
		Tween(fieldStroke, { Color = SilentUI.Theme.Border, Transparency = 0.88 }, 0.15)
		Tween(field, { BackgroundTransparency = 0.92 }, 0.15)
	end)
 
	return holder, box
end
 
function Tab:AddColorPicker(opts)
	opts = opts or {}
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local jan = self._janitor
 
	local card = BaseCard(self._page, height)
	local textX = AddLeadingIcon(card, opts.Icon, height)
	AddTitleDesc(card, textX, 52, opts.Text or "Color", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Color", card)
 
	local color = opts.Default or Color3.fromRGB(255, 255, 255)
	local hue, sat, val = Color3.toHSV(color)
 
	local swatchHolder = Instance.new("Frame")
	swatchHolder.AnchorPoint = Vector2.new(1, 0.5)
	swatchHolder.Position = UDim2.new(1, -14, 0.5, 0)
	swatchHolder.Size = UDim2.fromOffset(24, 24)
	swatchHolder.BackgroundColor3 = SilentUI.Theme.Surface
	swatchHolder.BackgroundTransparency = 0.9
	swatchHolder.BorderSizePixel = 0
	swatchHolder.ZIndex = Z.Content + 1
	swatchHolder.Parent = card
	Corner(swatchHolder, 6)
	local swatchStroke = Stroke(swatchHolder, SilentUI.Theme.Border, 1, 0.85)
 
	local swatch = Instance.new("Frame")
	swatch.AnchorPoint = Vector2.new(0.5, 0.5)
	swatch.Position = UDim2.fromScale(0.5, 0.5)
	swatch.Size = UDim2.fromOffset(16, 16)
	swatch.BackgroundColor3 = color
	swatch.BorderSizePixel = 0
	swatch.ZIndex = Z.Content + 2
	swatch.Parent = swatchHolder
	swatch:SetAttribute("SilentThemeExempt", true)
	Corner(swatch, 4)
 
	local click = Instance.new("TextButton")
	click.Text = ""
	click.AutoButtonColor = false
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.ZIndex = Z.Content + 3
	click.Parent = card
 
	local popupOpen = false
	local popupFrame, popupBackdrop, followConn
	local svCursor, hueCursor, svBox, hueBar, satGradient
	local hexBox, rBox, gBox, bBox
	local originalHue, originalSat, originalVal
	local draggingSV, draggingHue = false, false
	local colorInput = nil
	local dragEndedAt = 0
 
	local function currentColor()
		return Color3.fromHSV(hue, sat, val)
	end
 
	local function syncFields()
		if svCursor then svCursor.Position = UDim2.new(sat, 0, 1 - val, 0) end
		if hueCursor then hueCursor.Position = UDim2.new(hue, 0, 0.5, 0) end
		if svBox then svBox.BackgroundColor3 = Color3.new(1, 1, 1) end
		if satGradient then
			satGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1))
		end
 
		local c = currentColor()
		local r = math.floor(c.R * 255 + 0.5)
		local g = math.floor(c.G * 255 + 0.5)
		local b = math.floor(c.B * 255 + 0.5)
		if hexBox and not hexBox:IsFocused() then hexBox.Text = "#" .. c:ToHex():upper() end
		if rBox and not rBox:IsFocused() then rBox.Text = tostring(r) end
		if gBox and not gBox:IsFocused() then gBox.Text = tostring(g) end
		if bBox and not bBox:IsFocused() then bBox.Text = tostring(b) end
	end
 
	local signal = MakeSignal()
	local lastFired = nil
 
	local function ColorsClose(a, b)
		if a == nil or b == nil then return false end
		return math.abs(a.R - b.R) < 0.001
			and math.abs(a.G - b.G) < 0.001
			and math.abs(a.B - b.B) < 0.001
	end
 
	local function applyColor(fireCallback)
		local c = currentColor()
		swatch.BackgroundColor3 = c
		syncFields()
		if fireCallback then
			if not ColorsClose(c, lastFired) then
				lastFired = c
				local info = ChangeInfo()
				if opts.Callback then task.spawn(opts.Callback, c, info) end
				signal.Fire(c, info)
			end
		end
	end
 
	local function closePopup()
		if not popupOpen then return end
		popupOpen = false
		draggingSV, draggingHue = false, false
		colorInput = nil
		Private.RegisterPopupClose(closePopup)
		Tween(swatchStroke, { Color = SilentUI.Theme.Border, Transparency = 0.85 }, 0.15)
 
		if followConn then followConn:Disconnect(); followConn = nil end
		if popupBackdrop then popupBackdrop:Destroy(); popupBackdrop = nil end
 
		if popupFrame then
			local pf = popupFrame
			popupFrame = nil
			svCursor, hueCursor, svBox, hueBar, satGradient = nil, nil, nil, nil, nil
			hexBox, rBox, gBox, bBox = nil, nil, nil, nil
			Tween(pf, { Size = UDim2.new(0, pf.Size.X.Offset, 0, 0) }, 0.4,
				Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			Tween(pf, { BackgroundTransparency = 1 }, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(0.4, function() if pf then pf:Destroy() end end)
		end
	end
 
	local function updateSV(inputPos)
		if not svBox or svBox.AbsoluteSize.X <= 0 then return end
		local rel, sz = svBox.AbsolutePosition, svBox.AbsoluteSize
		sat = math.clamp((inputPos.X - rel.X) / sz.X, 0, 1)
		val = 1 - math.clamp((inputPos.Y - rel.Y) / sz.Y, 0, 1)
		applyColor(true)
	end
 
	local function updateHue(inputPos)
		if not hueBar or hueBar.AbsoluteSize.X <= 0 then return end
		local rel, sz = hueBar.AbsolutePosition, hueBar.AbsoluteSize
		hue = math.clamp((inputPos.X - rel.X) / sz.X, 0, 1)
		applyColor(true)
	end
 
	jan:Add(UserInputService.InputChanged:Connect(function(input)
		if not popupFrame then return end
		if input ~= colorInput
			and not (colorInput and colorInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement) then
			return
		end
		if draggingSV then updateSV(input.Position) end
		if draggingHue then updateHue(input.Position) end
	end))
 
	jan:Add(UserInputService.InputEnded:Connect(function(input)
		if input == colorInput
			or (colorInput and colorInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1) then
			if draggingSV or draggingHue then
				dragEndedAt = os.clock()
			end
			draggingSV, draggingHue = false, false
			colorInput = nil
		end
	end))
 
	local function requestCloseFromBackdrop()
		if draggingSV or draggingHue then return end
		if os.clock() - dragEndedAt < 0.2 then return end
		closePopup()
	end
 
	local function openPopup()
		if popupOpen then return end
		popupOpen = true
		originalHue, originalSat, originalVal = hue, sat, val
		lastFired = currentColor()
		Private.RegisterPopupOpen(closePopup)
		Tween(swatchStroke, { Color = SilentUI.Theme.Accent, Transparency = 0.3 }, 0.15)
 
		local root = SilentUI._Root
		local mainWindow = self._window and self._window._gui or root
		local popupW, popupH = 208, math.min(290, math.max(1, (Private.ViewportSize().Y - 16) / GetUIScale()))
 
		popupBackdrop = Private.MakePopupBackdrop(requestCloseFromBackdrop)
 
		popupFrame = Instance.new("ScrollingFrame")
		popupFrame.CanvasSize = UDim2.fromOffset(0, 290)
		popupFrame.ScrollingDirection = Enum.ScrollingDirection.Y
		popupFrame.ScrollBarThickness = 3
		popupFrame.ScrollBarImageColor3 = SilentUI.Theme.TextDim
		popupFrame.ScrollBarImageTransparency = 0.35
		popupFrame.BorderSizePixel = 0
		popupFrame.Name = "ColorPickerPopup"
		popupFrame.Active = true
		popupFrame.BackgroundColor3 = SilentUI.Theme.Background
		popupFrame.BackgroundTransparency = 1
		popupFrame.BorderSizePixel = 0
		popupFrame.ClipsDescendants = true
		popupFrame.ZIndex = Z.Popup
		popupFrame.Size = UDim2.new(0, popupW, 0, 0)
		popupFrame.Parent = root
		popupFrame:SetAttribute("SilentInterfacePanel", true)
		if self._window then popupFrame:SetAttribute("SilentWindowId", self._window._id) end
		Corner(popupFrame, 10)
		local popupStroke = Stroke(popupFrame, SilentUI.Theme.Border, 1, 0.92)
		Private.GlassLayer(popupFrame, 10, 0.985)
 
		local px, py = Private.ComputePopupPosition(mainWindow, card, popupW, popupH)
		popupFrame.Position = UDim2.fromOffset(px, py)
 
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 14)
		pad.PaddingBottom = UDim.new(0, 14)
		pad.PaddingLeft = UDim.new(0, 14)
		pad.PaddingRight = UDim.new(0, 14)
		pad.Parent = popupFrame
 
		local innerW = popupW - 28
 
		svBox = Instance.new("Frame")
		svBox.Name = "ColorSpectrum"
		svBox:SetAttribute("SilentThemeExempt", true)
		svBox.Active = true
		svBox.Position = UDim2.fromOffset(0, 0)
		svBox.Size = UDim2.fromOffset(innerW, 104)
		svBox.BackgroundColor3 = Color3.new(1, 1, 1)
		svBox.BorderSizePixel = 0
		svBox.ClipsDescendants = true
		svBox.ZIndex = Z.Popup + 1
		svBox.Parent = popupFrame
		Corner(svBox, 8)
 
		satGradient = Instance.new("UIGradient")
		satGradient.Name = "ColorSpectrumGradient"
		satGradient:SetAttribute("SilentThemeExempt", true)
		satGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1))
		satGradient.Parent = svBox
 
		local valOverlay = Instance.new("Frame")
		valOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
		valOverlay.BorderSizePixel = 0
		valOverlay.Size = UDim2.fromScale(1, 1)
		valOverlay.ZIndex = Z.Popup + 1
		valOverlay.Parent = svBox
		local valGradient = Instance.new("UIGradient")
		valGradient.Rotation = 90
		valGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		valGradient.Parent = valOverlay
 
		local svCursorLayer = Instance.new("Frame")
		svCursorLayer.BackgroundTransparency = 1
		svCursorLayer.BorderSizePixel = 0
		svCursorLayer.ClipsDescendants = false
		svCursorLayer.Position = svBox.Position
		svCursorLayer.Size = svBox.Size
		svCursorLayer.ZIndex = Z.Popup + 2
		svCursorLayer.Parent = popupFrame
 
		svCursor = Instance.new("Frame")
		svCursor.AnchorPoint = Vector2.new(0.5, 0.5)
		svCursor.Position = UDim2.new(sat, 0, 1 - val, 0)
		svCursor.Size = UDim2.fromOffset(16, 16)
		svCursor.BackgroundTransparency = 1
		svCursor.ZIndex = Z.Popup + 3
		svCursor.Parent = svCursorLayer
		Corner(svCursor, 8)
		Stroke(svCursor, Color3.new(0, 0, 0), 2, 0.15)
 
		local svCursorInner = Instance.new("Frame")
		svCursorInner.AnchorPoint = Vector2.new(0.5, 0.5)
		svCursorInner.Position = UDim2.fromScale(0.5, 0.5)
		svCursorInner.Size = UDim2.fromOffset(11, 11)
		svCursorInner.BackgroundTransparency = 1
		svCursorInner.ZIndex = Z.Popup + 4
		svCursorInner.Parent = svCursor
		Corner(svCursorInner, 6)
		Stroke(svCursorInner, SilentUI.Theme.Border, 2, 0)
 
		hueBar = Instance.new("Frame")
		hueBar.Name = "HueSpectrum"
		hueBar:SetAttribute("SilentThemeExempt", true)
		hueBar.Active = true
		hueBar.Position = UDim2.fromOffset(0, 114)
		hueBar.Size = UDim2.fromOffset(innerW, 10)
		hueBar.BackgroundColor3 = Color3.new(1, 1, 1)
		hueBar.BorderSizePixel = 0
		hueBar.ClipsDescendants = true
		hueBar.ZIndex = Z.Popup + 1
		hueBar.Parent = popupFrame
		Corner(hueBar, 5)
 
		local hueGradient = Instance.new("UIGradient")
		hueGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.000, Color3.fromHSV(0.000, 1, 1)),
			ColorSequenceKeypoint.new(0.166, Color3.fromHSV(0.166, 1, 1)),
			ColorSequenceKeypoint.new(0.333, Color3.fromHSV(0.333, 1, 1)),
			ColorSequenceKeypoint.new(0.500, Color3.fromHSV(0.500, 1, 1)),
			ColorSequenceKeypoint.new(0.666, Color3.fromHSV(0.666, 1, 1)),
			ColorSequenceKeypoint.new(0.833, Color3.fromHSV(0.833, 1, 1)),
			ColorSequenceKeypoint.new(1.000, Color3.fromHSV(1.000, 1, 1)),
		})
		hueGradient.Parent = hueBar
 
		local hueCursorLayer = Instance.new("Frame")
		hueCursorLayer.BackgroundTransparency = 1
		hueCursorLayer.BorderSizePixel = 0
		hueCursorLayer.ClipsDescendants = false
		hueCursorLayer.Position = hueBar.Position
		hueCursorLayer.Size = hueBar.Size
		hueCursorLayer.ZIndex = Z.Popup + 2
		hueCursorLayer.Parent = popupFrame
 
		hueCursor = Instance.new("Frame")
		hueCursor.Name = "HueCursor"
		hueCursor:SetAttribute("SilentThemeExempt", true)
		hueCursor.AnchorPoint = Vector2.new(0.5, 0.5)
		hueCursor.Position = UDim2.new(hue, 0, 0.5, 0)
		hueCursor.Size = UDim2.fromOffset(6, 10)
		hueCursor.BackgroundColor3 = Color3.new(1, 1, 1)
		hueCursor.BorderSizePixel = 0
		hueCursor.ZIndex = Z.Popup + 3
		hueCursor.Parent = hueCursorLayer
		Corner(hueCursor, 3)
		Stroke(hueCursor, Color3.new(0, 0, 0), 1, 0.4)
 
		local hexHolder, hexRef = Private.MiniField(popupFrame, "HEX", innerW, Z.Popup)
		hexHolder.Position = UDim2.fromOffset(0, 136)
		hexBox = hexRef
 
		local rgbRow = Instance.new("Frame")
		rgbRow.BackgroundTransparency = 1
		rgbRow.Position = UDim2.fromOffset(0, 182)
		rgbRow.Size = UDim2.fromOffset(innerW, 36)
		rgbRow.ZIndex = Z.Popup + 1
		rgbRow.Parent = popupFrame
 
		local rHolder, rRef = Private.MiniField(rgbRow, "R", 54, Z.Popup)
		rHolder.Position = UDim2.fromOffset(0, 0)
		rBox = rRef
 
		local gHolder, gRef = Private.MiniField(rgbRow, "G", 54, Z.Popup)
		gHolder.Position = UDim2.fromOffset(62, 0)
		gBox = gRef
 
		local bHolder, bRef = Private.MiniField(rgbRow, "B", 56, Z.Popup)
		bHolder.Position = UDim2.fromOffset(124, 0)
		bBox = bRef
 
		local btnRow = Instance.new("Frame")
		btnRow.BackgroundTransparency = 1
		btnRow.Position = UDim2.fromOffset(0, 232)
		btnRow.Size = UDim2.fromOffset(innerW, 30)
		btnRow.ZIndex = Z.Popup + 1
		btnRow.Parent = popupFrame
 
		local function MakeButton(text, x, w, filled)
			local btn = Instance.new("TextButton")
			btn.Position = UDim2.fromOffset(x, 0)
			btn.Size = UDim2.fromOffset(w, 30)
			btn.FontFace = SilentUI.Theme.Font
			btn.Text = text
			btn.TextSize = 13
			btn.AutoButtonColor = false
			btn.BorderSizePixel = 0
			btn.ZIndex = Z.Popup + 2
			if filled then
				btn.BackgroundColor3 = SilentUI.Theme.Accent
				btn.BackgroundTransparency = 0
				btn.TextColor3 = SilentUI.Theme.Background
			else
				btn.BackgroundColor3 = SilentUI.Theme.Surface
				btn.BackgroundTransparency = 0.92
				btn.TextColor3 = SilentUI.Theme.Text
			end
			btn.Parent = btnRow
			Corner(btn, 8)
			if not filled then Stroke(btn, SilentUI.Theme.Border, 1, 0.88) end
			return btn
		end
 
		local halfW = (innerW - 10) / 2
		local cancelBtn = MakeButton("Cancel", 0, halfW, false)
		local doneBtn   = MakeButton("Done", halfW + 10, halfW, true)
 
		cancelBtn.Activated:Connect(function()
			hue, sat, val = originalHue, originalSat, originalVal
			applyColor(true)
			closePopup()
		end)
		doneBtn.Activated:Connect(closePopup)
 
		svBox.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				if draggingSV or draggingHue then return end
				draggingSV = true
				colorInput = input
				updateSV(input.Position)
			end
		end)
 
		hueBar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				if draggingSV or draggingHue then return end
				draggingHue = true
				colorInput = input
				updateHue(input.Position)
			end
		end)
 
		hexBox:GetPropertyChangedSignal("Text"):Connect(function()
			local filtered = hexBox.Text:gsub("[^%x]", "")
			filtered = filtered:sub(1, 6)
			if filtered ~= hexBox.Text then hexBox.Text = filtered end
		end)
 
		hexBox.FocusLost:Connect(function()
			local clean = hexBox.Text:gsub("#", "")
			if #clean == 3 then
				clean = clean:sub(1, 1):rep(2) .. clean:sub(2, 2):rep(2) .. clean:sub(3, 3):rep(2)
			end
			if #clean == 6 then
				local ok, c = pcall(Color3.fromHex, clean)
				if ok and c then
					hue, sat, val = Color3.toHSV(c)
					applyColor(true)
					return
				end
			end
			syncFields()
		end)
 
		local function filterDigits(b)
			b:GetPropertyChangedSignal("Text"):Connect(function()
				local filtered = b.Text:gsub("%D", ""):sub(1, 3)
				if filtered ~= b.Text then b.Text = filtered end
			end)
		end
		filterDigits(rBox); filterDigits(gBox); filterDigits(bBox)
 
		local function onRGBCommit()
			local r = math.clamp(tonumber(rBox.Text) or 0, 0, 255)
			local g = math.clamp(tonumber(gBox.Text) or 0, 0, 255)
			local b = math.clamp(tonumber(bBox.Text) or 0, 0, 255)
			hue, sat, val = Color3.toHSV(Color3.fromRGB(r, g, b))
			applyColor(true)
		end
		rBox.FocusLost:Connect(onRGBCommit)
		gBox.FocusLost:Connect(onRGBCommit)
		bBox.FocusLost:Connect(onRGBCommit)
 
		syncFields()
 
		Tween(popupFrame, {
			Size = UDim2.new(0, popupW, 0, popupH),
			BackgroundTransparency = self._window and self._window._interfaceTransparency or 0.15,
		}, 0.44, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		Tween(popupStroke, { Transparency = 0.85 }, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
		followConn = RunService.RenderStepped:Connect(function()
			if not popupFrame or not card.Parent then return end
			local nx, ny = Private.ComputePopupPosition(mainWindow, card, popupW, popupH)
			popupFrame.Position = UDim2.fromOffset(nx, ny)
		end)
		jan:Add(followConn)
	end
 
	click.MouseButton1Click:Connect(function()
		if popupOpen then closePopup() else openPopup() end
	end)
 
	card.MouseEnter:Connect(function() Tween(card, { BackgroundTransparency = 0.93 }, 0.15) end)
	card.MouseLeave:Connect(function() Tween(card, { BackgroundTransparency = 0.96 }, 0.15) end)
 
	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, c, silent)
			hue, sat, val = Color3.toHSV(c)
			applyColor(not silent)
			if silent then lastFired = currentColor() end
		end,
		Get = function() return currentColor() end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() closePopup(); signal.Clear(); card:Destroy() end,
	}, "ColorPicker")
end
 
function Tab:AddKeybind(opts)
	opts = opts or {}
	local modeOrder = { "Toggle", "Hold", "Always" }
	local modeNames = { Toggle = "TGL", Hold = "HLD", Always = "ALW" }
	local mode = opts.Mode or "Toggle"
	assert(table.find(modeOrder, mode), "Keybind Mode must be Toggle, Hold, or Always")
	local currentKey, keyErr = Private.ResolveKeybindKey(opts.Default)
	assert(not keyErr, "Keybind Default " .. tostring(keyErr))
	local context = opts.Context or "global"
	assert(type(context) == "string" and context:gsub("%s", "") ~= "", "Keybind Context must be a non-empty string")
	local defaultKey, defaultMode, defaultContext = currentKey, mode, context
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local jan = self._janitor

	local card = BaseCard(self._page, height)
	local textX = AddLeadingIcon(card, opts.Icon, height)
	AddTitleDesc(card, textX, 128, opts.Text or "Keybind", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Keybind", card)

	local pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(1, 0.5)
	pill.Position = UDim2.new(1, -14, 0.5, 0)
	pill.Size = UDim2.fromOffset(138, 28)
	pill.BackgroundColor3 = SilentUI.Theme.Surface
	pill.BackgroundTransparency = 0.9
	pill.BorderSizePixel = 0
	pill.ZIndex = Z.Content + 2
	pill.Parent = card
	Corner(pill, 8)
	local pillStroke = Stroke(pill, SilentUI.Theme.Border, 1, 0.88)

	local keyIcon = Instance.new("ImageLabel")
	keyIcon.BackgroundTransparency = 1
	keyIcon.Image = ResolveIcon("keyboard")
	keyIcon.ImageColor3 = SilentUI.Theme.TextDim
	keyIcon.Size = UDim2.fromOffset(13, 13)
	keyIcon.AnchorPoint = Vector2.new(0, 0.5)
	keyIcon.Position = UDim2.new(0, 9, 0.5, 0)
	keyIcon.ZIndex = Z.Content + 3
	keyIcon.Parent = pill

	local keyLabel = Instance.new("TextLabel")
	keyLabel.BackgroundTransparency = 1
	keyLabel.FontFace = SilentUI.Theme.FontRegular
	keyLabel.Text = Private.KeybindLabel(currentKey)
	keyLabel.TextColor3 = SilentUI.Theme.Text
	keyLabel.TextSize = 13
	keyLabel.TextTruncate = Enum.TextTruncate.AtEnd
	keyLabel.TextXAlignment = Enum.TextXAlignment.Left
	keyLabel.Position = UDim2.fromOffset(28, 0)
	keyLabel.Size = UDim2.new(1, -82, 1, 0)
	keyLabel.ZIndex = Z.Content + 3
	keyLabel.Parent = pill

	local keyButton = Instance.new("TextButton")
	keyButton.Name = "KeyCapture"
	keyButton.Text = ""
	keyButton.AutoButtonColor = false
	keyButton.BackgroundTransparency = 1
	keyButton.Size = UDim2.new(1, -48, 1, 0)
	keyButton.ZIndex = Z.Content + 4
	keyButton.Parent = pill

	local modeButton = Instance.new("TextButton")
	modeButton.Name = "ModeSelector"
	modeButton.AutoButtonColor = false
	modeButton.BackgroundColor3 = SilentUI.Theme.Surface
	modeButton.BackgroundTransparency = 0.58
	modeButton.BorderSizePixel = 0
	modeButton.Position = UDim2.new(1, -43, 0, 4)
	modeButton.Size = UDim2.new(0, 39, 1, -8)
	modeButton.Text = modeNames[mode]
	modeButton.TextColor3 = SilentUI.Theme.TextDim
	modeButton.TextSize = 10
	modeButton.FontFace = SilentUI.Theme.Font
	modeButton.ZIndex = Z.Content + 4
	modeButton.Parent = pill
	Corner(modeButton, 5)

	local listening, holdActive, toggleActive = false, false, false
	local warnedMissingToggle = false
	local listenConn, modePopup, modeBackdrop = nil, nil, nil
	local signal, pressedSignal, stateSignal = MakeSignal(), MakeSignal(), MakeSignal()
	local modeSignal, contextSignal = MakeSignal(), MakeSignal()
	local api
	local control = {
		key = currentKey,
		mode = mode,
		context = context,
		stroke = pillStroke,
		listening = false,
		destroyed = false,
		label = opts.Text or "Keybind",
	}

	local function updateKeyVisual()
		keyLabel.Text = listening and "..." or Private.KeybindLabel(currentKey)
		modeButton.Text = modeNames[mode]
	end

	local function setToggleFlag(value, silent)
		if not opts.ToggleFlag then return false end
		local toggle = SilentUI.Flags[opts.ToggleFlag]
		if not toggle or toggle.Kind ~= "Toggle" then
			if not warnedMissingToggle then
				warnedMissingToggle = true
				warn("[SilentUI] Keybind ToggleFlag is not a registered Toggle: " .. tostring(opts.ToggleFlag))
			end
			return false
		end
		local previousSource = SilentUI._ChangeSource
		if previousSource == nil then SilentUI._ChangeSource = silent and "code" or "user" end
		local ok, err = pcall(toggle.Set, toggle, value == true, silent == true)
		SilentUI._ChangeSource = previousSource
		if not ok then warn("[SilentUI] Keybind could not update ToggleFlag: " .. tostring(err)) end
		return ok
	end

	local function getActive()
		if opts.ToggleFlag then
			local toggle = SilentUI.Flags[opts.ToggleFlag]
			if toggle and toggle.Kind == "Toggle" then
				local ok, value = pcall(toggle.Get, toggle)
				if ok then return value == true end
			end
		end
		if mode == "Always" then return true end
		if mode == "Hold" then return holdActive end
		if mode == "Toggle" then return toggleActive end
		return false
	end

	local function runWithCodeSource(callback)
		local previousSource = SilentUI._ChangeSource
		if previousSource == nil then SilentUI._ChangeSource = "code" end
		local result = table.pack(pcall(callback))
		SilentUI._ChangeSource = previousSource
		if not result[1] then error(result[2], 3) end
		return table.unpack(result, 2, result.n)
	end

	local function fireChanged(key, source)
		local info = ChangeInfo("bind")
		info.Key = key
		if source then info.Source = source end
		if opts.Callback then task.spawn(opts.Callback, key, "bind", info) end
		signal.Fire(key, info)
		stateSignal.Fire(api, info)
	end

	local function fireStateChanged(action)
		local info = ChangeInfo(action)
		info.Mode, info.Context, info.State = mode, context, getActive()
		stateSignal.Fire(api, info)
	end

	local function firePress(action, state)
		local info = ChangeInfo(action)
		info.State, info.Mode, info.Context = state, mode, context
		if opts.Callback then task.spawn(opts.Callback, currentKey, action, info) end
		pressedSignal.Fire(currentKey, info)
	end

	local function releaseHold(silent)
		if not holdActive then return end
		holdActive = false
		control.holdActive = false
		if opts.ToggleFlag then setToggleFlag(false, silent) end
		if not silent then
			firePress("release", false)
			fireStateChanged("active")
		end
	end
	control.releaseHold = releaseHold

	local function applyMode(nextMode, silent, source)
		assert(table.find(modeOrder, nextMode), "Keybind Mode must be Toggle, Hold, or Always")
		if mode == nextMode then return false end
		local previous = mode
		if previous == "Hold" then
			releaseHold(silent)
		elseif previous == "Toggle" and nextMode == "Hold" then
			toggleActive = false
			if opts.ToggleFlag then setToggleFlag(false, silent) end
		end
		mode = nextMode
		control.mode = mode
		if api then api.Mode = mode end
		if mode == "Always" then
			if opts.ToggleFlag then setToggleFlag(true, silent) else toggleActive = true end
		elseif previous == "Always" and mode ~= "Toggle" then
			if opts.ToggleFlag then setToggleFlag(false, silent) else toggleActive = false end
		end
		updateKeyVisual()
		if not silent then
			local info = ChangeInfo("mode")
			info.Previous, info.Mode = previous, mode
			if source then info.Source = source end
			modeSignal.Fire(mode, info)
			stateSignal.Fire(api, info)
		end
		RefreshKeybindConflicts()
		return true
	end

	local function applyContext(nextContext, silent, source)
		assert(type(nextContext) == "string" and nextContext:gsub("%s", "") ~= "", "Keybind Context must be a non-empty string")
		if context == nextContext then return false end
		local previous = context
		context = nextContext
		control.context = context
		if api then api.Context = context end
		if holdActive and not KeybindContextActive(context) then releaseHold(silent) end
		if not silent then
			local info = ChangeInfo("context")
			info.Previous, info.Context = previous, context
			if source then info.Source = source end
			contextSignal.Fire(context, info)
			stateSignal.Fire(api, info)
		end
		RefreshKeybindConflicts()
		return true
	end

	local function setKey(nextKey, silent)
		if currentKey == nextKey then return false end
		releaseHold(silent)
		currentKey = nextKey
		control.key = currentKey
		updateKeyVisual()
		RefreshKeybindConflicts()
		if not silent then fireChanged(currentKey) end
		return true
	end

	local function pressKey()
		if mode == "Hold" then
			if holdActive then return end
			holdActive = true
			control.holdActive = true
			if opts.ToggleFlag then setToggleFlag(true) end
			firePress("press", true)
			fireStateChanged("active")
		elseif mode == "Toggle" then
			local active = not getActive()
			if opts.ToggleFlag then setToggleFlag(active) else toggleActive = active end
			firePress("press", active)
			fireStateChanged("active")
		end
	end
	control.pressKey = pressKey

	local function stopListening()
		if not listening then return end
		listening = false
		control.listening = false
		if Private.KeybindCaptureStop == stopListening then Private.KeybindCaptureStop = nil end
		KeybindCapturing = false
		if listenConn then listenConn:Disconnect(); listenConn = nil end
		Tween(pillStroke, { Color = SilentUI.Theme.Border, Transparency = 0.88 }, 0.15)
		Tween(pill, { BackgroundTransparency = 0.9 }, 0.15)
		updateKeyVisual()
		RefreshKeybindConflicts()
	end

	local function startListening()
		if listening then return end
		if Private.KeybindCaptureStop then Private.KeybindCaptureStop() end
		releaseHold()
		listening = true
		control.listening = true
		KeybindCapturing = true
		Private.KeybindCaptureStop = stopListening
		updateKeyVisual()
		Tween(pillStroke, { Color = SilentUI.Theme.Accent, Transparency = 0.3 }, 0.15)
		Tween(pill, { BackgroundTransparency = 0.82 }, 0.15)
		RefreshKeybindConflicts()

		listenConn = UserInputService.InputBegan:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Escape then
				stopListening()
				return
			end
			if input.UserInputType == Enum.UserInputType.Keyboard
				and (input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete) then
				setKey(nil)
				stopListening()
				return
			end
			local pressed = KeybindInputKey(input)
			if not pressed then return end
			setKey(pressed)
			stopListening()
		end)
		jan:Add(listenConn)
	end

	local function closeModePopup()
		Private.RegisterPopupClose(closeModePopup)
		if modeBackdrop then modeBackdrop:Destroy(); modeBackdrop = nil end
		if modePopup then modePopup:Destroy(); modePopup = nil end
	end

	local function openModePopup()
		if modePopup then closeModePopup(); return end
		Private.CloseAnyOpenPopup()
		Private.RegisterPopupOpen(closeModePopup)
		modeBackdrop = Private.MakePopupBackdrop(closeModePopup)
		local root, scale = SilentUI._Root, GetUIScale()
		local view = Private.ViewportSize()
		local popupW, rowH, pad = 142, 30, 6
		local popupH = pad * 2 + #modeOrder * rowH
		local anchorPos, anchorSize = modeButton.AbsolutePosition, modeButton.AbsoluteSize
		local px = (anchorPos.X + anchorSize.X) / scale - popupW
		local py = (anchorPos.Y + anchorSize.Y) / scale + 5
		px = SafeClamp(px, 8, view.X / scale - popupW - 8)
		py = SafeClamp(py, 8, view.Y / scale - popupH - 8)
		modePopup = Instance.new("Frame")
		modePopup.Name = "KeybindModePopup"
		modePopup.Active = true
		modePopup.BackgroundColor3 = SilentUI.Theme.Background
		modePopup.BackgroundTransparency = 0.04
		modePopup.BorderSizePixel = 0
		modePopup.Position = UDim2.fromOffset(math.round(px), math.round(py))
		modePopup.Size = UDim2.fromOffset(popupW, popupH)
		modePopup.ZIndex = Z.Popup
		modePopup.Parent = root
		modePopup:SetAttribute("SilentInterfacePanel", true)
		if self._window then modePopup:SetAttribute("SilentWindowId", self._window._id) end
		Corner(modePopup, 9)
		Stroke(modePopup, SilentUI.Theme.Border, 1, 0.9)

		for index, option in ipairs(modeOrder) do
			local button = Instance.new("TextButton")
			button.Name = option
			button.AutoButtonColor = false
			button.BackgroundColor3 = SilentUI.Theme.Surface
			button.BackgroundTransparency = option == mode and 0.78 or 1
			button.BorderSizePixel = 0
			button.Position = UDim2.fromOffset(pad, pad + (index - 1) * rowH)
			button.Size = UDim2.new(1, -pad * 2, 0, rowH - 2)
			button.Text = ""
			button.ZIndex = Z.Popup + 1
			button.Parent = modePopup
			Corner(button, 6)
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.FontFace = SilentUI.Theme.FontRegular
			label.Text = option
			label.TextColor3 = option == mode and SilentUI.Theme.Text or SilentUI.Theme.TextDim
			label.TextSize = 12
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.Position = UDim2.fromOffset(9, 0)
			label.Size = UDim2.new(1, -18, 1, 0)
			label.ZIndex = Z.Popup + 2
			label.Parent = button
			button.MouseEnter:Connect(function()
				if modePopup then Tween(button, { BackgroundTransparency = 0.78 }, 0.1) end
			end)
			button.MouseLeave:Connect(function()
				if modePopup then Tween(button, { BackgroundTransparency = option == mode and 0.78 or 1 }, 0.1) end
			end)
			button.MouseButton1Click:Connect(function()
				applyMode(option, false, "user")
				closeModePopup()
			end)
		end
	end

	keyButton.MouseButton1Click:Connect(startListening)
	keyButton.MouseButton2Click:Connect(openModePopup)
	modeButton.MouseButton1Click:Connect(openModePopup)
	card.MouseEnter:Connect(function() Tween(card, { BackgroundTransparency = 0.93 }, 0.15) end)
	card.MouseLeave:Connect(function() Tween(card, { BackgroundTransparency = 0.96 }, 0.15) end)

	api = {
		Instance = card,
		Kind = "Keybind",
		Mode = mode,
		Context = context,
		ToggleFlag = opts.ToggleFlag,
		Set = function(_, value, silent)
			return runWithCodeSource(function()
				local nextKey, nextMode, nextContext, nextActive
				local activeSpecified = false
				if type(value) == "table" then
					local rawKey = value.key
					if rawKey == nil then rawKey = value.Key end
					if rawKey ~= nil then
						local key, err = Private.ResolveKeybindKey(rawKey)
						assert(not err, "Keybind value " .. tostring(err))
						nextKey = key
					end
					nextMode = value.mode or value.Mode
					if nextMode == "Press" then
						nextMode, nextActive, activeSpecified = "Toggle", false, true
					else
						nextActive = value.active
						if nextActive == nil then nextActive = value.Active end
						activeSpecified = nextActive ~= nil
					end
					nextContext = value.context or value.Context
					if nextMode ~= nil then assert(table.find(modeOrder, nextMode), "Keybind Mode must be Toggle, Hold, or Always") end
					if nextContext ~= nil then assert(type(nextContext) == "string" and nextContext:gsub("%s", "") ~= "", "Keybind Context must be a non-empty string") end
					if activeSpecified then assert(type(nextActive) == "boolean", "Keybind active state must be a boolean") end
				else
					local key, err = Private.ResolveKeybindKey(value)
					assert(not err, "Keybind value " .. tostring(err))
					nextKey = key
				end
				if nextMode then applyMode(nextMode, silent == true) end
				if nextContext then applyContext(nextContext, silent == true) end
				if nextKey ~= nil or value == nil or (type(value) == "table" and (value.key ~= nil or value.Key ~= nil)) then
					setKey(nextKey, silent == true)
				end
				if activeSpecified then
					if mode == "Toggle" then
						if opts.ToggleFlag then setToggleFlag(nextActive, silent == true) else toggleActive = nextActive end
					elseif mode == "Always" then
						if opts.ToggleFlag then setToggleFlag(true, silent == true) else toggleActive = true end
					end
				elseif mode == "Always" and opts.ToggleFlag then
					setToggleFlag(true, silent == true)
				end
				if activeSpecified and mode == "Hold" then releaseHold(silent == true) end
				if activeSpecified and not silent then fireStateChanged("active") end
			end)
		end,
		Get = function() return currentKey end,
		GetState = function()
			return { key = currentKey or "NONE", mode = mode, context = context, active = getActive() }
		end,
		GetActive = getActive,
		GetMode = function() return mode end,
		GetContext = function() return context end,
		SetMode = function(_, value, silent)
			return runWithCodeSource(function() return applyMode(value, silent == true) end)
		end,
		SetContext = function(_, value, silent)
			return runWithCodeSource(function() return applyContext(value, silent == true) end)
		end,
		SetActive = function(_, value, silent)
			return runWithCodeSource(function()
				assert(type(value) == "boolean", "Keybind active state must be a boolean")
				if mode == "Toggle" then
					if opts.ToggleFlag then setToggleFlag(value, silent == true) else toggleActive = value end
				elseif mode == "Always" then
					if not value then return false, "Always mode cannot be deactivated" end
					if opts.ToggleFlag then setToggleFlag(true, silent == true) else toggleActive = true end
				else
					return false, "active state can only be set in Toggle or Always mode"
				end
				if not silent then fireStateChanged("active") end
				return true
			end)
		end,
		Rebind = function(_, key) return api:Set(key) end,
		Unbind = function() return api:Set(nil) end,
		Reset = function()
			return api:Set({
				key = defaultKey or "NONE",
				mode = defaultMode,
				context = defaultContext,
			})
		end,
		GetConflicts = function()
			local conflicts = {}
			for _, other in ipairs(KeybindControls) do
				if Private.KeybindConflicts(control, other) then table.insert(conflicts, other.api or other) end
			end
			return conflicts
		end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		OnStateChanged = function(_, fn) return stateSignal.Connect(fn) end,
		OnPressed = function(_, fn) return pressedSignal.Connect(fn) end,
		OnModeChanged = function(_, fn) return modeSignal.Connect(fn) end,
		OnContextChanged = function(_, fn) return contextSignal.Connect(fn) end,
		Destroy = function()
			if control.destroyed then return end
			control.destroyed = true
			releaseHold(true)
			stopListening()
			closeModePopup()
			local index = table.find(KeybindControls, control)
			if index then table.remove(KeybindControls, index) end
			signal.Clear()
			pressedSignal.Clear()
			stateSignal.Clear()
			modeSignal.Clear()
			contextSignal.Clear()
			card:Destroy()
			RefreshKeybindConflicts()
		end,
	}
	control.api = api
	api = RegisterFlag(opts, api, "Keybind")
	table.insert(KeybindControls, control)
	RefreshKeybindConflicts()

	if not Private.KeybindInputHandlersInstalled then
		Private.KeybindInputHandlersInstalled = true
		LibJanitor:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if KeybindCapturing or gameProcessed or UserInputService:GetFocusedTextBox() then return end
			local pressed = KeybindInputKey(input)
			if not pressed then return end
			local matches = {}
			for _, item in ipairs(KeybindControls) do
				if not item.destroyed and not item.listening and item.mode ~= "Always"
					and (not item.api or not item.api.Flag or SilentUI.Flags[item.api.Flag] == item.api)
					and item.key == pressed and KeybindContextActive(item.context) then
					table.insert(matches, item)
				end
			end
			if #matches == 1 then matches[1].pressKey() end
		end))
		LibJanitor:Add(UserInputService.InputEnded:Connect(function(input)
			local released = KeybindInputKey(input)
			if not released then return end
			for _, item in ipairs(KeybindControls) do
				if not item.destroyed and item.holdActive and item.key == released then item.releaseHold() end
			end
		end))
		LibJanitor:Add(UserInputService.WindowFocusReleased:Connect(function()
			if Private.KeybindCaptureStop then Private.KeybindCaptureStop() end
			for _, item in ipairs(KeybindControls) do
				if item.holdActive then item.releaseHold() end
			end
		end))
	end
	if mode == "Always" and opts.ToggleFlag then setToggleFlag(true, true) end

	jan:Add(function()
		if api and not control.destroyed then api:Destroy() end
	end)
	return api
end

function SilentUI:SetKeybindContext(context)
	assert(type(context) == "string" and context:gsub("%s", "") ~= "", "Keybind context must be a non-empty string")
	if ActiveKeybindContext == context then return true end
	ActiveKeybindContext = context
	for _, control in ipairs(KeybindControls) do
		if control.holdActive and not KeybindContextActive(control.context) then control.releaseHold() end
	end
	RefreshKeybindConflicts()
	return true
end

function SilentUI:GetKeybindContext()
	return ActiveKeybindContext
end
 
Private.ConsoleColors = {
	[Enum.MessageType.MessageInfo]    = Color3.fromRGB(120, 170, 255),
	[Enum.MessageType.MessageWarning] = Color3.fromRGB(255, 190, 90),
	[Enum.MessageType.MessageError]   = Color3.fromRGB(255, 105, 105),
	[Enum.MessageType.MessageOutput]  = nil,
}
 
function Tab:AddConsole(opts)
	opts = opts or {}
	local height = opts.Height or 200
	local maxLogs = opts.MaxLogs or 300
	local jan = self._janitor
 
	local container = Instance.new("Frame")
	container.Name = "Console"
	container.BackgroundColor3 = SilentUI.Theme.Surface
	container.BackgroundTransparency = 0.35
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Size = UDim2.new(1, 0, 0, height)
	container.ZIndex = Z.Content
	container.Parent = self._page
	Corner(container, SilentUI.Theme.CornerRadiusSm)
	Stroke(container, SilentUI.Theme.Border, 1, 0.92)
 
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 34)
	header.ZIndex = Z.Content + 1
	header.Parent = container
 
	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, 12)
	headerPad.PaddingRight = UDim.new(0, 8)
	headerPad.Parent = header
 
	local titleRow = Instance.new("Frame")
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, -70, 1, 0)
	titleRow.ZIndex = Z.Content + 2
	titleRow.Parent = header
 
	local titleLayout = Instance.new("UIListLayout")
	titleLayout.FillDirection = Enum.FillDirection.Horizontal
	titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleLayout.Padding = UDim.new(0, 7)
	titleLayout.Parent = titleRow
 
	local titleIcon = Instance.new("ImageLabel")
	titleIcon.BackgroundTransparency = 1
	titleIcon.Image = ResolveIcon("terminal")
	titleIcon.ImageColor3 = SilentUI.Theme.TextDim
	titleIcon.Size = UDim2.fromOffset(14, 14)
	titleIcon.LayoutOrder = 1
	titleIcon.ZIndex = Z.Content + 3
	titleIcon.Parent = titleRow
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = SilentUI.Theme.Font
	titleLabel.Text = opts.Title or "Debug Console"
	titleLabel.TextColor3 = SilentUI.Theme.Text
	titleLabel.TextSize = 13
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.AutomaticSize = Enum.AutomaticSize.X
	titleLabel.Size = UDim2.fromOffset(0, 14)
	titleLabel.LayoutOrder = 2
	titleLabel.ZIndex = Z.Content + 3
	titleLabel.Parent = titleRow
 
	local controls = Instance.new("Frame")
	controls.BackgroundTransparency = 1
	controls.AnchorPoint = Vector2.new(1, 0.5)
	controls.Position = UDim2.new(1, 0, 0.5, 0)
	controls.Size = UDim2.fromOffset(58, 24)
	controls.ZIndex = Z.Content + 2
	controls.Parent = header
 
	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.FillDirection = Enum.FillDirection.Horizontal
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlsLayout.Padding = UDim.new(0, 4)
	controlsLayout.Parent = controls
 
	local function iconButton(icon, order)
		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = SilentUI.Theme.Surface
		btn.BackgroundTransparency = 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.fromOffset(24, 24)
		btn.LayoutOrder = order
		btn.ZIndex = Z.Content + 3
		btn.Parent = controls
		Corner(btn, 7)
 
		local ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Image = ResolveIcon(icon)
		ic.ImageColor3 = SilentUI.Theme.TextDim
		ic.Size = UDim2.fromOffset(13, 13)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.ZIndex = Z.Content + 4
		ic.Parent = btn
 
		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = 0.9 }, 0.12)
			Tween(ic, { ImageColor3 = SilentUI.Theme.Text }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = 1 }, 0.12)
			Tween(ic, { ImageColor3 = SilentUI.Theme.TextDim }, 0.12)
		end))
 
		return btn, ic
	end
 
	local copyBtn, copyIcon = iconButton("copy", 1)
	local clearBtn = iconButton("trash-2", 2)
 
	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = SilentUI.Theme.Surface
	divider.BackgroundTransparency = 0.92
	divider.BorderSizePixel = 0
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.Position = UDim2.fromOffset(0, 34)
	divider.ZIndex = Z.Content + 1
	divider.Parent = container
 
	local logsScroll = Instance.new("ScrollingFrame")
	logsScroll.Name = "Logs"
	logsScroll.BackgroundTransparency = 1
	logsScroll.BorderSizePixel = 0
	logsScroll.Position = UDim2.fromOffset(0, 35)
	logsScroll.Size = UDim2.new(1, 0, 1, -35)
	logsScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	logsScroll.ScrollBarThickness = 0
	logsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	logsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	logsScroll.ZIndex = Z.Content + 1
	logsScroll.Parent = container
 
	local logsPad = Instance.new("UIPadding")
	logsPad.PaddingTop = UDim.new(0, 8)
	logsPad.PaddingBottom = UDim.new(0, 8)
	logsPad.PaddingLeft = UDim.new(0, 10)
	logsPad.PaddingRight = UDim.new(0, 10)
	logsPad.Parent = logsScroll
 
	local logsLayout = Instance.new("UIListLayout")
	logsLayout.Padding = UDim.new(0, 4)
	logsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	logsLayout.Parent = logsScroll
 
	AddScrollbar(logsScroll)
	Private.AddContentScrollThumb(logsScroll, logsLayout, container, jan)
 
	local emptyState = Instance.new("Frame")
	emptyState.Name = "EmptyState"
	emptyState.BackgroundTransparency = 1
	emptyState.Position = UDim2.fromOffset(0, 35)
	emptyState.Size = UDim2.new(1, 0, 1, -35)
	emptyState.ZIndex = Z.Content + 2
	emptyState.Parent = container
 
	local emptyLayout = Instance.new("UIListLayout")
	emptyLayout.FillDirection = Enum.FillDirection.Vertical
	emptyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	emptyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	emptyLayout.Padding = UDim.new(0, 6)
	emptyLayout.Parent = emptyState
 
	local emptyIcon = Instance.new("ImageLabel")
	emptyIcon.BackgroundTransparency = 1
	emptyIcon.Image = ResolveIcon("frown")
	emptyIcon.ImageColor3 = SilentUI.Theme.TextDim
	emptyIcon.Size = UDim2.fromOffset(22, 22)
	emptyIcon.LayoutOrder = 1
	emptyIcon.ZIndex = Z.Content + 3
	emptyIcon.Parent = emptyState
 
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.FontFace = SilentUI.Theme.FontRegular
	emptyLabel.Text = "No logs at the moment"
	emptyLabel.TextColor3 = SilentUI.Theme.TextDim
	emptyLabel.TextSize = 12
	emptyLabel.AutomaticSize = Enum.AutomaticSize.XY
	emptyLabel.Size = UDim2.fromOffset(0, 14)
	emptyLabel.LayoutOrder = 2
	emptyLabel.ZIndex = Z.Content + 3
	emptyLabel.Parent = emptyState
 
	local logs = {}
	local logCount = 0
	local counter = 0
	local autoScroll = true
 
	local function trimLogs()
		while logCount > maxLogs do
			local oldest = table.remove(logs, 1)
			if oldest then
				oldest:Destroy()
				logCount = logCount - 1
			else
				break
			end
		end
	end
 
	local function escapeRich(text)
		return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
	end
 
	local function addLog(message, messageType)
		message = tostring(message or "")
		if message == "" then return end
		trimLogs()
 
		counter = counter + 1
		local color = Private.ConsoleColors[messageType] or SilentUI.Theme.Text
 
		local entry = Instance.new("TextLabel")
		entry.Name = "Entry"
		entry.BackgroundTransparency = 1
		entry.RichText = true
		entry.FontFace = SilentUI.Theme.FontRegular
		entry.TextSize = 12
		entry.TextWrapped = true
		entry.TextXAlignment = Enum.TextXAlignment.Left
		entry.TextYAlignment = Enum.TextYAlignment.Top
		entry.LineHeight = 1.25
		entry.AutomaticSize = Enum.AutomaticSize.Y
		entry.Size = UDim2.new(1, 0, 0, 14)
		entry.LayoutOrder = counter
		entry.ZIndex = Z.Content + 2
		entry.Text = string.format(
			'<font color="#%s" transparency="0.45">[%s]</font> <font color="#%s">%s</font>',
			SilentUI.Theme.TextDim:ToHex(), os.date("%H:%M:%S"),
			color:ToHex(), escapeRich(message)
		)
		entry.Parent = logsScroll
 
		table.insert(logs, entry)
		logCount = logCount + 1
		emptyState.Visible = false
 
		if autoScroll then
			task.defer(function()
				logsScroll.CanvasPosition = Vector2.new(0, logsScroll.AbsoluteCanvasSize.Y)
			end)
		end
	end
 
	jan:Add(logsScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local atBottom = logsScroll.CanvasPosition.Y >= logsScroll.AbsoluteCanvasSize.Y - logsScroll.AbsoluteWindowSize.Y - 20
		autoScroll = atBottom
	end))
 
	copyBtn.MouseButton1Click:Connect(function()
		local setclipboard = hasFn("setclipboard")
		if not setclipboard then return end
 
		local lines = {}
		for _, entry in ipairs(logs) do
			local clean = entry.Text
				:gsub('<font[^>]*>', "")
				:gsub("</font>", "")
				:gsub("&lt;", "<")
				:gsub("&gt;", ">")
				:gsub("&amp;", "&")
			table.insert(lines, clean)
		end
		setclipboard(table.concat(lines, "\n"))
 
		Tween(copyIcon, { ImageColor3 = Color3.fromRGB(120, 220, 140) }, 0.1)
		task.delay(0.4, function()
			if copyIcon.Parent then
				Tween(copyIcon, { ImageColor3 = SilentUI.Theme.TextDim }, 0.15)
			end
		end)
	end)
 
	local function clearLogs()
		for _, entry in ipairs(logs) do
			entry:Destroy()
		end
		table.clear(logs)
		logCount = 0
		emptyState.Visible = true
	end
 
	clearBtn.MouseButton1Click:Connect(clearLogs)
 
	if opts.AutoCapture ~= false then
		local LogService = game:GetService("LogService")
		jan:Add(LogService.MessageOut:Connect(addLog))
	end
 
	return {
		Instance = container,
		Log = function(_, message, messageType) addLog(message, messageType) end,
		Clear = function() clearLogs() end,
		Destroy = function() container:Destroy() end,
	}
end
 
function Tab:AddTable(opts)
	opts = opts or {}
	local jan = self._janitor
	local title = opts.Title or "Table"
	local hasDesc = opts.Description and opts.Description ~= ""
	local columns = opts.Columns or {}
	local rowHeight = opts.RowHeight or 30
	local bodyHeight = opts.Height or 200
	local sortable = opts.Sortable ~= false
	local striped = opts.Striped ~= false
 
	local totalWeight = 0
	for _, col in ipairs(columns) do
		col.Weight = col.Weight or 1
		totalWeight = totalWeight + col.Weight
	end
	if totalWeight <= 0 then totalWeight = 1 end
 
	local function colAlign(col)
		if col.Align == "Right" then return Enum.TextXAlignment.Right end
		if col.Align == "Center" then return Enum.TextXAlignment.Center end
		return Enum.TextXAlignment.Left
	end
 
	local function colX(index)
		local w = 0
		for i = 1, index - 1 do w = w + columns[i].Weight end
		return w / totalWeight
	end
 
	local PAD = 12
	local HEADER_H = hasDesc and 32 or 16
	local COLHEAD_H = 26
	local GAP1, GAP2 = 10, 6
	local colHeadY = PAD + HEADER_H + GAP1
	local scrollY = colHeadY + COLHEAD_H + GAP2
	local totalHeight = scrollY + bodyHeight + PAD
 
	local container = Instance.new("Frame")
	container.Name = "Table"
	container.BackgroundColor3 = SilentUI.Theme.Surface
	container.BackgroundTransparency = 0.35
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Size = UDim2.new(1, 0, 0, totalHeight)
	container.ZIndex = Z.Content
	container.Parent = self._page
	Corner(container, SilentUI.Theme.CornerRadiusSm)
	Stroke(container, SilentUI.Theme.Border, 1, 0.92)
	self._window:_RegisterSearchable(self, title, container)
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = SilentUI.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = SilentUI.Theme.Text
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Position = UDim2.fromOffset(PAD, PAD)
	titleLabel.Size = UDim2.new(1, -PAD * 2, 0, 16)
	titleLabel.ZIndex = Z.Content + 1
	titleLabel.Parent = container
 
	if hasDesc then
		local descLabel = Instance.new("TextLabel")
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = SilentUI.Theme.FontRegular
		descLabel.Text = opts.Description
		descLabel.TextColor3 = SilentUI.Theme.TextDim
		descLabel.TextSize = 12
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.Position = UDim2.fromOffset(PAD, PAD + 18)
		descLabel.Size = UDim2.new(1, -PAD * 2, 0, 14)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = container
	end
 
	local colHead = Instance.new("Frame")
	colHead.Name = "ColumnHeader"
	colHead.BackgroundTransparency = 1
	colHead.Position = UDim2.fromOffset(PAD, colHeadY)
	colHead.Size = UDim2.new(1, -PAD * 2, 0, COLHEAD_H)
	colHead.ZIndex = Z.Content + 1
	colHead.Parent = container
 
	local sortState = { Key = nil, Asc = true }
	local headerLabels = {}
 
	for ci, col in ipairs(columns) do
		local x0 = colX(ci)
		local wFrac = col.Weight / totalWeight
 
		local cellBtn = Instance.new("TextButton")
		cellBtn.Name = "Col" .. ci
		cellBtn.Text = ""
		cellBtn.AutoButtonColor = false
		cellBtn.BackgroundTransparency = 1
		cellBtn.Position = UDim2.new(x0, ci > 1 and 4 or 0, 0, 0)
		cellBtn.Size = UDim2.new(wFrac, ci > 1 and -4 or 0, 1, 0)
		cellBtn.ZIndex = Z.Content + 2
		cellBtn.Parent = colHead
 
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.FontFace = SilentUI.Theme.Font
		lbl.Text = tostring(col.Label or col.Key or "")
		lbl.TextColor3 = SilentUI.Theme.TextDim
		lbl.TextSize = 12
		lbl.TextXAlignment = colAlign(col)
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.ZIndex = Z.Content + 3
		lbl.Parent = cellBtn
 
		headerLabels[col.Key] = { Lbl = lbl, Text = tostring(col.Label or col.Key or "") }
 
		if sortable then
			cellBtn.MouseEnter:Connect(function()
				if sortState.Key ~= col.Key then Tween(lbl, { TextColor3 = SilentUI.Theme.Text }, 0.12) end
			end)
			cellBtn.MouseLeave:Connect(function()
				if sortState.Key ~= col.Key then Tween(lbl, { TextColor3 = SilentUI.Theme.TextDim }, 0.12) end
			end)
		end
	end
 
	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = SilentUI.Theme.Surface
	divider.BackgroundTransparency = 0.92
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromOffset(0, colHeadY + COLHEAD_H)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.ZIndex = Z.Content + 1
	divider.Parent = container
 
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, scrollY)
	scroll.Size = UDim2.new(1, 0, 0, bodyHeight)
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 0
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ZIndex = Z.Content + 1
	scroll.Parent = container
 
	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingLeft = UDim.new(0, PAD)
	scrollPad.PaddingRight = UDim.new(0, PAD)
	scrollPad.Parent = scroll
 
	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Parent = scroll
 
	AddScrollbar(scroll)
	Private.AddContentScrollThumb(scroll, rowsLayout, container, jan)
 
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.FontFace = SilentUI.Theme.FontRegular
	emptyLabel.Text = "No rows"
	emptyLabel.TextColor3 = SilentUI.Theme.TextDim
	emptyLabel.TextSize = 12
	emptyLabel.Position = UDim2.fromOffset(PAD, scrollY + 10)
	emptyLabel.Size = UDim2.new(1, -PAD * 2, 0, 16)
	emptyLabel.Visible = false
	emptyLabel.ZIndex = Z.Content + 1
	emptyLabel.Parent = container
 
	local currentRows = {}
	local rowFrames = {}
 
	local function clearRowFrames()
		for _, f in ipairs(rowFrames) do f:Destroy() end
		table.clear(rowFrames)
	end
 
	local function renderRows()
		clearRowFrames()
		emptyLabel.Visible = #currentRows == 0
		for ri, row in ipairs(currentRows) do
			local rowFrame = Instance.new("Frame")
			rowFrame.Name = "Row" .. ri
			rowFrame.BackgroundColor3 = SilentUI.Theme.Surface
			rowFrame.BackgroundTransparency = (striped and ri % 2 == 0) and 0.97 or 1
			rowFrame.BorderSizePixel = 0
			rowFrame.LayoutOrder = ri
			rowFrame.Size = UDim2.new(1, 0, 0, rowHeight)
			rowFrame.ZIndex = Z.Content + 2
			rowFrame.Parent = scroll
 
			for ci, col in ipairs(columns) do
				local x0 = colX(ci)
				local wFrac = col.Weight / totalWeight
 
				local cell = Instance.new("TextLabel")
				cell.Name = "Cell" .. ci
				cell.BackgroundTransparency = 1
				cell.FontFace = SilentUI.Theme.FontRegular
				cell.Text = tostring(row[col.Key] == nil and "" or row[col.Key])
				cell.TextColor3 = SilentUI.Theme.Text
				cell.TextSize = 12
				cell.TextXAlignment = colAlign(col)
				cell.TextTruncate = Enum.TextTruncate.AtEnd
				cell.Position = UDim2.new(x0, ci > 1 and 4 or 0, 0, 0)
				cell.Size = UDim2.new(wFrac, ci > 1 and -4 or 0, 1, 0)
				cell.ZIndex = Z.Content + 3
				cell.Parent = rowFrame
			end
 
			table.insert(rowFrames, rowFrame)
		end
	end
 
	local function compareValues(av, bv)
		local an, bn = tonumber(av), tonumber(bv)
		if an and bn then
			if an == bn then return 0 end
			return an < bn and -1 or 1
		end
		local as, bs = tostring(av or ""), tostring(bv or "")
		if as == bs then return 0 end
		return as < bs and -1 or 1
	end
 
	local function applySort()
		if not sortState.Key then return end
		table.sort(currentRows, function(a, b)
			local c = compareValues(a[sortState.Key], b[sortState.Key])
			if sortState.Asc then return c < 0 else return c > 0 end
		end)
		renderRows()
	end
 
	if sortable then
		for ci, col in ipairs(columns) do
			local cellBtn = colHead:FindFirstChild("Col" .. ci)
			if cellBtn then
				cellBtn.MouseButton1Click:Connect(function()
					if sortState.Key == col.Key then
						sortState.Asc = not sortState.Asc
					else
						sortState.Key = col.Key
						sortState.Asc = true
					end
					for key, info in pairs(headerLabels) do
						local arrow = ""
						if key == sortState.Key then arrow = sortState.Asc and "  \226\150\178" or "  \226\150\188" end
						info.Lbl.Text = info.Text .. arrow
						info.Lbl.TextColor3 = (key == sortState.Key) and SilentUI.Theme.Text or SilentUI.Theme.TextDim
					end
					applySort()
				end)
			end
		end
	end
 
	local api = {
		Instance = container,
		SetRows = function(_, rows)
			currentRows = rows or {}
			if sortState.Key then applySort() else renderRows() end
		end,
		GetRows = function() return currentRows end,
		Destroy = function() container:Destroy() end,
	}
 
	api:SetRows(opts.Rows or {})
 
	return api
end
 
function Private.Serialize(value)
	local t = typeof(value)
	if t == "Color3" then
		return { Color = value:ToHex(), Transparency = 0 }
	elseif t == "EnumItem" then
		return { __t = "Enum", v = tostring(value) }
	elseif t == "table" then
		local out = {}
		for key, item in pairs(value) do out[key] = Private.Serialize(item) end
		return out
	end
	return value
end
 
function Private.Deserialize(value)
	if type(value) ~= "table" then return value end
	if value.__t == "Nil" then
		return nil
	elseif value.__t == "Color3" then
		return Color3.new(value.r, value.g, value.b)
	elseif type(value.Color) == "string" then
		local ok, color = pcall(Color3.fromHex, value.Color)
		if ok then return color end
	elseif value.__t == "Enum" then
		local parts = string.split(value.v, ".")
		local ok, result = pcall(function()
			return Enum[parts[2]][parts[3]]
		end)
		if not ok or typeof(result) ~= "EnumItem" then error("invalid EnumItem in configuration", 2) end
		return result
	end
	local out = {}
	for key, item in pairs(value) do out[key] = Private.Deserialize(item) end
	return out
end

function Private.CopyConfigValue(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in pairs(value) do copy[key] = Private.CopyConfigValue(item) end
	return copy
end
 
function Tab:AddCardGrid(opts)
	opts = opts or {}
	local height = opts.Height or 380
	local sorts = opts.Sorts or {}
	local pageSize = opts.PageSize or 20
	local showSearch = opts.Search ~= false
	local descriptionHeight = opts.DescriptionHeight or 28
	local showNativeScrollbar = opts.ShowScrollbar == true
	local cardPadding = opts.CardPadding or 10
 
	local outer = Instance.new("Frame")
	outer.Name = "CardGrid"
	outer.BackgroundColor3 = SilentUI.Theme.Surface
	outer.BackgroundTransparency = 0.97
	outer.BorderSizePixel = 0
	outer.Size = UDim2.new(1, 0, 0, height)
	outer.ZIndex = Z.Content
	outer.Parent = self._page
	outer:SetAttribute("SilentInterfacePanel", true)
	if self._window then outer:SetAttribute("SilentWindowId", self._window._id) end
	Corner(outer, SilentUI.Theme.CornerRadiusSm)
	Stroke(outer, SilentUI.Theme.Border, 1, 0.95)
	self._window:_RegisterSearchable(self, opts.Title or "Cards", outer)
 
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = Z.Content + 1
	content.Parent = outer
 
	local OUTER_V_PAD = opts.OuterPadding or 18
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, OUTER_V_PAD)
	pad.PaddingBottom = UDim.new(0, OUTER_V_PAD)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = content
 
	local TOP_H, TABS_H = 32, 28
	local headerH = 0
	if showSearch then headerH = headerH + TOP_H end
	if #sorts > 1 then
		if headerH > 0 then headerH = headerH + 8 end
		headerH = headerH + TABS_H
	end
	if headerH > 0 then headerH = headerH + 10 end
 
	local searchBox
	if showSearch then
		local searchPill = Instance.new("Frame")
		searchPill.BackgroundColor3 = SilentUI.Theme.Surface
		searchPill.BackgroundTransparency = 0.92
		searchPill.BorderSizePixel = 0
		searchPill.Size = UDim2.new(1, 0, 0, TOP_H)
		searchPill.ZIndex = Z.Content + 1
		searchPill.Parent = content
		Corner(searchPill, 9)
		local searchStroke = Stroke(searchPill, SilentUI.Theme.Border, 1, 0.88)
 
		local searchIcon = Instance.new("ImageLabel")
		searchIcon.BackgroundTransparency = 1
		searchIcon.Image = ResolveIcon("search")
		searchIcon.ImageColor3 = SilentUI.Theme.TextDim
		searchIcon.Size = UDim2.fromOffset(13, 13)
		searchIcon.AnchorPoint = Vector2.new(0, 0.5)
		searchIcon.Position = UDim2.new(0, 10, 0.5, 0)
		searchIcon.ZIndex = Z.Content + 2
		searchIcon.Parent = searchPill
 
		searchBox = Instance.new("TextBox")
		searchBox.ClearTextOnFocus = false
		searchBox.FontFace = SilentUI.Theme.FontRegular
		searchBox.PlaceholderText = opts.SearchPlaceholder or "Search by name / tags..."
		searchBox.PlaceholderColor3 = SilentUI.Theme.TextDim
		searchBox.Text = ""
		searchBox.TextColor3 = SilentUI.Theme.Text
		searchBox.TextSize = 13
		searchBox.TextXAlignment = Enum.TextXAlignment.Left
		searchBox.TextYAlignment = Enum.TextYAlignment.Center
		searchBox.BackgroundTransparency = 1
		searchBox.ClipsDescendants = true
		searchBox.Position = UDim2.fromOffset(30, 0)
		searchBox.Size = UDim2.new(1, -40, 1, 0)
		searchBox.ZIndex = Z.Content + 2
		searchBox.Parent = searchPill
 
		searchBox.Focused:Connect(function()
			Tween(searchStroke, { Color = SilentUI.Theme.Accent, Transparency = 0.3 }, 0.15)
		end)
		searchBox.FocusLost:Connect(function()
			Tween(searchStroke, { Color = SilentUI.Theme.Border, Transparency = 0.88 }, 0.15)
		end)
	end
 
	local currentSort = opts.DefaultSort or sorts[1]
	local sortButtons = {}
	if #sorts > 1 then
		local tabsRow = Instance.new("Frame")
		tabsRow.BackgroundTransparency = 1
		tabsRow.Position = UDim2.fromOffset(0, showSearch and (TOP_H + 8) or 0)
		tabsRow.Size = UDim2.new(1, 0, 0, TABS_H)
		tabsRow.ZIndex = Z.Content + 1
		tabsRow.Parent = content
 
		local tabsLayout = Instance.new("UIListLayout")
		tabsLayout.FillDirection = Enum.FillDirection.Horizontal
		tabsLayout.Padding = UDim.new(0, 6)
		tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		tabsLayout.Parent = tabsRow
 
		for i, sortName in ipairs(sorts) do
			local btn = Instance.new("TextButton")
			btn.AutoButtonColor = false
			btn.Text = ""
			btn.BackgroundColor3 = SilentUI.Theme.Surface
			btn.BackgroundTransparency = (sortName == currentSort) and 0.85 or 1
			btn.BorderSizePixel = 0
			btn.AutomaticSize = Enum.AutomaticSize.X
			btn.Size = UDim2.fromOffset(0, TABS_H)
			btn.LayoutOrder = i
			btn.ZIndex = Z.Content + 1
			btn.Parent = tabsRow
			Corner(btn, 7)
 
			local btnPad = Instance.new("UIPadding")
			btnPad.PaddingLeft = UDim.new(0, 10)
			btnPad.PaddingRight = UDim.new(0, 10)
			btnPad.Parent = btn
 
			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.FontFace = SilentUI.Theme.Font
			lbl.Text = string.upper(sortName)
			lbl.TextColor3 = (sortName == currentSort) and SilentUI.Theme.Text or SilentUI.Theme.TextDim
			lbl.TextSize = 11
			lbl.AutomaticSize = Enum.AutomaticSize.X
			lbl.Size = UDim2.fromOffset(0, TABS_H)
			lbl.ZIndex = Z.Content + 2
			lbl.Parent = btn
 
			sortButtons[sortName] = { Button = btn, Label = lbl }
		end
	end
 
	local gridScroll = Instance.new("ScrollingFrame")
	gridScroll.BackgroundTransparency = 1
	gridScroll.BorderSizePixel = 0
	gridScroll.Position = UDim2.fromOffset(0, headerH)
	gridScroll.Size = UDim2.new(1, 0, 1, -headerH)
	gridScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	gridScroll.ScrollingEnabled = true
	gridScroll.Active = true
	gridScroll.ElasticBehavior = Enum.ElasticBehavior.Never
	gridScroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	gridScroll.ScrollBarThickness = showNativeScrollbar and (opts.ScrollBarThickness or 4) or 0
	gridScroll.ScrollBarImageColor3 = SilentUI.Theme.TextDim
	gridScroll.ScrollBarImageTransparency = 0.35
	gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	gridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	gridScroll.ZIndex = Z.Content + 1
	gridScroll.Parent = content
 
	-- Reserve room for the visible scrollbar so cards never sit underneath it.
	local GRID_RIGHT_PAD = gridScroll.ScrollBarThickness > 0 and (gridScroll.ScrollBarThickness + 6) or 16
	local GRID_TOP_PAD = 8
	local GRID_BOTTOM_PAD = 8
	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop = UDim.new(0, GRID_TOP_PAD)
	gridPad.PaddingRight = UDim.new(0, GRID_RIGHT_PAD)
	gridPad.Parent = gridScroll
 
	local MIN_CELL_W = opts.CardMinWidth or opts.CardWidth or 190
	local FIXED_COLUMNS = opts.Columns
	local MAX_COLUMNS = opts.MaxColumns
	local CELL_H = opts.CardHeight or 88
	local CELL_GAP = 8
 
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP)
	gridLayout.CellSize = UDim2.fromOffset(MIN_CELL_W, CELL_H)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridScroll
 
	local function updateGridCanvas()
		gridScroll.CanvasSize = UDim2.new(
			0, 0, 0,
			math.max(0, (gridLayout.AbsoluteContentSize.Y / GetUIScale()) + GRID_TOP_PAD + GRID_BOTTOM_PAD)
		)
	end
	gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateGridCanvas)
	task.defer(updateGridCanvas)
 
	local SAFETY_MARGIN = 4
	local currentColumns = 1
	local function relayoutGridColumns()
		local availableW = (gridScroll.AbsoluteSize.X / GetUIScale()) - GRID_RIGHT_PAD - SAFETY_MARGIN
		if availableW <= 0 then return end
		local columns = FIXED_COLUMNS and math.max(1, FIXED_COLUMNS)
			or math.max(1, math.floor((availableW + CELL_GAP) / (MIN_CELL_W + CELL_GAP)))
		if not FIXED_COLUMNS and MAX_COLUMNS then columns = math.min(columns, math.max(1, MAX_COLUMNS)) end
		local cellW = math.floor((availableW - (columns - 1) * CELL_GAP) / columns)
		currentColumns = columns
		gridLayout.CellSize = UDim2.fromOffset(math.max(1, cellW), CELL_H)
	end
	gridScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayoutGridColumns)
	task.defer(relayoutGridColumns)
 
	if not showNativeScrollbar then
		AddScrollbar(gridScroll)
		Private.AddContentScrollThumb(gridScroll, gridLayout, outer, self._janitor)
	end
 
	local MAX_OUTER_H = opts.Height or 300
	local showingCards = false
 
	local function applyOuterHeight(target)
		Tween(outer, { Size = UDim2.new(1, 0, 0, target) }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end
 
	local EMPTY_STATE_H = 220
	local function resizeOuterEmpty()
		showingCards = false
		if opts.FixedHeight then
			applyOuterHeight(MAX_OUTER_H)
			return
		end
		applyOuterHeight(math.min(headerH + OUTER_V_PAD + EMPTY_STATE_H + OUTER_V_PAD, MAX_OUTER_H))
	end
 
	local function resizeOuterToGridContent()
		if not showingCards then return end
		if opts.FixedHeight then
			applyOuterHeight(MAX_OUTER_H)
			return
		end
		local contentH = gridLayout.AbsoluteContentSize.Y
		if contentH <= 0 then return end
		local target = math.min(headerH + OUTER_V_PAD + contentH + OUTER_V_PAD, MAX_OUTER_H)
		applyOuterHeight(target)
	end
	gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resizeOuterToGridContent)
 
	local statusHolder = Instance.new("Frame")
	statusHolder.BackgroundTransparency = 1
	statusHolder.Position = UDim2.fromOffset(0, headerH)
	statusHolder.Size = UDim2.new(1, 0, 1, -headerH)
	statusHolder.Visible = false
	statusHolder.ZIndex = Z.Content + 2
	statusHolder.Parent = content
 
	local statusLayout = Instance.new("UIListLayout")
	statusLayout.FillDirection = Enum.FillDirection.Vertical
	statusLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	statusLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	statusLayout.Padding = UDim.new(0, 6)
	statusLayout.Parent = statusHolder
 
	local statusIcon = Instance.new("ImageLabel")
	statusIcon.BackgroundTransparency = 1
	statusIcon.ImageColor3 = SilentUI.Theme.TextDim
	statusIcon.Size = UDim2.fromOffset(24, 24)
	statusIcon.LayoutOrder = 1
	statusIcon.Visible = false
	statusIcon.ZIndex = Z.Content + 3
	statusIcon.Parent = statusHolder
 
	local statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.FontFace = SilentUI.Theme.FontRegular
	statusLabel.TextColor3 = SilentUI.Theme.TextDim
	statusLabel.TextSize = 12
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center
	statusLabel.AutomaticSize = Enum.AutomaticSize.Y
	statusLabel.Size = UDim2.new(1, -20, 0, 16)
	statusLabel.LayoutOrder = 2
	statusLabel.ZIndex = Z.Content + 3
	statusLabel.Parent = statusHolder
 
	local STATUS_ICONS = { loading = "loader-circle", empty = "frown", error = "triangle-alert" }
 
	local function openCardMenu(anchor, actions)
		if type(actions) ~= "table" or #actions == 0 then return end
 
		local popup, backdrop
		local function closeMenu()
			Private.RegisterPopupClose(closeMenu)
			if backdrop then backdrop:Destroy(); backdrop = nil end
			if popup then popup:Destroy(); popup = nil end
		end
 
		Private.RegisterPopupOpen(closeMenu)
		backdrop = Private.MakePopupBackdrop(closeMenu)
 
		local rowH, gap, pad = 32, 2, 8
		local popupW = 190
		local popupH = pad * 2 + #actions * rowH + math.max(0, #actions - 1) * gap
		local scale = GetUIScale()
		local view = Private.ViewportSize()
		local anchorPos, anchorSize = anchor.AbsolutePosition, anchor.AbsoluteSize
		local px = (anchorPos.X + anchorSize.X) / scale - popupW
		local py = (anchorPos.Y + anchorSize.Y) / scale + 5
		px = SafeClamp(px, 8, view.X / scale - popupW - 8)
		py = SafeClamp(py, 8, view.Y / scale - popupH - 8)
 
		popup = Instance.new("CanvasGroup")
		popup.Name = "CardActionsPopup"
		popup.Active = true
		popup.BackgroundColor3 = SilentUI.Theme.Background
		popup.BackgroundTransparency = self._window and self._window._interfaceTransparency or 0.04
		popup.BorderSizePixel = 0
		popup.Position = UDim2.fromOffset(math.round(px), math.round(py))
		popup.Size = UDim2.fromOffset(popupW, popupH)
		popup.ZIndex = Z.Popup
		popup.Parent = SilentUI._Root
		popup:SetAttribute("SilentInterfacePanel", true)
		if self._window then popup:SetAttribute("SilentWindowId", self._window._id) end
		Corner(popup, 10)
		Stroke(popup, SilentUI.Theme.Border, 1, 0.9)
		Private.GlassLayer(popup, 10, 0.985)
 
		local actionsHolder = Instance.new("Frame")
		actionsHolder.Name = "Actions"
		actionsHolder.BackgroundTransparency = 1
		actionsHolder.Size = UDim2.fromScale(1, 1)
		actionsHolder.ZIndex = Z.Popup + 1
		actionsHolder.Parent = popup
 
		local popupPad = Instance.new("UIPadding")
		popupPad.PaddingTop = UDim.new(0, pad)
		popupPad.PaddingBottom = UDim.new(0, pad)
		popupPad.PaddingLeft = UDim.new(0, pad)
		popupPad.PaddingRight = UDim.new(0, pad)
		popupPad.Parent = actionsHolder
 
		local popupLayout = Instance.new("UIListLayout")
		popupLayout.Padding = UDim.new(0, gap)
		popupLayout.SortOrder = Enum.SortOrder.LayoutOrder
		popupLayout.Parent = actionsHolder
 
		for i, action in ipairs(actions) do
			local button = Instance.new("TextButton")
			button.Name = "Action" .. i
			button.Text = ""
			button.AutoButtonColor = false
			button.BackgroundColor3 = SilentUI.Theme.Surface
			button.BackgroundTransparency = 1
			button.BorderSizePixel = 0
			button.Size = UDim2.new(1, 0, 0, rowH)
			button.LayoutOrder = i
			button.ZIndex = Z.Popup + 1
			button.Parent = actionsHolder
			Corner(button, 7)
 
			local icon = Instance.new("ImageLabel")
			icon.BackgroundTransparency = 1
			icon.Image = ResolveIcon(action.Icon or "circle")
			icon.ImageColor3 = action.Danger and SilentUI.Theme.Danger or SilentUI.Theme.TextDim
			icon.Size = UDim2.fromOffset(14, 14)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 9, 0.5, 0)
			icon.ZIndex = Z.Popup + 2
			icon.Parent = button
 
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.FontFace = SilentUI.Theme.FontRegular
			label.Text = tostring(action.Text or "Action")
			label.TextColor3 = action.Danger and SilentUI.Theme.Danger or SilentUI.Theme.Text
			label.TextSize = 12
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.Position = UDim2.fromOffset(31, 0)
			label.Size = UDim2.new(1, -39, 1, 0)
			label.ZIndex = Z.Popup + 2
			label.Parent = button
 
			button.MouseEnter:Connect(function()
				Tween(button, { BackgroundTransparency = 0.9 }, 0.1)
			end)
			button.MouseLeave:Connect(function()
				Tween(button, { BackgroundTransparency = 1 }, 0.1)
			end)
			button.MouseButton1Click:Connect(function()
				closeMenu()
				if action.Callback then task.spawn(action.Callback) end
			end)
		end
	end
 
	local function buildCard(item, animDelay)
		local cell = Instance.new("Frame")
		cell.Name = "GridCard"
		cell.BackgroundColor3 = SilentUI.Theme.Surface
		cell.BackgroundTransparency = 1
		cell.BorderSizePixel = 0
		cell.ClipsDescendants = true
		cell.ZIndex = Z.Content + 2
		cell.Parent = gridScroll
		Corner(cell, SilentUI.Theme.CornerRadiusSm)
		local cellStroke = Stroke(cell, SilentUI.Theme.Border, 1, 1)
 
		local cellScale = Instance.new("UIScale")
		cellScale.Scale = 0.9
		cellScale.Parent = cell
 
		task.delay(animDelay or 0, function()
			if not cell.Parent then return end
			Tween(cell, { BackgroundTransparency = 0.94 }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			Tween(cellStroke, { Transparency = 0.9 }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			Tween(cellScale, { Scale = 1 }, 0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end)
 
		local cellPad = Instance.new("UIPadding")
		cellPad.PaddingTop = UDim.new(0, cardPadding)
		cellPad.PaddingBottom = UDim.new(0, cardPadding)
		cellPad.PaddingLeft = UDim.new(0, cardPadding)
		cellPad.PaddingRight = UDim.new(0, cardPadding)
		cellPad.Parent = cell
 
		local textX = 0
		if item.Icon then
			local ICON_BOX = 24
			local iconHolder = Instance.new("Frame")
			iconHolder.BackgroundColor3 = SilentUI.Theme.Surface
			iconHolder.BackgroundTransparency = 0.9
			iconHolder.BorderSizePixel = 0
			iconHolder.Size = UDim2.fromOffset(ICON_BOX, ICON_BOX)
			iconHolder.ZIndex = Z.Content + 3
			iconHolder.Parent = cell
			Corner(iconHolder, 7)
 
			local iconImg = Instance.new("ImageLabel")
			iconImg.BackgroundTransparency = 1
			iconImg.Image = ResolveIcon(item.Icon)
			iconImg.ImageColor3 = SilentUI.Theme.Accent
			iconImg.Size = UDim2.fromOffset(13, 13)
			iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
			iconImg.Position = UDim2.fromScale(0.5, 0.5)
			iconImg.ZIndex = Z.Content + 4
			iconImg.Parent = iconHolder
 
			textX = ICON_BOX + 8
		end
 
		local hasPrimaryAction = item.Callback ~= nil
		local hasSecondaryAction = item.SecondaryCallback ~= nil
		local hasMenuAction = item.Menu and #item.Menu > 0
		local trailingReserve = (hasPrimaryAction and 26 or 0)
			+ (hasSecondaryAction and 30 or 0)
			+ (hasMenuAction and 30 or 0)
		if hasPrimaryAction then
 
			local actionBadge = Instance.new("Frame")
			actionBadge.Name = "LoadBadge"
			actionBadge.BackgroundColor3 = SilentUI.Theme.Accent
			actionBadge.BackgroundTransparency = 0.8
			actionBadge.BorderSizePixel = 0
			actionBadge.AnchorPoint = Vector2.new(1, 0)
			actionBadge.Position = UDim2.new(1, 0, 0, 0)
			actionBadge.Size = UDim2.fromOffset(22, 22)
			actionBadge.ZIndex = Z.Content + 6
			actionBadge.Parent = cell
			Corner(actionBadge, 7)
 
			local actionIcon = Instance.new("ImageLabel")
			actionIcon.BackgroundTransparency = 1
			actionIcon.Image = ResolveIcon(item.ActionIcon or "download")
			actionIcon.ImageColor3 = SilentUI.Theme.Accent
			actionIcon.Size = UDim2.fromOffset(12, 12)
			actionIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			actionIcon.Position = UDim2.fromScale(0.5, 0.5)
			actionIcon.ZIndex = Z.Content + 7
			actionIcon.Parent = actionBadge
 
			local actionClick = Instance.new("TextButton")
			actionClick.Text = ""
			actionClick.AutoButtonColor = false
			actionClick.BackgroundTransparency = 1
			actionClick.Size = UDim2.fromScale(1, 1)
			actionClick.ZIndex = Z.Content + 8
			actionClick.Parent = actionBadge
			actionClick.MouseButton1Click:Connect(function()
				item.Callback()
			end)
		end
 
		if hasSecondaryAction then
			local secondaryBadge = Instance.new("Frame")
			secondaryBadge.Name = "SecondaryActionBadge"
			secondaryBadge.BackgroundColor3 = item.SecondaryDanger
				and Color3.fromRGB(225, 76, 88)
				or SilentUI.Theme.Accent
			secondaryBadge.BackgroundTransparency = item.SecondaryDanger and 0.82 or 0.8
			secondaryBadge.BorderSizePixel = 0
			secondaryBadge.AnchorPoint = Vector2.new(1, 0)
			secondaryBadge.Position = UDim2.new(1, hasPrimaryAction and -30 or 0, 0, 0)
			secondaryBadge.Size = UDim2.fromOffset(22, 22)
			secondaryBadge.ZIndex = Z.Content + 6
			secondaryBadge.Parent = cell
			Corner(secondaryBadge, 7)
 
			local secondaryIcon = Instance.new("ImageLabel")
			secondaryIcon.BackgroundTransparency = 1
			secondaryIcon.Image = ResolveIcon(item.SecondaryIcon or "trash-2")
			secondaryIcon.ImageColor3 = item.SecondaryDanger
				and Color3.fromRGB(255, 125, 135)
				or SilentUI.Theme.Accent
			secondaryIcon.Size = UDim2.fromOffset(12, 12)
			secondaryIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			secondaryIcon.Position = UDim2.fromScale(0.5, 0.5)
			secondaryIcon.ZIndex = Z.Content + 7
			secondaryIcon.Parent = secondaryBadge
 
			local secondaryClick = Instance.new("TextButton")
			secondaryClick.Text = ""
			secondaryClick.AutoButtonColor = false
			secondaryClick.BackgroundTransparency = 1
			secondaryClick.Size = UDim2.fromScale(1, 1)
			secondaryClick.ZIndex = Z.Content + 8
			secondaryClick.Parent = secondaryBadge
			secondaryClick.MouseButton1Click:Connect(function()
				item.SecondaryCallback()
			end)
		end
 
		if hasMenuAction then
			local menuBadge = Instance.new("Frame")
			menuBadge.Name = "MenuBadge"
			menuBadge.BackgroundColor3 = SilentUI.Theme.Accent
			menuBadge.BackgroundTransparency = 0.8
			menuBadge.BorderSizePixel = 0
			menuBadge.AnchorPoint = Vector2.new(1, 0)
			menuBadge.Position = UDim2.new(
				1,
				-((hasPrimaryAction and 30 or 0) + (hasSecondaryAction and 30 or 0)),
				0,
				0
			)
			menuBadge.Size = UDim2.fromOffset(22, 22)
			menuBadge.ZIndex = Z.Content + 6
			menuBadge.Parent = cell
			Corner(menuBadge, 7)
 
			local menuIcon = Instance.new("ImageLabel")
			menuIcon.BackgroundTransparency = 1
			menuIcon.Image = ResolveIcon("Lucide:settings")
			menuIcon.ImageColor3 = SilentUI.Theme.Accent
			menuIcon.Size = UDim2.fromOffset(12, 12)
			menuIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			menuIcon.Position = UDim2.fromScale(0.5, 0.5)
			menuIcon.ZIndex = Z.Content + 7
			menuIcon.Parent = menuBadge
 
			local menuClick = Instance.new("TextButton")
			menuClick.Text = ""
			menuClick.AutoButtonColor = false
			menuClick.BackgroundTransparency = 1
			menuClick.Size = UDim2.fromScale(1, 1)
			menuClick.ZIndex = Z.Content + 8
			menuClick.Parent = menuBadge
			menuClick.MouseButton1Click:Connect(function()
				openCardMenu(menuBadge, item.Menu)
			end)
		end
 
		local cursorY = 0
 
		local titleLbl = Instance.new("TextLabel")
		titleLbl.BackgroundTransparency = 1
		titleLbl.FontFace = SilentUI.Theme.Font
		titleLbl.Text = item.Title or "Untitled"
		titleLbl.TextColor3 = SilentUI.Theme.Text
		titleLbl.TextSize = 13
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.TextYAlignment = Enum.TextYAlignment.Center
		titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
		titleLbl.Position = UDim2.fromOffset(textX, item.Icon and 4 or cursorY)
		titleLbl.Size = UDim2.new(1, -(textX + trailingReserve), 0, item.Icon and 24 or 16)
		titleLbl.ZIndex = Z.Content + 3
		titleLbl.Parent = cell
		cursorY = math.max(item.Icon and (24 + 6) or 0, cursorY + 16 + 3)
 
		if item.Description and item.Description ~= "" then
 
			local descLbl = Instance.new("TextLabel")
			descLbl.BackgroundTransparency = 1
			descLbl.FontFace = SilentUI.Theme.FontRegular
			descLbl.Text = item.Description
			descLbl.TextColor3 = SilentUI.Theme.TextDim
			descLbl.TextSize = 11
			descLbl.TextWrapped = true
			descLbl.TextTruncate = Enum.TextTruncate.None
			descLbl.TextXAlignment = Enum.TextXAlignment.Left
			descLbl.TextYAlignment = Enum.TextYAlignment.Top
			descLbl.Position = UDim2.fromOffset(0, cursorY)
			descLbl.Size = UDim2.new(1, -trailingReserve, 0, descriptionHeight)
			descLbl.ZIndex = Z.Content + 3
			descLbl.Parent = cell
			cursorY = cursorY + descriptionHeight + 3
		end
 
		if item.Byline and item.Byline ~= "" then
			local bylineLbl = Instance.new("TextLabel")
			bylineLbl.BackgroundTransparency = 1
			bylineLbl.FontFace = SilentUI.Theme.FontRegular
			bylineLbl.Text = item.Byline
			bylineLbl.TextColor3 = SilentUI.Theme.TextDim
			bylineLbl.TextTransparency = 0.25
			bylineLbl.TextSize = 10
			bylineLbl.TextXAlignment = Enum.TextXAlignment.Left
			bylineLbl.TextTruncate = Enum.TextTruncate.AtEnd
			bylineLbl.Position = UDim2.fromOffset(0, cursorY)
			bylineLbl.Size = UDim2.new(1, -trailingReserve, 0, 12)
			bylineLbl.ZIndex = Z.Content + 3
			bylineLbl.Parent = cell
		end
 
		if item.Stats and #item.Stats > 0 then
			local statsRow = Instance.new("Frame")
			statsRow.BackgroundTransparency = 1
			statsRow.AnchorPoint = Vector2.new(0, 1)
			statsRow.Position = UDim2.new(0, 0, 1, 0)
			statsRow.Size = UDim2.new(1, 0, 0, 16)
			statsRow.ZIndex = Z.Content + 3
			statsRow.Parent = cell
 
			local statsLayout = Instance.new("UIListLayout")
			statsLayout.FillDirection = Enum.FillDirection.Horizontal
			statsLayout.Padding = UDim.new(0, 10)
			statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
			statsLayout.Parent = statsRow
 
			for i, stat in ipairs(item.Stats) do
 
				local statFrame = Instance.new(stat.Callback and "TextButton" or "Frame")
				statFrame.BackgroundTransparency = 1
				statFrame.AutomaticSize = Enum.AutomaticSize.X
				statFrame.Size = UDim2.fromOffset(0, 14)
				statFrame.LayoutOrder = i
				statFrame.ZIndex = Z.Content + 3
				statFrame.Parent = statsRow
				if stat.Callback then
					statFrame.Text = ""
					statFrame.AutoButtonColor = false
				end
 
				local statLayout = Instance.new("UIListLayout")
				statLayout.FillDirection = Enum.FillDirection.Horizontal
				statLayout.VerticalAlignment = Enum.VerticalAlignment.Center
				statLayout.Padding = UDim.new(0, 3)
				statLayout.Parent = statFrame
 
				local statIcon = Instance.new("ImageLabel")
				statIcon.BackgroundTransparency = 1
				statIcon.Image = ResolveIcon(stat.Icon or "circle")
				statIcon.ImageColor3 = SilentUI.Theme.TextDim
				statIcon.Size = UDim2.fromOffset(11, 11)
				statIcon.LayoutOrder = 1
				statIcon.ZIndex = Z.Content + 4
				statIcon.Parent = statFrame
 
				local statLbl = Instance.new("TextLabel")
				statLbl.BackgroundTransparency = 1
				statLbl.FontFace = SilentUI.Theme.FontRegular
				statLbl.Text = tostring(stat.Text or "")
				statLbl.TextColor3 = SilentUI.Theme.TextDim
				statLbl.TextSize = 10
				statLbl.AutomaticSize = Enum.AutomaticSize.X
				statLbl.Size = UDim2.fromOffset(0, 12)
				statLbl.LayoutOrder = 2
				statLbl.ZIndex = Z.Content + 4
				statLbl.Parent = statFrame
 
				if stat.Callback then
					statFrame.MouseEnter:Connect(function()
						Tween(statIcon, { ImageColor3 = SilentUI.Theme.Accent }, 0.1)
						Tween(statLbl, { TextColor3 = SilentUI.Theme.Accent }, 0.1)
					end)
					statFrame.MouseLeave:Connect(function()
						Tween(statIcon, { ImageColor3 = SilentUI.Theme.TextDim }, 0.1)
						Tween(statLbl, { TextColor3 = SilentUI.Theme.TextDim }, 0.1)
					end)
					statFrame.MouseButton1Click:Connect(function()
						task.spawn(stat.Callback)
					end)
				end
			end
		end
 
		if item.Callback then
 
			local hasInteractiveStat = false
			if item.Stats then
				for _, stat in ipairs(item.Stats) do
					if stat.Callback then hasInteractiveStat = true end
				end
			end
 
			local click = Instance.new("TextButton")
			click.Text = ""
			click.AutoButtonColor = false
			click.BackgroundTransparency = 1
			click.Size = hasInteractiveStat and UDim2.new(1, 0, 1, -20) or UDim2.fromScale(1, 1)
			click.ZIndex = Z.Content + 5
			click.Parent = cell
 
			click.MouseEnter:Connect(function()
				Tween(cell, { BackgroundTransparency = 0.88 }, 0.12)
				Tween(cellStroke, { Transparency = 0.8 }, 0.12)
			end)
			click.MouseLeave:Connect(function()
				Tween(cell, { BackgroundTransparency = 0.94 }, 0.12)
				Tween(cellStroke, { Transparency = 0.9 }, 0.12)
			end)
			click.MouseButton1Click:Connect(function()
				task.spawn(item.Callback)
			end)
		end
 
		return cell
	end
 
	local currentQuery = ""
	local loadToken = 0
 
	local function clearGrid()
		for _, child in ipairs(gridScroll:GetChildren()) do
			if child.Name == "GridCard" then child:Destroy() end
		end
	end
 
	local function setStatus(msg, kind)
		local visible = msg ~= nil and msg ~= ""
		statusLabel.Text = msg or ""
		statusHolder.Visible = visible
		local iconName = visible and STATUS_ICONS[kind]
		statusIcon.Visible = iconName ~= nil
		if iconName then
			statusIcon.Image = ResolveIcon(iconName)
		end
	end
 
	local function computeCellHeight(items)
		local hasIcon, hasDesc, hasByline, hasStats = false, false, false, false
		for _, item in ipairs(items) do
			if item.Icon then hasIcon = true end
			if item.Description and item.Description ~= "" then hasDesc = true end
			if item.Byline and item.Byline ~= "" then hasByline = true end
			if item.Stats and #item.Stats > 0 then hasStats = true end
		end
		local h = 20
		h = h + (hasIcon and 24 or 16) + 3
		if hasDesc then h = h + descriptionHeight + 3 end
		if hasByline then h = h + 12 end
		if hasStats then h = h + 16 + 4 end
		return h
	end
 
	local function refresh()
		if not opts.Fetch then return end
		loadToken = loadToken + 1
		local myToken = loadToken
		clearGrid()
		setStatus(opts.LoadingText or "Loading...", "loading")
		resizeOuterEmpty()
		task.spawn(function()
			local ok, items, fetchErr = pcall(opts.Fetch, {
				Query = currentQuery,
				Sort = currentSort,
				PageSize = pageSize,
			})
			if myToken ~= loadToken then return end
			if not ok then
				setStatus(opts.ErrorText or tostring(items), "error")
				resizeOuterEmpty()
				return
			end
			if fetchErr then
				setStatus(opts.ErrorText or tostring(fetchErr), "error")
				resizeOuterEmpty()
				return
			end
			items = items or {}
			if #items == 0 then
				setStatus(opts.EmptyText or "Nothing here yet.", "empty")
				resizeOuterEmpty()
				return
			end
			setStatus(nil)
			if opts.AutoCardHeight ~= false then
				CELL_H = math.max(computeCellHeight(items), opts.MinCardHeight or 0)
				gridLayout.CellSize = UDim2.new(
					gridLayout.CellSize.X.Scale, gridLayout.CellSize.X.Offset,
					0, CELL_H
				)
			end
			showingCards = true
			for i, item in ipairs(items) do
 
				buildCard(item, math.min(i - 1, 8) * 0.035)
			end
 
			task.spawn(function()
				RunService.Heartbeat:Wait()
				RunService.Heartbeat:Wait()
				if myToken == loadToken then resizeOuterToGridContent() end
			end)
		end)
	end
 
	if searchBox then
		local debounceToken = 0
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			currentQuery = searchBox.Text
			debounceToken = debounceToken + 1
			local myDebounce = debounceToken
			task.delay(0.35, function()
				if myDebounce == debounceToken then refresh() end
			end)
		end)
	end
 
	for sortName, entry in pairs(sortButtons) do
		entry.Button.MouseButton1Click:Connect(function()
			if currentSort == sortName then return end
			currentSort = sortName
			for otherName, otherEntry in pairs(sortButtons) do
				local active = otherName == currentSort
				Tween(otherEntry.Button, { BackgroundTransparency = active and 0.85 or 1 }, 0.12)
				Tween(otherEntry.Label, { TextColor3 = active and SilentUI.Theme.Text or SilentUI.Theme.TextDim }, 0.12)
			end
			refresh()
		end)
	end
 
	if opts.AutoLoad ~= false and opts.Fetch then
		task.defer(refresh)
	end
 
	return {
		Instance = outer,
		Refresh = refresh,
		SetQuery = function(_, q)
			currentQuery = q or ""
			if searchBox then searchBox.Text = currentQuery end
			refresh()
		end,
		SetSort = function(_, s)
			currentSort = s
			refresh()
		end,
		Destroy = function() outer:Destroy() end,
	}
end
 
function Private.ReadControlValue(api)
	local getter = api.Kind == "Keybind" and type(api.GetState) == "function" and api.GetState or api.Get
	return getter(api)
end

function SilentUI:GetConfig()
	local data = {}
	local flags = {}
	for flag in pairs(self.Flags) do table.insert(flags, flag) end
	table.sort(flags)
	for _, flag in ipairs(flags) do
		local api = self.Flags[flag]
		if type(api.Get) ~= "function" then return nil, flag .. ": getter is unavailable" end
		local ok, value = pcall(Private.ReadControlValue, api)
		if not ok then return nil, flag .. ": getter failed: " .. tostring(value) end
		local encoded, serialized = pcall(Private.Serialize, value)
		if not encoded then return nil, flag .. ": value could not be serialized: " .. tostring(serialized) end
		if value ~= nil then
			data[flag] = serialized
		elseif api.Kind == "Keybind" then
			data[flag] = { __t = "Nil" }
		end
	end
	return data
end
 
function SilentUI:GetConfigJSON()
	local data, err = self:GetConfig()
	if not data then return nil, err end
	local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
	if not ok then return nil, tostring(encoded) end
	return encoded
end

function SilentUI:OnConfigLoaded(callback)
	assert(type(callback) == "function", "OnConfigLoaded expects a callback")
	return ConfigLoadedSignal.Connect(callback)
end

function SilentUI:GetValue(flag)
	local api = self.Flags[flag]
	if not api or type(api.Get) ~= "function" then return nil, "unknown flag: " .. tostring(flag) end
	local ok, value = pcall(Private.ReadControlValue, api)
	if not ok then return nil, tostring(value) end
	return value
end

function SilentUI:GetValues()
	local values = {}
	for flag, api in pairs(self.Flags) do
		if type(api.Get) == "function" then
			local ok, value = pcall(Private.ReadControlValue, api)
			if ok then values[flag] = Private.CopyConfigValue(value) end
		end
	end
	return values
end

-- Initialize controls after all tabs have been constructed and their saved values restored.
-- Unlike Set(..., false), this does not change flags or emit OnChanged notifications.
function SilentUI:InitializeCallbacks()
	local pending = {}
	for flag, api in pairs(self.Flags) do
		if api._InitializationCallback and not api._CallbacksInitialized then
			table.insert(pending, { Flag = flag, Api = api })
		end
	end
	table.sort(pending, function(a, b)
		local aToggle = a.Api.Kind == "Toggle"
		local bToggle = b.Api.Kind == "Toggle"
		if aToggle ~= bToggle then return not aToggle end
		return a.Api._RegistrationOrder < b.Api._RegistrationOrder
	end)

	local initialized, errors = 0, {}
	for _, entry in ipairs(pending) do
		local api = entry.Api
		if self.Flags[entry.Flag] == api and not api._CallbacksInitialized then
			local readOk, value = pcall(Private.ReadControlValue, api)
			if not readOk then
				table.insert(errors, { Flag = entry.Flag, Error = tostring(value) })
				warn("[SilentUI] Could not initialize '" .. entry.Flag .. "': " .. tostring(value))
			else
				api._CallbacksInitialized = true
				local info = { Source = "initialization", Action = "initialize" }
				local ok, err
				if api.Kind == "Textbox" then
					ok, err = pcall(api._InitializationCallback, Private.CopyConfigValue(value), false, info)
				elseif api.Kind == "AssetGrid" then
					ok, err = pcall(api._InitializationCallback, Private.CopyConfigValue(value), info,
						api.GetOption and api:GetOption() or nil)
				else
					ok, err = pcall(api._InitializationCallback, Private.CopyConfigValue(value), info)
				end
				if ok then
					initialized += 1
				else
					api._CallbacksInitialized = false
					table.insert(errors, { Flag = entry.Flag, Error = tostring(err) })
					warn("[SilentUI] Could not initialize '" .. entry.Flag .. "': " .. tostring(err))
				end
			end
		end
	end
	return #errors == 0, initialized, errors
end

SilentUI.GetFlag = SilentUI.GetValue
SilentUI.GetCurrentValues = SilentUI.GetValues

function Private.ResolveConfigFlag(flag)
	local current, visited = flag, {}
	while SilentUI.FlagMigrations[current] do
		if visited[current] then return nil, "cyclic flag migration" end
		visited[current] = true
		current = SilentUI.FlagMigrations[current]
	end
	return current
end

function Private.ConfigValuesEqual(first, second)
	if typeof(first) ~= typeof(second) or type(first) ~= type(second) then return false end
	if type(first) ~= "table" then return first == second end
	for key, value in pairs(first) do
		if not Private.ConfigValuesEqual(value, second[key]) then return false end
	end
	for key in pairs(second) do
		if first[key] == nil then return false end
	end
	return true
end

function Private.PrepareConfig(input)
	local data = input
	if type(data) == "string" then
		local ok, decoded = pcall(function() return HttpService:JSONDecode(data) end)
		if not ok or type(decoded) ~= "table" then return false, "Invalid configuration JSON" end
		data = decoded
	end
	if type(data) ~= "table" then return false, "Configuration must be a table or JSON string" end
	if type(data.Data) == "table" and data.Schema ~= nil then data = data.Data end

	local sourceKeys, errors = {}, {}
	for flag in pairs(data) do
		if type(flag) ~= "string" then
			table.insert(errors, "configuration keys must be strings")
		else
			table.insert(sourceKeys, flag)
		end
	end
	table.sort(sourceKeys)
	local migrated, origins, migrations = {}, {}, {}
	for _, sourceFlag in ipairs(sourceKeys) do
		local targetFlag, migrationErr = Private.ResolveConfigFlag(sourceFlag)
		if not targetFlag then
			table.insert(errors, sourceFlag .. ": " .. migrationErr)
		elseif origins[targetFlag] then
			table.insert(errors, "both '" .. origins[targetFlag] .. "' and '" .. sourceFlag .. "' resolve to '" .. targetFlag .. "'")
		else
			origins[targetFlag] = sourceFlag
			migrated[targetFlag] = data[sourceFlag]
			if sourceFlag ~= targetFlag then table.insert(migrations, { From = sourceFlag, To = targetFlag }) end
		end
	end
	if #errors > 0 then return false, table.concat(errors, "; ") end
	table.sort(migrations, function(a, b) return a.From < b.From end)

	local flags = {}
	for flag in pairs(migrated) do table.insert(flags, flag) end
	table.sort(flags)
	local staged = {}
	for _, flag in ipairs(flags) do
		local api = SilentUI.Flags[flag]
		if not api or type(api.Set) ~= "function" then
			table.insert(errors, flag .. ": unknown config flag")
		else
			local decodeOk, value = pcall(Private.Deserialize, migrated[flag])
			if not decodeOk then
				table.insert(errors, flag .. ": value could not be decoded: " .. tostring(value))
			else
				local validator = SilentUI.ConfigValidators[flag]
				if type(validator) ~= "function" then
					table.insert(errors, flag .. ": no validator is registered")
				else
					local ok, valid, normalized, reason = pcall(validator, value)
					if not ok then
						table.insert(errors, flag .. ": validator failed: " .. tostring(valid))
					elseif valid == true then
						table.insert(staged, { Flag = flag, Value = normalized })
					else
						table.insert(errors, flag .. ": " .. tostring(reason or normalized or "invalid value"))
					end
				end
			end
		end
	end
	if #errors > 0 then return false, table.concat(errors, "; ") end

	local changes = {}
	for _, entry in ipairs(staged) do
		local api = SilentUI.Flags[entry.Flag]
		local ok, current = pcall(Private.ReadControlValue, api)
		if not ok then return false, entry.Flag .. ": getter failed: " .. tostring(current) end
		if not Private.ConfigValuesEqual(current, entry.Value) then
			table.insert(changes, { Flag = entry.Flag, Before = Private.CopyConfigValue(current), After = Private.CopyConfigValue(entry.Value) })
		end
	end
	return true, { Staged = staged, Changes = changes, Migrations = migrations, changes = changes, migrations = migrations }
end

function SilentUI:PreviewConfig(data)
	local ok, prepared = Private.PrepareConfig(data)
	if not ok then return false, prepared end
	return true, { Changes = prepared.Changes, Migrations = prepared.Migrations, changes = prepared.Changes, migrations = prepared.Migrations }
end

function Private.RollbackConfigValues(applied)
	local errors = {}
	for index = #applied, 1, -1 do
		local prior = applied[index]
		local priorApi = SilentUI.Flags[prior.Flag]
		if priorApi and type(priorApi.Set) == "function" then
			local restored, restoreErr = pcall(priorApi.Set, priorApi, Private.CopyConfigValue(prior.Value), true)
			if not restored then table.insert(errors, prior.Flag .. ": " .. tostring(restoreErr)) end
		end
	end
	return errors
end

function SilentUI:SetConfig(data, silent)
	local ok, prepared = Private.PrepareConfig(data)
	if not ok then return false, prepared end
	local applied = {}
	local previousApplying = self._ApplyingConfig
	local previousSource = self._ChangeSource
	self._ApplyingConfig = true
	self._ChangeSource = "config"
	for _, entry in ipairs(prepared.Staged) do
		local api = self.Flags[entry.Flag]
		local readOk, snapshot = pcall(Private.ReadControlValue, api)
		if not readOk then
			local rollbackErrors = Private.RollbackConfigValues(applied)
			self._ApplyingConfig = previousApplying
			self._ChangeSource = previousSource
			local message = entry.Flag .. ": getter failed: " .. tostring(snapshot)
			if #rollbackErrors > 0 then message ..= "; rollback failed: " .. table.concat(rollbackErrors, ", ") end
			return false, message
		end
		table.insert(applied, { Flag = entry.Flag, Value = Private.CopyConfigValue(snapshot) })
		local setOk, setErr = pcall(api.Set, api, Private.CopyConfigValue(entry.Value), silent ~= false)
		if not setOk then
			local rollbackErrors = Private.RollbackConfigValues(applied)
			self._ApplyingConfig = previousApplying
			self._ChangeSource = previousSource
			local message = entry.Flag .. ": setter failed: " .. tostring(setErr)
			if #rollbackErrors > 0 then message ..= "; rollback failed: " .. table.concat(rollbackErrors, ", ") end
			return false, message
		end
	end
	self._ApplyingConfig = previousApplying
	self._ChangeSource = previousSource
	if not previousApplying and not self._ApplyingAutoConfig and self.SaveAutoConfig then
		local saved, saveErr = self:SaveAutoConfig()
		if not saved then warn("[SilentUI] config applied but automatic settings could not be saved: " .. tostring(saveErr)) end
	end
	ConfigLoadedSignal.Fire({
		Source = "config",
		Silent = silent ~= false,
		Changes = prepared.Changes,
		Migrations = prepared.Migrations,
		Values = self:GetValues(),
	})
	self:RefreshEnabledConditions()
	if self._RefreshFloatingBindings then self:_RefreshFloatingBindings() end
	return true, prepared.Migrations
end

function SilentUI:SetConfigJSON(configJson, silent)
	return self:SetConfig(configJson, silent)
end

function SilentUI:RegisterFlagMigration(oldFlag, newFlag)
	assert(type(oldFlag) == "string" and oldFlag:gsub("%s", "") ~= "", "old flag must be a non-empty string")
	assert(type(newFlag) == "string" and newFlag:gsub("%s", "") ~= "", "new flag must be a non-empty string")
	assert(oldFlag ~= newFlag, "old and new flags must be different")
	assert(not self.Flags[oldFlag], "cannot migrate active flag '" .. oldFlag .. "'")
	local existing = self.FlagMigrations[oldFlag]
	assert(existing == nil or existing == newFlag, "flag migration already targets '" .. tostring(existing) .. "'")
	local cursor, visited = newFlag, { [oldFlag] = true }
	while self.FlagMigrations[cursor] do
		assert(not visited[cursor], "flag migrations cannot contain a cycle")
		visited[cursor] = true
		cursor = self.FlagMigrations[cursor]
	end
	assert(cursor ~= oldFlag, "flag migrations cannot contain a cycle")
	self.FlagMigrations[oldFlag] = newFlag
	return true
end
 
function SilentUI:ListUIElements()
	local out = {}
	for flag, api in pairs(SilentUI.Flags) do
		local ok, value = pcall(Private.ReadControlValue, api)
		table.insert(out, {
			Flag  = flag,
			Kind  = api.Kind,
			Label = api.Label,
			Value = ok and value or nil,
		})
	end
	table.sort(out, function(a, b) return a.Flag < b.Flag end)
	return out
end
 
function SilentUI:SetUIElementValue(flag, value, silent)
	local api = SilentUI.Flags[flag]
	if not api or not api.Set then
		return false, "Unknown UI element: " .. tostring(flag)
	end
	local ok, err = pcall(api.Set, api, value, silent ~= false)
	if not ok then return false, tostring(err) end
	self:RefreshEnabledConditions()
	if self._RefreshFloatingBindings then self:_RefreshFloatingBindings() end
	return true
end

function SilentUI:RegisterCustomFlag(flag, opts)
	assert(type(flag) == "string" and flag:gsub("%s", "") ~= "", "custom flag must be a non-empty string")
	assert(type(opts) == "table" and type(opts.Get) == "function" and type(opts.Set) == "function",
		"custom flag expects Get and Set functions")
	local validator = opts.Validate or opts.Validator
	assert(validator == nil or type(validator) == "function", "custom flag Validate must be a function")
	if validator then
		local validate = validator
		validator = function(value)
			local result = table.pack(validate(value))
			if result[1] == true and result.n == 1 then return true, value end
			return table.unpack(result, 1, result.n)
		end
	end
	local signal = MakeSignal()
	local api = {
		Get = function() return opts.Get() end,
		Set = function(_, value, silent)
			local result = opts.Set(value, silent)
			if result == false then error("custom flag setter rejected the value", 2) end
			if not silent then signal.Fire(opts.Get(), ChangeInfo()) end
			return result
		end,
		OnChanged = function(_, callback) return signal.Connect(callback) end,
		NotifyChanged = function() signal.Fire(opts.Get(), ChangeInfo()) end,
		Destroy = function() signal.Clear() end,
	}
	return RegisterFlag({ Flag = flag, Text = opts.Text or flag }, api, "Custom", validator)
end

SilentUI.RegisterFlag = SilentUI.RegisterCustomFlag
SilentUI.SetFlag = SilentUI.SetUIElementValue
 
SilentUI.ConfigFolder = "Randoms"
SilentUI.SettingsDirectory = STORAGE_FOLDER .. "/Settings/Randoms"

function Private.EnsureDirectory(path)
	if not (Private.fn_isfolder and Private.fn_makefolder) then return false end
	local existsOk, exists = pcall(Private.fn_isfolder, path)
	if existsOk and exists then return true end
	pcall(Private.fn_makefolder, path)
	local retryOk, nowExists = pcall(Private.fn_isfolder, path)
	return retryOk and nowExists == true
end

function Private.EnsureSettingsDirectory()
	return Private.EnsureDirectory(STORAGE_FOLDER)
		and Private.EnsureDirectory(STORAGE_FOLDER .. "/Settings")
		and Private.EnsureDirectory(SilentUI.SettingsDirectory)
end

function Private.SafeConfigName(name)
	name = tostring(name or "config"):match("^%s*(.-)%s*$") or ""
	name = name:gsub("[^%w%._%- ]", "_"):gsub("%s+", "_"):gsub("%.+$", ""):sub(1, 64)
	if name == "" or name == "." or name == ".." then name = "config" end
	local reserved = string.upper(name)
	if reserved == "CON" or reserved == "PRN" or reserved == "AUX" or reserved == "NUL"
		or reserved:match("^COM[1-9]$") or reserved:match("^LPT[1-9]$") then
		name = "_" .. name
	end
	return name
end

function Private.SafeSettingsFolder(name)
	name = tostring(name or "Randoms"):match("^%s*(.-)%s*$") or ""
	name = name:gsub("[^%w%._%-]", "_"):gsub("%.+$", ""):sub(1, 64)
	if name == "" or name == "." or name == ".." then name = "Randoms" end
	local reserved = string.upper(name)
	if reserved == "CON" or reserved == "PRN" or reserved == "AUX" or reserved == "NUL"
		or reserved:match("^COM[1-9]$") or reserved:match("^LPT[1-9]$") then
		name = "_" .. name
	end
	return name
end

function Private.ConfigPath(name)
	return SilentUI.SettingsDirectory .. "/" .. SafeConfigName(name) .. ".cfg"
end

function Private.ConfigMetadataPath(path)
	return path .. ".meta.json"
end

function Private.BuildConfigEnvelope(name, data, meta)
	meta = meta or {}
	return {
		Schema      = 1,
		Name        = meta.Name or name,
		Description = meta.Description or "",
		Tags        = meta.Tags or {},
		CreatedAt   = meta.CreatedAt or os.time(),
		Data        = data,
	}
end
 
function Private.ReadConfigFile(path, fallbackName)
	if not (fn_isfile and fn_readfile) then return nil, "readfile unavailable" end
	local existsOk, exists = pcall(fn_isfile, path)
	if not existsOk or not exists then return nil, "config does not exist" end
	local ok, raw = pcall(fn_readfile, path)
	if not ok then return nil, raw end
	local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
	if not decodeOk then return nil, "failed to decode config" end
	if type(decoded) ~= "table" then return nil, "malformed config" end
	local envelope = type(decoded.Data) == "table" and decoded.Schema ~= nil
		and decoded or Private.BuildConfigEnvelope(fallbackName, decoded, {})
	if not envelope.Name then envelope.Name = fallbackName end
	local metadataPath = Private.ConfigMetadataPath(path)
	local metaExistsOk, metaExists = pcall(fn_isfile, metadataPath)
	if metaExistsOk and metaExists then
		local metaOk, metaRaw = pcall(fn_readfile, metadataPath)
		if metaOk then
			local metaDecodeOk, meta = pcall(function() return HttpService:JSONDecode(metaRaw) end)
			if metaDecodeOk and type(meta) == "table" then
				envelope.Name = meta.Name or envelope.Name or fallbackName
				envelope.Description = meta.Description or envelope.Description or ""
				envelope.Tags = meta.Tags or envelope.Tags or {}
				envelope.CreatedAt = meta.CreatedAt or envelope.CreatedAt or 0
			end
		end
	end
	return envelope, nil
end
 
function SilentUI:SaveConfig(name, opts)
	if not fn_writefile then return false, "writefile unavailable" end
	opts = opts or {}
	name = Private.SafeConfigName(name)
	if not Private.EnsureSettingsDirectory() then return false, "cannot create configuration folder" end
	local data, configErr = self:GetConfig()
	if not data then return false, configErr end
	local path = Private.ConfigPath(name)
	local saved, encoded = pcall(function() return HttpService:JSONEncode(data) end)
	if not saved then return false, tostring(encoded) end
	local writeOk, writeErr = pcall(fn_writefile, path, encoded)
	if not writeOk or writeErr == false then return false, tostring(writeErr or "writefile returned false") end
	local metadata = {
		Name = name,
		Description = opts.Description or "",
		Tags = opts.Tags or {},
		CreatedAt = opts.CreatedAt or os.time(),
	}
	local metadataOk, metadataJson = pcall(function() return HttpService:JSONEncode(metadata) end)
	if not metadataOk then return false, "config saved but metadata could not be encoded: " .. tostring(metadataJson) end
	local metaWriteOk, metaWriteErr = pcall(fn_writefile, Private.ConfigMetadataPath(path), metadataJson)
	if not metaWriteOk or metaWriteErr == false then return false, "config saved but metadata could not be written: " .. tostring(metaWriteErr or "writefile returned false") end
	return true
end
 
function Private.ReadNamedConfig(name)
	name = Private.SafeConfigName(name)
	local primary = Private.ReadConfigFile(Private.ConfigPath(name), name)
	if primary then return primary, Private.ConfigPath(name) end
	return nil, "config does not exist"
end

function SilentUI:LoadConfig(name, silent)
	local envelope, err = Private.ReadNamedConfig(name or "config")
	if not envelope then return false, err end
	return self:SetConfig(envelope.Data, silent)
end
 
function SilentUI:GetConfigMeta(name)
	local envelope, err = Private.ReadNamedConfig(name)
	if not envelope then return nil, err end
	return {
		Name        = envelope.Name or name,
		Description = envelope.Description or "",
		Tags        = envelope.Tags or {},
		CreatedAt   = envelope.CreatedAt,
	}
end
 
function SilentUI:GetSavedConfig(name)
	local envelope, err = Private.ReadNamedConfig(name)
	if not envelope then return nil, err end
	return envelope, nil
end
 
function SilentUI:ListConfigs()
	if not Private.fn_listfiles then return {}, "listfiles unavailable" end
	Private.EnsureSettingsDirectory()
	local directories = { SilentUI.SettingsDirectory }
	local out, seen = {}, {}
	for _, directory in ipairs(directories) do
		local ok, files = pcall(Private.fn_listfiles, directory)
		if ok and type(files) == "table" then
			for _, path in ipairs(files) do
				if type(path) == "string" then
					local normalized = path:gsub("\\", "/")
					local fileName = normalized:match("([^/]+)%.cfg$") or normalized:match("([^/]+)%.json$")
					if fileName and not fileName:match("%.meta$") and fileName ~= "cloud_identity" and fileName ~= "default_config" then
						local envelope = Private.ReadConfigFile(path, fileName)
						local name = envelope and Private.SafeConfigName(envelope.Name or fileName)
						if envelope and not seen[name] then
							seen[name] = true
							table.insert(out, {
								Name = envelope.Name or fileName,
								FileName = fileName,
							Description = envelope.Description or "",
							Tags = envelope.Tags or {},
							CreatedAt = envelope.CreatedAt or 0,
							})
						end
					end
				end
			end
		end
	end
	table.sort(out, function(a, b) return (a.CreatedAt or 0) > (b.CreatedAt or 0) end)
	return out, nil
end
 
function SilentUI:DeleteConfig(name)
	if not (fn_isfile and fn_delfile) then return false, "delfile unavailable" end
	local removed, errors = false, {}
	local paths = { Private.ConfigPath(name), Private.ConfigMetadataPath(Private.ConfigPath(name)) }
	for _, path in ipairs(paths) do
		local existsOk, exists = pcall(fn_isfile, path)
		if existsOk and exists then
			local delOk, err = pcall(fn_delfile, path)
			if delOk then removed = true else table.insert(errors, tostring(err)) end
		end
	end
	if #errors > 0 then return false, table.concat(errors, "; ") end
	if not removed then return false, "config does not exist" end
	return true
end
 
function SilentUI:RenameConfig(oldName, newName)
	local envelope, oldPath = Private.ReadNamedConfig(oldName)
	if not envelope then return false, oldPath end
	local newSafeName = Private.SafeConfigName(newName)
	if not (fn_writefile and Private.EnsureSettingsDirectory()) then return false, "cannot create configuration folder" end
	local newPath = Private.ConfigPath(newSafeName)
	local dataOk, dataJson = pcall(function() return HttpService:JSONEncode(envelope.Data) end)
	if not dataOk then return false, tostring(dataJson) end
	local writeOk, writeErr = pcall(fn_writefile, newPath, dataJson)
	if not writeOk or writeErr == false then return false, tostring(writeErr or "writefile returned false") end
	local metadata = {
		Name = newSafeName,
		Description = envelope.Description or "",
		Tags = envelope.Tags or {},
		CreatedAt = envelope.CreatedAt or os.time(),
	}
	local metaOk, metaJson = pcall(function() return HttpService:JSONEncode(metadata) end)
	if not metaOk then return false, "config renamed but metadata could not be encoded: " .. tostring(metaJson) end
	local metaWriteOk, metaWriteErr = pcall(fn_writefile, Private.ConfigMetadataPath(newPath), metaJson)
	if not metaWriteOk or metaWriteErr == false then return false, "config renamed but metadata could not be written: " .. tostring(metaWriteErr or "writefile returned false") end
	if oldPath ~= Private.ConfigPath(newSafeName) then
		for _, path in ipairs({ oldPath, Private.ConfigMetadataPath(oldPath) }) do
			if fn_isfile and fn_delfile then
				local existsOk, exists = pcall(fn_isfile, path)
				if existsOk and exists then pcall(fn_delfile, path) end
			end
		end
	end
	return true
end
 
function SilentUI:CreateSnapshot()
	return { Data = SilentUI:GetConfig(), CreatedAt = os.time() }
end
 
function SilentUI:RestoreSnapshot(snapshot, silent)
	if type(snapshot) ~= "table" or type(snapshot.Data) ~= "table" then
		return false, "invalid snapshot"
	end
	return SilentUI:SetConfig(snapshot.Data, silent)
end

function SilentUI:SetConfigFolder(name)
	local previousDirectory = self.SettingsDirectory
	self.ConfigFolder = Private.SafeSettingsFolder(name)
	self.SettingsDirectory = STORAGE_FOLDER .. "/Settings/" .. self.ConfigFolder
	self.settings_folder = self.ConfigFolder
	self.settings_directory = self.SettingsDirectory
	self.directory = STORAGE_FOLDER
	if previousDirectory ~= self.SettingsDirectory then
		self._AutoConfigLoadGeneration = (self._AutoConfigLoadGeneration or 0) + 1
		self._AutoConfigCheckedPath = nil
		self._AutoConfigPending = nil
		self._AutoConfigApplied = nil
	end
	self.SettingsDirectoryAvailable = Private.EnsureSettingsDirectory()
	self.settings_directory_available = self.SettingsDirectoryAvailable
	return self.ConfigFolder
end

function Private.AutoConfigPath()
	return SilentUI.SettingsDirectory .. "/default_config.json"
end

function SilentUI:_QueueAutoConfigLoaded()
	if type(self._AutoConfigPending) ~= "table" then return end
	self._AutoConfigLoadGeneration = (self._AutoConfigLoadGeneration or 0) + 1
	local generation = self._AutoConfigLoadGeneration
	task.delay(0.2, function()
		if self._AutoConfigLoadGeneration ~= generation or type(self._AutoConfigPending) ~= "table" then return end
		local applied, pending = {}, {}
		for sourceFlag in pairs(self._AutoConfigPending) do
			if self._AutoConfigApplied and self._AutoConfigApplied[sourceFlag] then
				table.insert(applied, sourceFlag)
			else
				table.insert(pending, sourceFlag)
			end
		end
		table.sort(applied)
		table.sort(pending)
		ConfigLoadedSignal.Fire({
			Source = "auto",
			Silent = true,
			AppliedFlags = applied,
			PendingFlags = pending,
			Values = self:GetValues(),
		})
	end)
end

function SilentUI:LoadAutoConfig()
	local path = Private.AutoConfigPath()
	if self._AutoConfigCheckedPath == path then return false end
	self._AutoConfigCheckedPath = path
	if not (fn_isfile and fn_readfile) then return false end
	local existsOk, exists = pcall(fn_isfile, path)
	if not existsOk or not exists then return false end
	local readOk, raw = pcall(fn_readfile, path)
	if not readOk then warn("[SilentUI] automatic settings could not be read: " .. tostring(raw)); return false end
	local decodeOk, data = pcall(function() return HttpService:JSONDecode(raw) end)
	if not decodeOk or type(data) ~= "table" then
		warn("[SilentUI] automatic settings are malformed; using control defaults")
		return false
	end
	if type(data.Data) == "table" and data.Schema ~= nil then data = data.Data end
	self._AutoConfigPending = data
	self._AutoConfigApplied = {}
	for flag in pairs(self.Flags) do self:ApplyAutoConfigFlag(flag) end
	self:_QueueAutoConfigLoaded()
	return true
end

function SilentUI:ApplyAutoConfigFlag(flag)
	local pending = self._AutoConfigPending
	local api = self.Flags[flag]
	if type(pending) ~= "table" or not api then return false end
	local sources = {}
	for sourceFlag, value in pairs(pending) do
		local targetFlag = Private.ResolveConfigFlag(sourceFlag)
		if value ~= nil and targetFlag == flag then table.insert(sources, sourceFlag) end
	end
	table.sort(sources)
	if #sources == 0 then return false end
	if #sources > 1 then
		warn("[SilentUI] automatic settings contain conflicting values for '" .. flag .. "'; skipped")
		return false
	end
	local sourceFlag = sources[1]
	local decodeOk, value = pcall(Private.Deserialize, pending[sourceFlag])
	if not decodeOk then
		warn("[SilentUI] saved setting for '" .. flag .. "' could not be decoded: " .. tostring(value))
		return false
	end
	local validator = self.ConfigValidators[flag]
	if type(validator) ~= "function" then
		warn("[SilentUI] saved setting for '" .. flag .. "' was skipped: no validator is registered")
		return false
	end
	local ok, valid, normalized, reason = pcall(validator, value)
	if not ok or valid ~= true then
		warn("[SilentUI] saved setting for '" .. flag .. "' was skipped: " .. tostring(reason or normalized or valid))
		return false
	end
	local getOk, snapshot = pcall(Private.ReadControlValue, api)
	if not getOk then
		warn("[SilentUI] saved setting for '" .. flag .. "' could not be applied: getter failed: " .. tostring(snapshot))
		return false
	end
	local previousApplying = self._ApplyingConfig
	local previousAutoApplying = self._ApplyingAutoConfig
	self._ApplyingConfig = true
	self._ApplyingAutoConfig = true
	local setOk, setErr = pcall(api.Set, api, normalized, true)
	if not setOk then pcall(api.Set, api, Private.CopyConfigValue(snapshot), true) end
	self._ApplyingAutoConfig = previousAutoApplying
	self._ApplyingConfig = previousApplying
	if not setOk then
		warn("[SilentUI] saved setting for '" .. flag .. "' could not be applied: " .. tostring(setErr))
		return false
	end
	self._AutoConfigApplied = self._AutoConfigApplied or {}
	self._AutoConfigApplied[sourceFlag] = true
	self:_QueueAutoConfigLoaded()
	return true
end

function SilentUI:SaveAutoConfig()
	if not Private.EnsureSettingsDirectory() then return false, "cannot create settings folder" end
	local data, err = self:GetConfig()
	if not data then return false, err end
	for sourceFlag, value in pairs(self._AutoConfigPending or {}) do
		local targetFlag = Private.ResolveConfigFlag(sourceFlag)
		if not targetFlag or not self.Flags[targetFlag] then data[sourceFlag] = value end
	end
	local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
	if not ok then return false, tostring(encoded) end
	if not fn_writefile then return false, "writefile unavailable" end
	local writeOk, writeErr = pcall(fn_writefile, Private.AutoConfigPath(), encoded)
	if not writeOk or writeErr == false then return false, tostring(writeErr or "writefile returned false") end
	self._AutoConfigPending = data
	return true
end

function SilentUI:QueueAutoConfigSave()
	if self._AutoConfigSaveScheduled then return end
	self._AutoConfigSaveScheduled = true
	local generation = self._AutoConfigSaveGeneration or 0
	local function save()
		if generation ~= (self._AutoConfigSaveGeneration or 0) then return end
		self._AutoConfigSaveScheduled = false
		if not self._ApplyingConfig then
			local ok, err = self:SaveAutoConfig()
			if not ok then warn("[SilentUI] automatic settings could not be saved: " .. tostring(err)) end
		end
	end
	if task and type(task.defer) == "function" then task.defer(save) else save() end
end


function SilentUI:GetInitialValue(flag)
	local api = self.Flags[flag]
	if not api or not api._HasInitialValue then return nil, "default unavailable for " .. tostring(flag) end
	return CopyInitialFlagValue(api._InitialValue)
end

-- Restores registered flags without mutating private helpers or replacing save methods.
-- By default only the automatic settings file is deleted; named profiles are retained.
function SilentUI:ResetConfiguration(opts)
	opts = opts or {}
	local clearAuto = opts.ClearAutoConfig ~= false
	local clearNamed = opts.ClearSavedConfigs == true
	local runCallbacks = opts.RunCallbacks ~= false
	if clearAuto and not fn_delfile and fn_isfile then
		local ok, exists = pcall(fn_isfile, Private.AutoConfigPath())
		if ok and exists then return false, "delfile is unavailable" end
	end
	local ordered, snapshots = {}, {}
	for flag, api in pairs(self.Flags) do
		if api._HasInitialValue then
			local ok, oldValue = pcall(Private.ReadControlValue, api)
			if not ok then return false, flag .. ": could not read value: " .. tostring(oldValue) end
			table.insert(ordered, { Flag = flag, Api = api })
			snapshots[flag] = CopyInitialFlagValue(oldValue)
		end
	end
	table.sort(ordered, function(a, b)
		local at, bt = a.Api.Kind == "Toggle", b.Api.Kind == "Toggle"
		if at ~= bt then return not at end
		return a.Flag < b.Flag
	end)
	local oldApplying, oldAuto = self._ApplyingConfig, self._ApplyingAutoConfig
	self._ApplyingConfig = true
	self._ApplyingAutoConfig = true
	local errors = {}
	for _, entry in ipairs(ordered) do
		local ok, err = pcall(entry.Api.Set, entry.Api, CopyInitialFlagValue(entry.Api._InitialValue), true)
		if not ok then
			table.insert(errors, entry.Flag .. ": " .. tostring(err))
			break
		end
	end
	if #errors > 0 then
		for _, entry in ipairs(ordered) do
			pcall(entry.Api.Set, entry.Api, CopyInitialFlagValue(snapshots[entry.Flag]), true)
		end
		self._ApplyingAutoConfig, self._ApplyingConfig = oldAuto, oldApplying
		self:RefreshEnabledConditions()
		return false, table.concat(errors, "; ")
	end
	self._AutoConfigSaveGeneration = (self._AutoConfigSaveGeneration or 0) + 1
	self._AutoConfigSaveScheduled = false
	self._AutoConfigLoadGeneration = (self._AutoConfigLoadGeneration or 0) + 1
	self._AutoConfigPending = {}
	self._AutoConfigApplied = {}
	self._AutoConfigCheckedPath = Private.AutoConfigPath()
	if runCallbacks then
		for _, entry in ipairs(ordered) do
			local cb = entry.Api._InitializationCallback
			if type(cb) == "function" then
				local info = { Source = "reset", Action = "reset" }
				local value = CopyInitialFlagValue(entry.Api._InitialValue)
				local ok, err
				if entry.Api.Kind == "Textbox" then
					ok, err = pcall(cb, value, false, info)
				elseif entry.Api.Kind == "AssetGrid" then
					ok, err = pcall(cb, value, info, entry.Api.GetOption and entry.Api:GetOption() or nil)
				else
					ok, err = pcall(cb, value, info)
				end
				if not ok then table.insert(errors, entry.Flag .. " callback: " .. tostring(err)) end
			end
		end
	end
	if clearAuto and fn_isfile and fn_delfile then
		local path = Private.AutoConfigPath()
		local ok, exists = pcall(fn_isfile, path)
		if ok and exists then
			local deleted, err = pcall(fn_delfile, path)
			if not deleted or err == false then
				table.insert(errors, "auto config: " .. tostring(err))
			end
		end
	end
	if clearNamed then
		local configs, listErr = self:ListConfigs()
		if listErr then table.insert(errors, tostring(listErr)) end
		for _, item in ipairs(configs) do
			local ok, err = self:DeleteConfig(item.FileName)
			if not ok then table.insert(errors, tostring(item.FileName) .. ": " .. tostring(err)) end
		end
	end
	self._ApplyingAutoConfig, self._ApplyingConfig = oldAuto, oldApplying
	self:RefreshEnabledConditions()
	if self._RefreshFloatingBindings then self:_RefreshFloatingBindings() end
	if not clearAuto then
		local saved, err = self:SaveAutoConfig()
		if not saved then table.insert(errors, "save defaults: " .. tostring(err)) end
	end
	ConfigLoadedSignal.Fire({ Source = "reset", Silent = true, Values = self:GetValues() })
	return #errors == 0, #errors == 0 and #ordered or table.concat(errors, "; ")
end

SilentUI.get_config = SilentUI.GetConfigJSON
SilentUI.preview_config = SilentUI.PreviewConfig
SilentUI.load_config = SilentUI.SetConfigJSON
SilentUI.register_flag_migration = SilentUI.RegisterFlagMigration
SilentUI.load_auto_config = SilentUI.LoadAutoConfig
SilentUI.save_auto_config = SilentUI.SaveAutoConfig
 
Private.CLOUD_TOKENS_PATH = STORAGE_FOLDER .. "/cloud_tokens.json"
Private.OLD_CLOUD_IDENTITY_PATH = STORAGE_FOLDER .. "/cloud_identity.json"

function Private.LoadCloudTokens()
	if fn_isfile and fn_readfile then
		for _, path in ipairs({ Private.CLOUD_TOKENS_PATH, Private.OLD_CLOUD_IDENTITY_PATH }) do
			local existsOk, exists = pcall(fn_isfile, path)
			if existsOk and exists then
				local ok, raw = pcall(fn_readfile, path)
				if ok then
					local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
					if decodeOk and type(decoded) == "table" and type(decoded.Tokens) == "table" then
						return decoded.Tokens
					end
				end
			end
		end
	end
	return {}
end

function Private.SaveCloudTokens(tokens)
	if not fn_writefile then
		if fn_isfile and fn_delfile then
			local existsOk, exists = pcall(fn_isfile, Private.OLD_CLOUD_IDENTITY_PATH)
			if existsOk and exists then pcall(fn_delfile, Private.OLD_CLOUD_IDENTITY_PATH) end
		end
		return false
	end
	Private.EnsureAssetsFolder()
	local encodeOk, encoded = pcall(function() return HttpService:JSONEncode({ Tokens = tokens }) end)
	if not encodeOk then return false end
		local writeOk, writeResult = pcall(fn_writefile, Private.CLOUD_TOKENS_PATH, encoded)
		if not writeOk or writeResult == false then return false end

	if fn_isfile then
		local existsOk, exists = pcall(fn_isfile, Private.OLD_CLOUD_IDENTITY_PATH)
		if existsOk and exists then
			if fn_delfile then pcall(fn_delfile, Private.OLD_CLOUD_IDENTITY_PATH) end
			local checkOk, stillExists = pcall(fn_isfile, Private.OLD_CLOUD_IDENTITY_PATH)
			if checkOk and stillExists then pcall(fn_writefile, Private.OLD_CLOUD_IDENTITY_PATH, encoded) end
		end
	end
	return true
end
 
Private.CLOUD_PUBLISH_COOLDOWN = 15
Private.LastCloudPublishAt = 0
 
function SilentUI:CloudService(opts)
	opts = opts or {}
	local baseUrl = opts.BaseUrl
	local cloudTokens = Private.LoadCloudTokens()
	Private.SaveCloudTokens(cloudTokens)
	local httpRequest = (syn and syn.request) or http_request or request
 
	local function apiRequest(method, path, body, extraHeaders)
		if not httpRequest then
			return nil, "Your executor doesn't support HTTP requests."
		end
		if not baseUrl or baseUrl == "" then
			return nil, "No cloud BaseUrl configured -- point CloudService's BaseUrl at your own backend."
		end
 
		local headers = {
			["Content-Type"] = "application/json",
		}
		if extraHeaders then
			for k, v in pairs(extraHeaders) do headers[k] = v end
		end
 
		local ok, res = pcall(httpRequest, {
			Url = baseUrl .. path,
			Method = method,
			Headers = headers,
			Body = body and HttpService:JSONEncode(body) or nil,
		})
		if not ok then return nil, tostring(res) end
 
		if res.StatusCode and (res.StatusCode < 200 or res.StatusCode >= 300) then
			local message = res.Body
			local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(res.Body) end)
			if decodeOk and type(decoded) == "table" and decoded.error then
				message = tostring(decoded.error)
			end
			return nil, "HTTP " .. tostring(res.StatusCode) .. ": " .. tostring(message)
		end
 
		if res.Body == nil or res.Body == "" then return {}, nil end
		local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(res.Body) end)
		if not decodeOk then return nil, "Failed to decode response." end
		return decoded, nil
	end
 
	local api = {}
 
	function api:List(state)
		state = state or {}
		local query = "?sort=" .. HttpService:UrlEncode(state.Sort or "top")
		if state.Query and state.Query ~= "" then
			query = query .. "&q=" .. HttpService:UrlEncode(state.Query)
		end
		if state.Cursor then
			query = query .. "&cursor=" .. HttpService:UrlEncode(tostring(state.Cursor))
		end
		query = query .. "&limit=" .. tostring(state.PageSize or 20)
 
		local decoded, err = apiRequest("GET", "/configs" .. query)
		if not decoded then return nil, err end
		return decoded.Items or {}, decoded.NextCursor
	end
 
	function api:ListMine()
		local decoded, err = apiRequest("GET", "/configs/mine")
		if not decoded then return nil, err end
		return decoded.Items or {}
	end
 
	function api:GetByShareCode(shareCode)
		return apiRequest("GET", "/configs/code/" .. HttpService:UrlEncode(tostring(shareCode)))
	end
 
	function api:Publish(meta, data)
		meta = meta or {}
		local now = os.clock()
		if now - Private.LastCloudPublishAt < Private.CLOUD_PUBLISH_COOLDOWN then
			return nil, string.format(
				"Please wait %ds before publishing again.",
				math.ceil(Private.CLOUD_PUBLISH_COOLDOWN - (now - Private.LastCloudPublishAt))
			)
		end
 
		local cleanName, nameBlocked = SilentUI:SanitizeText(meta.Name, { MaxLength = 60 })
		if nameBlocked or cleanName == "" then
			return nil, "Name was empty or blocked by the content filter."
		end
		local cleanDesc, descBlocked = SilentUI:SanitizeText(meta.Description or "", { MaxLength = 280 })
		if descBlocked then
			return nil, "Description was blocked by the content filter."
		end
 
		local cleanTags = {}
		for _, tag in ipairs(meta.Tags or {}) do
			local cleanTag = SilentUI:SanitizeText(tag, { MaxLength = 24 })
			if cleanTag ~= "" then table.insert(cleanTags, cleanTag) end
			if #cleanTags >= 8 then break end
		end
 
		Private.LastCloudPublishAt = now
 
		local decoded, err = apiRequest("POST", "/configs", {
			Name = cleanName,
			Description = cleanDesc,
			Tags = cleanTags,
			Data = data or SilentUI:GetConfig(),
		})
		if not decoded then return nil, err end
 
		if decoded.Id and decoded.OwnerToken then
			cloudTokens[decoded.Id] = decoded.OwnerToken
			Private.SaveCloudTokens(cloudTokens)
		end
		return decoded
	end
 
	function api:Delete(id)
		local token = cloudTokens[id]
		if not token then
			return false, "You don't have publish rights for this config on this device."
		end
		local decoded, err = apiRequest("DELETE", "/configs/" .. id, nil, {
			["X-SilentUI-Owner-Token"] = token,
		})
		if not decoded then return false, err end
		cloudTokens[id] = nil
		Private.SaveCloudTokens(cloudTokens)
		return true
	end
 
	function api:Like(id)
		local decoded, err = apiRequest("POST", "/configs/" .. id .. "/like")
		if not decoded then return false, err end
		return true
	end
 
	function api:Download(id)
		return apiRequest("POST", "/configs/" .. id .. "/download")
	end
 
	function api:SendChatMessage(text)
		return apiRequest("POST", "/chat/send", { Text = text })
	end
 
	function api:PollChatMessages(sinceId)
		local decoded, err = apiRequest("GET", "/chat?since=" .. tostring(sinceId or 0))
		if not decoded then return nil, err end
		return decoded.Messages or {}
	end
 
	function api:ReportChatMessage(messageId)
		local decoded, err = apiRequest("POST", "/chat/" .. tostring(messageId) .. "/report")
		if not decoded then return false, err end
		return true
	end
 
	return api
end
 
-- Shared drag controller for detachable bubbles and state panels.
local FloatingInternals = {
    Registry = {},
    ByFrame = {},
    ActiveDrag = nil,
    NextOrder = 0,
    Gap = 10,
    Margin = 12,
    ReflowQueued = false,
}

function FloatingInternals.Color(value, fallback)
    return typeof(value) == "Color3" and value or fallback
end

function FloatingInternals.Image(value)
    if type(value) == "number" then return "rbxassetid://" .. tostring(value) end
    if type(value) == "string" and value:match("^%d+$") then return "rbxassetid://" .. value end
    if type(value) == "string" then return ResolveIcon(value) end
    return ""
end

function FloatingInternals.GetFrame(widget)
    return widget and (widget.Instance or widget.Frame)
end

function FloatingInternals.GetViewport()
    local scale = math.max(GetUIScale(), 0.01)
    local view = Private.ViewportSize() / scale
    return view, scale
end

function FloatingInternals.GetLogicalRect(frame, scale)
    local root = SilentUI._Root
    if not frame or not frame.Parent or not root then return nil end
    local localScale = 1
    local widget = FloatingInternals.ByFrame[frame]
    if widget and widget._FloatingScale then
        localScale = math.max(widget._FloatingScale.Scale, 0.01)
    end
    local absolutePosition = (frame.AbsolutePosition - root.AbsolutePosition) / scale
    local absoluteSize = frame.AbsoluteSize / (scale * localScale)
    if absoluteSize.X <= 0 or absoluteSize.Y <= 0 then
        absoluteSize = Vector2.new(
            frame.Size.X.Offset > 0 and frame.Size.X.Offset or 52,
            frame.Size.Y.Offset > 0 and frame.Size.Y.Offset or 44
        )
    end
    return {
        X = absolutePosition.X,
        Y = absolutePosition.Y,
        W = absoluteSize.X,
        H = absoluteSize.Y,
    }
end

function FloatingInternals.SetPosition(widget, x, y, animate)
    local frame = FloatingInternals.GetFrame(widget)
    if not frame or not frame.Parent then return end
    local target = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
    if animate then
        Tween(frame, { Position = target }, 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    else
        frame.Position = target
    end
end

function FloatingInternals.Bounce(widget)
    local frame = FloatingInternals.GetFrame(widget)
    if not frame or not frame.Parent then return end
    local bounceScale = widget._FloatingBounceScale
    if not bounceScale then
        bounceScale = Instance.new("UIScale")
        bounceScale.Name = "SilentFloatingBounceScale"
        bounceScale.Scale = 1
        bounceScale.Parent = frame
        widget._FloatingBounceScale = bounceScale
    end
    bounceScale.Scale = 0.94
    Tween(bounceScale, { Scale = 1 }, 0.34, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
end

function FloatingInternals.IsOverlapping(a, b, gap)
    return a.X < b.X + b.W + gap
        and a.X + a.W + gap > b.X
        and a.Y < b.Y + b.H + gap
        and a.Y + a.H + gap > b.Y
end

function FloatingInternals.ResolveCollision(widget, requestedX, requestedY, animate)
    local frame = FloatingInternals.GetFrame(widget)
    if not frame or not frame.Parent then return false end
    local view, scale = FloatingInternals.GetViewport()
    local own = FloatingInternals.GetLogicalRect(frame, scale)
    if not own then return false end

    local margin = math.min(
        FloatingInternals.Margin,
        math.max(0, (view.X - 1) / 2),
        math.max(0, (view.Y - 1) / 2)
    )
    local gap = FloatingInternals.Gap
    local availableWidth = math.max(1, view.X - margin * 2)
    local availableHeight = math.max(1, view.Y - margin * 2)
    if own.W > availableWidth or own.H > availableHeight then
        widget._FloatingAutoStack = true
        FloatingInternals.Reflow(true)
        return false
    end
    local x = math.clamp(tonumber(requestedX) or own.X, margin, math.max(margin, view.X - own.W - margin))
    local y = math.clamp(tonumber(requestedY) or own.Y, margin, math.max(margin, view.Y - own.H - margin))
    local others = {}
    for other in pairs(FloatingInternals.Registry) do
        if other ~= widget and not other._Destroyed and other.Instance and other.Instance.Visible then
            local rect = FloatingInternals.GetLogicalRect(other.Instance, scale)
            if rect then table.insert(others, rect) end
        end
    end
    table.sort(others, function(left, right) return left.Y < right.Y end)

    for _ = 1, math.max(8, #others * 3) do
        local candidate = { X = x, Y = y, W = own.W, H = own.H }
        local collision = nil
        for _, otherRect in ipairs(others) do
            if FloatingInternals.IsOverlapping(candidate, otherRect, gap) then
                collision = otherRect
                break
            end
        end
        if not collision then
            FloatingInternals.SetPosition(widget, x, y, animate)
            return true
        end

        y = collision.Y + collision.H + gap
        if y + own.H > view.Y - margin then
            y = margin
            x = collision.X + collision.W + gap
        end
        if x + own.W > view.X - margin then
            -- Try a clean vertical slot at the left edge. Never restore the old
            -- position: keep the drag result and place it in the next free slot.
            x = margin
            y = collision.Y + collision.H + gap
            if y + own.H > view.Y - margin then
                y = margin
                x = collision.X + collision.W + gap
            end
            if x + own.W > view.X - margin or y + own.H > view.Y - margin then
                FloatingInternals.Bounce(widget)
                return false
            end
        end
    end

    FloatingInternals.Bounce(widget)
    return false
end

function FloatingInternals.Reflow(animate)
    if FloatingInternals.ReflowQueued then return end
    FloatingInternals.ReflowQueued = true
    task.defer(function()
        FloatingInternals.ReflowQueued = false
        local view, globalScale = FloatingInternals.GetViewport()
        local list = {}
        local maxWidth, totalHeight = 0, 0
        for widget in pairs(FloatingInternals.Registry) do
            local frame = FloatingInternals.GetFrame(widget)
            if not widget._Destroyed and widget._FloatingAutoStack and frame and frame.Parent and frame.Visible then
                local rect = FloatingInternals.GetLogicalRect(frame, globalScale)
                if rect then
                    table.insert(list, { Widget = widget, Rect = rect })
                    maxWidth = math.max(maxWidth, rect.W)
                    totalHeight += rect.H
                end
            end
        end
        table.sort(list, function(a, b)
            return (a.Widget._FloatingOrder or 0) < (b.Widget._FloatingOrder or 0)
        end)
        if #list == 0 then return end

        local margin = math.min(
            FloatingInternals.Margin,
            math.max(0, (view.X - 1) / 2),
            math.max(0, (view.Y - 1) / 2)
        )
        local availableHeight = math.max(1, view.Y - margin * 2)
        local availableWidth = math.max(1, view.X - margin * 2)
        local gap = #list > 1 and math.min(FloatingInternals.Gap, availableHeight / (#list - 1)) or 0
        local requiredHeight = totalHeight + gap * (#list - 1)
        local fit = math.min(
            1,
            availableHeight / math.max(requiredHeight, 1),
            availableWidth / math.max(maxWidth, 1)
        )
        fit = math.clamp(fit, 0.001, 1)

        local y = margin
        for _, item in ipairs(list) do
            local widget, rect = item.Widget, item.Rect
            if widget._FloatingScale then widget._FloatingScale.Scale = fit end
            local width = rect.W * fit
            local height = rect.H * fit
            local x = math.clamp(margin, margin, math.max(margin, view.X - width - margin))
            FloatingInternals.SetPosition(widget, x, y, animate == true)
            y += height + gap
        end

        -- User-positioned panels remain movable, but are clamped and pushed clear of all others.
        for widget in pairs(FloatingInternals.Registry) do
            local frame = FloatingInternals.GetFrame(widget)
            if not widget._Destroyed and not widget._FloatingAutoStack and frame and frame.Parent and frame.Visible then
                local rect = FloatingInternals.GetLogicalRect(frame, globalScale)
                if rect then FloatingInternals.ResolveCollision(widget, rect.X, rect.Y, false) end
            end
        end
    end)
end

function FloatingInternals.Register(widget, opts, scope)
    opts = opts or {}
    local frame = FloatingInternals.GetFrame(widget)
    if not frame then return end
    FloatingInternals.NextOrder += 1
    widget._FloatingOrder = FloatingInternals.NextOrder
    widget._FloatingAutoStack = opts.AutoStack ~= false
    widget._FloatingKind = widget._FloatingKind or (widget.Header and "StateList" or "Bubble")
    local scale = Instance.new("UIScale")
    scale.Name = "SilentFloatingLayoutScale"
    scale.Scale = 1
    scale.Parent = frame
    widget._FloatingScale = scale
    FloatingInternals.Registry[widget] = true
    FloatingInternals.ByFrame[frame] = widget
    SilentUI._FloatingWidgets[widget] = true
    if widget._FloatingKind == "StateList" then
        SilentUI._StateLists[widget] = true
        if widget.SetVisible then widget:SetVisible(SilentUI.UserSettings.ShowStatePanels) end
        if widget.SetStatusVisible then widget:SetStatusVisible(SilentUI.UserSettings.ShowStateValues) end
        if widget.SetLocked then widget:SetLocked(widget._FloatingLocked or SilentUI.UserSettings.LockStatePanels) end
        if widget.SetPassThrough then widget:SetPassThrough(widget._FloatingPassThrough or SilentUI.UserSettings.StatePanelsPassThrough) end
    elseif widget.SetVisible then
        widget:SetVisible(SilentUI.UserSettings.ShowFloatingWidgets)
    end
    scope:Add(function()
        FloatingInternals.Registry[widget] = nil
        FloatingInternals.ByFrame[frame] = nil
        SilentUI._FloatingWidgets[widget] = nil
        SilentUI._StateLists[widget] = nil
        if widget._FloatingScale then widget._FloatingScale = nil end
        task.defer(function() FloatingInternals.Reflow(true) end)
    end)
    scope:Add(SilentUI._Root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        FloatingInternals.Reflow(false)
    end))
    scope:Add(GlobalScale:GetPropertyChangedSignal("Scale"):Connect(function()
        FloatingInternals.Reflow(false)
    end))
    -- AutomaticSize.Y can settle after AddItem() and after font/viewport changes.
    -- Reflow from the final AbsoluteSize so adjacent floating panels never use stale heights.
    scope:Add(frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        FloatingInternals.Reflow(false)
    end))
    task.defer(function() FloatingInternals.Reflow(false) end)
end

function FloatingInternals.RegisterDrag(handle, frame, onTap, draggable, scope, _allowOffscreen, widget)
    widget = widget or FloatingInternals.ByFrame[frame]
    handle.Active = not (widget and widget._FloatingPassThrough)
    handle.Selectable = handle.Active
    scope:Add(handle.InputBegan:Connect(function(input)
        if widget and (widget._FloatingLocked or widget._FloatingPassThrough) then return end
        if FloatingInternals.ActiveDrag then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local view, scale = FloatingInternals.GetViewport()
        local root = SilentUI._Root
        local pos = (frame.AbsolutePosition - root.AbsolutePosition) / scale
        if widget then
            -- AutoStack only controls the initial placement. Once dragged, the
            -- widget keeps its user-selected position and is no longer reflowed.
            widget._FloatingAutoStack = false
        end
        FloatingInternals.ActiveDrag = {
            Input = input,
            Frame = frame,
            Widget = widget,
            Start = Vector2.new(input.Position.X, input.Position.Y),
            Position = pos,
            Moved = false,
            Draggable = draggable ~= false,
            OnTap = onTap,
            EdgeFeedback = false,
        }
    end))
    scope:Add(function()
        if FloatingInternals.ActiveDrag and FloatingInternals.ActiveDrag.Frame == frame then
            FloatingInternals.ActiveDrag = nil
        end
    end)
end

LibJanitor:Add(UserInputService.InputChanged:Connect(function(input)
    local drag = FloatingInternals.ActiveDrag
    if not drag or not drag.Draggable then return end
    local mouse = drag.Input.UserInputType == Enum.UserInputType.MouseButton1
    if (mouse and input.UserInputType ~= Enum.UserInputType.MouseMovement)
        or (not mouse and input ~= drag.Input) then return end

    local delta = Vector2.new(input.Position.X, input.Position.Y) - drag.Start
    if delta.Magnitude < 6 and not drag.Moved then return end
    drag.Moved = true

    local view, scale = FloatingInternals.GetViewport()
    local frame = drag.Frame
    local rect = FloatingInternals.GetLogicalRect(frame, scale)
    if not rect then return end
    local raw = drag.Position + delta / scale
    local maxX = math.max(FloatingInternals.Margin, view.X - rect.W - FloatingInternals.Margin)
    local maxY = math.max(FloatingInternals.Margin, view.Y - rect.H - FloatingInternals.Margin)
    local clampedX = math.clamp(raw.X, FloatingInternals.Margin, maxX)
    local clampedY = math.clamp(raw.Y, FloatingInternals.Margin, maxY)
    local beyond = math.abs(raw.X - clampedX) > 1 or math.abs(raw.Y - clampedY) > 1
    if beyond and not drag.EdgeFeedback and drag.Widget then
        drag.EdgeFeedback = true
        FloatingInternals.Bounce(drag.Widget)
    elseif not beyond then
        drag.EdgeFeedback = false
    end
    frame.Position = UDim2.fromOffset(math.floor(clampedX + 0.5), math.floor(clampedY + 0.5))
end))

LibJanitor:Add(UserInputService.InputEnded:Connect(function(input)
    local drag = FloatingInternals.ActiveDrag
    if not drag then return end
    local mouse = drag.Input.UserInputType == Enum.UserInputType.MouseButton1
    if not (mouse and input.UserInputType == Enum.UserInputType.MouseButton1)
        and not (not mouse and input == drag.Input) then return end
    FloatingInternals.ActiveDrag = nil
    if not drag.Moved and drag.Frame.Parent and drag.OnTap then
        drag.OnTap()
    elseif drag.Widget then
        local _, finalScale = FloatingInternals.GetViewport()
        local rect = FloatingInternals.GetLogicalRect(drag.Frame, finalScale)
        if drag.Widget._FloatingAutoStack then
            FloatingInternals.Reflow(true)
        elseif rect then
            FloatingInternals.ResolveCollision(drag.Widget, rect.X, rect.Y, true)
        end
    end
end))

function FloatingInternals.Scope(opts)
	local scope = SilentUI:CreateScope()
	if opts.Window then
		assert(type(opts.Window.OnDestroy) == "function", "Window must be a SilentUI window")
		scope:Add(opts.Window:OnDestroy(function() scope:Destroy() end))
	end
	return scope
end

function SilentUI:_RefreshFloatingBindings()
	for widget in pairs(FloatingInternals.Registry) do
		if not widget._Destroyed and type(widget.Refresh) == "function" then widget:Refresh() end
	end
end

-- CreateBubbleToggle({ Flag = "MyToggle", Icon = "shield", Color = Color3.fromRGB(...),
--    Position = UDim2.fromOffset(30, 230), Size = 50, Draggable = true,
--    AllowOffscreen = false }) -- default true for backward compatibility
function SilentUI:CreateBubbleToggle(opts)
	opts = opts or {}
	local scope = FloatingInternals.Scope(opts)
	local size = math.clamp(tonumber(opts.Size) or 52, 28, 120)
	local color = FloatingInternals.Color(opts.Color, self.Theme.Accent)
	local inactive = FloatingInternals.Color(opts.InactiveColor, self.Theme.Surface)
	local state = opts.Default == true
	local bubble = Instance.new("TextButton")
	bubble.Name = opts.Name or "SilentBubble"
	bubble.Text = ""
	bubble.AutoButtonColor = false
	bubble.BackgroundColor3 = state and color or inactive
	bubble.BorderSizePixel = 0
	bubble.Size = UDim2.fromOffset(size, size)
	bubble.Position = typeof(opts.Position) == "UDim2" and opts.Position or UDim2.fromOffset(12, 12)
	bubble.ZIndex = 500
	bubble.Parent = self._Root
	Corner(bubble, size / 2)
	local stroke = Stroke(bubble, color, 2, 0.25)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = FloatingInternals.Image(opts.Image or opts.AssetId or opts.Icon)
	icon.ImageColor3 = FloatingInternals.Color(opts.IconColor, Color3.new(1, 1, 1))
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromOffset(math.floor(size * 0.52), math.floor(size * 0.52))
	icon.ZIndex = bubble.ZIndex + 1
	icon.Parent = bubble
	scope:Add(bubble)
	local signal = MakeSignal()
	scope:Add(function() signal.Clear() end)
	local widget = {
		Instance = bubble,
		Icon = icon,
		Scope = scope,
		_FloatingKind = "Bubble",
		_Destroyed = false,
	}
	local source, sourceConnection
	local function resolveSource()
		local candidate = opts.Control or (opts.Flag and SilentUI.Flags[opts.Flag])
		if candidate ~= source then
			if sourceConnection then sourceConnection:Disconnect(); sourceConnection = nil end
			source = candidate
			if source then
				local onChange = source.OnStateChanged or source.OnChanged
				if type(onChange) == "function" then
					sourceConnection = onChange(source, function() widget:Refresh() end)
				end
			end
		end
		return source
	end
	local function render()
		bubble.BackgroundColor3 = state and color or inactive
		stroke.Color = color
		stroke.Transparency = state and 0.1 or 0.68
	end
	function widget:Refresh()
		if self._Destroyed then return end
		local api = resolveSource()
		if api and type(api.Get) == "function" then
			local ok, value = pcall(api.Get, api)
			if ok and type(value) == "boolean" then
				local changed = state ~= value
				state = value
				render()
				if changed then signal.Fire(state, "flag") end
			end
		else
			render()
		end
	end
	function widget:Get() return state end
	function widget:Set(value)
		if self._Destroyed then return false, "bubble destroyed" end
		value = value == true
		local api = resolveSource()
		if api and type(api.Set) == "function" then
			local previous = state
			local ok, err = pcall(api.Set, api, value, false)
			if not ok then return false, tostring(err) end
			self:Refresh()
			if state ~= previous and opts.Callback then task.spawn(opts.Callback, state) end
		else
			local changed = value ~= state
			state = value
			render()
			if changed then
				signal.Fire(state, "bubble")
				if opts.Callback then task.spawn(opts.Callback, state) end
			end
		end
		return true
	end
	function widget:SetColor(value)
		assert(typeof(value) == "Color3", "SetColor expects a Color3")
		color = value
		render()
	end
	function widget:SetInactiveColor(value)
		assert(typeof(value) == "Color3", "SetInactiveColor expects a Color3")
		inactive = value
		render()
	end
	function widget:SetImage(value) icon.Image = FloatingInternals.Image(value) end
	function widget:SetVisible(visible)
		bubble.Visible = visible == true
		FloatingInternals.Reflow(true)
	end
	function widget:SetPosition(position)
		assert(typeof(position) == "UDim2", "SetPosition expects UDim2")
		if self._FloatingAutoStack then
			bubble.Position = position
			FloatingInternals.Reflow(true)
		else
			FloatingInternals.ResolveCollision(self, position.X.Offset, position.Y.Offset, true)
		end
	end
	function widget:OnChanged(callback) return signal.Connect(callback) end
	function widget:Destroy()
		if self._Destroyed then return end
		self._Destroyed = true
		FloatingInternals.Registry[self] = nil
		FloatingInternals.ByFrame[bubble] = nil
		if sourceConnection then sourceConnection:Disconnect(); sourceConnection = nil end
		scope:Destroy()
		task.defer(function() FloatingInternals.Reflow(true) end)
	end
	scope:Add(function()
		widget._Destroyed = true
		FloatingInternals.Registry[widget] = nil
		FloatingInternals.ByFrame[bubble] = nil
		if sourceConnection then sourceConnection:Disconnect(); sourceConnection = nil end
	end)
	FloatingInternals.Register(widget, opts, scope)
	FloatingInternals.RegisterDrag(bubble, bubble, function() widget:Set(not state) end,
		opts.Draggable, scope, false, widget)
	scope:Add(SilentUI:OnConfigLoaded(function() widget:Refresh() end))
	widget:Refresh()
	return widget
end

function Window:CreateBubbleToggle(opts)
	opts = opts or {}
	local config = table.clone(opts)
	config.Window = self
	return SilentUI:CreateBubbleToggle(config)
end



-- Detachable, event-driven state/keybind list. Never polls on Heartbeat.
function SilentUI:CreateStateList(opts)
	opts = opts or {}
	local scope = FloatingInternals.Scope(opts)
	local background = FloatingInternals.Color(opts.Color, self.Theme.Background)
	local activeColor = FloatingInternals.Color(opts.ActiveColor, self.Theme.Accent)
	local inactiveColor = FloatingInternals.Color(opts.InactiveColor, self.Theme.TextDim)
	local viewport, globalScale = FloatingInternals.GetViewport()
	local maxWidth = math.max(112, math.min(360, viewport.X - FloatingInternals.Margin * 2))
	local width = math.clamp(tonumber(opts.Width) or 190, math.min(112, maxWidth), maxWidth)
	local panel = Instance.new("Frame")
	panel.Name = opts.Name or "SilentStateList"
	panel.BackgroundColor3 = background
	panel.BackgroundTransparency = math.clamp(tonumber(opts.Transparency) or 0.15, 0, 1)
	panel.BorderSizePixel = 0
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Size = UDim2.fromOffset(width, 0)
	panel.Position = typeof(opts.Position) == "UDim2" and opts.Position or UDim2.fromOffset(12, 12)
	panel.ZIndex = 501
	panel.Parent = self._Root
	Corner(panel, tonumber(opts.CornerRadius) or 10)
	local border = Stroke(panel, activeColor, 1, 0.65)
	scope:Add(panel)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 7)
	padding.PaddingBottom = UDim.new(0, 7)
	padding.PaddingLeft = UDim.new(0, 9)
	padding.PaddingRight = UDim.new(0, 9)
	padding.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel
	local header = Instance.new("TextButton")
	header.Name = "DragHandle"
	header.BackgroundTransparency = 1
	header.Text = opts.Title or "Keybinds"
	header.FontFace = self.Theme.Font
	header.TextColor3 = FloatingInternals.Color(opts.TitleColor, self.Theme.Text)
	header.TextSize = 13
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.AutoButtonColor = false
	header.Size = UDim2.new(1, 0, 0, 23)
	header.LayoutOrder = 0
	header.ZIndex = panel.ZIndex + 1
	header.Parent = panel
	panel.Active = false
	panel.Selectable = false
	if opts.TitleKey then self:Localize(header, opts.TitleKey) end
	local items = {}
	local nextOrder = 0
	local list = {
		Instance = panel,
		Header = header,
		Scope = scope,
		_FloatingKind = "StateList",
		_FloatingLocked = opts.Locked == true,
		_FloatingPassThrough = opts.PassThrough == true,
		_FloatingDraggable = opts.Draggable ~= false,
		_StatusVisible = opts.ShowStatus ~= false and SilentUI.UserSettings.ShowStateValues,
		_Destroyed = false,
	}
	local function refreshHeaderInput()
		-- InputSink.None lets touches reach the game beneath this state panel.
		header.Active = not list._FloatingPassThrough
		header.Selectable = not list._FloatingPassThrough
		pcall(function()
			header.InputSink = list._FloatingPassThrough and Enum.InputSink.None or Enum.InputSink.Activate
		end)
		pcall(function() panel.InputSink = Enum.InputSink.None end)
	end
	refreshHeaderInput()
	function list:SetLocked(value)
		self._FloatingLocked = value == true
		if self._FloatingLocked and FloatingInternals.ActiveDrag
			and FloatingInternals.ActiveDrag.Widget == self then
			FloatingInternals.ActiveDrag = nil
		end
		return true
	end
	function list:SetPassThrough(value)
		self._FloatingPassThrough = value == true
		if self._FloatingPassThrough and FloatingInternals.ActiveDrag
			and FloatingInternals.ActiveDrag.Widget == self then
			FloatingInternals.ActiveDrag = nil
		end
		refreshHeaderInput()
		return true
	end
	function list:SetStatusVisible(value)
		self._StatusVisible = value == true
		for _, entry in pairs(items) do
			if entry.Status then entry.Status.Visible = self._StatusVisible end
		end
		return true
	end
	local function boolState(value)
		if type(value) == "boolean" then return value end
		if type(value) == "table" then
			if type(value.Active) == "boolean" then return value.Active end
			if type(value.Enabled) == "boolean" then return value.Enabled end
		end
		return value ~= nil and value ~= false
	end
	local function refreshEntry(entry)
		if list._Destroyed then return end
		local info = entry.Info
		local value = entry.ManualState
		local api = info.Control or (info.Flag and SilentUI.Flags[info.Flag])
		if api ~= entry.Source then
			if entry.Connection then entry.Connection:Disconnect(); entry.Connection = nil end
			entry.Source = api
			if api then
				local listener = api.OnStateChanged or api.OnChanged
				if type(listener) == "function" then
					entry.Connection = listener(api, function() refreshEntry(entry) end)
				end
			end
		end
		if api then
			local getter = api.GetActive or api.Get
			if type(getter) == "function" then
				local ok, result = pcall(getter, api)
				if ok then value = result end
			end
		elseif type(info.Get) == "function" then
			local ok, result = pcall(info.Get)
			if ok then value = result end
		end
		local active = boolState(value)
		local tint = active and FloatingInternals.Color(info.Color, activeColor)
			or FloatingInternals.Color(info.InactiveColor, inactiveColor)
		entry.Dot.BackgroundColor3 = tint
		entry.Status.Text = active and tostring(info.ActiveText or "ON") or tostring(info.InactiveText or "OFF")
		entry.Status.TextColor3 = tint
		entry.Active = active
	end
	function list:AddItem(info)
		assert(type(info) == "table", "state list item must be a table")
		nextOrder += 1
		local key = info.Id or info.Flag or info.Text or tostring(nextOrder)
		key = tostring(key)
		if items[key] then error("duplicate state list item: " .. key, 2) end
		local row = Instance.new("Frame")
		row.Name = "State_" .. key
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 22)
		row.LayoutOrder = nextOrder
		row.ZIndex = panel.ZIndex + 1
		row.Parent = panel
		local dot = Instance.new("Frame")
		dot.Name = "StateDot"
		dot.BackgroundColor3 = inactiveColor
		dot.BorderSizePixel = 0
		dot.Size = UDim2.fromOffset(7, 7)
		dot.Position = UDim2.fromOffset(1, 7)
		dot.ZIndex = row.ZIndex + 1
		dot.Parent = row
		Corner(dot, 4)
		local textLabel = Instance.new("TextLabel")
		textLabel.Name = "Label"
		textLabel.BackgroundTransparency = 1
		textLabel.Text = tostring(info.Text or info.Label or info.Flag or key)
		textLabel.TextColor3 = FloatingInternals.Color(info.TextColor, SilentUI.Theme.Text)
		textLabel.FontFace = SilentUI.Theme.FontRegular
		textLabel.TextSize = 12
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		textLabel.TextTruncate = Enum.TextTruncate.AtEnd
		textLabel.Position = UDim2.fromOffset(14, 0)
		textLabel.Size = UDim2.new(1, -58, 1, 0)
		textLabel.ZIndex = row.ZIndex + 1
		textLabel.Parent = row
		if info.TextKey then SilentUI:Localize(textLabel, info.TextKey) end
		local status = Instance.new("TextLabel")
		status.Name = "Status"
		status.BackgroundTransparency = 1
		status.Text = "OFF"
		status.TextColor3 = inactiveColor
		status.FontFace = SilentUI.Theme.Font
		status.TextSize = 11
		status.TextXAlignment = Enum.TextXAlignment.Right
		status.Position = UDim2.new(1, -44, 0, 0)
		status.Size = UDim2.new(0, 44, 1, 0)
		status.ZIndex = row.ZIndex + 1
		status.Visible = list._StatusVisible
		status.Parent = row
		local entry = {
			Info = info, Row = row, Label = textLabel, Dot = dot,
			Status = status, ManualState = info.Default == true,
		}
		items[key] = entry
		refreshEntry(entry)
		task.defer(function() FloatingInternals.Reflow(false) end)
		return key
	end
	function list:RemoveItem(key)
		local entry = items[tostring(key)]
		if not entry then return false end
		items[tostring(key)] = nil
		if entry.Connection then entry.Connection:Disconnect() end
		entry.Row:Destroy()
		task.defer(function() FloatingInternals.Reflow(false) end)
		return true
	end
	function list:SetItemState(key, value)
		local entry = items[tostring(key)]
		if not entry then return false end
		entry.ManualState = value == true
		refreshEntry(entry)
		return true
	end
	function list:SetColor(value)
		assert(typeof(value) == "Color3", "SetColor expects Color3")
		background = value
		panel.BackgroundColor3 = value
	end
	function list:SetActiveColor(value)
		assert(typeof(value) == "Color3", "SetActiveColor expects Color3")
		activeColor = value
		border.Color = value
		self:Refresh()
	end
	function list:SetInactiveColor(value)
		assert(typeof(value) == "Color3", "SetInactiveColor expects Color3")
		inactiveColor = value
		self:Refresh()
	end
	function list:SetVisible(value)
		panel.Visible = value == true
		FloatingInternals.Reflow(true)
	end
	function list:SetPosition(position)
		assert(typeof(position) == "UDim2", "SetPosition expects UDim2")
		if self._FloatingAutoStack then
			panel.Position = position
			FloatingInternals.Reflow(true)
		else
			FloatingInternals.ResolveCollision(self, position.X.Offset, position.Y.Offset, true)
		end
	end
	function list:Refresh()
		if self._Destroyed then return end
		for _, entry in pairs(items) do refreshEntry(entry) end
	end
	function list:Destroy()
		if self._Destroyed then return end
		self._Destroyed = true
		FloatingInternals.Registry[self] = nil
		FloatingInternals.ByFrame[panel] = nil
		for _, entry in pairs(items) do
			if entry.Connection then entry.Connection:Disconnect() end
		end
		table.clear(items)
		scope:Destroy()
		task.defer(function() FloatingInternals.Reflow(true) end)
	end
	scope:Add(function()
		list._Destroyed = true
		FloatingInternals.Registry[list] = nil
		FloatingInternals.ByFrame[panel] = nil
		for _, entry in pairs(items) do
			if entry.Connection then entry.Connection:Disconnect() end
		end
		table.clear(items)
	end)
	local collapsed = false
	FloatingInternals.Register(list, opts, scope)
	FloatingInternals.RegisterDrag(header, panel, function()
		if opts.Collapsible then
			collapsed = not collapsed
			for _, entry in pairs(items) do entry.Row.Visible = not collapsed end
			task.defer(function() FloatingInternals.Reflow(true) end)
		end
	end, opts.Draggable, scope, false, list)
	for _, info in ipairs(opts.Items or {}) do list:AddItem(info) end
	scope:Add(SilentUI:OnConfigLoaded(function() list:Refresh() end))
	return list
end

function Window:CreateStateList(opts)
	opts = opts or {}
	local config = table.clone(opts)
	config.Window = self
	return SilentUI:CreateStateList(config)
end

SilentUI.CreateKeybindList = SilentUI.CreateStateList
Window.CreateKeybindList = Window.CreateStateList

-- Public declarative adapter, keeping all existing Add* methods intact.
function Tab:AddControl(opts)
	assert(type(opts) == "table", "AddControl expects a definition table")
	local normalized = table.clone(opts)
	normalized.Text = normalized.Text or normalized.Name or normalized.name
	normalized.Flag = normalized.Flag or normalized.flag
	normalized.Options = normalized.Options or normalized.Items or normalized.items
	if normalized.Default == nil then normalized.Default = normalized.default end
	normalized.Callback = normalized.Callback or normalized.callback
	normalized.MultiSelect = normalized.MultiSelect == true or normalized.multiselect == true
	local kind = string.lower(tostring(normalized.Type or normalized.Kind or normalized.type or ""))
	local methods = {
		toggle = "AddToggle", slider = "AddSlider",
		dropdown = "AddDropdown", select = "AddDropdown",
		assetgrid = "AddAssetGrid", imagegrid = "AddAssetGrid",
		button = "AddButton", textbox = "AddTextbox",
		card = "AddCard", rating = "AddRating", table = "AddTable",
		console = "AddConsole", cardgrid = "AddCardGrid",
		infogrid = "AddInfoGrid", systeminfogrid = "AddSystemInfoGrid",
		gradientcard = "AddGradientCard", divider = "AddDivider",
		colorpicker = "AddColorPicker", color = "AddColorPicker",
		keybind = "AddKeybind", paragraph = "AddParagraph",
		label = "AddLabel", section = "AddSection",
	}
	local method = methods[kind]
	assert(method and type(self[method]) == "function", "unsupported AddControl Type: " .. kind)
	return self[method](self, normalized)
end

function Tab:AddControls(definitions)
	assert(type(definitions) == "table", "AddControls expects an array")
	local result = {}
	for index, definition in ipairs(definitions) do
		local control = self:AddControl(definition)
		result[index] = control
		local key = definition.Id or definition.Flag or definition.flag
		if key ~= nil then result[key] = control end
	end
	return result
end


function FloatingInternals.DestroyAllWindowJanitors()
	local windows = table.clone(SilentUI._Windows)
	for _, win in ipairs(windows) do
		win._destroyed = true
		Private.FireWindowDestroyCallbacks(win)
		if win._janitor then win._janitor:Destroy() end
	end
	table.clear(SilentUI._Windows)
end
 
SilentUI._Root.Destroying:Connect(function()
	Private.DestroyActiveScopes()
	Private.AcrylicShuttingDown = true
	FloatingInternals.DestroyAllWindowJanitors()
	Private.DestroyAllAcrylicControllers()
	LibJanitor:Destroy()
end)
 
function SilentUI:Unload()
	Private.DestroyActiveScopes()
	Private.CloseAnyOpenPopup()
	Private.AcrylicShuttingDown = true
	FloatingInternals.DestroyAllWindowJanitors()
	Private.DestroyAllAcrylicControllers()
	LibJanitor:Destroy()
	if SilentUI._Root then SilentUI._Root:Destroy() end
end
 
do
	local globalTable = Private.GetGlobalTable()
	globalTable.__SilentUI_Unload = function()
		pcall(function() SilentUI:Unload() end)
	end
end
 
return SilentUI
