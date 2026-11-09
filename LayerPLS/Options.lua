-- The LayerPLS page under Escape > Options > AddOns.

local ADDON, ns = ...

local CATEGORY_NAME = "LayerPLS"
local VARIABLE_PREFIX = "LayerPLS_"

local category

--------------------------------------------------------------------------------
-- Whisper text row. The options panel has no text box control of its own.
--------------------------------------------------------------------------------

LayerPLSTextControlMixin = CreateFromMixins(SettingsControlMixin)

function LayerPLSTextControlMixin:OnLoad()
    SettingsControlMixin.OnLoad(self)

    local box = CreateFrame("EditBox", nil, self, "InputBoxTemplate")
    box:SetSize(250, 22)
    box:SetPoint("LEFT", self, "CENTER", -75, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(255)
    box:SetScript("OnEnterPressed", function(editBox)
        editBox:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(editBox)
        editBox:SetText(self:GetSetting():GetValue())
        editBox:ClearFocus()
    end)
    box:HookScript("OnEditFocusLost", function()
        self:Commit()
    end)
    self.EditBox = box
end

function LayerPLSTextControlMixin:Init(initializer)
    SettingsControlMixin.Init(self, initializer)
    self.EditBox:SetText(self:GetSetting():GetValue())
    self:EvaluateState()
end

function LayerPLSTextControlMixin:SetValue(value)
    if not self.EditBox:HasFocus() then
        self.EditBox:SetText(value)
    end
end

function LayerPLSTextControlMixin:Commit()
    local setting = self.data and self.data.setting
    if not setting then
        return
    end
    local text = strtrim(self.EditBox:GetText())
    if text == "" then
        self.EditBox:SetText(setting:GetValue())
    elseif text ~= setting:GetValue() then
        setting:SetValue(text)
    end
end

function LayerPLSTextControlMixin:Release()
    self.EditBox:ClearFocus()
    SettingsControlMixin.Release(self)
end

--------------------------------------------------------------------------------
-- Page
--------------------------------------------------------------------------------

local function SnapToStep(value, step)
    return math.floor(value / step + 0.5) * step
end

local function AddProxy(key, varType, name, onChange, step)
    return Settings.RegisterProxySetting(
        category,
        VARIABLE_PREFIX .. key,
        varType,
        name,
        ns.DEFAULTS[key],
        function()
            return ns.db[key]
        end,
        function(value)
            ns.db[key] = step and SnapToStep(value, step) or value
            if onChange then
                onChange(value)
            end
        end
    )
end

local function AddSlider(key, name, tooltip, minimum, maximum, step, format, onChange)
    local setting = AddProxy(key, Settings.VarType.Number, name, onChange, step)
    local options = Settings.CreateSliderOptions(minimum, maximum, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return format:format(SnapToStep(value, step))
    end)
    Settings.CreateSlider(category, setting, options, tooltip)
end

local function GetSkinOptions()
    local container = Settings.CreateControlTextContainer()
    for _, id in ipairs(ns.SkinOrder) do
        local skin = ns.Skins[id]
        container:Add(id, skin.name, skin.description)
    end
    return container:GetData()
end

local function AddSection(layout, title)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
end

local function AddButton(layout, name, buttonText, tooltip, onClick)
    layout:AddInitializer(CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, true))
end

local function AddAppearanceSection(layout)
    AddSection(layout, "Appearance")

    local skin = AddProxy("skin", Settings.VarType.String, "Skin", ns.ApplyAppearance)
    Settings.CreateDropdown(category, skin, GetSkinOptions, "How the LayerPLS window looks.")

    local compact = AddProxy("compact", Settings.VarType.Boolean, "Small Button Mode", ns.ApplyAppearance)
    Settings.CreateCheckbox(category, compact, "Shows one small icon per action instead of the full window. Hover an icon to see what it does.")

    local shown = Settings.RegisterProxySetting(
        category,
        VARIABLE_PREFIX .. "shown",
        Settings.VarType.Boolean,
        "Show Window",
        true,
        ns.IsWindowShown,
        ns.ApplyWindowShown
    )
    Settings.CreateCheckbox(category, shown, "Same as typing /lp.")

    AddButton(layout, "Window Position", "Reset", "Moves the window back to the top of the screen.", ns.ResetPosition)
end

local function AddWhisperSection(layout)
    AddSection(layout, "Whispers")

    local message = AddProxy("message", Settings.VarType.String, "Whisper Text")
    local data = Settings.CreateSettingInitializerData(message, nil, "What players receive. Press Enter to save.")
    local row = Settings.CreateSettingInitializer("LayerPLSTextControlTemplate", data)
    row:AddSearchTags(message:GetName())
    layout:AddInitializer(row)

    AddSlider("whisperDelay", "Time Between Whispers", "Slower is less likely to get you reported or throttled.", 1, 10, 0.5, "%.1f sec")
    AddSlider("askCooldown", "Ask Same Player Again After", "A player who was already asked is skipped for this long.", 1, 60, 1, "%d min")
    AddSlider("manualBatch", "Whispers Per Click If Blocked", "Only used if the game blocks automatic whispers.", 1, 10, 1, "%d")
end

local function AddSearchSection(layout)
    AddSection(layout, "Player Search")

    AddSlider("levelRange", "Level Range", "How many levels below and above you the level buttons cover.", 1, 20, 1, "%d", ns.ResetScans)
    AddSlider("whoTimeout", "/who Reply Timeout", "How long to wait before giving up on a /who.", 3, 15, 1, "%d sec")
end

local function AddDataSection(layout)
    AddSection(layout, "Data")

    AddButton(layout, "Players Already Asked", "Forget", "Lets LayerPLS whisper players it asked recently.", ns.ForgetAsked)
end

function ns.BuildOptions()
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory(CATEGORY_NAME)

    AddAppearanceSection(layout)
    AddWhisperSection(layout)
    AddSearchSection(layout)
    AddDataSection(layout)

    Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
    Settings.OpenToCategory(category:GetID())
end

-- Tells an open options page that a value changed from outside it.
function ns.NotifySetting(key)
    Settings.NotifyUpdate(VARIABLE_PREFIX .. key)
end
