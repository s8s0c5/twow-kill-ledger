--[[ KillLedger — Turtle WoW / 1.12. English "You have slain …". No libraries. ]]

local ADDON_NAME = "twow-kill-ledger"
local MAX_ROWS = 750
local LIST_LINES = 14

local db
local filterPve = true
local filterPvp = true
local listOffset = 0
local poiFrame
local mainFrame
local rowFrames = {}
local rowFontStrings = {}
local recent = {}

local function zoneSnap()
  local mx, my = GetPlayerMapPosition("player")
  if mx == 0 and my == 0 then
    mx, my = nil, nil
  end
  return GetRealZoneText() or "", GetSubZoneText() or "", mx, my
end

local function rememberUnit(unit)
  if not unit or not UnitExists(unit) then
    return
  end
  local n = UnitName(unit)
  if not n then
    return
  end
  local z, s, mx, my = zoneSnap()
  recent[n] = {
    isPlayer = UnitIsPlayer(unit) and 1 or nil,
    level = UnitLevel(unit),
    class = UnitClassification(unit),
    zone = z,
    sub = s,
    mx = mx,
    my = my,
    t = time(),
  }
end

local function trimKills()
  while db.kills and getn(db.kills) > MAX_ROWS do
    tremove(db.kills, 1)
  end
end

local function formatWhen(ts)
  return date("%Y-%m-%d %H:%M", ts)
end

local function filteredCount()
  if not db or not db.kills then
    return 0
  end
  local c = 0
  for i = 1, getn(db.kills) do
    local k = db.kills[i].kind
    if (k == "PvE" and filterPve) or (k == "PvP" and filterPvp) then
      c = c + 1
    end
  end
  return c
end

local function nthFilteredNewest(n)
  if not db or not db.kills then
    return
  end
  local seen = 0
  for i = getn(db.kills), 1, -1 do
    local k = db.kills[i].kind
    if (k == "PvE" and filterPve) or (k == "PvP" and filterPvp) then
      seen = seen + 1
      if seen == n then
        return i
      end
    end
  end
end

local function refreshList()
  if not mainFrame or not mainFrame:IsVisible() then
    return
  end
  local total = filteredCount()
  local maxOff = max(0, total - LIST_LINES)
  if listOffset > maxOff then
    listOffset = maxOff
  end
  if listOffset < 0 then
    listOffset = 0
  end
  for line = 1, LIST_LINES do
    local rf = rowFrames[line]
    local idx = nthFilteredNewest(listOffset + line)
    if not idx then
      rf:Hide()
      rf.killIndex = nil
    else
      rf:Show()
      rf.killIndex = idx
      local e = db.kills[idx]
      local lvl = (e.victimLevel and e.victimLevel > 0) and (" [" .. e.victimLevel .. "]") or ""
      rowFontStrings[line][1]:SetText(e.kind .. "  " .. e.victim .. lvl)
      rowFontStrings[line][2]:SetText(formatWhen(e.ts) .. "  " .. (e.zone or ""))
    end
  end
end

local function hidePoi()
  if poiFrame then
    poiFrame:Hide()
    poiFrame.entry = nil
  end
end

local function showPoiOnWorldMap(e)
  if not e or not e.mx or not e.my or not WorldMapButton then
    return
  end
  if (GetRealZoneText() or "") ~= (e.zone or "") then
    DEFAULT_CHAT_FRAME:AddMessage("KillLedger: open the world map in |cffffcc00" .. (e.zone or "?") .. "|r to see this pin.")
  end
  if not poiFrame then
    poiFrame = CreateFrame("Frame", "KillLedgerPOI", WorldMapButton)
    poiFrame:SetWidth(16)
    poiFrame:SetHeight(16)
    local tex = poiFrame:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Minimap\\Tracking\\Class")
  end
  poiFrame.entry = e
  local w, h = WorldMapButton:GetWidth(), WorldMapButton:GetHeight()
  poiFrame:ClearAllPoints()
  poiFrame:SetPoint("CENTER", WorldMapButton, "TOPLEFT", e.mx * w, -e.my * h)
  poiFrame:Show()
end

