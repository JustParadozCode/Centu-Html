-- CentuDox UI Library v1.0.0
-- Single-file Roblox Luau UI library for executors and LocalScripts.
--
-- Highlights
--   * Glass window with an aurora backdrop and a slowly rotating neon border
--   * Live stat cards with sparkline history
--   * Adaptive tab dock with an animated active pill
--   * Two-column sections that balance themselves
--   * Toast notifications with progress bars
--   * Flags registry, drag, minimize, hide/show hotkey, scale-to-screen
--   * Controls: Button, Toggle, Slider, Dropdown, Keybind, Input,
--     Label, Paragraph, Divider
--
-- Loading (executor)
--   local CentuDox = loadstring(game:HttpGet("<raw url to CentuDox.luau>"))()
--
-- Loading (LocalScript / ModuleScript)
--   local CentuDox = require(path.to.CentuDox)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local GLOBAL_ENV = (type(getgenv) == "function" and getgenv()) or _G

local LIBRARY_NAME = "CentuDox"
local LIBRARY_VERSION = "1.0.0"

-- Layout is authored at this size and scaled to the screen with a UIScale.
local BASE_WIDTH = 680
local BASE_HEIGHT = 500
local HEADER_HEIGHT = 64
local BODY_HEIGHT = BASE_HEIGHT - HEADER_HEIGHT
local STATS_Y = 8
local STATS_HEIGHT = 62
local CONTENT_Y = 80
local DOCK_HEIGHT = 46
local DOCK_BOTTOM = 12
local CONTENT_HEIGHT = BODY_HEIGHT - CONTENT_Y - DOCK_HEIGHT - DOCK_BOTTOM - 10
local DOCK_INNER_WIDTH = BASE_WIDTH - 32 - 12
local SPARK_SAMPLES = 14
local NOTIFY_WIDTH = 290

local THEME = {
    base = Color3.fromRGB(8, 10, 19),
    panel = Color3.fromRGB(14, 17, 31),
    card = Color3.fromRGB(20, 24, 42),
    raised = Color3.fromRGB(30, 35, 60),
    stroke = Color3.fromRGB(70, 82, 130),
    text = Color3.fromRGB(236, 241, 255),
    muted = Color3.fromRGB(138, 147, 184),
    dim = Color3.fromRGB(58, 64, 96),
    cyan = Color3.fromRGB(56, 236, 255),
    violet = Color3.fromRGB(139, 92, 246),
    magenta = Color3.fromRGB(236, 72, 153),
    success = Color3.fromRGB(52, 211, 153),
    warning = Color3.fromRGB(251, 191, 36),
    danger = Color3.fromRGB(248, 113, 113),
}

local FONT = {
    bold = Enum.Font.GothamBold,
    medium = Enum.Font.GothamMedium,
    regular = Enum.Font.Gotham,
}

local BRAND_SEQUENCE = ColorSequence.new({
    ColorSequenceKeypoint.new(0, THEME.cyan),
    ColorSequenceKeypoint.new(0.5, THEME.violet),
    ColorSequenceKeypoint.new(1, THEME.magenta),
})

local KIND_COLORS = {
    info = THEME.cyan,
    success = THEME.success,
    warning = THEME.warning,
    error = THEME.danger,
    danger = THEME.danger,
}

local CentuDox = {
    Name = LIBRARY_NAME,
    Version = LIBRARY_VERSION,
}

local activeWindows = {}
local windowCounter = 0
local notifyHolder
local notifyCounter = 0
local orderCounters = setmetatable({}, {__mode = "k"})

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------

local function copyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            result[key] = copyTable(value)
        else
            result[key] = value
        end
    end
    return result
end

local function normalizeOptions(options, fallbackLabel)
    if type(options) == "string" then
        return {label = options, title = options}
    end
    options = type(options) == "table" and options or {}
    if fallbackLabel and options.label == nil and options.title == nil then
        options.label = fallbackLabel
    end
    return options
end

local function labelOf(options, fallback)
    return tostring(options.label or options.title or fallback or "")
end

local function nextOrder(container)
    local value = (orderCounters[container] or 0) + 1
    orderCounters[container] = value
    return value
end

-- Creates an instance, applies properties, and parents it last for speed.
local function make(className, properties)
    local parent = properties.Parent
    properties.Parent = nil
    local instance = Instance.new(className)
    for property, value in pairs(properties) do
        instance[property] = value
    end
    instance.Parent = parent
    return instance
end

local function corner(parent, radius)
    return make("UICorner", {
        CornerRadius = UDim.new(0, radius or 8),
        Parent = parent,
    })
end

