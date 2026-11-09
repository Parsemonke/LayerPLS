-- LayerPLS: one-click layer invite requests for World of Warcraft: Forever.
-- A button click runs /who for your zone, then whispers each player found.

local ADDON, ns = ...

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

ns.DEFAULTS = {
    skin         = "flat",
    compact      = false,
    message      = "hey, could you inv me for a layer swap pls? will leave right after, ty :)",
    whisperDelay = 1.5,  -- seconds between whispers
    askCooldown  = 60,   -- minutes before the same player can be asked again
    manualBatch  = 5,    -- whispers per click if timed whispers get blocked
    levelRange   = 5,    -- bottom buttons cover this many levels below/above you
    whoTimeout   = 6,    -- seconds to wait for a /who reply
}

local NOTE_DURATION = 6  -- seconds a status note stays on a button

local GREEN = { 0.25, 0.85, 0.35 }
local GREEN_TEXT = "|cff40d959%s|r"

ns.MODE_ORDER = { "all", "nearby", "below", "above" }

-- Icons are tried in order; the first one the client has is used.
ns.MODES = {
    all = {
        color = { 1.00, 1.00, 1.00 },
        icons = { "Achievement_GuildPerk_HaveGroup", "INV_SideTab_GroupFinder_c60" },
    },
    nearby = {
        color = GREEN,
        icons = { "Icon_TreasureMap", "Spell_Shadow_Teleport", "Ability_Tracking" },
    },
    below = {
        color = GREEN,
        icons = { "Misc_ArrowLeft" },
    },
    above = {
        color = { 0.90, 0.25, 0.25 },
        icons = { "Misc_ArrowRight" },
    },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local db
local notes = {}          -- mode -> { text, expires }
local latestNote
local scans = {}          -- mode -> { zone, level, brackets }; level ranges still to query
local who                 -- the /who we are waiting on
local run                 -- the whisper queue being sent
local blizzardWhoMuted = false

local function Print(text)
    print("|cff4fd1c5LayerPLS|r: " .. text)
end
ns.Print = Print

local function CurrentZone()
    return GetRealZoneText() or ""
end

-- The subzone you are in, or the zone name where there is no subzone.
local function CurrentSubzone()
    return GetMinimapZoneText() or ""
end

local function PlayerFullName()
    local name, surname = UnitNameUnmodified("player")
    if surname and surname ~= "" then
        return name .. " " .. surname
    end
    return name
end

local function FullRange(mode)
    local level = UnitLevel("player")
    if mode == "below" then
        return math.max(1, level - db.levelRange), level - 1
    elseif mode == "above" then
        return level + 1, math.min(GetMaxPlayerLevel(), level + db.levelRange)
    end
    return 1, GetMaxPlayerLevel()
end

local function ScanMatches(scan)
    return scan and scan.zone == CurrentZone() and scan.level == UnitLevel("player")
end

--------------------------------------------------------------------------------
-- Button state
--------------------------------------------------------------------------------

local function HasMoreToScan(mode)
    return ScanMatches(scans[mode]) and #scans[mode].brackets > 0
end

-- What a button is busy with or has just reported, or nil when it has nothing to say.
local function ActivityText(mode)
    if run and run.mode == mode then
        if run.manual then
            return (#run.queue - run.index + 1) .. " left"
        end
        return (run.index - 1) .. "/" .. #run.queue .. " sent"
    end
    if who and who.mode == mode then
        return "searching..."
    end
    local note = notes[mode]
    if note and GetTime() < note.expires then
        return note.text
    end
    notes[mode] = nil
    return nil
end

local function StatusText(mode)
    local activity = ActivityText(mode)
    if activity then
        return activity
    end

    local low, high = FullRange(mode)
    if low > high then
        return "no levels in range"
    end
    if HasMoreToScan(mode) then
        return "more - click again"
    end
    if mode == "all" then
        return CurrentZone()
    end
    if mode == "nearby" then
        return GREEN_TEXT:format(CurrentSubzone())
    end
    return "Lv " .. low .. "-" .. high
end

local function IdleLabel(mode)
    if mode == "all" then
        return "Everyone"
    elseif mode == "nearby" then
        return "Avoid Nearby"
    elseif mode == "below" then
        return "-" .. db.levelRange .. " Levels"
    end
    return "+" .. db.levelRange .. " Levels"
end

local function LabelText(mode)
    if run and run.mode == mode then
        if run.manual then
            return "Send next " .. math.min(db.manualBatch, #run.queue - run.index + 1)
        end
        return "Stop"
    end
    return IdleLabel(mode)
end

local function BadgeText(mode)
    if run and run.mode == mode then
        return #run.queue - run.index + 1
    end
    if who and who.mode == mode then
        return "..."
    end
    return nil
end

local function DescriptionText(mode)
    local zone = CurrentZone()
    if mode == "all" then
        return "Whisper everyone in " .. zone .. "."
    end
    if mode == "nearby" then
        local subzone = CurrentSubzone()
        local avoided = (subzone == zone or subzone == "") and "near you" or ("in " .. subzone)
        return "Whisper everyone in " .. zone .. " except players " .. avoided .. "."
    end
    local low, high = FullRange(mode)
    if low > high then
        return "There are no levels " .. (mode == "below" and "below" or "above") .. " yours."
    end
    local levels = low == high and low or (low .. "-" .. high)
    return "Whisper level " .. levels .. " players in " .. zone .. "."
end

-- What clicking would do when the button's name doesn't already say it.
local function HintText(mode, active)
    if run and run.mode == mode then
        if run.manual then
            return "Click to send the next " .. math.min(db.manualBatch, #run.queue - run.index + 1) .. "."
        end
        return "Click to stop."
    end
    if (run or who) and not active then
        return "Another request is running."
    end
    if not who and HasMoreToScan(mode) then
        return "Click to ask the next group of players."
    end
    return nil
end

function ns.GetButtonState(mode)
    local low, high = FullRange(mode)
    local running = run ~= nil and run.mode == mode
    local active = running or (who ~= nil and who.mode == mode)
    local subzone = CurrentSubzone()
    return {
        title = IdleLabel(mode),
        label = LabelText(mode),
        status = StatusText(mode),
        activity = ActivityText(mode),
        description = DescriptionText(mode),
        hint = HintText(mode, active),
        available = low <= high and (active or not (run or who)),
        active = active,
        running = running,
        progress = running and (run.index - 1) / #run.queue or 0,
        badge = BadgeText(mode),
        detail = (mode == "nearby" and not running and subzone ~= "") and subzone or nil,
    }
end

function ns.GetZoneName()
    return CurrentZone()
end

-- Icon-only layouts have no status line, so this is shown under the icons.
function ns.GetCompactMessage()
    if latestNote and GetTime() < latestNote.expires then
        return latestNote.text
    end
    latestNote = nil
    for _, mode in ipairs(ns.MODE_ORDER) do
        if HasMoreToScan(mode) then
            return IdleLabel(mode) .. ": more - click again"
        end
    end
    return nil
end

-- What is happening right now, for skins with one status area, and how far a run has got.
function ns.GetActivity()
    if run then
        return ActivityText(run.mode), (run.index - 1) / #run.queue
    end
    if who then
        return ActivityText(who.mode)
    end
    return ns.GetCompactMessage()
end

local function SetNote(mode, text)
    local note = { text = text, expires = GetTime() + NOTE_DURATION }
    notes[mode] = note
    latestNote = note
    ns.RefreshAll()
    C_Timer.After(NOTE_DURATION + 0.05, ns.RefreshAll)
end

--------------------------------------------------------------------------------
-- Whispering
--------------------------------------------------------------------------------

local RUN_EVENTS = {
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_SYSTEM",
    "ADDON_ACTION_BLOCKED",
    "ADDON_ACTION_FORBIDDEN",
}

local eventFrame = CreateFrame("Frame")

local function StopRun(reason)
    if not run then
        return
    end
    local finished = run
    if finished.ticker then
        finished.ticker:Cancel()
    end
    run = nil
    for _, event in ipairs(RUN_EVENTS) do
        eventFrame:UnregisterEvent(event)
    end
    if reason then
        SetNote(finished.mode, reason)
    else
        ns.RefreshAll()
    end
end

-- Sends one whisper. Returns false if the run had to stop.
local function SendNext()
    if C_ChatInfo.InChatMessagingLockdown() then
        StopRun("chat locked")
        return false
    end
    local target = run.queue[run.index]
    run.index = run.index + 1
    run.sent = run.sent + 1
    db.asked[target] = time()
    C_ChatInfo.SendChatMessage(db.message, "WHISPER", nil, target)
    return true
end

-- Falls back to sending from clicks if the client refuses timed whispers.
local function GoManual()
    if not run or run.manual then
        return
    end
    run.manual = true
    if run.ticker then
        run.ticker:Cancel()
        run.ticker = nil
    end
    if run.confirmed == 0 then
        for i = 1, run.index - 1 do
            db.asked[run.queue[i]] = nil
        end
        run.index = 1
        run.sent = 0
    end
    Print("the game blocked automatic whispers. Keep clicking the button to send them in small batches.")
    ns.RefreshAll()
end

local function FinishIfDone()
    if run and run.index > #run.queue then
        StopRun(run.sent .. " asked")
        return true
    end
    return false
end

local function OnTick()
    if not run then
        return
    end
    -- Whispers echo back within moments, so silence after three means they never left.
    if run.sent >= 3 and run.confirmed == 0 then
        GoManual()
        return
    end
    if SendNext() and not FinishIfDone() then
        ns.RefreshAll()
    end
end

local function StartRun(mode, queue)
    run = { mode = mode, queue = queue, index = 1, sent = 0, confirmed = 0 }
    for _, event in ipairs(RUN_EVENTS) do
        eventFrame:RegisterEvent(event)
    end
    run.ticker = C_Timer.NewTicker(db.whisperDelay, OnTick)
    OnTick()
end

local function SendManualBatch()
    for _ = 1, db.manualBatch do
        if not run or run.index > #run.queue or not SendNext() then
            break
        end
    end
    if not FinishIfDone() then
        ns.RefreshAll()
    end
end

--------------------------------------------------------------------------------
-- /who
--------------------------------------------------------------------------------

-- Blizzard's Who list opens the group finder on every WHO_LIST_UPDATE, so it is
-- taken off the event while our own query runs.
local function MuteBlizzardWho()
    if LFGWhoListFrame and not LFGWhoListFrame:IsShown() then
        LFGWhoListFrame:UnregisterEvent("WHO_LIST_UPDATE")
        blizzardWhoMuted = true
    end
end

local function ReleaseBlizzardWho()
    if blizzardWhoMuted then
        blizzardWhoMuted = false
        LFGWhoListFrame:RegisterEvent("WHO_LIST_UPDATE")
    end
    C_FriendList.SetWhoToUi(LFGWhoListFrame ~= nil and LFGWhoListFrame:IsShown())
end

local function NextBracket(mode, zone)
    local scan = scans[mode]
    if not ScanMatches(scan) or #scan.brackets == 0 then
        local low, high = FullRange(mode)
        if low > high then
            return nil
        end
        scan = { zone = zone, level = UnitLevel("player"), brackets = { { low, high } } }
        scans[mode] = scan
    end
    return table.remove(scan.brackets, 1)
end

local function StartWho(mode)
    if IsInGroup() then
        SetNote(mode, "leave group first")
        return
    end
    local zone = CurrentZone()
    local subzone = CurrentSubzone()
    if zone == "" or (mode == "nearby" and subzone == "") then
        SetNote(mode, "zone unknown")
        return
    end
    local bracket = NextBracket(mode, zone)
    if not bracket then
        return
    end

    local query = { mode = mode, zone = zone, low = bracket[1], high = bracket[2] }
    if mode == "nearby" then
        query.avoidArea = subzone
    end
    who = query
    MuteBlizzardWho()
    C_FriendList.SetWhoToUi(true)
    C_FriendList.SendWho(
        string.format('%s"%s" %d-%d', WHO_TAG_ZONE or "z-", zone, query.low, query.high),
        Enum.SocialWhoOrigin.Social
    )
    C_Timer.After(db.whoTimeout, function()
        if who == query then
            who = nil
            ReleaseBlizzardWho()
            if scans[mode] then
                table.insert(scans[mode].brackets, 1, bracket)
            end
            SetNote(mode, "no reply, retry")
        end
    end)
    ns.RefreshAll()
end

local function RecentlyAsked(name, now)
    local askedAt = db.asked[name]
    return askedAt and now - askedAt < db.askCooldown * 60
end

local function HandleWhoResults()
    local query = who
    who = nil
    -- Deferred: re-registering during this dispatch could still hand Blizzard this event.
    C_Timer.After(0, ReleaseBlizzardWho)

    local shown, total = C_FriendList.GetNumWhoResults()

    -- The server caps replies, so a full reply is split into two narrower level ranges.
    local cap = MAX_WHOS_FROM_SERVER or 50
    if (total > shown or shown >= cap) and query.low < query.high and scans[query.mode] then
        local mid = math.floor((query.low + query.high) / 2)
        local brackets = scans[query.mode].brackets
        table.insert(brackets, 1, { mid + 1, query.high })
        table.insert(brackets, 1, { query.low, mid })
    end

    local me = PlayerFullName()
    local now = time()
    local queue = {}
    local skippedNearby = 0
    for i = 1, shown do
        -- On Forever, info.area is the player's subzone, never the parent zone.
        -- The zone itself is already enforced by the /who filter.
        local info = C_FriendList.GetWhoInfo(i)
        if info
            and info.level >= query.low and info.level <= query.high
            and info.fullName ~= me
            and not RecentlyAsked(info.fullName, now)
        then
            if query.avoidArea and info.area == query.avoidArea then
                skippedNearby = skippedNearby + 1
            else
                queue[#queue + 1] = info.fullName
            end
        end
    end

    if #queue == 0 then
        local note = "nobody new"
        if shown == 0 then
            note = "nobody found"
        elseif skippedNearby > 0 then
            note = "all nearby"
        end
        SetNote(query.mode, note)
        return
    end
    StartRun(query.mode, queue)
end

--------------------------------------------------------------------------------
-- Actions used by the window and the options page
--------------------------------------------------------------------------------

function ns.HandleClick(mode)
    if run then
        if run.mode == mode then
            if run.manual then
                SendManualBatch()
            else
                StopRun("stopped")
            end
        end
        return
    end
    if not who then
        StartWho(mode)
    end
end

function ns.ResetScans()
    wipe(scans)
    ns.RefreshAll()
end

function ns.ForgetAsked()
    wipe(db.asked)
    ns.ResetScans()
    Print("cleared the list of players already asked.")
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON then
        return
    end
    eventFrame:UnregisterEvent("ADDON_LOADED")

    LayerPLSDB = LayerPLSDB or {}
    db = LayerPLSDB
    ns.db = db
    for key, value in pairs(ns.DEFAULTS) do
        if db[key] == nil then
            db[key] = value
        end
    end
    db.asked = db.asked or {}

    local now = time()
    for player, askedAt in pairs(db.asked) do
        if now - askedAt >= db.askCooldown * 60 then
            db.asked[player] = nil
        end
    end

    ns.BuildOptions()
end

function handlers.PLAYER_LOGIN()
    ns.ApplyAppearance()
end

function handlers.PLAYER_ENTERING_WORLD()
    ns.RefreshAll()
end

function handlers.PLAYER_LEVEL_UP()
    C_Timer.After(1, ns.RefreshAll)
end

function handlers.UI_SCALE_CHANGED()
    ns.OnUIScaleChanged()
end

function handlers.ZONE_CHANGED()
    ns.RefreshAll()
end

handlers.ZONE_CHANGED_INDOORS = handlers.ZONE_CHANGED

function handlers.ZONE_CHANGED_NEW_AREA()
    StopRun("zone changed")
    ns.RefreshAll()
end

function handlers.WHO_LIST_UPDATE()
    if who then
        HandleWhoResults()
    end
end

function handlers.PARTY_INVITE_REQUEST()
    StopRun("invite received")
end

function handlers.GROUP_JOINED()
    StopRun("in a group")
end

function handlers.CHAT_MSG_WHISPER_INFORM()
    if run then
        run.confirmed = run.confirmed + 1
    end
end

function handlers.CHAT_MSG_SYSTEM(message)
    if not ERR_CHAT_THROTTLED or (issecretvalue and issecretvalue(message)) then
        return
    end
    if message == ERR_CHAT_THROTTLED then
        StopRun("chat throttled")
    end
end

function handlers.ADDON_ACTION_BLOCKED(addonName)
    if addonName == ADDON then
        GoManual()
    end
end

handlers.ADDON_ACTION_FORBIDDEN = handlers.ADDON_ACTION_BLOCKED

eventFrame:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)

for _, event in ipairs({
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LEVEL_UP",
    "UI_SCALE_CHANGED",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED_NEW_AREA",
    "WHO_LIST_UPDATE",
    "PARTY_INVITE_REQUEST",
    "GROUP_JOINED",
}) do
    eventFrame:RegisterEvent(event)
end

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

SLASH_LAYERPLS1 = "/layerpls"
SLASH_LAYERPLS2 = "/lp"
SlashCmdList.LAYERPLS = function(input)
    local command, rest = strmatch(input or "", "^(%S*)%s*(.-)$")
    command = command:lower()

    if command == "" then
        ns.SetWindowShown(not ns.IsWindowShown())
    elseif command == "options" then
        ns.OpenOptions()
    elseif command == "msg" then
        if rest ~= "" then
            db.message = rest:sub(1, 255)
            ns.NotifySetting("message")
        end
        Print("whisper text: " .. db.message)
    elseif command == "stop" then
        StopRun("stopped")
    elseif command == "reset" then
        ns.ForgetAsked()
    else
        Print("/lp show or hide - /lp options open settings - /lp msg <text> set the whisper - /lp stop - /lp reset forget who was asked")
    end
end
