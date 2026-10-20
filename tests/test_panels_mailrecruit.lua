-- Module panels built with WM.UI: Mail & Trade Logger, Recruiter (main,
-- messages and history windows).
-- Usage: lua5.1 test_panels_mailrecruit.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env
env.ChatFrame_AddMessageEventFilter = function() end
W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/MailLogger.lua")
W.load("Modules/Recruiter.lua")
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

local function Init(mod)
    local ok = pcall(mod.Initialize, mod)
    if not ok and mod.InitDB then mod:InitDB() end
end

local function FindCheckbox(panel, pattern)
    for _, w in ipairs(panel.layout.widgets) do
        local t = rawget(w, "Text")
        if t and t:GetText() and t:GetText():find(pattern, 1, true) then
            return w
        end
    end
end

local function FindButton(panel, pattern)
    for _, w in ipairs(panel.layout.widgets) do
        if w._template == "UIPanelButtonTemplate" and w:GetText() and w:GetText():find(pattern, 1, true) then
            return w
        end
    end
    for _, b in ipairs(panel.footerButtons) do
        if b:GetText() and b:GetText():find(pattern, 1, true) then return b end
    end
end

local function Escapable(name)
    for _, n in ipairs(env.UISpecialFrames) do if n == name then return true end end
    return false
end

local function CountShown(pool)
    local n = 0
    for _, r in ipairs(pool) do if r:IsShown() then n = n + 1 end end
    return n
end

-- ============ Mail & Trade Logger ============
local ML = WM.modules.MailLogger
Init(ML)
check("mail logger db for this character", env.MailLoggerDB.characters["Me-Testrealm"] ~= nil)

-- Seed two characters' logs
local me = env.MailLoggerDB.characters["Me-Testrealm"]
me.log = {
    { type = "gold", timestamp = "t1", data = { amount = 10000, sender = "Bob" } },
    { type = "item", timestamp = "t2", data = { itemName = "Linen", count = 5, sender = "Bob" } },
    { type = "ah_sale", timestamp = "t3", data = { itemName = "Ore", amount = 500 } },
    { type = "ah_cancelled", timestamp = "t4", data = { itemName = "Hat" } },
}
me.tradeLog = {
    { timestamp = "t5", partner = "Ann", received = { money = 100, items = {} }, given = { money = 0, items = { {} } } },
}
env.MailLoggerDB.characters["Alt-Testrealm"] = {
    log = { { type = "gold", timestamp = "a1", data = { amount = 1, sender = "X" } } },
    tradeLog = {},
}

