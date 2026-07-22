local ADDON_NAME, GearCheck = ...

-- ============================================================
-- Options Panel (Interface > AddOns > GearCheck)
-- ============================================================

local panel = CreateFrame("Frame", "GearCheckOptionsPanel", InterfaceOptionsFramePanelContainer)
panel.name = "GearCheck"
panel:Hide()

local function MakeTitle(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetText(text)
    return fs
end

local function MakeLabel(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetText(text)
    return fs
end

local function MakeCheckbox(parent, key, label, desc, x, y)
    local cb = CreateFrame("CheckButton", "GearCheckOpt_" .. key, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb.Text = _G[cb:GetName() .. "Text"]
    cb.Text:SetText(label)

    cb.tooltipText = label
    cb.tooltipRequirement = desc

    cb:SetScript("OnClick", function(self)
        GearCheckDB.raidBuffs = GearCheckDB.raidBuffs or {}
        GearCheckDB.raidBuffs[key] = self:GetChecked() == 1

        -- Misery and IFF don't stack — if one is checked, note it
        if key == "misery" and GearCheckDB.raidBuffs.misery then
            -- Just informational, both can be checked but only 3% applies
        end

        print("|cffffcc00GearCheck|r: " .. label .. " " .. (GearCheckDB.raidBuffs[key] and "ON" or "OFF"))

        -- Show effective cap
        local caps = GearCheck.GetEffectiveHitCaps()
        print(("  Effective spell hit cap: %d%%"):format(caps.spell))
    end)

    cb._key = key
    return cb
end

-- Build the panel
MakeTitle(panel, "GearCheck", -16)

MakeLabel(panel, "|cff888888Hit cap tracking, stat comparison, and DPS delta estimates|r", -40)

MakeLabel(panel, "Raid Buffs / Debuffs", -75)
MakeLabel(panel, "|cff888888Toggle the buffs your raid provides. This adjusts the hit caps shown in tooltips.|r", -93)
MakeLabel(panel, "|cff888888Misery and Improved Faerie Fire do not stack (3% from either).|r", -108)

local cb1 = MakeCheckbox(panel, "misery",
    "Shadow Priest (Misery)",
    "Reduces spell hit needed by 3%. Does not stack with Improved Faerie Fire.",
    16, -130)

local cb2 = MakeCheckbox(panel, "iff",
    "Balance Druid (Improved Faerie Fire)",
    "Reduces spell hit needed by 3%. Does not stack with Misery.",
    16, -158)

local cb3 = MakeCheckbox(panel, "heroicPresence",
    "Draenei in Party (Heroic Presence)",
    "Reduces all hit needed by 1%.",
    16, -186)

MakeLabel(panel, " ", -220)
MakeLabel(panel, "Hit Caps (base vs with buffs):", -230)

local capSummary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
capSummary:SetPoint("TOPLEFT", 16, -248)
capSummary:SetJustifyH("LEFT")

local function UpdateCapSummary()
    local caps = GearCheck.GetEffectiveHitCaps()
    local lines = {
        ("  Spell Hit:  %d%% (need %d hit rating from gear)"):format(caps.spell, math.ceil(caps.spell * 32.79)),
        ("  Melee Hit:  %d%% (need %d hit rating from gear)"):format(caps.melee_yellow, math.ceil(caps.melee_yellow * 32.79)),
    }
    capSummary:SetText(table.concat(lines, "\n"))
end

-- Refresh checkboxes when panel shows
panel:SetScript("OnShow", function()
    GearCheckDB.raidBuffs = GearCheckDB.raidBuffs or {}
    cb1:SetChecked(GearCheckDB.raidBuffs.misery)
    cb2:SetChecked(GearCheckDB.raidBuffs.iff)
    cb3:SetChecked(GearCheckDB.raidBuffs.heroicPresence)
    UpdateCapSummary()
end)

-- Update summary when checkboxes change
local origOnClick = cb1:GetScript("OnClick")
for _, cb in ipairs({ cb1, cb2, cb3 }) do
    local orig = cb:GetScript("OnClick")
    cb:SetScript("OnClick", function(self)
        orig(self)
        UpdateCapSummary()
    end)
end

-- Slash command to open
local function OpenOptions()
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel) -- called twice to work around Blizzard bug
end

GearCheck.OpenOptions = OpenOptions

-- Register panel
InterfaceOptions_AddCategory(panel)
