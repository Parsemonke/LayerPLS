-- Window skins. Each skin builds its own frames, because Blizzard's templates
-- are fixed at creation. Built windows are kept and swapped.

local ADDON, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8x8"
local ICON_PATH = "Interface\\Icons\\"
local ICON_FALLBACK = ICON_PATH .. "INV_Misc_QuestionMark"
local ICON_TRIM = { 0.08, 0.92, 0.08, 0.92 }

local ICON_SIZE = 30

local TOOLTIP_GAP = 8

local CLICK_AFTER_DRAG_DELAY = 0.2

ns.Skins = {}
ns.SkinOrder = {}

local windows = {}
local current
local lastDragTime = 0
local warnedAboutSkin = false

--------------------------------------------------------------------------------
-- Shared helpers
--------------------------------------------------------------------------------

local function RegisterSkin(id, skin)
    ns.Skins[id] = skin
    ns.SkinOrder[#ns.SkinOrder + 1] = id
end

local function ResolveIcon(mode)
    for _, name in ipairs(ns.MODES[mode].icons) do
        local path = ICON_PATH .. name
        local fileID = GetFileIDFromPath(path)
        if fileID and fileID > 0 then
            return path
        end
    end
    return ICON_FALLBACK
end

local function ColorOf(mode)
    return unpack(ns.MODES[mode].color)
end

local function SavePosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint()
    ns.db.position = { point, relativePoint, x, y }
end

local function ApplyPosition(frame)
    frame:ClearAllPoints()
    local position = ns.db.position
    if position then
        frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

local function StartDrag(frame)
    frame:StartMoving()
end

local function StopDrag(frame)
    frame:StopMovingOrSizing()
    SavePosition(frame)
    lastDragTime = GetTime()
end

local function NewWindow(template, width, height, name)
    local frame = CreateFrame("Frame", name, UIParent, template)
    frame:SetSize(width, height)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:Hide()
    return { frame = frame, buttons = {} }
end

local function MakeShellDraggable(window)
    local frame = window.frame
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", StartDrag)
    frame:SetScript("OnDragStop", StopDrag)
end

local function Sentence(text)
    return (text:gsub("^%l", string.upper))
end

-- Beside the window rather than over it, on the side with more room.
local function AnchorTooltip(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    if frame:GetCenter() > UIParent:GetWidth() / 2 then
        GameTooltip:SetPoint("TOPRIGHT", frame, "TOPLEFT", -TOOLTIP_GAP, 0)
    else
        GameTooltip:SetPoint("TOPLEFT", frame, "TOPRIGHT", TOOLTIP_GAP, 0)
    end
end

local function ShowTooltip(button, state)
    AnchorTooltip(button:GetParent())
    GameTooltip_SetTitle(GameTooltip, state.title)
    GameTooltip_AddNormalLine(GameTooltip, state.description)
    if state.activity then
        GameTooltip_AddHighlightLine(GameTooltip, Sentence(state.activity))
    end
    if state.hint then
        local AddHint = state.available and GameTooltip_AddInstructionLine or GameTooltip_AddDisabledLine
        AddHint(GameTooltip, state.hint)
    end
    GameTooltip:Show()
end

local function PaintButton(button)
    local state = ns.GetButtonState(button.mode)
    button:Paint(state)
    if button.showsTooltip and button.hovered then
        ShowTooltip(button, state)
    end
end

local function AttachBehavior(button, window, mode, showsTooltip)
    button.mode = mode
    button.showsTooltip = showsTooltip
    window.buttons[mode] = button

    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function(self)
        if GetTime() - lastDragTime >= CLICK_AFTER_DRAG_DELAY then
            ns.HandleClick(self.mode)
        end
        -- A CheckButton toggles itself on click, whatever the click ended up doing.
        PaintButton(self)
    end)
    button:SetScript("OnDragStart", function()
        StartDrag(window.frame)
    end)
    button:SetScript("OnDragStop", function()
        StopDrag(window.frame)
    end)
    button:HookScript("OnEnter", function(self)
        self.hovered = true
        PaintButton(self)
    end)
    button:HookScript("OnLeave", function(self)
        self.hovered = false
        PaintButton(self)
        if self.showsTooltip then
            GameTooltip:Hide()
        end
    end)
end

local function LayoutIconRow(window, gap, inset)
    for index, mode in ipairs(ns.MODE_ORDER) do
        local x = inset + (index - 1) * (ICON_SIZE + gap)
        window.buttons[mode]:SetPoint("TOPLEFT", x, -inset)
    end
end

local function IconRowLength(gap, inset)
    local count = #ns.MODE_ORDER
    return inset * 2 + count * ICON_SIZE + (count - 1) * gap
end

local function AddCompactNote(window, text)
    text:SetPoint("TOP", window.frame, "BOTTOM", 0, -3)
    text:SetWidth(240)
    text:SetWordWrap(false)
    window.note = text
end

-- Level buttons carry their range on the icon, in the same colors as the window.
local function PaintLevelTag(button)
    if button.levelTag then
        button.levelTag:SetText((button.mode == "below" and "-" or "+") .. ns.db.levelRange)
    end
end

local function IsLevelMode(mode)
    return mode == "below" or mode == "above"
end

--------------------------------------------------------------------------------
-- Flat skin
--------------------------------------------------------------------------------

local FLAT_WIDTH, FLAT_PADDING, FLAT_GAP = 225, 3, 3
local FLAT_TOP_HEIGHT, FLAT_BOTTOM_HEIGHT = 46, 36
local FLAT_LINE_LENGTH, FLAT_LINE_HEIGHT, FLAT_LINE_INSET = 14, 2, 5
local FLAT_ICON_LINE_LENGTH, FLAT_ICON_LINE_INSET = 8, 2

local function GetFlatFont()
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    if media then
        for _, name in ipairs({ "Expressway", "PT Sans Narrow" }) do
            if media:IsValid("font", name) then
                return media:Fetch("font", name)
            end
        end
    end
    return STANDARD_TEXT_FONT
end

local function ApplyFlatBackdrop(target)
    target:SetBackdrop({
        bgFile = WHITE,
        edgeFile = WHITE,
        edgeSize = PixelUtil.GetPixelToUIUnitFactor() / target:GetEffectiveScale(),
    })
end

local function ApplyFlatWindowBackdrop(window)
    ApplyFlatBackdrop(window.frame)
    window.frame:SetBackdropColor(0.03, 0.03, 0.03, 0.85)
    window.frame:SetBackdropBorderColor(0, 0, 0, 1)
    for _, button in pairs(window.buttons) do
        ApplyFlatBackdrop(button)
    end
end

local function PaintFlatSurface(button, state)
    button:SetAlpha(state.available and 1 or 0.45)
    if state.available and (state.active or button.hovered) then
        button:SetBackdropBorderColor(ColorOf(button.mode))
        button:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
    else
        button:SetBackdropBorderColor(0, 0, 0, 1)
        button:SetBackdropColor(0.07, 0.07, 0.07, 0.95)
    end
end

local function PaintFlatProgress(button, state)
    if state.running then
        button.progress:SetWidth(math.max(1, (button:GetWidth() - 2) * state.progress))
        button.progress:Show()
    else
        button.progress:Hide()
    end
end

local function AddFlatProgress(button, mode)
    local r, g, b = ColorOf(mode)
    local progress = button:CreateTexture(nil, "OVERLAY")
    progress:SetColorTexture(r, g, b, 0.8)
    progress:SetHeight(FLAT_LINE_HEIGHT)
    progress:SetPoint("BOTTOMLEFT", 1, 1)
    progress:Hide()
    button.progress = progress
end

local function AddFlatLine(button, mode, length, inset)
    local r, g, b = ColorOf(mode)
    local line = button:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(r, g, b, 1)
    line:SetSize(length, FLAT_LINE_HEIGHT)
    line:SetPoint("TOPLEFT", inset, -inset)
end

local function CreateFlatText(button, fontPath, size, yOffset, r, g, b)
    local text = button:CreateFontString(nil, "OVERLAY")
    text:SetFont(fontPath, size, "")
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    text:SetTextColor(r, g, b)
    text:SetPoint("CENTER", 0, yOffset)
    text:SetWidth(button:GetWidth() - 8)
    text:SetWordWrap(false)
    return text
end

local function PaintFlatFull(button, state)
    button.label:SetText(state.label)
    button.sub:SetText(state.status)
    PaintFlatSurface(button, state)
    PaintFlatProgress(button, state)
end

local function CreateFlatFullButton(window, mode, width, height, labelSize, subSize)
    local button = CreateFrame("Button", nil, window.frame, "BackdropTemplate")
    button:SetSize(width, height)

    local fontPath = GetFlatFont()
    local spread = math.floor(height / 5)
    button.label = CreateFlatText(button, fontPath, labelSize, spread, 1, 1, 1)
    button.sub = CreateFlatText(button, fontPath, subSize, -spread, 0.62, 0.62, 0.62)
    AddFlatLine(button, mode, FLAT_LINE_LENGTH, FLAT_LINE_INSET)
    AddFlatProgress(button, mode)

    button.Paint = PaintFlatFull
    AttachBehavior(button, window, mode, false)
    return button
end

local function BuildFlatFull()
    local height = FLAT_PADDING * 2 + FLAT_GAP * 2 + FLAT_TOP_HEIGHT * 2 + FLAT_BOTTOM_HEIGHT
    local window = NewWindow("BackdropTemplate", FLAT_WIDTH, height)
    MakeShellDraggable(window)

    local innerWidth = FLAT_WIDTH - FLAT_PADDING * 2
    local halfWidth = (innerWidth - FLAT_GAP) / 2

    CreateFlatFullButton(window, "all", innerWidth, FLAT_TOP_HEIGHT, 15, 10)
        :SetPoint("TOPLEFT", FLAT_PADDING, -FLAT_PADDING)
    CreateFlatFullButton(window, "nearby", innerWidth, FLAT_TOP_HEIGHT, 15, 10)
        :SetPoint("TOPLEFT", FLAT_PADDING, -(FLAT_PADDING + FLAT_TOP_HEIGHT + FLAT_GAP))
    CreateFlatFullButton(window, "below", halfWidth, FLAT_BOTTOM_HEIGHT, 12, 9)
        :SetPoint("BOTTOMLEFT", FLAT_PADDING, FLAT_PADDING)
    CreateFlatFullButton(window, "above", halfWidth, FLAT_BOTTOM_HEIGHT, 12, 9)
        :SetPoint("BOTTOMRIGHT", -FLAT_PADDING, FLAT_PADDING)

    window.OnScaleChanged = ApplyFlatWindowBackdrop
    ApplyFlatWindowBackdrop(window)
    return window
end

local function PaintFlatIcon(button, state)
    PaintFlatSurface(button, state)
    PaintFlatProgress(button, state)
    PaintLevelTag(button)
    button.icon:SetDesaturated(not state.available)
    button.badge:SetText(state.badge or "")
end

local function CreateFlatIconButton(window, mode, fontPath)
    local button = CreateFrame("Button", nil, window.frame, "BackdropTemplate")
    button:SetSize(ICON_SIZE, ICON_SIZE)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ResolveIcon(mode))
    icon:SetTexCoord(unpack(ICON_TRIM))
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetSize(ICON_SIZE - 2, ICON_SIZE - 2)
    button.icon = icon

    local badge = button:CreateFontString(nil, "OVERLAY")
    badge:SetFont(fontPath, 11, "OUTLINE")
    badge:SetPoint("CENTER")
    button.badge = badge

    if IsLevelMode(mode) then
        local tag = button:CreateFontString(nil, "OVERLAY")
        tag:SetFont(fontPath, 10, "OUTLINE")
        tag:SetTextColor(ColorOf(mode))
        tag:SetPoint("BOTTOMRIGHT", -1, 2)
        button.levelTag = tag
    end

    AddFlatLine(button, mode, FLAT_ICON_LINE_LENGTH, FLAT_ICON_LINE_INSET)
    AddFlatProgress(button, mode)

    button.Paint = PaintFlatIcon
    AttachBehavior(button, window, mode, true)