local function rowTooltip(self)
  if not self.killIndex then
    return
  end
  local e = db.kills[self.killIndex]
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(e.victim, 1, 1, 1)
  GameTooltip:AddLine(e.kind .. "  " .. formatWhen(e.ts), 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Killer: " .. (e.killer or "?"), 0.7, 0.7, 0.7)
  if e.zone and e.zone ~= "" then
    GameTooltip:AddLine(e.zone .. ((e.sub and e.sub ~= "") and (" / " .. e.sub) or ""), 0.6, 0.8, 0.6)
  end
  if e.victimLevel and e.victimLevel > 0 then
    GameTooltip:AddLine("Level: " .. e.victimLevel, 0.7, 0.7, 0.9)
  end
  if e.class and e.class ~= "normal" and e.class ~= "" then
    GameTooltip:AddLine(e.class, 0.6, 0.6, 0.7)
  end
  if e.mx and e.my then
    GameTooltip:AddLine(format("Map: %.3f, %.3f", e.mx, e.my), 0.5, 0.5, 0.5)
  else
    GameTooltip:AddLine("Map: (no position)", 0.5, 0.5, 0.5)
  end
  GameTooltip:Show()
end

local function makeMainFrame()
  local f = CreateFrame("Frame", "KillLedgerFrame", UIParent)
  f:SetWidth(420)
  f:SetHeight(460)
  f:SetPoint("CENTER", 0, 0)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function()
    f:StartMoving()
  end)
  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
  end)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  f:SetBackdropColor(0, 0, 0, 0.85)

  local left = f:CreateTexture(nil, "ARTWORK")
  left:SetTexture("Interface\\QuestFrame\\UI-QuestLog-Book-Left")
  left:SetWidth(256)
  left:SetHeight(256)
  left:SetPoint("TOPLEFT", 8, -8)
  local right = f:CreateTexture(nil, "ARTWORK")
  right:SetTexture("Interface\\QuestFrame\\UI-QuestLog-Book-Right")
  right:SetWidth(128)
  right:SetHeight(256)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -18)
  title:SetText("Kill Ledger")

  local close = CreateFrame("Button", nil, f)
  close:SetWidth(24)
  close:SetHeight(24)
  close:SetPoint("TOPRIGHT", -8, -8)
  close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
  close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
  close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
  close:SetScript("OnClick", function()
    f:Hide()
    hidePoi()
  end)

  local bpve = CreateFrame("Button", nil, f)
  bpve:SetWidth(80)
  bpve:SetHeight(22)
  bpve:SetPoint("TOPLEFT", 24, -44)
  local bpveText = bpve:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  local bpvp = CreateFrame("Button", nil, f)
  bpvp:SetWidth(80)
  bpvp:SetHeight(22)
  bpvp:SetPoint("LEFT", bpve, "RIGHT", 8, 0)
  local bpvpText = bpvp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

  local function syncFilterButtons()
    bpveText:SetText(filterPve and "PvE: on" or "PvE: off")
    bpvpText:SetText(filterPvp and "PvP: on" or "PvP: off")
  end

  bpve:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
  bpve:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
  bpve:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
  bpveText:SetPoint("CENTER", bpve, "CENTER", 0, 1)
  bpveText:SetFontObject("GameFontNormalSmall")
  bpve:SetScript("OnClick", function()
    filterPve = not filterPve
    if not filterPve and not filterPvp then
      filterPvp = true
    end
    listOffset = 0
    syncFilterButtons()
    refreshList()
  end)
  bpvp:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
  bpvp:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
  bpvp:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
  bpvpText:SetPoint("CENTER", bpvp, "CENTER", 0, 1)
  bpvpText:SetFontObject("GameFontNormalSmall")
  bpvp:SetScript("OnClick", function()
    filterPvp = not filterPvp
    if not filterPve and not filterPvp then
      filterPve = true
    end
    listOffset = 0
    syncFilterButtons()
    refreshList()
  end)

  f:SetScript("OnShow", function()
    syncFilterButtons()
    refreshList()
  end)
  f:SetScript("OnHide", function()
    hidePoi()
  end)

  local listBg = CreateFrame("Frame", nil, f)
  listBg:SetPoint("TOPLEFT", 20, -78)
  listBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 200, 48)

  for line = 1, LIST_LINES do
    local rf = CreateFrame("Button", nil, listBg)
    rf:SetHeight(22)
    rf:SetPoint("TOPLEFT", 4, -4 - (line - 1) * 22)
    rf:SetPoint("TOPRIGHT", listBg, "TOPRIGHT", -80, -4 - (line - 1) * 22)
    rf:SetScript("OnEnter", function()
      rowTooltip(rf)
    end)
    rf:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    local t1 = rf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t1:SetPoint("LEFT", 4, 0)
    t1:SetJustifyH("LEFT")
    local t2 = rf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t2:SetPoint("TOPLEFT", t1, "BOTTOMLEFT", 0, -2)
    t2:SetJustifyH("LEFT")
    rowFontStrings[line] = { t1, t2 }
    local mapb = CreateFrame("Button", nil, rf)
    mapb:SetWidth(56)
    mapb:SetHeight(18)
    mapb:SetPoint("RIGHT", rf, "RIGHT", 0, 0)
    mapb:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    mapb:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    mapb:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    local mf = mapb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mf:SetPoint("CENTER", mapb, "CENTER", 0, 1)
    mf:SetText("Map")
    mapb:SetScript("OnClick", function()
      if not rf.killIndex then
        return
      end
      local e = db.kills[rf.killIndex]
      if not e.mx or not e.my then
        DEFAULT_CHAT_FRAME:AddMessage("KillLedger: no map position for this entry.")
        return
      end
      ToggleWorldMap()
      showPoiOnWorldMap(e)
    end)
    mapb:SetScript("OnEnter", function()
      rowTooltip(rf)
    end)
    mapb:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    rowFrames[line] = rf
  end

  listBg:EnableMouseWheel(true)
  listBg:SetScript("OnMouseWheel", function()
    local total = filteredCount()
    local maxOff = max(0, total - LIST_LINES)
    if arg1 > 0 then
      listOffset = max(0, listOffset - 3)
    else
      listOffset = min(maxOff, listOffset + 3)
    end
    refreshList()
  end)

  f:Hide()
  mainFrame = f
  tinsert(UISpecialFrames, f:GetName())