local function outline(parent, color, thickness, transparency)
    return make("UIStroke", {
        Color = color or THEME.stroke,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

local function brandGradient(parent, rotation)
    return make("UIGradient", {
        Color = BRAND_SEQUENCE,
        Rotation = rotation or 0,
        Parent = parent,
    })
end

local function tween(object, duration, goal, style, direction)
    local animation = TweenService:Create(
        object,
        TweenInfo.new(duration or 0.2, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out),
        goal
    )
    animation:Play()
    return animation
end

local function track(window, connection)
    window._connections[#window._connections + 1] = connection
    return connection
end

local function invoke(callback, ...)
    if type(callback) ~= "function" then
        return
    end
    local arguments = table.pack(...)
    task.spawn(function()
        local ok, err = pcall(callback, table.unpack(arguments, 1, arguments.n))
        if not ok then
            warn("[" .. LIBRARY_NAME .. "] callback error: " .. tostring(err))
        end
    end)
end

local function setFlag(window, flag, value)
    if flag ~= nil and window then
        window._flags[flag] = value
    end
end

local function executorFunction(name)
    local value = GLOBAL_ENV[name]
    if value == nil and GLOBAL_ENV ~= _G then
        value = _G[name]
    end
    return type(value) == "function" and value or nil
end

local function resolveGuiParent(configured)
    if typeof(configured) == "Instance" then
        return configured
    end

    local getHui = executorFunction("gethui")
    if getHui then
        local ok, hiddenUi = pcall(getHui)
        if ok and typeof(hiddenUi) == "Instance" then
            if hiddenUi:IsA("ScreenGui") then
                return hiddenUi.Parent or CoreGui
            end
            return hiddenUi
        end
    end

    if pcall(function()
        return CoreGui.Name
    end) then
        return CoreGui
    end

    return LocalPlayer:WaitForChild("PlayerGui")
end

local function protectGui(screen)
    local protect = (type(syn) == "table" and syn.protect_gui) or executorFunction("protectgui")
    if protect then
        pcall(protect, screen)
    end
end

local function computeScale()
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local fit = math.min((viewport.X - 40) / BASE_WIDTH, (viewport.Y - 60) / BASE_HEIGHT)
    local cap = UserInputService.TouchEnabled and 0.85 or 1
    return math.clamp(fit, 0.5, cap)
end

---------------------------------------------------------------------------
-- Stat cards
---------------------------------------------------------------------------

local function drawSpark(stat)
    local history = stat.history
    local low, high = math.huge, -math.huge
    for _, sample in ipairs(history) do
        low = math.min(low, sample)
        high = math.max(high, sample)
    end
    local range = math.max(high - low, 1e-6)
    for index, bar in ipairs(stat.bars) do
        local sample = history[index]
        local height = 3
        if sample then
            height = 3 + ((sample - low) / range) * 17
        end
        tween(bar, 0.2, {Size = UDim2.fromOffset(3, math.floor(height + 0.5))})
    end
end

local function defaultStats(profile)
    return {
        {key = "fps", label = "FPS", value = "--", color = THEME.cyan, spark = true},
        {key = "ping", label = "PING", value = "--ms", color = THEME.success, spark = true},
        {key = "plan", label = "PLAN", value = profile.plan, color = THEME.violet},
    }
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local function relayoutDock(window)
    local count = #window._tabOrder
    if count == 0 then
        return
    end
    local width = math.clamp(math.floor((DOCK_INNER_WIDTH - 6 * (count - 1)) / count), 64, 112)
    for _, tab in ipairs(window._tabOrder) do
        tab._button.Size = UDim2.fromOffset(width, 38)
    end
end

local function setTabActive(tab, active)
    tween(tab._activeFill, 0.25, {BackgroundTransparency = active and 0.1 or 1})
    tween(tab._button, 0.2, {BackgroundTransparency = active and 1 or 0.55})
    tween(tab._icon, 0.2, {[tab._iconProperty] = active and THEME.text or THEME.muted})
    tween(tab._nameLabel, 0.2, {TextColor3 = active and THEME.text or THEME.muted})
    tween(tab._indicator, 0.25, {Size = active and UDim2.new(0.5, 0, 0, 2) or UDim2.new(0, 0, 0, 2)})
end

local function refreshOverlay(tab)
    if tab._overlay then
        tab._overlay.Visible = tab._locked == true and tab._window._activeTab == tab
    end
end

local function selectTab(window, tab)
    local previous = window._activeTab
    if previous == tab then
        return
    end
    if previous then
        previous._page.Visible = false
        setTabActive(previous, false)
        refreshOverlay(previous)
    end

    window._activeTab = tab
    tab._page.Visible = true
    tab._page.Position = UDim2.fromOffset(0, 14)
    tween(tab._page, 0.3, {Position = UDim2.new()})
    setTabActive(tab, true)
    refreshOverlay(tab)
end

---------------------------------------------------------------------------
-- Section builder helpers
---------------------------------------------------------------------------

local function pickColumn(tab, preferred)
    if preferred == "left" then
        return tab._columns[1]
    elseif preferred == "right" then
        return tab._columns[2]
    end
    local left, right = tab._columns[1], tab._columns[2]
    return left.weight <= right.weight and left or right
end

-- Adds one element to a section body and keeps the column weight in sync,
-- so the next section lands in the shorter column.
local function addElement(section, className, properties, weight)
    section._column.weight += weight or 1
    properties.LayoutOrder = nextOrder(section._body)
    properties.Parent = section._body
    return make(className, properties)
end

local function addRow(section, height)
    local row = addElement(section, "Frame", {
        Size = UDim2.new(1, 0, 0, height or 36),
        BackgroundColor3 = THEME.raised,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
    }, 1)
    corner(row, 9)
    return row
end

local function rowText(parent, text, size, position, color)
    return make("TextLabel", {
        BackgroundTransparency = 1,
        Position = position or UDim2.fromOffset(12, 0),
        Size = size or UDim2.new(1, -24, 1, 0),
        Font = FONT.medium,
        TextSize = 12,
        TextColor3 = color or THEME.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = tostring(text),
        Parent = parent,
    })
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

local function buildButton(section, o)
    local callback = o.callback or o.onClick
    local button = addElement(section, "TextButton", {
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = THEME.violet,
        BackgroundTransparency = 0.82,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = FONT.bold,
        TextSize = 12,
        TextColor3 = THEME.text,
        Text = string.upper(labelOf(o, "Button")),
    }, 1)
    corner(button, 9)
    local edge = outline(button, THEME.cyan, 1, 0.65)

    button.MouseEnter:Connect(function()
        tween(button, 0.15, {BackgroundTransparency = 0.6})
        tween(edge, 0.15, {Transparency = 0.1})
    end)
    button.MouseLeave:Connect(function()
        tween(button, 0.15, {BackgroundTransparency = 0.82})
        tween(edge, 0.15, {Transparency = 0.65})
    end)
    button.MouseButton1Click:Connect(function()
        tween(button, 0.08, {BackgroundTransparency = 0.2})
        task.delay(0.1, function()
            if button.Parent then
                tween(button, 0.2, {BackgroundTransparency = 0.6})
            end
        end)
        invoke(callback)
    end)

    local handle = {}
    function handle.SetText(text)
        button.Text = string.upper(tostring(text))
    end
    function handle.Destroy()
        button:Destroy()
    end
    return handle
end

local function buildToggle(section, o)
    local window = section._window
    local state = o.default == true
    local row = addRow(section, 36)
    local label = rowText(row, labelOf(o, "Toggle"), UDim2.new(1, -70, 1, 0))

    local switch = make("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(42, 22),
        BackgroundColor3 = THEME.dim,
        BorderSizePixel = 0,
        Parent = row,
    })
    corner(switch, 11)
    local fill = make("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = switch,
    })
    corner(fill, 11)
    brandGradient(fill, 0)
    local knob = make("Frame", {
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.new(0, 3, 0.5, -8),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Parent = switch,
    })
    corner(knob, 8)

    local button = make("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = row,
    })

    local handle = {}

    local function render(animated)
        local knobPosition = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
        local fillTransparency = state and 0 or 1
        local labelColor = state and THEME.text or THEME.muted
        if animated then
            tween(knob, 0.2, {Position = knobPosition})
            tween(fill, 0.2, {BackgroundTransparency = fillTransparency})
            tween(label, 0.2, {TextColor3 = labelColor})
        else
            knob.Position = knobPosition
            fill.BackgroundTransparency = fillTransparency
            label.TextColor3 = labelColor
        end
    end

    function handle.Set(value, silent)
        state = value == true
        render(true)
        setFlag(window, o.flag, state)
        if not silent then
            invoke(o.onChange, state)
        end
    end
    function handle.Get()
        return state
    end
    function handle.Destroy()
        row:Destroy()
    end

    button.MouseButton1Click:Connect(function()
        handle.Set(not state)
    end)

    render(false)
    setFlag(window, o.flag, state)
    return handle