end

local function BuildFlatCompact()
    local width = IconRowLength(FLAT_GAP, FLAT_PADDING)
    local window = NewWindow("BackdropTemplate", width, ICON_SIZE + FLAT_PADDING * 2)
    MakeShellDraggable(window)

    local fontPath = GetFlatFont()
    for _, mode in ipairs(ns.MODE_ORDER) do
        CreateFlatIconButton(window, mode, fontPath)
    end
    LayoutIconRow(window, FLAT_GAP, FLAT_PADDING)

    local note = window.frame:CreateFontString(nil, "OVERLAY")
    note:SetFont(fontPath, 10, "OUTLINE")
    AddCompactNote(window, note)

    window.OnScaleChanged = ApplyFlatWindowBackdrop
    ApplyFlatWindowBackdrop(window)
    return window
end

RegisterSkin("flat", {
    name = "Flat",
    description = "Dark and thin-bordered, in the style of ElvUI and EllesmereUI.",
    BuildFull = BuildFlatFull,
    BuildCompact = BuildFlatCompact,
})

--------------------------------------------------------------------------------
-- WoW Forever skin: Blizzard's own templates and art
--------------------------------------------------------------------------------

local NATIVE_WINDOW_NAME = "LayerPLSWindow"
local NATIVE_ICON_NAME = "LayerPLSActionButton"
local NATIVE_PORTRAIT = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Portrait"

