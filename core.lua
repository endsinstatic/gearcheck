local ADDON_NAME, GearCheck = ...

-- WotLK 3.3.5a combat rating conversions at level 80
local RATING_PER_PERCENT = {
    hit     = 32.79,    -- hit rating per 1% hit
    crit    = 45.91,    -- crit rating per 1% crit
    haste   = 32.79,    -- haste rating per 1% haste
    expertise = 32.79 / 4, -- expertise rating per 1 expertise (8.20 per point)
    arpen   = 13.99,    -- armor pen rating per 1% ArPen
}

-- Base hit caps vs level 83 boss (in percent) — adjusted by raid buffs
local BASE_HIT_CAPS = {
    melee_yellow = 8,
    melee_white  = 28,
    spell        = 17,
}

-- Expertise cap: 26 expertise = 6.50% dodge reduction
local EXPERTISE_CAP = 26

local function GetEffectiveHitCaps()
    local buffs = GearCheckDB and GearCheckDB.raidBuffs or {}
    local caps = {}
    for k, v in pairs(BASE_HIT_CAPS) do caps[k] = v end

    -- Misery / Improved Faerie Fire: -3% spell hit (don't stack with each other)
    if buffs.misery or buffs.iff then
        caps.spell = caps.spell - 3
    end

    -- Heroic Presence: -1% all hit
    if buffs.heroicPresence then
        caps.spell = caps.spell - 1
        caps.melee_yellow = caps.melee_yellow - 1
        caps.melee_white = caps.melee_white - 1
    end

    return caps
end

GearCheck.GetEffectiveHitCaps = GetEffectiveHitCaps

-- Stat keys from GetItemStats
local STAT_KEYS = {
    ITEM_MOD_STRENGTH_SHORT        = "str",
    ITEM_MOD_AGILITY_SHORT         = "agi",
    ITEM_MOD_STAMINA_SHORT         = "sta",
    ITEM_MOD_INTELLECT_SHORT       = "int",
    ITEM_MOD_SPIRIT_SHORT          = "spi",
    ITEM_MOD_ATTACK_POWER_SHORT    = "ap",
    ITEM_MOD_SPELL_POWER_SHORT     = "sp",
    ITEM_MOD_HIT_RATING_SHORT      = "hit",
    ITEM_MOD_CRIT_RATING_SHORT     = "crit",
    ITEM_MOD_HASTE_RATING_SHORT    = "haste",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "expertise",
    ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "arpen",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "defense",
    ITEM_MOD_DODGE_RATING_SHORT    = "dodge",
    ITEM_MOD_PARRY_RATING_SHORT    = "parry",
    ITEM_MOD_BLOCK_RATING_SHORT    = "block",
    ITEM_MOD_RESILIENCE_RATING_SHORT = "resilience",
}

-- Default stat weights (Spellhance Enhancement Shaman)
-- Users can customise via /gc weights
local DEFAULT_WEIGHTS = {
    hit   = 3.50,  -- until spell hit cap, then 0
    sp    = 2.80,
    haste = 2.20,
    crit  = 1.80,
    ap    = 1.00,
    agi   = 1.80,
    str   = 1.10,
    arpen = 0.50,
    int   = 0.40,
    sta   = 0.01,
    spi   = 0.00,
    expertise = 2.50, -- until cap, then 0
}

-- Equip slot mapping: inventory slot ID -> slot name
local SLOT_NAMES = {
    [1]  = "Head",       [2]  = "Neck",       [3]  = "Shoulder",
    [4]  = "Shirt",      [5]  = "Chest",      [6]  = "Waist",
    [7]  = "Legs",       [8]  = "Feet",       [9]  = "Wrist",
    [10] = "Hands",      [11] = "Finger0",    [12] = "Finger1",
    [13] = "Trinket0",   [14] = "Trinket1",   [15] = "Back",
    [16] = "MainHand",   [17] = "OffHand",    [18] = "Ranged",
}

-- Equip location string -> inventory slot IDs
local EQUIP_LOC_TO_SLOT = {
    INVTYPE_HEAD           = { 1 },
    INVTYPE_NECK           = { 2 },
    INVTYPE_SHOULDER       = { 3 },
    INVTYPE_BODY           = { 4 },
    INVTYPE_CHEST          = { 5 },
    INVTYPE_ROBE           = { 5 },
    INVTYPE_WAIST          = { 6 },
    INVTYPE_LEGS           = { 7 },
    INVTYPE_FEET           = { 8 },
    INVTYPE_WRIST          = { 9 },
    INVTYPE_HAND           = { 10 },
    INVTYPE_FINGER         = { 11, 12 },
    INVTYPE_TRINKET        = { 13, 14 },
    INVTYPE_CLOAK          = { 15 },
    INVTYPE_WEAPON         = { 16, 17 },
    INVTYPE_2HWEAPON       = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND  = { 17 },
    INVTYPE_HOLDABLE       = { 17 },
    INVTYPE_SHIELD         = { 17 },
    INVTYPE_RANGED         = { 18 },
    INVTYPE_RANGEDRIGHT    = { 18 },
    INVTYPE_THROWN          = { 18 },
    INVTYPE_RELIC          = { 18 },
}

-- ============================================================
-- Hit Cap Tracking
-- ============================================================

local function GetMeleeHitPercent()
    local bonus = GetCombatRatingBonus(CR_HIT_MELEE)
    local mod = GetHitModifier and GetHitModifier() or 0
    return bonus + mod
end

local function GetSpellHitPercent()
    local bonus = GetCombatRatingBonus(CR_HIT_SPELL)
    local mod = GetSpellHitModifier and GetSpellHitModifier() or 0
    return bonus + mod
end

local function GetPlayerExpertise()
    local exp = GetExpertise()
    return exp or 0
end

local function FormatCapLine(label, current, cap, unit, showRating)
    unit = unit or "%%"
    local remaining = cap - current
    if remaining <= 0 then
        if showRating then
            local overRating = math.floor(-remaining * RATING_PER_PERCENT.hit)
            return ("|cff20ff20%s: %.1f%s CAPPED|r |cff888888(+%d rating over)|r"):format(label, current, unit, overRating)
        end
        return ("|cff20ff20%s: %.1f%s (CAPPED)|r"):format(label, current, unit)
    else
        if showRating then
            local needRating = math.ceil(remaining * RATING_PER_PERCENT.hit)
            return ("|cffff8020%s: %.1f / %.0f%s (need %d rating)|r"):format(label, current, cap, unit, needRating)
        end
        return ("|cffff8020%s: %.1f / %.0f%s (need %.1f)|r"):format(label, current, cap, unit, remaining)
    end
end

local function AddHitCapLines(tooltip)
    local meleeHit = GetMeleeHitPercent()
    local spellHit = GetSpellHitPercent()
    local expertise = GetPlayerExpertise()
    local caps = GetEffectiveHitCaps()

    local buffs = GearCheckDB and GearCheckDB.raidBuffs or {}
    local buffNote = ""
    if buffs.misery then buffNote = " w/Misery"
    elseif buffs.iff then buffNote = " w/IFF"
    end
    if buffs.heroicPresence then
        buffNote = buffNote .. (buffNote ~= "" and "+" or " w/") .. "Draenei"
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("|cffffcc00GearCheck|r" .. (buffNote ~= "" and (" |cff888888(" .. buffNote:sub(2) .. ")|r") or ""))
    tooltip:AddLine(FormatCapLine("Spell Hit", spellHit, caps.spell, "%", true))
    tooltip:AddLine(FormatCapLine("Melee Hit", meleeHit, caps.melee_yellow, "%", true))
    tooltip:AddLine(FormatCapLine("Expertise", expertise, EXPERTISE_CAP, ""))
end

-- ============================================================
-- Item Stat Extraction
-- ============================================================

local function NormalizeStats(itemLink)
    if not itemLink then return nil end
    local raw = {}
    GetItemStats(itemLink, raw)
    local stats = {}
    for key, value in pairs(raw) do
        local short = STAT_KEYS[key]
        if short then
            stats[short] = (stats[short] or 0) + value
        end
    end
    return stats
end

local function GetEquippedStats(slotID)
    local link = GetInventoryItemLink("player", slotID)
    if not link then return {} end
    return NormalizeStats(link) or {}
end

local function GetBestEquippedSlot(slots)
    local bestSlot = slots[1]
    local bestScore = -999999

    local weights = GearCheckDB and GearCheckDB.weights or DEFAULT_WEIGHTS
    for _, slotID in ipairs(slots) do
        local stats = GetEquippedStats(slotID)
        local score = 0
        for stat, value in pairs(stats) do
            score = score + value * (weights[stat] or 0)
        end
        if score < bestScore or bestSlot == slots[1] then
            bestScore = score
            bestSlot = slotID
        end
    end
    return bestSlot
end

-- ============================================================
-- DPS Delta Calculation
-- ============================================================

local function CalcDPSDelta(tooltipStats, equippedStats)
    local weights = GearCheckDB and GearCheckDB.weights or DEFAULT_WEIGHTS
    local delta = 0
    local details = {}

    -- Collect all stat keys
    local allKeys = {}
    for k in pairs(tooltipStats) do allKeys[k] = true end
    for k in pairs(equippedStats) do allKeys[k] = true end

    -- Check if hit/expertise are over cap (reduce weight to 0)
    local activeWeights = {}
    for k, v in pairs(weights) do
        activeWeights[k] = v
    end

    local spellHit = GetSpellHitPercent()
    local caps = GetEffectiveHitCaps()
    if spellHit >= caps.spell then
        activeWeights.hit = 0
    end

    local expertise = GetPlayerExpertise()
    if expertise >= EXPERTISE_CAP then
        activeWeights.expertise = 0
    end

    for stat in pairs(allKeys) do
        local newVal = tooltipStats[stat] or 0
        local oldVal = equippedStats[stat] or 0
        local diff = newVal - oldVal
        if diff ~= 0 then
            local w = activeWeights[stat] or 0
            local contribution = diff * w
            delta = delta + contribution
            if w > 0 then
                details[#details + 1] = {
                    stat = stat,
                    diff = diff,
                    contribution = contribution,
                }
            end
        end
    end

    table.sort(details, function(a, b)
        return math.abs(a.contribution) > math.abs(b.contribution)
    end)

    return delta, details
end

-- ============================================================
-- Tooltip Hook
-- ============================================================

local function OnTooltipSetItem(tooltip)
    local _, itemLink = tooltip:GetItem()
    if not itemLink then return end

    -- Get item equip location
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    if not equipLoc or equipLoc == "" then
        -- Non-equippable item — just show hit caps on character panel
        return
    end

    local slots = EQUIP_LOC_TO_SLOT[equipLoc]
    if not slots then return end

    -- Get stats for the tooltip item
    local tooltipStats = NormalizeStats(itemLink)
    if not tooltipStats then return end

    -- Find which equipped slot to compare against
    local compareSlot = GetBestEquippedSlot(slots)
    local equippedStats = GetEquippedStats(compareSlot)

    -- Calculate DPS delta
    local delta, details = CalcDPSDelta(tooltipStats, equippedStats)

    -- Add comparison lines
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffffcc00GearCheck|r vs " .. (SLOT_NAMES[compareSlot] or "?"))

    if #details > 0 then
        for _, d in ipairs(details) do
            local sign = d.diff > 0 and "+" or ""
            local color = d.diff > 0 and "|cff20ff20" or "|cffff4040"
            tooltip:AddDoubleLine(
                ("  %s%d %s"):format(sign, d.diff, d.stat),
                ("%s%+.1f DPS|r"):format(color, d.contribution)
            )
        end
    end

    local totalColor = delta >= 0 and "|cff20ff20" or "|cffff4040"
    local arrow = delta >= 0 and "UPGRADE" or "DOWNGRADE"
    tooltip:AddLine(("%s  %s %+.1f DPS|r"):format(totalColor, arrow, delta))

    -- Always show hit caps
    AddHitCapLines(tooltip)

    tooltip:Show()
end

-- ============================================================
-- Character Panel Hit Display
-- ============================================================

local function OnCharacterFrame()
    AddHitCapLines(GameTooltip)
    GameTooltip:Show()
end

-- ============================================================
-- Slash Commands
-- ============================================================

local function PrintWeights()
    local weights = GearCheckDB and GearCheckDB.weights or DEFAULT_WEIGHTS
    print("|cffffcc00GearCheck|r stat weights:")
    local sorted = {}
    for k, v in pairs(weights) do
        sorted[#sorted + 1] = { stat = k, weight = v }
    end
    table.sort(sorted, function(a, b) return a.weight > b.weight end)
    for _, entry in ipairs(sorted) do
        if entry.weight > 0 then
            print(("  %s = %.2f"):format(entry.stat, entry.weight))
        end
    end
end

local function SetWeight(stat, value)
    if not DEFAULT_WEIGHTS[stat] then
        print("|cffffcc00GearCheck|r: Unknown stat '" .. stat .. "'")
        print("  Valid: " .. table.concat((function()
            local keys = {}
            for k in pairs(DEFAULT_WEIGHTS) do keys[#keys + 1] = k end
            table.sort(keys)
            return keys
        end)(), ", "))
        return
    end
    GearCheckDB.weights = GearCheckDB.weights or {}
    for k, v in pairs(DEFAULT_WEIGHTS) do
        if not GearCheckDB.weights[k] then
            GearCheckDB.weights[k] = v
        end
    end
    GearCheckDB.weights[stat] = tonumber(value) or 0
    print("|cffffcc00GearCheck|r: " .. stat .. " = " .. GearCheckDB.weights[stat])
end

local function PrintCaps()
    local meleeHit = GetMeleeHitPercent()
    local spellHit = GetSpellHitPercent()
    local meleeRating = GetCombatRating(CR_HIT_MELEE)
    local spellRating = GetCombatRating(CR_HIT_SPELL)
    local expertise = GetPlayerExpertise()
    local caps = GetEffectiveHitCaps()

    local buffs = GearCheckDB and GearCheckDB.raidBuffs or {}
    local notes = {}
    if buffs.misery then notes[#notes + 1] = "Misery" end
    if buffs.iff then notes[#notes + 1] = "Imp. Faerie Fire" end
    if buffs.heroicPresence then notes[#notes + 1] = "Heroic Presence" end

    print("|cffffcc00GearCheck|r hit caps" .. (#notes > 0 and (" (with " .. table.concat(notes, ", ") .. ")") or "") .. ":")

    local spellNeed = math.max(0, math.ceil((caps.spell - spellHit) * RATING_PER_PERCENT.hit))
    local spellOver = math.max(0, math.floor((spellHit - caps.spell) * RATING_PER_PERCENT.hit))
    if spellHit >= caps.spell then
        print(("  Spell Hit:  %.1f%% / %d%%  |cff20ff20CAPPED|r (+%d rating over, can drop %d rating)"):format(
            spellHit, caps.spell, spellOver, spellOver))
    else
        print(("  Spell Hit:  %.1f%% / %d%%  |cffff8020need %d more hit rating|r (= %d Rigid gems)"):format(
            spellHit, caps.spell, spellNeed, math.ceil(spellNeed / 20)))
    end

    local meleeNeed = math.max(0, math.ceil((caps.melee_yellow - meleeHit) * RATING_PER_PERCENT.hit))
    if meleeHit >= caps.melee_yellow then
        print(("  Melee Hit:  %.1f%% / %d%%  |cff20ff20CAPPED|r"):format(meleeHit, caps.melee_yellow))
    else
        print(("  Melee Hit:  %.1f%% / %d%%  |cffff8020need %d more hit rating|r"):format(
            meleeHit, caps.melee_yellow, meleeNeed))
    end

    print(("  Expertise:  %d / %d%s"):format(expertise, EXPERTISE_CAP,
        expertise >= EXPERTISE_CAP and "  |cff20ff20CAPPED|r" or
        ("  |cffff8020need " .. (EXPERTISE_CAP - expertise) .. " more|r")))
end

-- ============================================================
-- Gear Export
-- ============================================================

local EXPORT_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

-- Hidden tooltip for scanning enchant names
local scanTip = CreateFrame("GameTooltip", "GearCheckScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")

local function GetEnchantText(slotID)
    scanTip:ClearLines()
    scanTip:SetInventoryItem("player", slotID)
    -- Enchant line is typically green text containing common enchant keywords
    for i = 2, scanTip:NumLines() do
        local line = _G["GearCheckScanTipTextLeft" .. i]
        if line then
            local text = line:GetText()
            local r, g, b = line:GetTextColor()
            -- Green text (enchants) has g > 0.9 and r < 0.2 and b < 0.2
            if text and g > 0.9 and r < 0.2 and b < 0.2 then
                -- Skip gem socket lines and "Durability" etc.
                if not text:match("^%a+ Socket$")
                    and not text:match("^Durability")
                    and not text:match("^Requires")
                    and not text:match("^Item Level")
                    and not text:match("^Equip:")
                    and not text:match("^Use:")
                    and not text:match("^Chance on")
                    and not text:match("^Classes:")
                    and not text:match("^Set:") then
                    return text
                end
            end
        end
    end
    return nil
end

local function BuildExportText()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    -- Character info
    local name = UnitName("player")
    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    local _, race = UnitRace("player")
    add("=== GearCheck Export ===")
    add(("%s | %s %s | Level %d"):format(name, race, class, level))
    add("")

    -- Combat ratings
    local meleeHit = GetMeleeHitPercent()
    local spellHit = GetSpellHitPercent()
    local expertise = GetPlayerExpertise()
    local caps = GetEffectiveHitCaps()

    local buffs = GearCheckDB and GearCheckDB.raidBuffs or {}
    local buffList = {}
    if buffs.misery then buffList[#buffList + 1] = "Misery" end
    if buffs.iff then buffList[#buffList + 1] = "IFF" end
    if buffs.heroicPresence then buffList[#buffList + 1] = "Heroic Presence" end

    add("--- Caps ---")
    add(("Spell Hit: %.1f%% / %d%% (%s)"):format(spellHit, caps.spell,
        spellHit >= caps.spell and "CAPPED" or ("need " .. math.ceil((caps.spell - spellHit) * RATING_PER_PERCENT.hit) .. " rating")))
    add(("Melee Hit: %.1f%% / %d%% (%s)"):format(meleeHit, caps.melee_yellow,
        meleeHit >= caps.melee_yellow and "CAPPED" or ("need " .. math.ceil((caps.melee_yellow - meleeHit) * RATING_PER_PERCENT.hit) .. " rating")))
    add(("Expertise: %d / %d (%s)"):format(expertise, EXPERTISE_CAP,
        expertise >= EXPERTISE_CAP and "CAPPED" or ("need " .. (EXPERTISE_CAP - expertise))))
    if #buffList > 0 then
        add(("Raid buffs: %s"):format(table.concat(buffList, ", ")))
    end
    add("")

    -- Combat stats
    add("--- Ratings ---")
    add(("Hit Rating: %d  |  Crit Rating: %d  |  Haste Rating: %d"):format(
        GetCombatRating(CR_HIT_SPELL),
        GetCombatRating(CR_CRIT_MELEE),
        GetCombatRating(CR_HASTE_MELEE)))
    add(("AP: %d  |  SP: %d"):format(
        UnitAttackPower("player"),
        GetSpellBonusDamage(4) or 0)) -- school 4 = fire, close enough for Enh
    add(("Crit: %.1f%% melee / %.1f%% spell"):format(
        GetCritChance(),
        GetSpellCritChance(4)))
    add(("Haste: %.1f%%"):format(GetCombatRatingBonus(CR_HASTE_MELEE)))
    add("")

    -- Equipped gear
    add("--- Gear ---")
    for _, slotID in ipairs(EXPORT_SLOTS) do
        local link = GetInventoryItemLink("player", slotID)
        local slotName = SLOT_NAMES[slotID] or ("Slot" .. slotID)
        if link then
            local itemName, _, quality, iLevel = GetItemInfo(link)
            if itemName then
                -- Get gem names
                local gems = {}
                for i = 1, 3 do
                    local gemName, gemLink = GetItemGem(link, i)
                    if gemName then
                        -- Extract gem stats from the gem's own tooltip
                        local gemStats = gemLink and NormalizeStats(gemLink)
                        local gemDesc = gemName
                        if gemStats then
                            local gsParts = {}
                            for _, k in ipairs({ "hit", "sp", "ap", "haste", "crit", "agi", "str", "int", "sta", "expertise", "arpen" }) do
                                if gemStats[k] and gemStats[k] > 0 then
                                    gsParts[#gsParts + 1] = "+" .. gemStats[k] .. " " .. k
                                end
                            end
                            if #gsParts > 0 then
                                gemDesc = gemName .. " (" .. table.concat(gsParts, ", ") .. ")"
                            end
                        end
                        gems[#gems + 1] = gemDesc
                    end
                end

                -- Get item base stats
                local stats = NormalizeStats(link)
                local statParts = {}
                if stats then
                    local order = { "hit", "sp", "ap", "haste", "crit", "agi", "str", "int", "sta", "arpen", "expertise" }
                    for _, k in ipairs(order) do
                        if stats[k] and stats[k] > 0 then
                            statParts[#statParts + 1] = k .. ":" .. stats[k]
                        end
                    end
                end

                -- Get enchant name via tooltip scan
                local enchantText = GetEnchantText(slotID)

                add(("%-10s iLvl %-3d  %s"):format(slotName, iLevel or 0, itemName))
                if #statParts > 0 then
                    add("           Stats:   " .. table.concat(statParts, ", "))
                end
                if enchantText then
                    add("           Enchant: " .. enchantText)
                end
                if #gems > 0 then
                    add("           Gems:    " .. table.concat(gems, " | "))
                end
            end
        else
            add(("%-10s (empty)"):format(slotName))
        end
    end

    add("")
    add("=== End Export ===")
    return table.concat(lines, "\n")
end

-- Export frame (copy-paste dialog)
local exportFrame

local function ShowExportFrame(text)
    if not exportFrame then
        local f = CreateFrame("Frame", "GearCheckExportFrame", UIParent)
        f:SetWidth(600)
        f:SetHeight(450)
        f:SetPoint("CENTER")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        f:SetBackdropColor(0, 0, 0, 1)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetFrameStrata("DIALOG")

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -16)
        title:SetText("|cffffcc00GearCheck Export|r  (Ctrl+A, Ctrl+C to copy)")

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -5, -5)

        local scroll = CreateFrame("ScrollFrame", "GearCheckExportScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -40)
        scroll:SetPoint("BOTTOMRIGHT", -36, 16)

        local editBox = CreateFrame("EditBox", "GearCheckExportEditBox", scroll)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject(GameFontHighlightSmall)
        editBox:SetWidth(540)
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        scroll:SetScrollChild(editBox)

        f.editBox = editBox
        exportFrame = f
    end

    exportFrame.editBox:SetText(text)
    exportFrame:Show()
    exportFrame.editBox:HighlightText()
    exportFrame.editBox:SetFocus()
end

SLASH_GEARCHECK1 = "/gearcheck"
SLASH_GEARCHECK2 = "/gc"
SlashCmdList["GEARCHECK"] = function(msg)
    local cmd, arg1, arg2 = msg:match("^(%S+)%s*(%S*)%s*(%S*)")
    cmd = (cmd or ""):lower()

    if cmd == "weights" then
        PrintWeights()
    elseif cmd == "weight" and arg1 ~= "" and arg2 ~= "" then
        SetWeight(arg1:lower(), arg2)
    elseif cmd == "caps" or cmd == "hit" then
        PrintCaps()
    elseif cmd == "reset" then
        GearCheckDB.weights = nil
        print("|cffffcc00GearCheck|r: Weights reset to defaults.")
    elseif cmd == "export" then
        ShowExportFrame(BuildExportText())
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        GearCheck.OpenOptions()
    else
        print("|cffffcc00GearCheck|r commands:")
        print("  /gc caps — show hit/expertise caps")
        print("  /gc export — export gear for analysis")
        print("  /gc weights — show current stat weights")
        print("  /gc weight <stat> <value> — set a weight")
        print("  /gc reset — reset weights to defaults")
        print("  /gc options — open settings panel")
    end
end

-- ============================================================
-- Init
-- ============================================================

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        GearCheckDB = GearCheckDB or {}
        GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
        print("|cffffcc00GearCheck|r loaded. /gc for commands.")
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