end

local function buildSlider(section, o)
    local window = section._window
    local minimum = tonumber(o.min) or 0
    local maximum = tonumber(o.max) or 100
    if maximum <= minimum then
        maximum = minimum + 1
    end
    local step = tonumber(o.step) or 1
    if step <= 0 then
        step = 1
    end
    local decimals = o.decimals or (step % 1 == 0 and 0 or 2)
    local suffix = tostring(o.suffix or "")
    local value = math.clamp(tonumber(o.default) or minimum, minimum, maximum)
    local dragging = false

    local row = addRow(section, 50)
    rowText(row, labelOf(o, "Slider"), UDim2.new(1, -110, 0, 20), UDim2.fromOffset(12, 6))
    local readout = make("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 6),
        Size = UDim2.fromOffset(98, 20),
        Font = FONT.bold,
        TextSize = 12,
        TextColor3 = THEME.cyan,
        TextXAlignment = Enum.TextXAlignment.Right,
        Text = "",
        Parent = row,
    })

    local trackFrame = make("Frame", {
        Position = UDim2.fromOffset(12, 33),
        Size = UDim2.new(1, -24, 0, 6),
        BackgroundColor3 = THEME.dim,
        BorderSizePixel = 0,
        Parent = row,
    })
    corner(trackFrame, 3)
    local fill = make("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Parent = trackFrame,
    })
    corner(fill, 3)
    brandGradient(fill, 0)
    local knob = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(14, 14),
        BackgroundColor3 = THEME.text,
        BorderSizePixel = 0,
        Parent = trackFrame,
    })
    corner(knob, 7)
    outline(knob, THEME.cyan, 2, 0)

    local hitArea = make("TextButton", {
        Position = UDim2.fromOffset(0, -10),
        Size = UDim2.new(1, 0, 1, 20),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = trackFrame,
    })

    local handle = {}

    local function render(animated)
        local ratio = (value - minimum) / (maximum - minimum)
        readout.Text = string.format("%." .. decimals .. "f", value) .. suffix
        if animated then
            tween(fill, 0.12, {Size = UDim2.fromScale(ratio, 1)})
            tween(knob, 0.12, {Position = UDim2.fromScale(ratio, 0.5)})
        else
            fill.Size = UDim2.fromScale(ratio, 1)
            knob.Position = UDim2.fromScale(ratio, 0.5)
        end
    end

    local function setValue(raw, silent)
        local numeric = tonumber(raw) or value
        local snapped = math.floor((numeric - minimum) / step + 0.5) * step + minimum
        snapped = math.clamp(snapped, minimum, maximum)
        if snapped == value then
            return
        end
        value = snapped
        render(not dragging)
        setFlag(window, o.flag, value)
        if not silent then
            invoke(o.onChange, value)
        end
    end

    local function updateFromX(x)
        local ratio = math.clamp((x - trackFrame.AbsolutePosition.X) / math.max(trackFrame.AbsoluteSize.X, 1), 0, 1)
        setValue(minimum + ratio * (maximum - minimum))
    end

    hitArea.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateFromX(input.Position.X)
        end
    end)
    track(window, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromX(input.Position.X)
        end
    end))
    track(window, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    function handle.Set(newValue, silent)
        setValue(newValue, silent)
    end
    function handle.Get()
        return value
    end
    function handle.Destroy()
        row:Destroy()
    end

    render(false)
    setFlag(window, o.flag, value)
    return handle
end

local function buildDropdown(section, o)
    local window = section._window
    local values = copyTable(o.values or {})
    local selected = o.default
    if selected == nil then
        selected = values[1]
    end
    local open = false
    local handle = {}

    local row = addElement(section, "Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.raised,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
    }, 1)
    corner(row, 9)
    make("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Parent = row})
    make("UIPadding", {
        PaddingLeft = UDim.new(0, 6),
        PaddingRight = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
        Parent = row,
    })

    local header = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = 1,
        Parent = row,
    })
    rowText(header, labelOf(o, "Dropdown"), UDim2.new(0.5, 0, 1, 0), UDim2.fromOffset(6, 0))
    local valueLabel = make("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -26, 0.5, 0),
        Size = UDim2.new(0.5, -34, 1, 0),
        Font = FONT.bold,
        TextSize = 12,
        TextColor3 = THEME.cyan,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = "",
        Parent = header,
    })
    local chevron = make("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -6, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        Font = FONT.bold,
        TextSize = 16,
        TextColor3 = THEME.muted,
        Text = "›",
        Rotation = 90,
        Parent = header,
    })

    local list = make("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 29),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = THEME.cyan,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
        LayoutOrder = 2,
        Parent = row,
    })
    make("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list})

    local optionButtons = {}

    local function refresh()
        valueLabel.Text = selected ~= nil and tostring(selected) or "None"
        for index, optionButton in ipairs(optionButtons) do
            optionButton.TextColor3 = values[index] == selected and THEME.cyan or THEME.muted
        end
    end

    local function setOpen(state)
        open = state
        list.Visible = state
        tween(chevron, 0.18, {Rotation = state and -90 or 90})
    end

    local function renderOptions()
        for _, optionButton in ipairs(optionButtons) do
            optionButton:Destroy()
        end
        table.clear(optionButtons)
        list.Size = UDim2.new(1, 0, 0, math.max(1, math.min(#values, 6)) * 29)
        for index, option in ipairs(values) do
            local optionButton = make("TextButton", {
                Size = UDim2.new(1, -4, 0, 26),
                BackgroundColor3 = THEME.card,
                BackgroundTransparency = 0.2,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Font = FONT.medium,
                TextSize = 12,
                TextColor3 = THEME.muted,
                Text = tostring(option),
                LayoutOrder = index,
                Parent = list,
            })
            corner(optionButton, 7)
            optionButton.MouseEnter:Connect(function()
                tween(optionButton, 0.12, {BackgroundTransparency = 0})
            end)
            optionButton.MouseLeave:Connect(function()
                tween(optionButton, 0.12, {BackgroundTransparency = 0.2})
            end)
            optionButton.MouseButton1Click:Connect(function()
                handle.Set(option)
                setOpen(false)
            end)
            optionButtons[#optionButtons + 1] = optionButton
        end
        refresh()
    end

    header.MouseButton1Click:Connect(function()
        setOpen(not open)
    end)

    function handle.Set(option, silent)
        local changed = option ~= selected
        selected = option
        refresh()
        setFlag(window, o.flag, selected)
        if changed and not silent then
            invoke(o.onChange, selected)
        end
    end
    function handle.Get()
        return selected
    end
    function handle.SetValues(newValues)
        values = copyTable(newValues or {})
        renderOptions()
    end
    function handle.Destroy()
        row:Destroy()
    end

    renderOptions()
    setFlag(window, o.flag, selected)
    return handle
end

local function buildKeybind(section, o)
    local window = section._window
    local current = o.default
    local listening = false
    local captureConnection
    local handle = {}

    local row = addRow(section, 36)
    rowText(row, labelOf(o, "Keybind"), UDim2.new(1, -140, 1, 0))

    local chip = make("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(120, 24),
        BackgroundColor3 = THEME.panel,
        BackgroundTransparency = 0.1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = FONT.bold,
        TextSize = 11,
        TextColor3 = THEME.cyan,
        Text = "",
        Parent = row,
    })
    corner(chip, 7)
    outline(chip, THEME.cyan, 1, 0.6)

    local function refresh()
        if listening then
            chip.Text = "PRESS A KEY"
            chip.TextColor3 = THEME.warning
        else
            chip.Text = current and current.Name or "NONE"
            chip.TextColor3 = THEME.cyan
        end
    end

    local function stopListening()
        listening = false
        if captureConnection then
            captureConnection:Disconnect()
            captureConnection = nil
        end
        refresh()
    end

    chip.MouseButton1Click:Connect(function()
        if listening then
            stopListening()
            return
        end
        listening = true
        refresh()
        captureConnection = UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end
            local key = input.KeyCode
            if key == Enum.KeyCode.Escape then
                key = nil
            end
            stopListening()
            local changed = key ~= current
            current = key
            refresh()
            setFlag(window, o.flag, current)
            if changed then
                invoke(o.onChange, current)
            end
        end)
    end)

    local hotkey = track(window, UserInputService.InputBegan:Connect(function(input, processed)
        if processed or listening or current == nil then
            return
        end
        if input.KeyCode == current then
            invoke(o.onPressed, current)
        end
    end))

    function handle.Set(key, silent)
        local changed = key ~= current
        current = key
        refresh()
        setFlag(window, o.flag, current)
        if changed and not silent then
            invoke(o.onChange, current)
        end
    end
    function handle.Get()
        return current
    end
    function handle.Destroy()
        stopListening()
        hotkey:Disconnect()
        row:Destroy()
    end

    refresh()
    setFlag(window, o.flag, current)
    return handle
end

local function buildInput(section, o)
    local window = section._window
    local last = o.default ~= nil and tostring(o.default) or ""
    local row = addRow(section, 36)
    rowText(row, labelOf(o, "Input"), UDim2.new(0.42, 0, 1, 0))

    local box = make("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.new(0.56, 0, 0, 24),
        BackgroundColor3 = THEME.panel,
        BackgroundTransparency = 0.1,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Font = FONT.medium,
        TextSize = 12,
        TextColor3 = THEME.text,
        PlaceholderColor3 = THEME.dim,
        PlaceholderText = tostring(o.placeholder or ""),
        Text = last,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = row,
    })
    corner(box, 7)
    make("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = box})
    local edge = outline(box, THEME.cyan, 1, 1)

    box.Focused:Connect(function()
        tween(edge, 0.2, {Transparency = 0.2})
    end)
    box.FocusLost:Connect(function(enterPressed)
        tween(edge, 0.2, {Transparency = 1})
        local text = box.Text
        setFlag(window, o.flag, text)
        if text ~= last then
            last = text
            invoke(o.onChange, text, enterPressed)
        end
    end)

    local handle = {}
    function handle.Get()
        return box.Text
    end
    function handle.Set(text)
        box.Text = tostring(text)
        last = box.Text
        setFlag(window, o.flag, last)
    end
    function handle.Destroy()
        row:Destroy()
    end

    setFlag(window, o.flag, last)
    return handle
end

local function buildLabel(section, o)
    local label = addElement(section, "TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = FONT.regular,
        TextSize = 12,
        TextColor3 = o.color or THEME.muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        RichText = o.rich == true,
        Text = tostring(o.text or o.label or ""),
    }, 1)

    local handle = {}
    function handle.Set(text)
        label.Text = tostring(text)
    end
    function handle.Destroy()
        label:Destroy()
    end
    return handle
end

local function buildParagraph(section, o)
    local box = addElement(section, "Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.raised,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
    }, 2)
    corner(box, 9)
    make("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
        PaddingTop = UDim.new(0, 9),
        PaddingBottom = UDim.new(0, 10),
        Parent = box,
    })
    make("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = box})

    local title = make("TextLabel", {
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        Font = FONT.bold,
        TextSize = 13,
        TextColor3 = THEME.cyan,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = tostring(o.title or ""),
        Parent = box,
    })
    local body = make("TextLabel", {
        LayoutOrder = 2,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = FONT.regular,
        TextSize = 12,
        TextColor3 = THEME.muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Text = tostring(o.text or ""),
        Parent = box,
    })

    local handle = {}
    function handle.Set(newTitle, newText)
        title.Text = tostring(newTitle or "")
        body.Text = tostring(newText or "")
    end
    function handle.Destroy()
        box:Destroy()
    end
    return handle
end

local function buildDivider(section)
    local line = addElement(section, "Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = THEME.stroke,
        BorderSizePixel = 0,
    }, 1)
    make("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0.2),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = line,
    })
    return {
        Destroy = function()
            line:Destroy()
        end,
    }
