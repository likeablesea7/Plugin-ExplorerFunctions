if not plugin then
	return
end

local Selection = game:GetService("Selection")
local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

--============================================================
-- Config / Theme
--============================================================

local DATA_KEY_BASE = "ExplorerFunctions_Data_v1" -- suffixed with GameId per experience

-- Hex colors for RichText fragments (mirrors THEME.textDim / an accent green).
local DIM_HEX = "#8C8C8C"
local VALUE_HEX = "#8FE6A8"

local THEME = {
	bg       = Color3.fromRGB(30, 30, 30),
	bar      = Color3.fromRGB(37, 37, 38),
	btn      = Color3.fromRGB(51, 51, 54),
	btnHover = Color3.fromRGB(66, 66, 70),
	text     = Color3.fromRGB(220, 220, 220),
	textDim  = Color3.fromRGB(140, 140, 140),
	header   = Color3.fromRGB(96, 160, 255),
	service  = Color3.fromRGB(120, 200, 140),
	rowSel      = Color3.fromRGB(38, 79, 120),
	rowLatest   = Color3.fromRGB(52, 104, 156),
	rowHover    = Color3.fromRGB(45, 45, 48),
	border      = Color3.fromRGB(60, 60, 62),
	addBtn      = Color3.fromRGB(52, 130, 72),
	addBtnHover = Color3.fromRGB(64, 150, 86),
}

--============================================================
-- Property catalog
--
-- Ordered, categorized list of the UI properties this tool understands.
-- Detection just tries to read each on the live element (pcall), so whichever
-- of these an element actually declares becomes its "detected properties".
-- "style" marks appearance / text-appearance properties (used by Copy Style).
--============================================================

local PROP_CATALOG = {
	{ cat = "Background", style = true, props = {
		"BackgroundColor3", "BackgroundTransparency", "BorderColor3", "BorderSizePixel", "BorderMode",
	}},
	{ cat = "Transform", props = {
		"Position", "Size", "AnchorPoint", "Rotation", "AutomaticSize", "SizeConstraint",
		"Orientation", "CFrame",
	}},
	{ cat = "Layout & Visibility", props = {
		"Visible", "ZIndex", "LayoutOrder", "ClipsDescendants",
	}},
	{ cat = "Behavior", props = {
		"Active", "Selectable", "AutoButtonColor", "Modal", "Selected",
		"ScrollingEnabled", "ClearTextOnFocus", "TextEditable", "MultiLine",
	}},
	{ cat = "Text", style = true, props = {
		"FontFace", "TextColor3", "TextSize", "TextScaled", "TextWrapped",
		"TextXAlignment", "TextYAlignment", "TextTransparency", "TextTruncate",
		"RichText", "LineHeight", "MaxVisibleGraphemes",
	}},
	{ cat = "Text Stroke", style = true, props = {
		"TextStrokeColor3", "TextStrokeTransparency",
	}},
	{ cat = "Text Content", props = {
		"Text", "PlaceholderText",
	}},
	{ cat = "Placeholder", style = true, props = {
		"PlaceholderColor3",
	}},
	{ cat = "Image", props = {
		"Image", "ImageRectOffset", "ImageRectSize",
	}},
	{ cat = "Image Style", style = true, props = {
		"ImageColor3", "ImageTransparency", "ScaleType", "SliceCenter", "SliceScale", "TileSize", "ResampleMode",
	}},
	{ cat = "Scrolling", props = {
		"CanvasSize", "CanvasPosition", "ScrollingDirection", "AutomaticCanvasSize",
		"ElasticBehavior", "VerticalScrollBarInset", "HorizontalScrollBarInset",
	}},
	{ cat = "Scroll Bar", style = true, props = {
		"ScrollBarThickness", "ScrollBarImageColor3", "ScrollBarImageTransparency",
		"TopImage", "MidImage", "BottomImage",
	}},
	{ cat = "Canvas Group", style = true, props = {
		"GroupColor3", "GroupTransparency",
	}},
	{ cat = "Viewport", style = true, props = {
		"Ambient", "LightColor", "LightDirection",
	}},

	-- Non-UI (3D / physics) properties. These share the flat detect-by-read
	-- mechanism, so any class exposing them (Part, MeshPart, Model, Attachment,
	-- Weld, WeldConstraint, HingeConstraint, SpringConstraint, ...) picks them up.
	{ cat = "Physics", props = {
		"Anchored", "CanCollide", "CanTouch", "CanQuery", "Locked", "Massless", "CastShadow", "Shape",
	}},
	{ cat = "Surface", style = true, props = {
		"Color", "Material", "MaterialVariant", "Transparency", "Reflectance",
	}},
	{ cat = "Mesh", props = {
		"TextureID", "DoubleSided", "RenderFidelity", "CollisionFidelity",
	}},
	{ cat = "Model", props = {
		"WorldPivot", "LevelOfDetail", "ModelStreamingMode",
	}},
	{ cat = "Attachment", props = {
		"Axis", "SecondaryAxis",
	}},
	{ cat = "Joint", props = {
		"C0", "C1",
	}},
	{ cat = "Constraint", props = {
		"Enabled", "ActuatorType", "ActuatorRelativeTo", "LimitsEnabled", "Restitution",
		"TargetAngle", "AngularSpeed", "MotorMaxTorque", "MotorMaxAcceleration", "ServoMaxTorque",
		"LowerAngle", "UpperAngle",
		"Stiffness", "Damping", "FreeLength", "MaxForce", "MaxLength", "MinLength",
		"Coils", "Radius", "Thickness",
	}},

	-- Layout objects (UIListLayout / UIGridLayout). The "Layout" props are shared
	-- by both, so they carry across a List<->Grid swap; the family-specific props
	-- are kept in swap memory so a swap-back can restore them.
	{ cat = "Layout", props = {
		"FillDirection", "HorizontalAlignment", "VerticalAlignment", "SortOrder", "StartCorner",
	}},
	{ cat = "List Layout", props = {
		"Padding", "ItemLineAlignment", "Wraps", "HorizontalFlex", "VerticalFlex",
	}},
	{ cat = "Grid Layout", props = {
		"CellSize", "CellPadding", "FillDirectionMaxCells",
	}},
}

-- Flatten into an ordered name list + info lookup. Applying / detecting in this
-- order keeps base properties before class-specific ones and is deterministic.
local PROP_ORDER = {}
local PROP_INFO = {}
for _, group in ipairs(PROP_CATALOG) do
	for _, name in ipairs(group.props) do
		table.insert(PROP_ORDER, name)
		PROP_INFO[name] = { cat = group.cat, style = group.style == true }
	end
end

-- Position / size related properties (used by the "Copy Pos" button).
local POS_SET = {
	Position = true, Size = true, AnchorPoint = true, Rotation = true,
	AutomaticSize = true, SizeConstraint = true, LayoutOrder = true,
	Orientation = true, CFrame = true, -- BaseParts (Part / MeshPart)
}

-- Classes an element may be swapped into, per family. This top-to-bottom order is
-- the Swap menu's layout order; the current class is skipped. A GuiObject swaps
-- among UI element classes; a layout object (UIListLayout/UIGridLayout) swaps
-- among layout classes.
local SWAP_ORDER = {
	"Frame", "ScrollingFrame", "TextButton", "TextLabel", "TextBox",
	"ImageLabel", "ImageButton", "CanvasGroup", "ViewportFrame", "VideoFrame",
}

local SWAP_LAYOUT_ORDER = {
	"UIListLayout", "UIGridLayout",
}

-- Icon image for each swap class, shown to the left of the class name. An empty
-- string shows a blank placeholder box; a set image hides that box.
local SWAP_ICONS = {
	Frame          = "rbxassetid://136745022842164",
	ScrollingFrame = "rbxassetid://80832694523145",
	TextButton     = "rbxassetid://130877948484472",
	TextLabel      = "rbxassetid://77047417775689",
	TextBox        = "rbxassetid://76155028129663",
	ImageLabel     = "rbxassetid://75478228858323",
	ImageButton    = "rbxassetid://136714409121667",
	CanvasGroup    = "rbxassetid://79718291046627",
	ViewportFrame  = "rbxassetid://128155805590911",
	VideoFrame     = "rbxassetid://120956755659774",
	UIListLayout   = "rbxassetid://110871426007384",
	UIGridLayout   = "rbxassetid://106105002721909",
}

--============================================================
-- State
--============================================================

local toolOrder = {} -- ordered array of tool ids (user-reorderable)
local activeIndex = 1