local NATIVE_WIDTH = 290
local NATIVE_PADDING = 8
local NATIVE_BIG_HEIGHT, NATIVE_SMALL_HEIGHT, NATIVE_ROW_GAP, NATIVE_COLUMN_GAP = 30, 26, 3, 4
local NATIVE_TEXT_MARGIN = 24
local NATIVE_ICON_GAP = 5

-- Where ButtonFrameTemplate puts its inset once the button bar is hidden.
local NATIVE_INSET_LEFT, NATIVE_INSET_RIGHT, NATIVE_INSET_TOP, NATIVE_INSET_BOTTOM = 4, 6, 60, 4

-- The strip right of the portrait, between the title bar and the inset.
local NATIVE_HEADER_LEFT, NATIVE_HEADER_RIGHT = 58, 24
local NATIVE_HEADER_WIDTH = NATIVE_WIDTH - NATIVE_HEADER_LEFT - NATIVE_HEADER_RIGHT
local NATIVE_HEADER_X = NATIVE_HEADER_LEFT + NATIVE_HEADER_WIDTH / 2
local NATIVE_HEADER_Y, NATIVE_ZONE_Y, NATIVE_STATUS_Y = -42, -35, -50
local NATIVE_PROGRESS_WIDTH = 180

local function PlayClickSound()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