end

local function attachControls(section)
    section.AddButton = function(options)
        return buildButton(section, normalizeOptions(options, "Button"))
    end
    section.AddToggle = function(options)
        return buildToggle(section, normalizeOptions(options, "Toggle"))
    end
    section.AddSlider = function(options)
        return buildSlider(section, normalizeOptions(options, "Slider"))
    end
    section.AddDropdown = function(options)
        return buildDropdown(section, normalizeOptions(options, "Dropdown"))
    end
    section.AddKeybind = function(options)
        return buildKeybind(section, normalizeOptions(options, "Keybind"))
    end
    section.AddInput = function(options)
        return buildInput(section, normalizeOptions(options, "Input"))
    end
    section.AddLabel = function(options)
        return buildLabel(section, normalizeOptions(options))
    end
    section.AddParagraph = function(options)
        return buildParagraph(section, normalizeOptions(options))
    end
    section.AddDivider = function()
        return buildDivider(section)
    end
end

local function buildSection(tab, o)
    local column = pickColumn(tab, o.column)
    column.weight += 3

    local card = make("Frame", {
        Name = "Section",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.card,
        BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(column.frame),
        Parent = column.frame,
    })
    corner(card, 12)
    outline(card, THEME.stroke, 1, 0.4)
    make("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Parent = card})

    local header = make("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = card,
    })
    local accent = make("Frame", {
        Position = UDim2.fromOffset(14, 11),
        Size = UDim2.fromOffset(3, 14),
        BackgroundColor3 = THEME.cyan,
        BorderSizePixel = 0,
        Parent = header,
    })
    corner(accent, 2)
    brandGradient(accent, 90)
    make("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(24, 8),
        Size = UDim2.new(1, -150, 0, 20),
        Font = FONT.bold,
        TextSize = 13,
        TextColor3 = THEME.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = string.upper(labelOf(o, "Section")),
        Parent = header,
    })
    if o.category then
        make("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(1, -132, 0, 8),
            Size = UDim2.fromOffset(120, 20),
            Font = FONT.medium,
            TextSize = 10,
            TextColor3 = THEME.muted,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = string.upper(tostring(o.category)),
            Parent = header,
        })
    end

    local body = make("Frame", {
        Name = "Body",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 2,
        Parent = card,
    })
    make("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, 2),
        PaddingBottom = UDim.new(0, 10),
        Parent = body,
    })
    make("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body})

    local section = {
        _window = tab._window,
        _tab = tab,
        _body = body,
        _column = column,
        Frame = card,
    }
    attachControls(section)
    return section
end

---------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------

local function getNotifyHolder()
    if notifyHolder and notifyHolder.Parent then
        return notifyHolder
    end
    local screen = make("ScreenGui", {
        Name = "CentuDox_Notifications",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 10000,
    })
    protectGui(screen)
    screen.Parent = resolveGuiParent(nil)

    notifyHolder = make("Frame", {
        Name = "Holder",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -20, 1, -20),
        Size = UDim2.fromOffset(NOTIFY_WIDTH, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = screen,
    })
    make("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        Parent = notifyHolder,
    })
    return notifyHolder