-- Record every frame made, to find the Choice's buttons by parent
local created = {}
local baseCreateFrame = env.CreateFrame
env.CreateFrame = function(...)
    local f = baseCreateFrame(...)
    created[#created + 1] = f
    return f
end

local mp = ML:ToggleUI() or ML:CreateUI()
check("mail logger shown", mp:IsShown() and env.WM_MailLoggerFrame == mp)
check("mail logger height <= 600", mp:GetHeight() <= 600)
check("mail logger fits a 768 screen", mp:GetHeight() <= 768 - 16)
check("mail logger has a list area", mp.layout.fill ~= nil)
check("mail logger closes on Escape", Escapable("WM_MailLoggerFrame"))

-- Tabs: Mail is current and marked
local tabButtons = {}
for _, f in ipairs(created) do
    if f._parent == ML.tabChoice and f._template == "UIPanelButtonTemplate" then
        tabButtons[#tabButtons + 1] = f
    end
end
local function TabText(i) return tabButtons[i] and tabButtons[i]:GetText() or "" end
check("four tabs", #tabButtons >= 4)
check("mail tab is marked", TabText(1):find("00FF00", 1, true) and not TabText(2):find("00FF00", 1, true))
check("mail tab shown", ML.mailTab:IsShown() and not ML.tradesTab:IsShown())
check("mail rows listed", CountShown(ML.mailRows) == 4)
check("filters row visible on mail tab", not ML.filterRow.hidden)
check("settings rows hidden on mail tab", ML.settingsRows[1].hidden and not ML.settingsRows[1].frame:IsShown())

W.click(tabButtons[2])
check("trades tab current", ML.currentTab == "trades")
check("trades tab marked", TabText(2):find("00FF00", 1, true) and not TabText(1):find("00FF00", 1, true))
check("trades tab shown", ML.tradesTab:IsShown() and not ML.mailTab:IsShown())
check("trade rows listed", CountShown(ML.tradeRows) == 1)
check("filters hidden off the mail tab", ML.filterRow.hidden)

W.click(tabButtons[3])
check("summary tab shown", ML.summaryTab:IsShown())
check("summary names this character", ML.summaryText:GetText():find("Me-Testrealm", 1, true))

W.click(tabButtons[4])
check("settings tab current and marked", ML.currentTab == "settings" and TabText(4):find("00FF00", 1, true))
check("settings rows shown on settings tab", not ML.settingsRows[1].hidden and ML.settingsRows[1].frame:IsShown())
local notif = FindCheckbox(mp, "Show chat notifications")
check("notifications checkbox on", notif and notif:GetChecked() == true)
W.click(notif)
check("notifications checkbox writes", env.MailLoggerDB.showNotifications == false)
for label, key in pairs({ ["Log gold received"] = "logGold", ["Log items received"] = "logItems",
                          ["Log auction house transactions"] = "logAuctionHouse", ["Log trades"] = "logTrades" }) do
    local cb = FindCheckbox(mp, label)
    W.click(cb)
    check(label .. " writes", env.MailLoggerDB[key] == false)
    check(label .. " has a tooltip", cb:GetScript("OnEnter") ~= nil)
    W.click(cb)
end

-- Filters
W.click(tabButtons[1])
local goldFilter = FindCheckbox(mp, "Gold")
check("gold filter has a tooltip", goldFilter and goldFilter:GetScript("OnEnter") ~= nil)
W.click(goldFilter)
check("gold filter hides gold rows", CountShown(ML.mailRows) == 3)
local expired = FindCheckbox(mp, "Expired")
W.click(expired)
check("expired filter also hides cancelled auctions", CountShown(ML.mailRows) == 2)
W.click(goldFilter); W.click(expired)
check("filters back on", CountShown(ML.mailRows) == 4)

-- Character dropdown
local dd = ML.charDropdown
check("character dropdown keeps its name", dd.dropdown:GetName() == "WM_MailLoggerCharDropdown")
check("dropdown shows this character", env.UIDropDownMenu_GetText(dd.dropdown) == "Me-Testrealm")
local items = W.openMenu(dd.dropdown)
check("dropdown lists both characters", #items == 2)
local alt
for _, it in ipairs(items) do if it.value == "Alt-Testrealm" then alt = it end end
alt.func()
check("dropdown text follows the choice", env.UIDropDownMenu_GetText(dd.dropdown) == "Alt-Testrealm")
check("mail list shows the alt's log", CountShown(ML.mailRows) == 1)
W.click(tabButtons[3])
check("summary shows the alt", ML.summaryText:GetText():find("Alt-Testrealm", 1, true))

-- Reopen keeps the same frame and current tab
ML:ToggleUI()
check("mail logger hides", not mp:IsShown())
ML:ToggleUI()
check("mail logger reopens on the same tab", mp:IsShown() and ML.currentTab == "summary" and ML.summaryTab:IsShown())
check("same mail frame on reopen", ML:CreateUI() == mp)

-- ============ Recruiter ============
local RC = WM.modules.Recruiter
Init(RC)
local db = env.RecruitingToolDB
check("recruiter db", db and db.enabledClasses)

RC:ToggleUI()
local rp = env.WM_RecruiterFrame
check("recruiter shown", rp and rp:IsShown() and RC.mainFrame == rp)
check("recruiter height <= 600", rp:GetHeight() <= 600)
check("recruiter has a log area", rp.layout.fill ~= nil and rp.logChild ~= nil)
check("recruiter closes on Escape", Escapable("WM_RecruiterFrame"))
local fillTop = select(5, rp.layout.fill.frame:GetPoint(1))
check("log keeps at least 100px", 560 - 40 - 44 - (-fillTop) >= 100)

-- Class grid
local rows = {}
for name, cb in pairs(rp.classCheckboxes) do
    rows[cb:GetPoint(1) and select(2, cb:GetPoint(1))] = true
end
local nrows = 0
for _ in pairs(rows) do nrows = nrows + 1 end
check("nine class checkboxes", (function() local n = 0 for _ in pairs(rp.classCheckboxes) do n = n + 1 end return n end)() == 9)
check("class grid wraps onto two rows", nrows == 2)
local mage = rp.classCheckboxes.Mage
check("mage checkbox labelled and on", rawget(mage, "Text"):GetText() == "Mage" and mage:GetChecked())
check("class checkbox has a tooltip", mage:GetScript("OnEnter") ~= nil)
W.click(mage)
check("class checkbox writes", db.enabledClasses.Mage == false)
W.click(mage)

local hide = FindCheckbox(rp, "Hide outgoing")
W.click(hide)
check("hide whispers writes", db.hideWhispers == false)

-- Edit boxes
local function Type(box, text, how)
    local e = box.editBox
    e:SetFocus()
    e:SetText(text)
    if how == "enter" then W.fire(e, "OnEnterPressed") else e:ClearFocus() end
end
Type(rp.minLvlInput, "20", "enter")
check("min level saves on Enter", db.minLevel == 20)
Type(rp.maxLvlInput, "60")
check("max level saves on focus lost", db.maxLevel == 60)
Type(rp.cooldownInput, "30", "enter")
check("cooldown capped at 14", db.cooldownDays == 14)
Type(rp.guildInput, "Testers", "enter")
check("guild name saves", db.guildName == "Testers")
Type(rp.msgInput, "<%GUILD%> wants you", "enter")
check("message saves", db.message == "<%GUILD%> wants you")
rp.minLvlInput.editBox:SetFocus()
rp.minLvlInput.editBox:SetText("5")
W.fire(rp.minLvlInput.editBox, "OnEscapePressed")
check("Escape restores the saved level", rp.minLvlInput:GetText() == "20" and db.minLevel == 20)
check("level box has a tooltip", rp.minLvlInput.editBox:GetScript("OnEnter") ~= nil)

-- Status fields update through the module's own functions
check("idle status", rp.statusText:GetText():find("Idle", 1, true))
check("continue disabled when idle", not rp.continueBtn:IsEnabled())
env.DEFAULT_CHAT_FRAME.editBox = W.NewFrame()
env.ChatEdit_SendText = function() end
env.C_FriendList = false   -- use the Classic who API below
env.GetNumWhoResults = function() return 2 end
env.GetWhoInfo = function(i)
    if i == 1 then return "Newbie", "", 30, "Human", "Warrior", "Elwynn", "WARRIOR" end
    return "Guilded", "Some Guild", 30, "Human", "Warrior", "Elwynn", "WARRIOR"
end
W.click(rp.startBtn)
check("scan writes typed values first", db.minLevel == 20 and db.guildName == "Testers")
check("scanning status", rp.statusText:GetText():find("Scanning", 1, true))
RC:ProcessWhoResults()
check("waiting status", rp.statusText:GetText():find("Waiting", 1, true))
check("continue enabled while waiting", rp.continueBtn:IsEnabled())
check("harvest text counts the find", rp.harvestText:GetText():find("|cFFFFFF001|r", 1, true))
RC:UpdateLogDisplay()
check("activity log rows", rp.logEntries and #rp.logEntries > 0 and rp.logEntries[1]:IsShown())

-- Messages window
W.click(rp.showMsgBtn)
local mf = env.WM_RecruiterMessageFrame
check("messages window shown", mf and mf:IsShown())
check("messages window height <= 600", mf:GetHeight() <= 600)
check("messages window closes on Escape", Escapable("WM_RecruiterMessageFrame"))
check("messages window lists the harvested player", #mf.rows == 1 and mf.rows[1]:IsShown())
check("count line", mf.countText:GetText():find("|cFF00FF001|r ready", 1, true))
local opened
env.ChatFrame_OpenChat = function(t) opened = t end
W.click(mf.rows[1].sendBtn)
check("send prefills the whisper", opened == "/w Newbie <Testers> wants you")
check("send marks the player", db.whispered.Newbie ~= nil)
check("row flips to Unmark", mf.rows[1].sendBtn:GetText() == "Unmark")
check("whispered count updates", rp.whisperedText:GetText():find("|cFFFFFF001|r", 1, true))
W.click(mf.rows[1].sendBtn)
check("unmark clears the cooldown", db.whispered.Newbie == nil)
check("message window has Mark All Sent", FindButton(mf, "Mark All Sent") ~= nil)
W.click(FindButton(mf, "Clear List"))
check("clear list empties the rows", not mf.rows[1]:IsShown())
RC:ShowMessageList()
check("messages window toggles closed", not mf:IsShown())

W.click(rp.stopBtn)
check("stop returns to idle", rp.statusText:GetText():find("Idle", 1, true) and not rp.continueBtn:IsEnabled())

-- History window
db.whispered = { Ann = 100, Bob = 200 }
W.click(rp.viewHistoryBtn)
local hf = env.WM_RecruiterHistoryFrame
check("history window shown", hf and hf:IsShown())
check("history height <= 600", hf:GetHeight() <= 600)
check("history closes on Escape", Escapable("WM_RecruiterHistoryFrame"))
check("history count", hf.countText:GetText():find("|cFFFFFF002|r", 1, true))
check("history newest first", #hf.historyEntries == 2 and hf.historyEntries[1]:GetText():find("Bob", 1, true))
RC:ShowHistoryWindow()
check("history toggles closed", not hf:IsShown())
RC:ShowHistoryWindow()
check("history reopens", hf:IsShown())

check("footer has Clear History", FindButton(rp, "Clear History") ~= nil)
RC:ToggleUI()
check("recruiter hides", not rp:IsShown())
check("same recruiter frame", RC:CreateUI() == rp)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