-- Copied property clipboard: { [propName] = value }. Session-only: never saved,
-- so it is empty again after re-entering a session.
local copied = {}

-- Which property names were last ticked in the Copy menu (set on "Copy"). The
-- menu opens with these pre-checked; empty at first, so the first open is all
-- unchecked. Session-only.
local copyChecked = {}

-- Active nudge mode for the D-Pad on the UI Editor page: "Position" | "Size" | "Origin".
local nudgeMode = "Position"

-- Hovering the D-Pad hides Studio's big selection outline: the current selection
-- is armed as the nudge target and deselected while the cursor is over the pad,
-- then re-selected on leave. Lets you nudge/preview small elements uncluttered.
local nudgeTarget = {}        -- armed target (kept while deselected during hover)
local nudgeInvert = false     -- UIPadding: subtract instead of add
local nudgeUniform = false    -- Size: nudge both dimensions together
local nudgeStatusLabel        -- page label showing the armed target (set in renderPage)
local nudgeModeHolder         -- Position/Size/Origin column (set in renderPage)
local nudgeInvertBtn          -- Invert toggle for UIPadding (set in renderPage)
local updateNudgeStatus       -- forward-declared; refreshes nudgeStatusLabel
local updateNudgePageMode     -- forward-declared; shows the mode column vs Invert
local nudgeRelayout           -- forward-declared; keeps the label below the controls

-- Swap memory: instance -> full property snapshot ever seen for that logical
-- element. Weak keys so destroyed elements drop out. Lets us restore a property
-- that a previous swap's class couldn't hold, if a later class supports it.
local swapMemory = setmetatable({}, { __mode = "k" })

-- forward declarations
local refreshAll, refreshTabs, refreshTopbar, refreshPage, save
local showCopyMenu, showSwapMenu, showLayoutOrderMenu

--============================================================
-- Safe accessors / selection
--============================================================

local function safeParent(inst)
	local ok, p = pcall(function() return inst.Parent end)
	if ok then return p end
	return nil
end

local function safeName(inst)
	local ok, n = pcall(function() return inst.Name end)
	if ok then return n end
	return "?"
end

local function safeClass(inst)
	local ok, c = pcall(function() return inst.ClassName end)
	if ok then return c end
	return "?"
end

local function isA(inst, class)
	local ok, res = pcall(function() return inst:IsA(class) end)
	return ok and res
end

local function currentSelection()
	return Selection:Get()
end

-- Last selected instance (single-target actions use this).
local function latestSelected()
	local sel = Selection:Get()
	return sel[#sel]
end

-- Last selected instance, but only if it is a 2D UI element.
local function latestGui()
	local inst = latestSelected()
	if inst and isA(inst, "GuiObject") then
		return inst
	end
	return nil
end

-- Last selected instance if Copy Style / Copy Pos can read it: a UI element or a
-- BasePart (Part, MeshPart, ...).
local function latestCopyable()
	local inst = latestSelected()
	if inst and (isA(inst, "GuiObject") or isA(inst, "BasePart")) then
		return inst
	end
	return nil
end

--============================================================
-- RichText / value formatting
--============================================================

local function escapeRich(s)
	s = tostring(s)
	s = s:gsub("&", "&amp;")
	s = s:gsub("<", "&lt;")
	s = s:gsub(">", "&gt;")
	return s
end

local function numStr(n)
	if n == math.floor(n) and math.abs(n) < 1e9 then
		return string.format("%d", n)
	end
	return string.format("%.3g", n)
end

local function round255(x)
	return math.clamp(math.floor(x * 255 + 0.5), 0, 255)
end

-- Concise, human-readable preview of a property value (for the Copy menu).
local function fmtValue(v)
	local t = typeof(v)
	if t == "Color3" then
		return string.format("%d, %d, %d", round255(v.R), round255(v.G), round255(v.B))
	elseif t == "UDim2" then
		return string.format("{%s, %d}, {%s, %d}", numStr(v.X.Scale), v.X.Offset, numStr(v.Y.Scale), v.Y.Offset)
	elseif t == "UDim" then
		return string.format("{%s, %d}", numStr(v.Scale), v.Offset)
	elseif t == "Vector2" then
		return string.format("%s, %s", numStr(v.X), numStr(v.Y))
	elseif t == "Vector3" then
		return string.format("%s, %s, %s", numStr(v.X), numStr(v.Y), numStr(v.Z))
	elseif t == "EnumItem" then
		return v.Name
	elseif t == "BrickColor" then
		return v.Name
	elseif t == "CFrame" then
		return string.format("%s, %s, %s", numStr(v.X), numStr(v.Y), numStr(v.Z))
	elseif t == "number" then
		return numStr(v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		local s = v
		if #s > 42 then s = s:sub(1, 42) .. "..." end
		return '"' .. s .. '"'
	elseif t == "Font" then
		local weight = "Regular"
		pcall(function() weight = v.Weight.Name end)
		return "Font(" .. weight .. ")"
	elseif t == "Rect" then
		return string.format("{%s, %s}, {%s, %s}", numStr(v.Min.X), numStr(v.Min.Y), numStr(v.Max.X), numStr(v.Max.Y))
	end
	local s = tostring(v)
	if #s > 42 then s = s:sub(1, 42) .. "..." end
	return s
end

--============================================================
-- Property detect / copy / paste / swap
--============================================================

local function readProp(inst, name)
	local ok, v = pcall(function() return inst[name] end)
	if ok then return true, v end
	return false, nil
end

local function writeProp(inst, name, value)
	return pcall(function() inst[name] = value end)
end

-- Ordered list of { name, value, cat, style } for every catalog property the
-- element actually exposes.
local function detectProps(inst)
	local out = {}
	for _, name in ipairs(PROP_ORDER) do
		local ok, v = readProp(inst, name)
		if ok then
			table.insert(out, { name = name, value = v, cat = PROP_INFO[name].cat, style = PROP_INFO[name].style })
		end
	end
	return out
end

local function copiedCount()
	local n = 0
	for _ in pairs(copied) do n += 1 end
	return n
end

-- Apply the clipboard to one instance; returns how many properties took.
local function pasteInto(inst)
	local applied = 0
	for _, name in ipairs(PROP_ORDER) do
		if copied[name] ~= nil then
			if writeProp(inst, name, copied[name]) then
				applied += 1
			end
		end
	end
	return applied
end

-- Wrap a mutation in a ChangeHistory recording so Ctrl+Z works. Falls back to a
-- waypoint on Studio builds without the recording API.
local function recorded(name, fn)
	local id = nil
	pcall(function() id = ChangeHistoryService:TryBeginRecording(name) end)
	local ok, err = pcall(fn)
	if id then
		pcall(function() ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit) end)
	else
		pcall(function() ChangeHistoryService:SetWaypoint(name) end)
	end
	if not ok then
		warn("[ExplorerFunctions] " .. tostring(err))
	end
end

-- Union of this element's live properties with anything remembered for it from a
-- prior swap (live values win). Used so swaps never lose data across classes.
local function unionSnapshot(inst)
	local snap = {}
	local mem = swapMemory[inst]
	if mem then
		for k, v in pairs(mem) do snap[k] = v end
	end
	for _, p in ipairs(detectProps(inst)) do
		snap[p.name] = p.value
	end
	return snap
end

-- Change an element's class in place: build the new class, carry over every
-- supported property (and children), drop the old one, select the new one.
local function performSwap(oldInst, newClass)
	local snap = unionSnapshot(oldInst)
	local parent = safeParent(oldInst)
	local newInst = nil
	recorded("Swap to " .. newClass, function()
		newInst = Instance.new(newClass)
		for _, name in ipairs(PROP_ORDER) do
			if snap[name] ~= nil then
				writeProp(newInst, name, snap[name])
			end
		end
		pcall(function() newInst.Name = oldInst.Name end)
		for _, child in ipairs(oldInst:GetChildren()) do
			pcall(function() child.Parent = newInst end)
		end
		newInst.Parent = parent
		-- Detach (don't Destroy) the old element: Destroy() locks its Parent and
		-- makes Undo warn "Parent property is locked". Leaving it parentless keeps
		-- the swap fully undoable; it's off the tree and gets collected.
		oldInst.Parent = nil
	end)
	if newInst then
		-- Carry the full union forward so a property this class couldn't hold can
		-- still come back on a future swap to a class that supports it.
		swapMemory[newInst] = snap
		pcall(function() Selection:Set({ newInst }) end)
	end
	return newInst
end

--============================================================
-- Dock widget
--============================================================

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false, -- start closed
	false, -- do not override the previously saved enabled state
	470, 820, -- default float size
	320, 320 -- minimum size
)

local widget
pcall(function()
	widget = plugin:CreateDockWidgetPluginGuiAsync("ExplorerFunctionsPanel", widgetInfo)
end)
if not widget then
	widget = plugin:CreateDockWidgetPluginGui("ExplorerFunctionsPanel", widgetInfo)
end
widget.Title = "Explorer Functions"

-- Clear leftover children if this plugin re-ran in the same session.
for _, c in ipairs(widget:GetChildren()) do
	c:Destroy()
end

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, 0, 1, 0)
content.BackgroundColor3 = THEME.bg
content.BorderSizePixel = 0
content.Parent = widget