local function NativeLabel(state)
    if not state.detail then
        return state.label
    end
    local detail = state.available and GREEN_FONT_COLOR:WrapTextInColorCode(state.detail) or state.detail
    return state.label .. " (" .. detail .. ")"
end

-- A long subzone drops to the game's smaller button font before it gets cut off.
local function FitNativeText(button, label)
    button.measure:SetText(label)
    local small = button.measure:GetStringWidth() > button:GetFontString():GetWidth()
    if small ~= button.usesSmallFont then
        button.usesSmallFont = small
        button:SetNormalFontObject(small and GameFontNormalSmall or GameFontNormal)
        button:SetHighlightFontObject(small and GameFontHighlightSmall or GameFontHighlight)
        button:SetDisabledFontObject(small and GameFontDisableSmall or GameFontDisable)
    end
end

local function PaintNativeFull(button, state)
    local label = NativeLabel(state)
    FitNativeText(button, label)
    button:SetText(label)
    button:SetEnabled(state.available)
    if state.active then
        button:LockHighlight()
    else
        button:UnlockHighlight()
    end
end

local function CreateNativeFullButton(window, mode, template, width, height, x, y)
    local button = CreateFrame("Button", nil, window.frame, template)
    button:SetSize(width, height)
    button:SetPoint("TOPLEFT", x, -y)

    -- These templates have no text region until the first SetText.
    button:SetText(mode)
    local text = button:GetFontString()
    text:SetWidth(width - NATIVE_TEXT_MARGIN)
    text:SetWordWrap(false)

    button.measure = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.measure:Hide()
    button.usesSmallFont = false

    button.Paint = PaintNativeFull
    AttachBehavior(button, window, mode, true)
    button:HookScript("OnClick", PlayClickSound)
end