end

local function notify(options)
    if type(options) == "string" then
        options = {text = options}
    end
    options = type(options) == "table" and options or {}

    local holder = getNotifyHolder()
    notifyCounter += 1
    local accent = KIND_COLORS[options.kind] or THEME.cyan
    local duration = math.max(tonumber(options.duration) or 4, 0.5)

    local card = make("Frame", {
        Size = UDim2.fromOffset(NOTIFY_WIDTH, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.panel,
        BackgroundTransparency = 0.04,
        BorderSizePixel = 0,
        LayoutOrder = notifyCounter,
        Parent = holder,
    })
    corner(card, 12)
    local edge = outline(card, accent, 1, 0.35)
    local scale = make("UIScale", {Scale = 0.92, Parent = card})
    make("UIPadding", {
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        Parent = card,
    })
    make("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = card})

    local titleLabel = make("TextLabel", {
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        Font = FONT.bold,
        TextSize = 13,
        TextColor3 = accent,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = tostring(options.title or "CentuDox"),
        Parent = card,
    })
    local textLabel = make("TextLabel", {
        LayoutOrder = 2,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = FONT.regular,
        TextSize = 12,
        TextColor3 = THEME.muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Text = tostring(options.text or ""),
        Parent = card,
    })
    local bar = make("Frame", {
        LayoutOrder = 3,
        Size = UDim2.new(1, 0, 0, 3),
        BackgroundColor3 = THEME.dim,
        BorderSizePixel = 0,
        Parent = card,
    })
    corner(bar, 2)
    local progress = make("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
        Parent = bar,
    })
    corner(progress, 2)

    tween(scale, 0.3, {Scale = 1}, Enum.EasingStyle.Back)
    tween(progress, duration, {Size = UDim2.fromScale(0, 1)}, Enum.EasingStyle.Linear)

    task.delay(duration, function()
        if not card.Parent then
            return
        end
        tween(scale, 0.25, {Scale = 0.92})
        tween(card, 0.25, {BackgroundTransparency = 1})
        tween(edge, 0.25, {Transparency = 1})
        tween(titleLabel, 0.25, {TextTransparency = 1})
        tween(textLabel, 0.25, {TextTransparency = 1})
        task.delay(0.3, function()
            card:Destroy()
        end)
    end)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function CentuDox.Notify(options)
    notify(options)
end

function CentuDox.GetActiveWindows()
    local windows = {}
    for _, window in pairs(activeWindows) do
        if not window._destroyed then
            table.insert(windows, window)
        end
    end
    table.sort(windows, function(a, b)
        return a._id < b._id
    end)
    return windows
end

function CentuDox.UnloadAll()
    for _, window in ipairs(CentuDox.GetActiveWindows()) do
        window.Unload()
    end
end

function CentuDox.ExposeGlobal(name)
    local globalName = type(name) == "string" and name ~= "" and name or "CentuDoxLibrary"
    GLOBAL_ENV[globalName] = CentuDox
    return CentuDox
end

function CentuDox.CreateWindow(options)
    options = normalizeOptions(options)
    windowCounter += 1

    local given = type(options.profile) == "table" and options.profile or {}
    local profile = {
        displayName = given.displayName or LocalPlayer.DisplayName,
        handle = given.handle or LocalPlayer.Name,
        plan = given.plan or "Member",
    }

    local window = {
        _id = windowCounter,
        _connections = {},
        _tabs = {},
        _tabOrder = {},
        _stats = {},
        _flags = {},
        _activeTab = nil,
        _visible = true,
        _minimized = false,
        _destroyed = false,
        _toggleKey = options.toggleKey or Enum.KeyCode.RightShift,
        _onUnload = options.onUnload,
        _scale = 1,
    }
    activeWindows[window._id] = window

    ---------------------------------------------------------------- root
    local screen = make("ScreenGui", {
        Name = "CentuDox_" .. window._id,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 500 + window._id,
    })
    protectGui(screen)
    screen.Parent = resolveGuiParent(options.parent)
    window.Gui = screen

    window._scale = options.scale or computeScale()
    local scaler = make("UIScale", {Scale = window._scale})

    local main = make("Frame", {
        Name = "Main",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(BASE_WIDTH, BASE_HEIGHT),
        BackgroundColor3 = THEME.base,
        BackgroundTransparency = 0.04,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = screen,
    })
    corner(main, 18)
    scaler.Parent = main
    window.Main = main

    local backdrop = make("UIGradient", {
        Color = ColorSequence.new(Color3.fromRGB(18, 22, 44), THEME.base),
        Rotation = 120,
        Parent = main,
    })
    backdrop.Name = "Backdrop"

    -- Aurora orbs drawn first so they sit behind everything else.
    local function createOrb(size, color)
        local orb = make("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(size, size),
            BackgroundColor3 = color,
            BackgroundTransparency = 0.84,
            BorderSizePixel = 0,
            Parent = main,
        })
        corner(orb, size)
        return orb
    end
    local orbA = createOrb(380, THEME.cyan)
    local orbB = createOrb(320, THEME.violet)
    local orbC = createOrb(240, THEME.magenta)
    orbC.BackgroundTransparency = 0.9

    local border = outline(main, Color3.new(1, 1, 1), 1.5, 0)
    local borderGradient = brandGradient(border, 0)

    ---------------------------------------------------------------- header
    local header = make("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
        BackgroundTransparency = 1,
        Active = true, -- receives drag input on the header
        Parent = main,
    })

    local logo = make("TextLabel", {
        Name = "Logo",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(20, 10),
        Size = UDim2.fromOffset(260, 30),
        Font = FONT.bold,
        TextSize = 24,
        TextColor3 = Color3.new(1, 1, 1),
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = tostring(options.title or LIBRARY_NAME),
        Parent = header,
    })
    brandGradient(logo, 0)

    make("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(20, 40),
        Size = UDim2.fromOffset(340, 16),
        Font = FONT.medium,
        TextSize = 11,
        TextColor3 = THEME.muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = tostring(options.versionText or ("v" .. LIBRARY_VERSION)),
        Parent = header,
    })

    -- Profile chip
    local chip = make("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -116, 0, 12),
        Size = UDim2.fromOffset(196, 40),
        BackgroundColor3 = THEME.card,
        BackgroundTransparency = 0.1,
        BorderSizePixel = 0,
        Parent = header,
    })
    corner(chip, 12)
    outline(chip, THEME.stroke, 1, 0.4)
    local avatar = make("ImageLabel", {
        Position = UDim2.fromOffset(5, 4),
        Size = UDim2.fromOffset(32, 32),
        BackgroundColor3 = THEME.raised,
        BorderSizePixel = 0,
        Image = "",
        Parent = chip,
    })
    corner(avatar, 16)
    make("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(46, 6),
        Size = UDim2.new(1, -54, 0, 14),
        Font = FONT.bold,
        TextSize = 12,
        TextColor3 = THEME.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = tostring(profile.displayName),
        Parent = chip,
    })
    make("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(46, 21),
        Size = UDim2.new(1, -54, 0, 13),
        Font = FONT.medium,
        TextSize = 10,
        TextColor3 = THEME.cyan,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = "@" .. tostring(profile.handle) .. "  ·  " .. tostring(profile.plan),
        Parent = chip,
    })
    task.spawn(function()
        local ok, image = pcall(function()
            return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
        end)
        if ok and avatar.Parent then
            avatar.Image = image
        end
    end)

    local function headerButton(position, glyph, hoverColor)
        local button = make("TextButton", {
            Position = position,
            Size = UDim2.fromOffset(28, 28),
            BackgroundColor3 = THEME.card,
            BackgroundTransparency = 0.1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = FONT.bold,
            TextSize = 16,
            TextColor3 = THEME.muted,
            Text = glyph,
            Parent = header,
        })
        corner(button, 8)
        button.MouseEnter:Connect(function()
            tween(button, 0.15, {BackgroundColor3 = hoverColor, TextColor3 = THEME.text})
        end)
        button.MouseLeave:Connect(function()
            tween(button, 0.15, {BackgroundColor3 = THEME.card, TextColor3 = THEME.muted})
        end)
        return button
    end

    local minimizeButton = headerButton(UDim2.new(1, -66, 0, 18), "-", THEME.violet)
    local closeButton = headerButton(UDim2.new(1, -34, 0, 18), "×", THEME.danger)

    ---------------------------------------------------------------- body
    local body = make("Frame", {
        Name = "Body",
        Position = UDim2.fromOffset(0, HEADER_HEIGHT),
        Size = UDim2.new(1, 0, 0, BODY_HEIGHT),
        BackgroundTransparency = 1,
        Parent = main,
    })

    -- Stat cards
    local statDefs = type(options.stats) == "table" and options.stats or defaultStats(profile)
    local statsRow = make("Frame", {
        Name = "Stats",
        Position = UDim2.fromOffset(16, STATS_Y),
        Size = UDim2.new(1, -32, 0, STATS_HEIGHT),
        BackgroundTransparency = 1,
        Parent = body,
    })
    make("UIGridLayout", {
        CellSize = UDim2.new(1 / math.max(#statDefs, 1), -6, 1, 0),
        CellPadding = UDim2.fromOffset(6, 0),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = statsRow,
    })

    for index, definition in ipairs(statDefs) do
        local color = definition.color or THEME.cyan
        local card = make("Frame", {
            Name = tostring(definition.key),
            BackgroundColor3 = THEME.card,
            BackgroundTransparency = 0.1,
            BorderSizePixel = 0,
            LayoutOrder = index,
            Parent = statsRow,
        })
        corner(card, 12)
        outline(card, THEME.stroke, 1, 0.5)

        make("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(12, 8),
            Size = UDim2.new(1, -24, 0, 14),
            Font = FONT.medium,
            TextSize = 10,
            TextColor3 = THEME.muted,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = string.upper(tostring(definition.label or definition.key)),
            Parent = card,
        })
        local valueLabel = make("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(12, 22),
            Size = UDim2.new(1, -24, 0, 30),
            Font = FONT.bold,
            TextSize = 20,
            TextColor3 = color,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = tostring(definition.value or "--"),
            Parent = card,
        })

        local bars = {}
        if definition.spark then
            local sparkFrame = make("Frame", {
                AnchorPoint = Vector2.new(1, 1),
                Position = UDim2.new(1, -10, 1, -8),
                Size = UDim2.fromOffset(SPARK_SAMPLES * 4 - 1, 20),
                BackgroundTransparency = 1,
                Parent = card,
            })
            for barIndex = 1, SPARK_SAMPLES do
                local bar = make("Frame", {
                    AnchorPoint = Vector2.new(0, 1),
                    Position = UDim2.new(0, (barIndex - 1) * 4, 1, 0),
                    Size = UDim2.fromOffset(3, 3),
                    BackgroundColor3 = color,
                    BackgroundTransparency = 0.15,
                    BorderSizePixel = 0,
                    Parent = sparkFrame,
                })
                corner(bar, 2)
                bars[barIndex] = bar
            end
        end

        window._stats[definition.key] = {
            valueLabel = valueLabel,
            spark = definition.spark == true,
            bars = bars,
            history = {},
        }
    end

    -- Content area: every tab page lives here.
    local content = make("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(16, CONTENT_Y),
        Size = UDim2.new(1, -32, 0, CONTENT_HEIGHT),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = body,
    })

    -- Tab dock
    local dock = make("Frame", {
        Name = "Dock",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -DOCK_BOTTOM),
        Size = UDim2.new(1, -32, 0, DOCK_HEIGHT),
        BackgroundColor3 = THEME.panel,
        BackgroundTransparency = 0.12,
        BorderSizePixel = 0,
        Parent = body,
    })
    corner(dock, 14)
    outline(dock, THEME.stroke, 1, 0.4)
    local dockScroll = make("ScrollingFrame", {
        Name = "Tabs",
        Position = UDim2.fromOffset(6, 4),
        Size = UDim2.new(1, -12, 1, -8),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        ScrollingDirection = Enum.ScrollingDirection.X,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = THEME.cyan,
        ElasticBehavior = Enum.ElasticBehavior.Never,
        Parent = dock,
    })
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = dockScroll,
    })

    ---------------------------------------------------------------- stat API
    function window.SetStat(key, value)
        local stat = window._stats[key]
        if not stat then
            return
        end
        stat.valueLabel.Text = tostring(value)
        if stat.spark then
            local number = tonumber(string.match(tostring(value), "[%-]?%d+%.?%d*"))
            if number then
                table.insert(stat.history, number)
                if #stat.history > SPARK_SAMPLES then
                    table.remove(stat.history, 1)
                end
                drawSpark(stat)
            end
        end
    end

    ---------------------------------------------------------------- tab API
    function window.CreateTab(tabOptions)
        tabOptions = normalizeOptions(tabOptions, "Tab")
        local id = tostring(tabOptions.id or tabOptions.title or tabOptions.label or ("tab" .. (#window._tabOrder + 1)))
        if window._tabs[id] then
            return window._tabs[id]
        end

        local title = tostring(tabOptions.title or tabOptions.label or id)
        local tab = {
            _window = window,
            id = id,
            title = title,
            _columns = {},
            _locked = false,
        }

        -- Page
        local page = make("ScrollingFrame", {
            Name = "Page_" .. id,
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = THEME.cyan,
            ScrollBarImageTransparency = 0.25,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            Visible = false,
            Parent = content,
        })
        make("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10), Parent = page})
        make("UIPadding", {PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6), Parent = page})
        tab._page = page

        local row = make("Frame", {
            Name = "Row",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = 1,
            Parent = page,
        })
        make("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 10),
            Parent = row,
        })
        for columnIndex = 1, 2 do
            local column = make("Frame", {
                Name = "Column" .. columnIndex,
                Size = UDim2.new(0.5, -5, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                LayoutOrder = columnIndex,
                Parent = row,
            })
            make("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10), Parent = column})
            tab._columns[columnIndex] = {frame = column, weight = 0}
        end

        -- Dock button
        local button = make("TextButton", {
            Name = id,
            Size = UDim2.fromOffset(90, 38),
            BackgroundColor3 = THEME.raised,
            BackgroundTransparency = 0.55,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            LayoutOrder = #window._tabOrder + 1,
            Parent = dockScroll,
        })
        corner(button, 10)
        tab._button = button

        local activeFill = make("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = button,
        })
        corner(activeFill, 10)
        brandGradient(activeFill, 0)
        tab._activeFill = activeFill

        if tabOptions.iconImage then
            tab._icon = make("ImageLabel", {
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0.5, 0),
                Position = UDim2.new(0.5, 0, 0, 4),
                Size = UDim2.fromOffset(15, 15),
                Image = tostring(tabOptions.iconImage),
                ImageColor3 = THEME.muted,
                Parent = button,
            })
            tab._iconProperty = "ImageColor3"
        else
            local initials = tabOptions.icon or string.upper(string.sub(title, 1, 2))
            tab._icon = make("TextLabel", {
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(0, 2),
                Size = UDim2.new(1, 0, 0, 18),
                Font = FONT.bold,
                TextSize = 13,
                TextColor3 = THEME.muted,
                Text = tostring(initials),
                Parent = button,
            })
            tab._iconProperty = "TextColor3"
        end

        tab._nameLabel = make("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 4, 0, 20),
            Size = UDim2.new(1, -8, 0, 14),
            Font = FONT.medium,
            TextSize = 10,
            TextColor3 = THEME.muted,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = string.upper(title),
            Parent = button,
        })

        tab._indicator = make("Frame", {
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 1, -1),
            Size = UDim2.new(0, 0, 0, 2),
            BackgroundColor3 = THEME.cyan,
            BorderSizePixel = 0,
            Parent = button,
        })
        corner(tab._indicator, 2)
        brandGradient(tab._indicator, 0)

        button.MouseEnter:Connect(function()
            if window._activeTab ~= tab then
                tween(button, 0.15, {BackgroundTransparency = 0.3})
            end
        end)
        button.MouseLeave:Connect(function()
            if window._activeTab ~= tab then
                tween(button, 0.15, {BackgroundTransparency = 0.55})
            end
        end)
        button.MouseButton1Click:Connect(function()
            selectTab(window, tab)
        end)

        -- Tab methods
        function tab.Select()
            selectTab(window, tab)
        end
        function tab.CreateSection(sectionOptions)
            return buildSection(tab, normalizeOptions(sectionOptions, "Section"))
        end
        function tab.SetAccessDenied(message)
            tab._locked = message ~= nil and message ~= false
            if not tab._overlay then
                tab._overlay = make("Frame", {
                    Name = "Locked_" .. id,
                    Size = UDim2.fromScale(1, 1),
                    BackgroundColor3 = THEME.base,
                    BackgroundTransparency = 0.1,
                    BorderSizePixel = 0,
                    Active = true, -- swallows clicks so controls underneath stay inert
                    Visible = false,
                    ZIndex = 5,
                    Parent = content,
                })
                corner(tab._overlay, 12)
                outline(tab._overlay, THEME.cyan, 1, 0.5)
                make("TextLabel", {
                    BackgroundTransparency = 1,
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.new(0.5, 0, 0.5, -16),
                    Size = UDim2.new(1, -40, 0, 22),
                    Font = FONT.bold,
                    TextSize = 16,
                    TextColor3 = THEME.cyan,
                    Text = "LOCKED",
                    ZIndex = 6,
                    Parent = tab._overlay,
                })
                tab._overlayMessage = make("TextLabel", {
                    BackgroundTransparency = 1,
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.new(0.5, 0, 0.5, 14),
                    Size = UDim2.new(1, -60, 0, 40),
                    Font = FONT.medium,
                    TextSize = 12,
                    TextColor3 = THEME.muted,
                    TextWrapped = true,
                    ZIndex = 6,
                    Parent = tab._overlay,
                })
            end
            tab._overlayMessage.Text = type(message) == "string" and message or "This tab is locked."
            refreshOverlay(tab)
        end

        window._tabs[id] = tab
        table.insert(window._tabOrder, tab)
        relayoutDock(window)
        if not window._activeTab then
            selectTab(window, tab)
        end
        return tab
    end

    function window.SelectTab(target)
        local tab = type(target) == "table" and target or window._tabs[tostring(target)]
        if tab then
            selectTab(window, tab)
        end
    end

    ---------------------------------------------------------------- flags
    function window.GetFlags()
        return copyTable(window._flags)
    end

    function window.Notify(notification)
        notify(notification)
    end

    ---------------------------------------------------------------- visibility
    function window.Toggle(state)
        if window._destroyed then
            return
        end
        if state == nil then
            state = not window._visible
        end
        if state == window._visible then
            return
        end
        window._visible = state
        if state then
            main.Visible = true
            tween(scaler, 0.28, {Scale = window._scale}, Enum.EasingStyle.Back)
        else
            local hide = tween(scaler, 0.2, {Scale = window._scale * 0.9})
            hide.Completed:Connect(function()
                if not window._visible and not window._destroyed then
                    main.Visible = false
                end
            end)
        end
    end

    function window.Minimize()
        if window._destroyed then
            return
        end
        window._minimized = not window._minimized
        if window._minimized then
            body.Visible = false
            tween(main, 0.3, {Size = UDim2.fromOffset(BASE_WIDTH, HEADER_HEIGHT)})
            minimizeButton.Text = "+"
        else
            body.Visible = true
            tween(main, 0.3, {Size = UDim2.fromOffset(BASE_WIDTH, BASE_HEIGHT)})
            minimizeButton.Text = "-"
        end
    end

    function window.SetToggleKey(key)
        window._toggleKey = key
    end

    ---------------------------------------------------------------- lifecycle
    function window.Unload()
        if window._destroyed then
            return
        end
        window._destroyed = true
        for index = #window._connections, 1, -1 do
            local connection = window._connections[index]
            window._connections[index] = nil
            pcall(function()
                connection:Disconnect()
            end)
        end
        activeWindows[window._id] = nil
        screen:Destroy()
        invoke(window._onUnload)
    end
    window.Destroy = window.Unload

    ---------------------------------------------------------------- behaviour
    minimizeButton.MouseButton1Click:Connect(function()
        window.Minimize()
    end)
    closeButton.MouseButton1Click:Connect(function()
        window.Unload()
    end)

    -- Drag by the header.
    local dragging = false
    local dragStart = Vector2.zero
    local startPosition = main.Position
    track(window, header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = main.Position
        end
    end))
    track(window, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = (input.Position - dragStart) / window._scale
            main.Position = startPosition + UDim2.fromOffset(delta.X, delta.Y)
        end
    end))
    track(window, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    -- Hotkey to hide / show.
    track(window, UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == window._toggleKey then
            window.Toggle()
        end
    end))

    -- Rescale when the viewport changes.
    local camera = workspace.CurrentCamera
    if camera and not options.scale then
        track(window, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            window._scale = computeScale()
            if window._visible then
                scaler.Scale = window._scale
            end
        end))
    end

    -- Ambient animation: border rotation and drifting aurora orbs.
    local clock = 0
    track(window, RunService.Heartbeat:Connect(function(deltaTime)
        clock += deltaTime
        borderGradient.Rotation = (clock * 55) % 360
        orbA.Position = UDim2.new(0.86, math.sin(clock * 0.35) * 26, 0.14, math.cos(clock * 0.27) * 14)
        orbB.Position = UDim2.new(0.12, math.cos(clock * 0.3) * 22, 0.92, math.sin(clock * 0.4) * 12)
        orbC.Position = UDim2.new(0.55, math.sin(clock * 0.22) * 40, 0.4, math.cos(clock * 0.31) * 26)
    end))

    -- Open animation.
    scaler.Scale = window._scale * 0.9
    tween(scaler, 0.4, {Scale = window._scale}, Enum.EasingStyle.Back)

    ---------------------------------------------------------------- home tab
    window.SetStat("plan", profile.plan)

    if options.showHome ~= false then
        local home = window.CreateTab({id = "home", title = "Home", icon = "HO"})
        local welcome = home.CreateSection({title = "WELCOME", category = LIBRARY_NAME, column = "left"})
        welcome.AddParagraph({
            title = "Hey, " .. tostring(profile.displayName),
            text = tostring(options.welcomeText or ("CentuDox is ready. Pick a tab in the dock to get started, or press " .. window._toggleKey.Name .. " to hide this window.")),
        })
        local account = home.CreateSection({title = "ACCOUNT", category = "PROFILE", column = "right"})
        account.AddLabel({text = "Handle: @" .. tostring(profile.handle)})
        account.AddLabel({text = "Plan: " .. tostring(profile.plan)})
        account.AddDivider()
        account.AddButton({
            label = "Show / Hide Window",
            callback = function()
                window.Toggle()
            end,
        })

        if type(options.changelog) == "table" and #options.changelog > 0 then
            local changes = home.CreateSection({title = "CHANGELOG", category = "UPDATES"})
            for _, entry in ipairs(options.changelog) do
                changes.AddParagraph({title = entry.title, text = entry.text})
            end
        end
    end

    return window
end

GLOBAL_ENV.CentuDoxLibrary = CentuDox

return CentuDox