--============================================================
-- Widget-building helpers
--============================================================

local function createBtnVisual(parent, text)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = THEME.btn
	b.BorderSizePixel = 0
	b.Size = UDim2.new(0, 0, 1, -6)
	b.AutomaticSize = Enum.AutomaticSize.X
	b.Font = Enum.Font.Gotham
	b.TextSize = 13
	b.TextColor3 = THEME.text
	b.Text = text
	b.Name = "Btn_" .. text
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = b
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = b
	b.Parent = parent
	return b
end

local function makeButton(parent, text, cb, bgColor, hoverColor)
	local b = createBtnVisual(parent, text)
	local base = bgColor or THEME.btn
	local hover = hoverColor or THEME.btnHover
	b.BackgroundColor3 = base
	b.MouseEnter:Connect(function() b.BackgroundColor3 = hover end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = base end)
	b.MouseButton1Click:Connect(function()
		local ok, err = pcall(cb)
		if not ok then warn("[ExplorerFunctions] " .. tostring(err)) end
	end)
	return b
end

-- A toggle button that keeps its "on" color even when the cursor leaves.
-- (Kept from the previous plugin as a shared styling primitive for future tools.)
local function makeToggle(parent, text, isOn, onClick)
	local b = createBtnVisual(parent, text)
	local function paint()
		b.BackgroundColor3 = isOn() and THEME.rowSel or THEME.btn
	end
	b.MouseEnter:Connect(function()
		if not isOn() then b.BackgroundColor3 = THEME.btnHover end
	end)
	b.MouseLeave:Connect(paint)
	b.MouseButton1Click:Connect(function()
		local ok, err = pcall(onClick)
		if not ok then warn("[ExplorerFunctions] " .. tostring(err)) end
		paint()
	end)
	paint()
	return b, paint
end

local function makeStrip(parent, yPos, height)
	local strip = Instance.new("ScrollingFrame")
	strip.BackgroundColor3 = THEME.bar
	strip.BorderSizePixel = 0
	strip.Size = UDim2.new(1, 0, 0, height)
	strip.Position = UDim2.new(0, 0, 0, yPos)
	strip.ScrollBarThickness = 4
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.CanvasSize = UDim2.new(0, 0, 0, 0)
	strip.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = strip
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = strip
	return strip
end

local function makeOverlay()
	local o = Instance.new("Frame")
	o.BackgroundColor3 = THEME.bg
	o.BorderSizePixel = 0
	o.Active = true -- sink input so the page underneath isn't clickable
	o.Position = UDim2.new(0, 0, 0, 0)
	o.Size = UDim2.new(1, 0, 1, 0)
	o.Visible = false
	o.ZIndex = 50
	o.Parent = content
	return o
end