end

local function toggleMainFrame()
  if not mainFrame then
    makeMainFrame()
  end
  if mainFrame:IsVisible() then
    mainFrame:Hide()
    hidePoi()
  else
    mainFrame:Show()
  end
end

_G.SLASH_KILLLEDGER1 = "/killledger"
_G.SlashCmdList["KILLLEDGER"] = function()
  toggleMainFrame()
end

local function addKill(kind, victim, victimLevel, zone, sub, mx, my, classTag)
  if not db or not db.kills or not victim or victim == "" then
    return
  end
  local ts = time()
  local n = getn(db.kills)
  if n > 0 then
    local p = db.kills[n]
    if p.victim == victim and (ts - p.ts) <= 1 then
      return
    end
  end
  tinsert(db.kills, {
    ts = ts,
    kind = kind,
    victim = victim,
    victimLevel = victimLevel,
    killer = UnitName("player") or "?",
    zone = zone,
    sub = sub,
    mx = mx,
    my = my,
    class = classTag,
  })
  trimKills()
  refreshList()
end

local function parseSlain(msg)
  if not db or not msg or strsub(msg, 1, 15) ~= "You have slain " then
    return
  end
  local name = strsub(msg, 16)
  name = gsub(gsub(name, "^%s+", ""), "[!%.]+$", "")
  if name == "" then
    return
  end
  local r = recent[name]
  local kind = (r and r.isPlayer) and "PvP" or "PvE"
  local vl = r and r.level or 0
  local classTag = r and r.class or nil
  local z, s, mx, my = "", "", nil, nil
  if r and r.zone ~= "" then
    z, s, mx, my = r.zone, r.sub, r.mx, r.my
  end
  if z == "" then
    z, s, mx, my = zoneSnap()
  end
  addKill(kind, name, vl, z, s, mx, my, classTag)
end

local miniBtn = CreateFrame("Button", nil, Minimap)
miniBtn:SetWidth(20)
miniBtn:SetHeight(20)
miniBtn:SetFrameStrata("MEDIUM")
miniBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local miniIcon = miniBtn:CreateTexture(nil, "OVERLAY")
miniIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
miniIcon:SetAllPoints()
miniBtn:SetScript("OnClick", toggleMainFrame)
miniBtn:SetScript("OnEnter", function()
  GameTooltip:SetOwner(miniBtn, "ANCHOR_LEFT")
  GameTooltip:SetText("Kill Ledger", 1, 1, 1)
  GameTooltip:AddLine("Click to open your kill ledger.", nil, nil, nil, 1)
  GameTooltip:Show()
end)
miniBtn:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

local function minimapButtonPlace()
  if not db then
    return
  end
  local ang = db.mmAngle
  if not ang then
    ang = math.rad(215)
  end
  local x = 52 - 80 * math.cos(ang)
  local y = 80 * math.sin(ang) - 52
  miniBtn:ClearAllPoints()
  miniBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

miniBtn:RegisterForDrag("RightButton")
miniBtn:SetScript("OnDragStart", function()
  miniBtn:LockHighlight()
  miniBtn.isMoving = true
end)
miniBtn:SetScript("OnDragStop", function()
  miniBtn:UnlockHighlight()
  miniBtn.isMoving = false
end)
miniBtn:SetScript("OnUpdate", function()
  if not miniBtn.isMoving or not db then
    return
  end
  local mx, my = GetCursorPosition()
  local s = miniBtn:GetEffectiveScale()
  mx, my = mx / s, my / s
  local cx, cy = Minimap:GetCenter()
  local ang = math.atan2(my - cy, mx - cx)
  db.mmAngle = ang
  minimapButtonPlace()
end)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_MISC_INFO")
eventFrame:RegisterEvent("WORLD_MAP_UPDATE")

eventFrame:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    KillLedgerDB = KillLedgerDB or {}
    db = KillLedgerDB
    db.kills = db.kills or {}
    minimapButtonPlace()
  elseif event == "PLAYER_TARGET_CHANGED" then
    rememberUnit("target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    rememberUnit("mouseover")
  elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" or event == "CHAT_MSG_COMBAT_MISC_INFO" then
    parseSlain(arg1)
  elseif event == "WORLD_MAP_UPDATE" then
    if poiFrame and poiFrame:IsVisible() and poiFrame.entry then
      showPoiOnWorldMap(poiFrame.entry)
    end
  end
end)