local function PlaceInNativeHeader(region, y)
    region:SetPoint("CENTER", region:GetParent(), "TOPLEFT", NATIVE_HEADER_X, y)
end

local function CreateNativeHeaderText(window, template)
    local text = window.frame:CreateFontString(nil, "OVERLAY", template)
    text:SetWidth(NATIVE_HEADER_WIDTH)
    text:SetWordWrap(false)
    return text
end

-- The bar the game's Skills and Reputation panels use.
local function CreateNativeProgressBar(window)
    local bar = CreateFrame("Frame", nil, window.frame, "ColoredProgressBarTemplate")
    bar:SetWidth(NATIVE_PROGRESS_WIDTH)
    bar:SetFillTextureByColorType(ColoredProgressBarMixin.ColorType.Green)
    PlaceInNativeHeader(bar, NATIVE_HEADER_Y)
    bar:Hide()
    return bar
end

local function PaintNativeHeader(window)
    local message, progress = ns.GetActivity()

    window.zone:SetShown(progress == nil)
    window.status:SetShown(progress == nil and message ~= nil)
    window.progress:SetShown(progress ~= nil)

    if progress then
        window.progress:SetFillPercent(progress)
        window.progress:SetText(message)
    else
        window.zone:SetText(ns.GetZoneName())
        window.status:SetText(message and Sentence(message) or "")
        PlaceInNativeHeader(window.zone, message and NATIVE_ZONE_Y or NATIVE_HEADER_Y)
    end
end

-- ButtonFrameTemplate is what the game's Character and Friends windows are built on.
local function BuildNativeFull()
    local rowsHeight = NATIVE_BIG_HEIGHT * 2 + NATIVE_SMALL_HEIGHT + NATIVE_ROW_GAP * 2
    local height = NATIVE_INSET_TOP + NATIVE_PADDING * 2 + rowsHeight + NATIVE_INSET_BOTTOM
    local window = NewWindow("ButtonFrameTemplate", NATIVE_WIDTH, height, NATIVE_WINDOW_NAME)
    MakeShellDraggable(window)

    local frame = window.frame
    ButtonFrameTemplate_HideButtonBar(frame)
    frame:SetTitle("LayerPLS")
    frame:SetPortraitToAsset(NATIVE_PORTRAIT)
    frame.onCloseCallback = function()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        ns.SetWindowShown(false)
        return false
    end

    window.zone = CreateNativeHeaderText(window, "GameFontNormal")
    window.status = CreateNativeHeaderText(window, "GameFontHighlightSmall")
    PlaceInNativeHeader(window.status, NATIVE_STATUS_Y)
    window.progress = CreateNativeProgressBar(window)
    window.PaintHeader = PaintNativeHeader

    local left = NATIVE_INSET_LEFT + NATIVE_PADDING
    local top = NATIVE_INSET_TOP + NATIVE_PADDING
    local innerWidth = NATIVE_WIDTH - NATIVE_INSET_LEFT - NATIVE_INSET_RIGHT - NATIVE_PADDING * 2
    local halfWidth = (innerWidth - NATIVE_COLUMN_GAP) / 2
    local secondRow = top + NATIVE_BIG_HEIGHT + NATIVE_ROW_GAP
    local thirdRow = secondRow + NATIVE_BIG_HEIGHT + NATIVE_ROW_GAP

    CreateNativeFullButton(window, "all", "SharedButtonTemplate", innerWidth, NATIVE_BIG_HEIGHT, left, top)
    CreateNativeFullButton(window, "nearby", "SharedButtonTemplate", innerWidth, NATIVE_BIG_HEIGHT, left, secondRow)
    CreateNativeFullButton(window, "below", "SharedButtonSmallTemplate", halfWidth, NATIVE_SMALL_HEIGHT, left, thirdRow)
    CreateNativeFullButton(window, "above", "SharedButtonSmallTemplate", halfWidth, NATIVE_SMALL_HEIGHT,
        left + halfWidth + NATIVE_COLUMN_GAP, thirdRow)

    return window
end

local function PaintNativeIcon(button, state)
    PaintLevelTag(button)
    button:SetEnabled(state.available)
    button:SetChecked(state.active)
    button.icon:SetDesaturated(not state.available)
    button.Count:SetText(state.badge or "")