-- Tab button (kept identical in styling to the previous plugin's group tabs).
local function makeTab(parent, name, index, isActive)
	local b = createBtnVisual(parent, name)
	b.LayoutOrder = index * 10
	b.TextColor3 = THEME.header
	local base = isActive and THEME.rowSel or THEME.btn
	b.BackgroundColor3 = base
	b.MouseEnter:Connect(function()
		if not isActive then b.BackgroundColor3 = THEME.btnHover end
	end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = base end)
	b.MouseButton1Click:Connect(function()
		activeIndex = index
		save()
		refreshAll()
	end)
	return b
end

local function makeArrow(parent, text, layoutOrder, cb)
	local b = createBtnVisual(parent, text)
	b.LayoutOrder = layoutOrder
	b.TextColor3 = THEME.text
	b.MouseEnter:Connect(function() b.BackgroundColor3 = THEME.btnHover end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = THEME.btn end)
	b.MouseButton1Click:Connect(function()
		local ok, err = pcall(cb)
		if not ok then warn("[ExplorerFunctions] " .. tostring(err)) end
	end)
	return b
end

local function clearChildren(guiObj)
	for _, child in ipairs(guiObj:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
end

--============================================================
-- Layout
--   Row 1 / Row 2  : per-tool action buttons (rebuilt on tab switch)
--   tabRow         : the tools, reorderable via < >
--   pageArea       : the active tool's page
--
-- Note: the previous plugin's main node-list scrolling frame and the bottom info
-- bar are intentionally not built yet - they'll return when a tool needs them.
--============================================================

local actionRow = makeStrip(content, 4, 28)
local actionRow2 = makeStrip(content, 34, 28)
local tabRow = makeStrip(content, 64, 28)

local pageArea = Instance.new("Frame")
pageArea.Name = "PageArea"
pageArea.BackgroundColor3 = THEME.bg
pageArea.BorderSizePixel = 0
pageArea.Position = UDim2.new(0, 0, 0, 94)
pageArea.Size = UDim2.new(1, 0, 1, -94)
pageArea.Parent = content

--============================================================
-- Copy overlay (property picker)
--============================================================

-- Overlay top/bottom bar heights (match the old plugin's info-bar height).
local TOPBAR_H = 26
local BOTTOMBAR_H = 26

local copyOverlay = makeOverlay()

-- Top bar: title (left) + Copy / Close (right). Title styled like the old
-- plugin's "Press Ctrl+C to copy..." info line (Gotham, size 12).
local copyBar = Instance.new("Frame")
copyBar.BackgroundColor3 = THEME.bar
copyBar.BorderSizePixel = 0
copyBar.Size = UDim2.new(1, 0, 0, TOPBAR_H)
copyBar.ZIndex = 51
copyBar.Parent = copyOverlay

local copyTitle = Instance.new("TextLabel")
copyTitle.BackgroundTransparency = 1
copyTitle.Position = UDim2.new(0, 8, 0, 0)
copyTitle.Size = UDim2.new(1, -130, 1, 0)
copyTitle.Font = Enum.Font.Gotham
copyTitle.TextSize = 12
copyTitle.TextColor3 = THEME.text
copyTitle.TextXAlignment = Enum.TextXAlignment.Left
copyTitle.TextTruncate = Enum.TextTruncate.AtEnd
copyTitle.Text = "Copy"
copyTitle.ZIndex = 52
copyTitle.Parent = copyBar

-- Copy confirm: styled the same as Close (no accent color).
local copyConfirm = createBtnVisual(copyBar, "Copy")
copyConfirm.AutomaticSize = Enum.AutomaticSize.None
copyConfirm.AnchorPoint = Vector2.new(1, 0.5)
copyConfirm.Position = UDim2.new(1, -68, 0.5, 0)
copyConfirm.Size = UDim2.new(0, 56, 0, 22)
copyConfirm.ZIndex = 52
copyConfirm.MouseEnter:Connect(function() copyConfirm.BackgroundColor3 = THEME.btnHover end)
copyConfirm.MouseLeave:Connect(function() copyConfirm.BackgroundColor3 = THEME.btn end)

local copyCloseBtn = createBtnVisual(copyBar, "Close")
copyCloseBtn.AutomaticSize = Enum.AutomaticSize.None
copyCloseBtn.AnchorPoint = Vector2.new(1, 0.5)
copyCloseBtn.Position = UDim2.new(1, -6, 0.5, 0)
copyCloseBtn.Size = UDim2.new(0, 56, 0, 22)
copyCloseBtn.ZIndex = 52
copyCloseBtn.MouseEnter:Connect(function() copyCloseBtn.BackgroundColor3 = THEME.btnHover end)
copyCloseBtn.MouseLeave:Connect(function() copyCloseBtn.BackgroundColor3 = THEME.btn end)

local copyScroll = Instance.new("ScrollingFrame")
copyScroll.BackgroundColor3 = THEME.bg
copyScroll.BorderColor3 = THEME.border
copyScroll.BorderSizePixel = 1
copyScroll.Position = UDim2.new(0, 0, 0, TOPBAR_H)
copyScroll.Size = UDim2.new(1, 0, 1, -(TOPBAR_H + BOTTOMBAR_H))
copyScroll.ClipsDescendants = true
copyScroll.ScrollBarThickness = 8
copyScroll.ScrollingDirection = Enum.ScrollingDirection.Y
copyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
copyScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
copyScroll.ZIndex = 51
copyScroll.Parent = copyOverlay
do
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = copyScroll
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = copyScroll
end

-- Bottom bar (styled like the old plugin's bottom "Key:" panel): All / None + count.
local copyBottom = Instance.new("Frame")
copyBottom.BackgroundColor3 = THEME.bar
copyBottom.BorderSizePixel = 0
copyBottom.AnchorPoint = Vector2.new(0, 1)
copyBottom.Position = UDim2.new(0, 0, 1, 0)
copyBottom.Size = UDim2.new(1, 0, 0, BOTTOMBAR_H)
copyBottom.ZIndex = 51
copyBottom.Parent = copyOverlay

local allBtn = createBtnVisual(copyBottom, "All")
allBtn.AutomaticSize = Enum.AutomaticSize.None
allBtn.AnchorPoint = Vector2.new(0, 0.5)
allBtn.Position = UDim2.new(0, 8, 0.5, 0)
allBtn.Size = UDim2.new(0, 44, 0, 20)
allBtn.ZIndex = 52
allBtn.MouseEnter:Connect(function() allBtn.BackgroundColor3 = THEME.btnHover end)
allBtn.MouseLeave:Connect(function() allBtn.BackgroundColor3 = THEME.btn end)

local noneBtn = createBtnVisual(copyBottom, "None")
noneBtn.AutomaticSize = Enum.AutomaticSize.None
noneBtn.AnchorPoint = Vector2.new(0, 0.5)
noneBtn.Position = UDim2.new(0, 58, 0.5, 0)
noneBtn.Size = UDim2.new(0, 52, 0, 20)
noneBtn.ZIndex = 52
noneBtn.MouseEnter:Connect(function() noneBtn.BackgroundColor3 = THEME.btnHover end)
noneBtn.MouseLeave:Connect(function() noneBtn.BackgroundColor3 = THEME.btn end)

local copyCount = Instance.new("TextLabel")
copyCount.BackgroundTransparency = 1
copyCount.AnchorPoint = Vector2.new(1, 0.5)
copyCount.Position = UDim2.new(1, -10, 0.5, 0)
copyCount.Size = UDim2.new(0, 120, 1, 0)
copyCount.Font = Enum.Font.Gotham
copyCount.TextSize = 12
copyCount.TextColor3 = THEME.textDim
copyCount.TextXAlignment = Enum.TextXAlignment.Right
copyCount.Text = ""
copyCount.ZIndex = 52
copyCount.Parent = copyBottom

local copyMenuItems = {} -- { name, value, checked, cb (checkbox), row }

-- Checked box uses the selected-tab blue with a checkmark; unchecked is blank.
local function paintCheckbox(item)
	if item.checked then
		item.cb.BackgroundColor3 = THEME.rowSel
		item.cb.Text = "✓"
	else
		item.cb.BackgroundColor3 = THEME.btn
		item.cb.Text = ""
	end
end

local function updateCopyCount()
	local n = 0
	for _, item in ipairs(copyMenuItems) do
		if item.checked then n += 1 end
	end
	copyCount.Text = n .. " / " .. #copyMenuItems
end

local function setAllChecked(v)
	for _, item in ipairs(copyMenuItems) do
		item.checked = v
		paintCheckbox(item)
	end
	updateCopyCount()
end

local function copyHeaderRow(text, order)
	local h = Instance.new("TextLabel")
	h.BackgroundTransparency = 1
	h.Size = UDim2.new(1, 0, 0, 22)
	h.Font = Enum.Font.GothamBold
	h.TextSize = 14
	h.TextColor3 = THEME.header
	h.TextXAlignment = Enum.TextXAlignment.Left
	h.Text = "-- " .. text .. " " .. string.rep("-", 20)
	h.LayoutOrder = order
	h.ZIndex = 52
	h.Parent = copyScroll
end

local function copyPropRow(p, order)
	local row = Instance.new("TextButton")
	row.AutoButtonColor = false
	row.BackgroundColor3 = THEME.rowHover
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, 18)
	row.Font = Enum.Font.Code
	row.TextSize = 14
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextColor3 = THEME.text
	row.TextTruncate = Enum.TextTruncate.AtEnd
	row.RichText = true
	row.Text = escapeRich(p.name)
		.. ' <font color="' .. DIM_HEX .. '">=</font> '
		.. '<font color="' .. VALUE_HEX .. '">' .. escapeRich(fmtValue(p.value)) .. "</font>"
	row.LayoutOrder = order
	row.ZIndex = 52
	do
		local pad = Instance.new("UIPadding")
		pad.PaddingRight = UDim.new(0, 26)
		pad.Parent = row
	end
	row.Parent = copyScroll

	-- Checkbox: styled like a selected tab button (blue when on) with a checkmark.
	local cb = Instance.new("TextButton")
	cb.AutoButtonColor = false
	cb.AnchorPoint = Vector2.new(1, 0.5)
	cb.Position = UDim2.new(1, -4, 0.5, 0)
	cb.Size = UDim2.new(0, 16, 0, 16)
	cb.BackgroundColor3 = THEME.btn
	cb.BorderSizePixel = 0
	cb.Font = Enum.Font.GothamBold
	cb.TextSize = 12
	cb.TextColor3 = THEME.text
	cb.Text = ""
	cb.ZIndex = 53
	do
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = cb
	end
	cb.Parent = row

	-- Default-checked from the remembered set (empty on first open = all off).
	local item = { name = p.name, value = p.value, checked = copyChecked[p.name] == true, cb = cb, row = row }
	local function toggle()
		item.checked = not item.checked
		paintCheckbox(item)
		updateCopyCount()
	end
	row.MouseEnter:Connect(function()
		row.BackgroundTransparency = 0
	end)
	row.MouseLeave:Connect(function()
		row.BackgroundTransparency = 1
	end)
	row.MouseButton1Click:Connect(toggle)
	cb.MouseButton1Click:Connect(toggle)
	paintCheckbox(item)
	return item
end

-- Build (or rebuild) the Copy menu for the current Explorer selection. Works on
-- any instance (UI or 3D/physics), opens regardless of selection, and re-runs
-- live whenever the Explorer selection changes.
showCopyMenu = function()
	clearChildren(copyScroll)
	copyMenuItems = {}
	local inst = latestSelected()
	if not inst then
		copyTitle.Text = "Select element to Copy from."
		updateCopyCount()
		copyOverlay.Visible = true
		return
	end
	copyTitle.Text = "Copy : " .. safeName(inst) .. " (" .. safeClass(inst) .. ")"

	local order = 0
	local lastCat = nil
	for _, p in ipairs(detectProps(inst)) do
		if p.cat ~= lastCat then
			order += 1
			copyHeaderRow(p.cat, order)
			lastCat = p.cat
		end
		order += 1
		table.insert(copyMenuItems, copyPropRow(p, order))
	end

	updateCopyCount()
	copyScroll.CanvasPosition = Vector2.new(0, 0)
	copyOverlay.Visible = true
end

copyConfirm.MouseButton1Click:Connect(function()
	copied = {}
	copyChecked = {}
	for _, item in ipairs(copyMenuItems) do
		if item.checked then
			copied[item.name] = item.value
			copyChecked[item.name] = true -- remember for the next time the menu opens
		end
	end
	copyOverlay.Visible = false
	if refreshTopbar then refreshTopbar() end
end)
copyCloseBtn.MouseButton1Click:Connect(function() copyOverlay.Visible = false end)
allBtn.MouseButton1Click:Connect(function() setAllChecked(true) end)
noneBtn.MouseButton1Click:Connect(function() setAllChecked(false) end)

--============================================================
-- Swap overlay (class picker)
--============================================================

local swapOverlay = makeOverlay()

local swapBar = Instance.new("Frame")
swapBar.BackgroundColor3 = THEME.bar
swapBar.BorderSizePixel = 0
swapBar.Size = UDim2.new(1, 0, 0, TOPBAR_H)
swapBar.ZIndex = 51
swapBar.Parent = swapOverlay

local swapTitle = Instance.new("TextLabel")
swapTitle.BackgroundTransparency = 1
swapTitle.Position = UDim2.new(0, 8, 0, 0)
swapTitle.Size = UDim2.new(1, -74, 1, 0)
swapTitle.Font = Enum.Font.Gotham
swapTitle.TextSize = 12
swapTitle.TextColor3 = THEME.text
swapTitle.TextXAlignment = Enum.TextXAlignment.Left
swapTitle.TextTruncate = Enum.TextTruncate.AtEnd
swapTitle.Text = "Swap"
swapTitle.ZIndex = 52
swapTitle.Parent = swapBar

local swapCloseBtn = createBtnVisual(swapBar, "Close")
swapCloseBtn.AutomaticSize = Enum.AutomaticSize.None
swapCloseBtn.AnchorPoint = Vector2.new(1, 0.5)
swapCloseBtn.Position = UDim2.new(1, -6, 0.5, 0)
swapCloseBtn.Size = UDim2.new(0, 56, 0, 22)
swapCloseBtn.ZIndex = 52
swapCloseBtn.MouseEnter:Connect(function() swapCloseBtn.BackgroundColor3 = THEME.btnHover end)
swapCloseBtn.MouseLeave:Connect(function() swapCloseBtn.BackgroundColor3 = THEME.btn end)
swapCloseBtn.MouseButton1Click:Connect(function() swapOverlay.Visible = false end)

local swapScroll = Instance.new("ScrollingFrame")
swapScroll.BackgroundColor3 = THEME.bg
swapScroll.BorderColor3 = THEME.border
swapScroll.BorderSizePixel = 1
swapScroll.Position = UDim2.new(0, 0, 0, TOPBAR_H)
swapScroll.Size = UDim2.new(1, 0, 1, -TOPBAR_H)
swapScroll.ClipsDescendants = true
swapScroll.ScrollBarThickness = 8
swapScroll.ScrollingDirection = Enum.ScrollingDirection.Y
swapScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
swapScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
swapScroll.ZIndex = 51
swapScroll.Parent = swapOverlay
do
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = swapScroll
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = swapScroll
end

-- One class option: [icon] ClassName. Class name is plain white; a transparent
-- button on top handles hover + click so the icon/label show through beneath it.
local function swapClassRow(class, order, inst)
	local rowFrame = Instance.new("Frame")
	rowFrame.BackgroundColor3 = THEME.rowHover
	rowFrame.BackgroundTransparency = 1
	rowFrame.BorderSizePixel = 0
	rowFrame.Size = UDim2.new(1, 0, 0, 18)
	rowFrame.LayoutOrder = order
	rowFrame.ZIndex = 52
	rowFrame.Parent = swapScroll

	local img = SWAP_ICONS[class] or ""
	local icon = Instance.new("ImageLabel")
	icon.BackgroundColor3 = THEME.btn
	-- Show the placeholder box only until a real icon is set.
	icon.BackgroundTransparency = (img ~= "") and 1 or 0
	icon.BorderSizePixel = 0
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 1, 0.5, 0)
	icon.Size = UDim2.new(0, 16, 0, 16)
	icon.Image = img
	icon.ZIndex = 52
	do
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 3)
		corner.Parent = icon
	end
	icon.Parent = rowFrame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 22, 0, 0)
	nameLabel.Size = UDim2.new(1, -22, 1, 0)
	nameLabel.Font = Enum.Font.Code
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = THEME.text
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = class
	nameLabel.ZIndex = 52
	nameLabel.Parent = rowFrame

	local clickBtn = Instance.new("TextButton")
	clickBtn.BackgroundTransparency = 1
	clickBtn.Text = ""
	clickBtn.Size = UDim2.new(1, 0, 1, 0)
	clickBtn.ZIndex = 53
	clickBtn.Parent = rowFrame
	clickBtn.MouseEnter:Connect(function() rowFrame.BackgroundTransparency = 0 end)
	clickBtn.MouseLeave:Connect(function() rowFrame.BackgroundTransparency = 1 end)
	clickBtn.MouseButton1Click:Connect(function()
		performSwap(inst, class)
		swapOverlay.Visible = false
		if refreshTopbar then refreshTopbar() end
	end)
end

-- The latest selected swappable instance and the ordered target-class list for
-- its family: GuiObjects swap among UI element classes; layout objects
-- (UIListLayout / UIGridLayout / ...) swap among layout classes.
local function latestSwapTarget()
	local inst = latestSelected()
	if not inst then return nil end
	if isA(inst, "GuiObject") then
		return inst, SWAP_ORDER
	elseif isA(inst, "UIGridStyleLayout") then
		return inst, SWAP_LAYOUT_ORDER
	end
	return nil
end

-- Build (or rebuild) the Swap menu for the current selection. Opens regardless
-- of selection and re-runs live when the Explorer selection changes.
showSwapMenu = function()
	clearChildren(swapScroll)
	local inst, classes = latestSwapTarget()
	if not inst then
		swapTitle.Text = "Select element to Swap from."
		swapOverlay.Visible = true
		return
	end
	swapTitle.Text = "Swap : " .. safeName(inst) .. " (" .. safeClass(inst) .. ")"

	local curClass = safeClass(inst)
	local order = 0
	for _, class in ipairs(classes) do
		if class ~= curClass then
			order += 1
			swapClassRow(class, order, inst)
		end
	end

	swapScroll.CanvasPosition = Vector2.new(0, 0)
	swapOverlay.Visible = true
end

--============================================================
-- LayoutOrder overlay (gap-free list reordering)
--============================================================