end

-- SmallActionButtonTemplate is what the game's stance and pet bars are built on.
local function CreateNativeIconButton(window, mode, index)
    local button = CreateFrame("CheckButton", NATIVE_ICON_NAME .. index, window.frame, "SmallActionButtonTemplate")
    button:SetMotionScriptsWhileDisabled(true)

    -- The game does the same for action buttons that hold no action, so pings pass through.
    button:ClearAttribute("ping-receiver")

    button.icon:SetTexture(ResolveIcon(mode))
    if IsLevelMode(mode) then
        button.levelTag = button.HotKey
        button.levelTag:SetTextColor(ColorOf(mode))
    end

    button.Paint = PaintNativeIcon
    AttachBehavior(button, window, mode, true)
    button:HookScript("OnClick", PlayClickSound)
end

local function BuildNativeCompact()
    local window = NewWindow(nil, IconRowLength(NATIVE_ICON_GAP, 0), ICON_SIZE)

    for index, mode in ipairs(ns.MODE_ORDER) do
        CreateNativeIconButton(window, mode, index)
    end
    LayoutIconRow(window, NATIVE_ICON_GAP, 0)

    AddCompactNote(window, window.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    return window
end

RegisterSkin("forever", {
    name = "WoW Forever",
    description = "Built like the game's own Character and Guild windows, with its own art.",
    templates = {
        "ButtonFrameTemplate",
        "SharedButtonTemplate",
        "SharedButtonSmallTemplate",
        "ColoredProgressBarTemplate",
        "SmallActionButtonTemplate",
    },
    BuildFull = BuildNativeFull,
    BuildCompact = BuildNativeCompact,
})

--------------------------------------------------------------------------------
-- Window management
--------------------------------------------------------------------------------

local function HasTemplates(skin)
    for _, template in ipairs(skin.templates or {}) do
        if not C_XMLUtil.GetTemplateInfo(template) then
            return false
        end
    end
    return true
end

-- A game patch that renames a Blizzard template should cost the skin, not the window.
local function ChosenSkinID()
    local skinID = ns.Skins[ns.db.skin] and ns.db.skin or ns.DEFAULTS.skin
    if HasTemplates(ns.Skins[skinID]) then
        return skinID
    end
    if not warnedAboutSkin then
        warnedAboutSkin = true
        ns.Print("the " .. ns.Skins[skinID].name .. " skin needs Blizzard parts this game version doesn't have, so the "
            .. ns.Skins[ns.DEFAULTS.skin].name .. " skin is used instead.")
    end
    return ns.DEFAULTS.skin
end

local function GetWindow()
    local skinID = ChosenSkinID()
    local key = skinID .. (ns.db.compact and ":compact" or ":full")
    if not windows[key] then
        local skin = ns.Skins[skinID]
        windows[key] = ns.db.compact and skin.BuildCompact() or skin.BuildFull()
    end
    return windows[key]
end

function ns.RefreshAll()
    if not current then
        return
    end
    for _, button in pairs(current.buttons) do
        PaintButton(button)
    end
    if current.note then
        current.note:SetText(ns.GetCompactMessage() or "")
    end
    if current.PaintHeader then
        current:PaintHeader()
    end
end

function ns.ApplyAppearance()
    local nextWindow = GetWindow()
    if current and current ~= nextWindow then
        current.frame:Hide()
    end
    current = nextWindow
    ApplyPosition(current.frame)
    current.frame:SetShown(not ns.db.hidden)
    ns.RefreshAll()
end

function ns.OnUIScaleChanged()
    for _, window in pairs(windows) do
        if window.OnScaleChanged then
            window:OnScaleChanged()
        end
    end
    ns.RefreshAll()
end

function ns.ResetPosition()
    ns.db.position = nil
    if current then
        ApplyPosition(current.frame)
    end
end

function ns.IsWindowShown()
    return not ns.db.hidden
end

function ns.ApplyWindowShown(shown)
    ns.db.hidden = not shown
    if current then
        current.frame:SetShown(shown)
    end
end

function ns.SetWindowShown(shown)
    ns.ApplyWindowShown(shown)
    ns.NotifySetting("shown")
end