-- Reorder one parent's GuiObject children: normalize their LayoutOrder to
-- 0..n-1 (fixing gaps and ties from the current order), then move the selected
-- subset as one gap-free group. mode: "left" (-1), "right" (+1), "min", "max".
local function reorderParent(parent, selSet, mode)
	local kids = {}
	for i, c in ipairs(parent:GetChildren()) do
		if isA(c, "GuiObject") then
			table.insert(kids, { inst = c, ord = c.LayoutOrder, idx = i })
		end
	end
	if #kids == 0 then return end
	-- Current relative order = LayoutOrder, ties broken by Explorer child index.
	table.sort(kids, function(a, b)
		if a.ord ~= b.ord then return a.ord < b.ord end
		return a.idx < b.idx
	end)

	local pos = {} -- inst -> normalized 0-based order
	local U, S = {}, {} -- unselected / selected, each in normalized order
	for i, k in ipairs(kids) do
		pos[k.inst] = i - 1
		if selSet[k.inst] then
			table.insert(S, k.inst)
		else
			table.insert(U, k.inst)
		end
	end
	if #S == 0 then return end

	-- How many unselected elements sit before a given normalized order.
	local function unselectedBefore(orderVal)
		local c = 0
		for _, u in ipairs(U) do
			if pos[u] < orderVal then c += 1 end
		end
		return c
	end

	-- Insertion index of the selected group within the unselected sequence.
	local idx
	if mode == "left" then
		idx = unselectedBefore(pos[S[1]]) - 1
	elseif mode == "right" then
		idx = unselectedBefore(pos[S[#S]]) + 1
	elseif mode == "min" then
		idx = 0
	else -- "max"
		idx = #U
	end
	idx = math.clamp(idx, 0, #U)

	-- Rebuild the sibling order: unselected, with the selected block spliced in.
	local final = {}
	for i = 1, idx do table.insert(final, U[i]) end
	for _, s in ipairs(S) do table.insert(final, s) end
	for i = idx + 1, #U do table.insert(final, U[i]) end

	for i, inst in ipairs(final) do
		pcall(function() inst.LayoutOrder = i - 1 end)
	end
end

-- Group the selected GuiObjects by parent, then reorder each parent's list.
local function applyReorder(mode)
	local byParent = {}
	for _, inst in ipairs(currentSelection()) do
		if isA(inst, "GuiObject") then
			local p = safeParent(inst)
			if p then
				byParent[p] = byParent[p] or {}
				byParent[p][inst] = true
			end
		end
	end
	if not next(byParent) then return end
	recorded("Reorder LayoutOrder", function()
		for parent, selSet in pairs(byParent) do
			reorderParent(parent, selSet, mode)
		end
	end)
end

local loOverlay = makeOverlay()

local loBar = Instance.new("Frame")
loBar.BackgroundColor3 = THEME.bar
loBar.BorderSizePixel = 0
loBar.Size = UDim2.new(1, 0, 0, TOPBAR_H)
loBar.ZIndex = 51
loBar.Parent = loOverlay

local loTitle = Instance.new("TextLabel")
loTitle.BackgroundTransparency = 1
loTitle.Position = UDim2.new(0, 8, 0, 0)
loTitle.Size = UDim2.new(1, -74, 1, 0)
loTitle.Font = Enum.Font.Gotham
loTitle.TextSize = 12
loTitle.TextColor3 = THEME.text
loTitle.TextXAlignment = Enum.TextXAlignment.Left
loTitle.TextTruncate = Enum.TextTruncate.AtEnd
loTitle.Text = "LayoutOrder"
loTitle.ZIndex = 52
loTitle.Parent = loBar

local loCloseBtn = createBtnVisual(loBar, "Close")
loCloseBtn.AutomaticSize = Enum.AutomaticSize.None
loCloseBtn.AnchorPoint = Vector2.new(1, 0.5)
loCloseBtn.Position = UDim2.new(1, -6, 0.5, 0)
loCloseBtn.Size = UDim2.new(0, 56, 0, 22)
loCloseBtn.ZIndex = 52
loCloseBtn.MouseEnter:Connect(function() loCloseBtn.BackgroundColor3 = THEME.btnHover end)
loCloseBtn.MouseLeave:Connect(function() loCloseBtn.BackgroundColor3 = THEME.btn end)
loCloseBtn.MouseButton1Click:Connect(function() loOverlay.Visible = false end)

-- Blank main frame (same look as the Copy menu's list frame, but empty).
local loBody = Instance.new("Frame")
loBody.BackgroundColor3 = THEME.bg
loBody.BorderColor3 = THEME.border
loBody.BorderSizePixel = 1
loBody.Position = UDim2.new(0, 0, 0, TOPBAR_H)
loBody.Size = UDim2.new(1, 0, 1, -TOPBAR_H)
loBody.ClipsDescendants = true
loBody.ZIndex = 51
loBody.Parent = loOverlay

-- Top-center controls: row 1 = "< Left" / "Right >", row 2 = "Min" / "Max".
local loButtons = Instance.new("Frame")
loButtons.BackgroundTransparency = 1
loButtons.AnchorPoint = Vector2.new(0.5, 0)
loButtons.Position = UDim2.new(0.5, 0, 0, 12)
loButtons.AutomaticSize = Enum.AutomaticSize.XY
loButtons.Size = UDim2.new(0, 0, 0, 0)
loButtons.ZIndex = 52
loButtons.Parent = loBody
do
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = loButtons
end

local function loRow(order)
	local r = Instance.new("Frame")
	r.BackgroundTransparency = 1
	r.AutomaticSize = Enum.AutomaticSize.XY
	r.Size = UDim2.new(0, 0, 0, 0)
	r.LayoutOrder = order
	r.ZIndex = 52
	r.Parent = loButtons
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = r
	return r
end

-- Selected instances that are UI elements (only these can be reordered).
local function selectedGuis()
	local out = {}
	for _, inst in ipairs(currentSelection()) do
		if isA(inst, "GuiObject") then table.insert(out, inst) end
	end
	return out
end

-- Swap the LayoutOrder values of exactly two selected UI elements.
local function swapOrders()
	local guis = selectedGuis()
	if #guis ~= 2 then
		warn("[ExplorerFunctions] Select exactly 2 elements to swap their LayoutOrder.")
		return
	end
	local a, b = guis[1], guis[2]
	recorded("Swap LayoutOrder", function()
		a.LayoutOrder, b.LayoutOrder = b.LayoutOrder, a.LayoutOrder
	end)
end

local function loMakeButton(parent, text, order, cb)
	local b = createBtnVisual(parent, text)
	b.AutomaticSize = Enum.AutomaticSize.X
	b.Size = UDim2.new(0, 0, 0, 22)
	b.LayoutOrder = order
	b.ZIndex = 52
	b.MouseEnter:Connect(function() b.BackgroundColor3 = THEME.btnHover end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = THEME.btn end)
	b.MouseButton1Click:Connect(function()
		local ok, err = pcall(cb)
		if not ok then warn("[ExplorerFunctions] " .. tostring(err)) end
	end)
	return b
end

do
	local row1 = loRow(1)
	loMakeButton(row1, "< Left", 1, function() applyReorder("left") end)
	loMakeButton(row1, "Right >", 2, function() applyReorder("right") end)
	local row2 = loRow(2)
	loMakeButton(row2, "Min", 1, function() applyReorder("min") end)
	loMakeButton(row2, "Max", 2, function() applyReorder("max") end)
	local row3 = loRow(3)
	loMakeButton(row3, "Swap", 1, function() swapOrders() end)
end

-- Open / refresh the LayoutOrder menu for the current selection.
showLayoutOrderMenu = function()
	local guis = selectedGuis()
	local n = #guis
	if n == 0 then
		loTitle.Text = "Select List element to Reorder."
		loButtons.Visible = false
	elseif n == 1 then
		loTitle.Text = "LayoutOrder : " .. safeName(guis[1]) .. " (" .. safeClass(guis[1]) .. ")"
		loButtons.Visible = true
	else
		loTitle.Text = "LayoutOrder : ..."
		loButtons.Visible = true
	end
	loOverlay.Visible = true
end

--============================================================
-- Tool actions
--============================================================

local function onCopy()
	showCopyMenu()
end

local function onCopyStyle()
	local inst = latestCopyable()
	if not inst then
		warn("[ExplorerFunctions] Select a UI element or Part in the Explorer first.")
		return
	end
	copied = {}
	for _, p in ipairs(detectProps(inst)) do
		if p.style then
			copied[p.name] = p.value
		end
	end
	-- Also carry the Text, unless it's the default "Label" (which we never want).
	local ok, txt = readProp(inst, "Text")
	if ok and typeof(txt) == "string" and txt ~= "Label" then
		copied.Text = txt
	end
	if refreshTopbar then refreshTopbar() end
end

local function onCopyPos()
	local inst = latestCopyable()
	if not inst then
		warn("[ExplorerFunctions] Select a UI element or Part in the Explorer first.")
		return
	end
	copied = {}
	for _, p in ipairs(detectProps(inst)) do
		if POS_SET[p.name] then
			copied[p.name] = p.value
		end
	end
	if refreshTopbar then refreshTopbar() end
end

local function onPaste()
	if copiedCount() == 0 then
		warn("[ExplorerFunctions] Nothing copied yet. Use Copy, Copy Style or Copy Pos first.")
		return
	end
	local targets = currentSelection()
	if #targets == 0 then
		warn("[ExplorerFunctions] Select the element(s) to paste into.")
		return
	end
	recorded("Paste properties", function()
		for _, t in ipairs(targets) do
			pasteInto(t)
		end
	end)
end

local function onSwap()
	showSwapMenu()
end

local function onLayoutOrder()
	showLayoutOrderMenu()
end

local function pasteLabel()
	local n = copiedCount()
	if n > 0 then return "Paste (" .. n .. ")" end
	return "Paste"
end

--============================================================
-- Nudge (D-Pad) — pixel/anchor nudging on the UI Editor page
--============================================================

-- Snap v to the next 0.5 grid line strictly in direction s (+1 up / -1 down).
-- e.g. 0.1 with s=+1 -> 0.5 (not 0.6); a value already on the grid steps a full 0.5.
local function snapHalf(v, s)
	local k = v / 0.5
	if s > 0 then
		return (math.floor(k + 1e-6) + 1) * 0.5
	else
		return (math.ceil(k - 1e-6) - 1) * 0.5
	end
end

-- Apply one nudge to a single element. axis = "x"/"y"; dir = +1 (right/down) or
-- -1 (left/up). Only the offset (or anchor) of the pressed axis changes; scales
-- and the other axis are left untouched.
local function nudgeInstance(inst, axis, dir)
	if isA(inst, "UIPadding") then
		-- Each direction grows the padding on the OPPOSITE edge (pressing a way
		-- pushes the content that way): up->Bottom, down->Top, left->Right,
		-- right->Left. Invert subtracts instead of adds.
		local delta = nudgeInvert and -1 or 1
		local prop
		if axis == "x" then
			prop = (dir > 0) and "PaddingLeft" or "PaddingRight"
		else
			prop = (dir > 0) and "PaddingTop" or "PaddingBottom"
		end
		local cur = inst[prop]
		inst[prop] = UDim.new(cur.Scale, cur.Offset + delta)
		return
	end
	if nudgeMode == "Position" then
		local p = inst.Position
		if axis == "x" then
			inst.Position = UDim2.new(p.X.Scale, p.X.Offset + dir, p.Y.Scale, p.Y.Offset)
		else
			inst.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset + dir)
		end
	elseif nudgeMode == "Size" then
		-- Grow when nudging away from the anchor, shrink when nudging toward it
		-- (centered anchor: + direction grows). A purely scale-based axis (offset
		-- == 0) nudges by 0.01 scale; otherwise by 1 px. Uniform nudges both axes.
		local a = inst.AnchorPoint
		local sz = inst.Size
		local anc = (axis == "x") and a.X or a.Y
		local awayDir = (anc < 0.5) and 1 or ((anc > 0.5) and -1 or 0)
		local sign = (awayDir ~= 0) and (dir * awayDir) or dir
		local function bump(u)
			if u.Offset == 0 then
				local s = u.Scale + sign * 0.01
				return UDim.new(math.floor(s * 10000 + 0.5) / 10000, 0)
			end
			return UDim.new(u.Scale, u.Offset + sign)
		end
		local nx, ny = sz.X, sz.Y
		if nudgeUniform then
			nx, ny = bump(sz.X), bump(sz.Y)
		elseif axis == "x" then
			nx = bump(sz.X)
		else
			ny = bump(sz.Y)
		end
		inst.Size = UDim2.new(nx.Scale, nx.Offset, ny.Scale, ny.Offset)
	elseif nudgeMode == "Origin" then
		-- Move the AnchorPoint on a 0.5 grid, clamped to [0, 1].
		local a = inst.AnchorPoint
		if axis == "x" then
			inst.AnchorPoint = Vector2.new(math.clamp(snapHalf(a.X, dir), 0, 1), a.Y)
		else
			inst.AnchorPoint = Vector2.new(a.X, math.clamp(snapHalf(a.Y, dir), 0, 1))
		end
	end
end

local function stillValid(inst)
	local ok, res = pcall(function() return inst.Parent ~= nil and inst:IsDescendantOf(game) end)
	return ok and res
end

-- Elements the nudge tool can act on: UI elements and UIPadding modifiers.
local function isNudgeable(inst)
	return isA(inst, "GuiObject") or isA(inst, "UIPadding")
end

local function selectedNudgeables()
	local out = {}
	for _, inst in ipairs(currentSelection()) do
		if isNudgeable(inst) then table.insert(out, inst) end
	end
	return out
end

-- Targets for a nudge: the live selection if any, otherwise the remembered target
-- (so nudging keeps working while a cursor-hover has the element deselected).
local function resolveNudgeTargets()
	local live = selectedNudgeables()
	if #live > 0 then return live end
	local kept = {}
	for _, inst in ipairs(nudgeTarget) do
		if isNudgeable(inst) and stillValid(inst) then table.insert(kept, inst) end
	end
	return kept
end

-- The active target's family decides the page controls: a UIPadding target shows
-- the "Invert" button, everything else shows the Position/Size/Origin column.
local function nudgeIsPadding()
	local t = resolveNudgeTargets()
	return #t > 0 and isA(t[#t], "UIPadding")
end

updateNudgeStatus = function()
	if not nudgeStatusLabel then return end
	local t = resolveNudgeTargets()
	if #t == 0 then
		nudgeStatusLabel.Text = ""
	elseif #t == 1 then
		nudgeStatusLabel.Text = "Nudging: " .. safeName(t[1]) .. " (" .. safeClass(t[1]) .. ")"
	else
		nudgeStatusLabel.Text = "Nudging: " .. #t .. " elements"
	end
end

updateNudgePageMode = function()
	if not nudgeModeHolder or not nudgeInvertBtn then return end
	local pad = nudgeIsPadding()
	nudgeModeHolder.Visible = not pad
	nudgeInvertBtn.Visible = pad
	if nudgeRelayout then nudgeRelayout() end
end

-- Keep the "Nudging:" label just below whichever left block is showing (the mode
-- column is one row taller in Size mode because of the Uniform sub-button) and
-- below the D-Pad, so nothing overlaps. Mirrors the button metrics (24 h, 4 gap).
nudgeRelayout = function()
	if not nudgeStatusLabel then return end
	local blockBottom
	if nudgeInvertBtn and nudgeInvertBtn.Visible then
		blockBottom = 12 + 24 -- single Invert button
	else
		local n = (nudgeMode == "Size") and 4 or 3
		blockBottom = 12 + (n * 24 + (n - 1) * 4)
	end
	local y = math.max(blockBottom, 12 + 88) + 10 -- 12 + 88 = D-Pad bottom
	nudgeStatusLabel.Position = UDim2.new(0, 12, 0, y)
end

local function nudgeUIRefresh()
	updateNudgeStatus()
	updateNudgePageMode()
end

-- Nudge every target (one undo step). While the cursor is over the D-Pad the
-- element is already deselected, so it's mutated through its stored reference.
local function doNudge(axis, dir)
	local guis = resolveNudgeTargets()
	if #guis == 0 then
		warn("[ExplorerFunctions] Select a UI element to nudge.")
		return
	end
	recorded("Nudge " .. (nudgeIsPadding() and "Padding" or nudgeMode), function()
		for _, inst in ipairs(guis) do
			pcall(function() nudgeInstance(inst, axis, dir) end)
		end
	end)
	nudgeTarget = guis -- keep armed for subsequent presses
	nudgeUIRefresh()
end

-- D-Pad hover: while the cursor is over the pad, hide Studio's selection outline
-- by arming the current selection as the nudge target and deselecting it; restore
-- the selection when the cursor leaves.
local nudgeRestore = {} -- elements to re-select on hover-out

local function beginNudgeHover()
	local sel = selectedNudgeables()
	if #sel > 0 then
		nudgeTarget = sel
		nudgeRestore = sel
		pcall(function() Selection:Set({}) end)
	end
	nudgeUIRefresh()
end

local function endNudgeHover()
	if #nudgeRestore > 0 then
		local kept = {}
		for _, inst in ipairs(nudgeRestore) do
			if stillValid(inst) then table.insert(kept, inst) end
		end
		nudgeRestore = {}
		if #kept > 0 then pcall(function() Selection:Set(kept) end) end
	end
	nudgeUIRefresh()
end

--============================================================
-- Tools registry
--   Each tab is a tool. buildTopbar() returns { row1, row2 } of button specs;
--   renderPage(parent) draws the tool's page. Add tools here in the future.
--============================================================

local TOOL_DEFS = {}
local DEFAULT_ORDER = { "ui_editor" }

TOOL_DEFS.ui_editor = {
	id = "ui_editor",
	name = "UI Editor",
	buildTopbar = function()
		return {
			{ { text = pasteLabel(), cb = onPaste }, { text = "Swap", cb = onSwap }, { text = "LayoutOrder", cb = onLayoutOrder } },
			{ { text = "Copy", cb = onCopy }, { text = "Copy Style", cb = onCopyStyle }, { text = "Copy Pos", cb = onCopyPos } },
		}
	end,
	-- Page body: nudge controls. Left = mode column (Position / Size / Origin,
	-- one active at a time); right = a D-Pad that nudges the selection.
	renderPage = function(parent)
		-- Mode column (top-left)
		local modeHolder = Instance.new("Frame")
		modeHolder.BackgroundTransparency = 1
		modeHolder.Position = UDim2.new(0, 12, 0, 12)
		modeHolder.Size = UDim2.new(0, 96, 0, 0)
		modeHolder.AutomaticSize = Enum.AutomaticSize.Y
		modeHolder.Parent = parent
		do
			local layout = Instance.new("UIListLayout")
			layout.FillDirection = Enum.FillDirection.Vertical
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Padding = UDim.new(0, 4)
			layout.Parent = modeHolder
		end

		local modeBtns = {}
		local uniformBtn
		local function repaintModes()
			for mode, b in pairs(modeBtns) do
				b.BackgroundColor3 = (nudgeMode == mode) and THEME.rowSel or THEME.btn
			end
			if uniformBtn then uniformBtn.Visible = (nudgeMode == "Size") end
			if nudgeRelayout then nudgeRelayout() end
		end
		local function addMode(text, order)
			local b = createBtnVisual(modeHolder, text)
			b.AutomaticSize = Enum.AutomaticSize.None
			b.Size = UDim2.new(1, 0, 0, 24)
			b.LayoutOrder = order
			modeBtns[text] = b
			b.MouseEnter:Connect(function()
				if nudgeMode ~= text then b.BackgroundColor3 = THEME.btnHover end
			end)
			b.MouseLeave:Connect(repaintModes)
			b.MouseButton1Click:Connect(function()
				nudgeMode = text
				repaintModes()
			end)
		end
		addMode("Position", 1)
		addMode("Size", 2)
		addMode("Origin", 4)

		-- "Uniform" sub-button, sits below Size and only shows while Size mode is
		-- active; when on, nudges apply to both dimensions at once.
		uniformBtn = createBtnVisual(modeHolder, "Uniform")
		uniformBtn.AutomaticSize = Enum.AutomaticSize.None
		uniformBtn.Size = UDim2.new(1, 0, 0, 24)
		uniformBtn.LayoutOrder = 3
		local function paintUniform()
			uniformBtn.BackgroundColor3 = nudgeUniform and THEME.rowSel or THEME.btn
		end
		uniformBtn.MouseEnter:Connect(function()
			if not nudgeUniform then uniformBtn.BackgroundColor3 = THEME.btnHover end
		end)
		uniformBtn.MouseLeave:Connect(paintUniform)
		uniformBtn.MouseButton1Click:Connect(function()
			nudgeUniform = not nudgeUniform
			paintUniform()
		end)
		paintUniform()
		repaintModes()
		nudgeModeHolder = modeHolder

		-- Invert toggle (shown in place of the mode column when a UIPadding is the
		-- target): flips padding nudges from +1 px to -1 px.
		nudgeInvertBtn = createBtnVisual(parent, "Invert")
		nudgeInvertBtn.AutomaticSize = Enum.AutomaticSize.None
		nudgeInvertBtn.Position = UDim2.new(0, 12, 0, 12)
		nudgeInvertBtn.Size = UDim2.new(0, 96, 0, 24)
		nudgeInvertBtn.Visible = false
		local function paintInvert()
			nudgeInvertBtn.BackgroundColor3 = nudgeInvert and THEME.rowSel or THEME.btn
		end
		nudgeInvertBtn.MouseEnter:Connect(function()
			if not nudgeInvert then nudgeInvertBtn.BackgroundColor3 = THEME.btnHover end
		end)
		nudgeInvertBtn.MouseLeave:Connect(paintInvert)
		nudgeInvertBtn.MouseButton1Click:Connect(function()
			nudgeInvert = not nudgeInvert
			paintInvert()
		end)
		paintInvert()

		-- D-Pad (top-right)
		local pad = Instance.new("Frame")
		pad.BackgroundTransparency = 1
		pad.AnchorPoint = Vector2.new(1, 0)
		pad.Position = UDim2.new(1, -12, 0, 12)
		pad.Size = UDim2.new(0, 88, 0, 88)
		pad.Parent = parent

		local function addArrow(text, x, y, axis, dir)
			local b = createBtnVisual(pad, text)
			b.AutomaticSize = Enum.AutomaticSize.None
			b.Size = UDim2.new(0, 28, 0, 28)
			b.Position = UDim2.new(0, x, 0, y)
			b.TextSize = 16
			local padChild = b:FindFirstChildOfClass("UIPadding")
			if padChild then padChild:Destroy() end -- let the glyph center in the square
			b.MouseEnter:Connect(function() b.BackgroundColor3 = THEME.btnHover end)
			b.MouseLeave:Connect(function() b.BackgroundColor3 = THEME.btn end)
			b.MouseButton1Click:Connect(function()
				local ok, err = pcall(function() doNudge(axis, dir) end)
				if not ok then warn("[ExplorerFunctions] " .. tostring(err)) end
			end)
		end
		addArrow("↑", 30, 0, "y", -1)
		addArrow("←", 0, 30, "x", -1)
		addArrow("→", 60, 30, "x", 1)
		addArrow("↓", 30, 60, "y", 1)

		-- Hovering anywhere over the D-Pad hides Studio's selection outline (arms +
		-- deselects the current selection); leaving re-selects it. Handlers live on
		-- the container so moving between the arrow buttons doesn't re-trigger.
		pad.Active = true
		pad.MouseEnter:Connect(beginNudgeHover)
		pad.MouseLeave:Connect(endNudgeHover)

		nudgeStatusLabel = Instance.new("TextLabel")
		nudgeStatusLabel.BackgroundTransparency = 1
		nudgeStatusLabel.Position = UDim2.new(0, 12, 0, 108)
		nudgeStatusLabel.Size = UDim2.new(1, -24, 0, 40)
		nudgeStatusLabel.Font = Enum.Font.Gotham
		nudgeStatusLabel.TextSize = 12
		nudgeStatusLabel.TextColor3 = THEME.textDim
		nudgeStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
		nudgeStatusLabel.TextYAlignment = Enum.TextYAlignment.Top
		nudgeStatusLabel.TextWrapped = true
		nudgeStatusLabel.Text = ""
		nudgeStatusLabel.Parent = parent
		nudgeUIRefresh()
	end,
}

local function activeTool()
	return TOOL_DEFS[toolOrder[activeIndex]]
end

--============================================================
-- Persistence (tab order + active tab, per experience)
--============================================================

local function dataKey()
	return DATA_KEY_BASE .. "_" .. tostring(game.GameId)
end

save = function()
	pcall(function()
		plugin:SetSetting(dataKey(), HttpService:JSONEncode({ active = activeIndex, order = toolOrder }))
	end)
end

-- Build a valid tool order from a (possibly stale) saved list: keep known ids in
-- their saved order, then append any tools that aren't in it yet.
local function rebuildOrder(saved)
	local seen, order = {}, {}
	if type(saved) == "table" then
		for _, id in ipairs(saved) do
			if TOOL_DEFS[id] and not seen[id] then
				table.insert(order, id)
				seen[id] = true
			end
		end
	end
	for _, id in ipairs(DEFAULT_ORDER) do
		if TOOL_DEFS[id] and not seen[id] then
			table.insert(order, id)
			seen[id] = true
		end
	end
	return order
end

local function load()
	toolOrder = rebuildOrder(nil)
	activeIndex = 1
	local raw = plugin:GetSetting(dataKey())
	if not raw then return end
	local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or type(data) ~= "table" then return end
	toolOrder = rebuildOrder(data.order)
	activeIndex = tonumber(data.active) or 1
	if activeIndex < 1 or activeIndex > #toolOrder then activeIndex = 1 end
end

--============================================================
-- Refresh
--============================================================

refreshTopbar = function()
	clearChildren(actionRow)
	clearChildren(actionRow2)
	local tool = activeTool()
	if not tool then return end
	local rows = tool.buildTopbar()
	for _, spec in ipairs(rows[1] or {}) do
		makeButton(actionRow, spec.text, spec.cb)
	end
	for _, spec in ipairs(rows[2] or {}) do
		makeButton(actionRow2, spec.text, spec.cb)
	end
end

refreshTabs = function()
	clearChildren(tabRow)
	for i, id in ipairs(toolOrder) do
		local def = TOOL_DEFS[id]
		local isActive = (i == activeIndex)
		if isActive and i > 1 then
			makeArrow(tabRow, "<", i * 10 - 1, function()
				toolOrder[i], toolOrder[i - 1] = toolOrder[i - 1], toolOrder[i]
				activeIndex = i - 1
				save()
				refreshAll()
			end)
		end
		makeTab(tabRow, def.name, i, isActive)
		if isActive and i < #toolOrder then
			makeArrow(tabRow, ">", i * 10 + 1, function()
				toolOrder[i], toolOrder[i + 1] = toolOrder[i + 1], toolOrder[i]
				activeIndex = i + 1
				save()
				refreshAll()
			end)
		end
	end
end

refreshPage = function()
	clearChildren(pageArea)
	local tool = activeTool()
	if tool and tool.renderPage then
		tool.renderPage(pageArea)
	end
end

refreshAll = function()
	refreshTabs()
	refreshTopbar()
	refreshPage()
end

--============================================================
-- Toolbar + toggle + selection watcher
--============================================================

local toolbar = plugin:CreateToolbar("Explorer Functions")
local toggleButton = toolbar:CreateButton("ExplorerFunctionsToggle", "Show / hide the Explorer Functions panel", "", "Explorer Fn")
toggleButton.ClickableWhenViewportHidden = true

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggleButton:SetActive(widget.Enabled)
	if widget.Enabled then refreshAll() end
end)

-- While a menu is open, keep it pointed at the latest Explorer selection.
Selection.SelectionChanged:Connect(function()
	if not widget.Enabled then return end
	if copyOverlay.Visible then showCopyMenu() end
	if swapOverlay.Visible then showSwapMenu() end
	if loOverlay.Visible then showLayoutOrderMenu() end
	if updateNudgeStatus then updateNudgeStatus() end
	if updateNudgePageMode then updateNudgePageMode() end
end)

--============================================================
-- Init
--============================================================

load()
if #toolOrder == 0 then
	toolOrder = rebuildOrder(nil)
end
refreshAll()
