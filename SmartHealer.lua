--Original idea of this addon is based on Ogrisch's LazySpell

SmartHealer = AceLibrary("AceAddon-2.0"):new("AceHook-2.1", "AceConsole-2.0", "AceDB-2.0")
SmartHealer:RegisterDB("SmartHealerDB")
SmartHealer:RegisterDefaults("account", {
    overheal = 1,
    categories = {
        ["tanks"] = {
            overheal = 1.25,
            players = {},
        },
        ["melees"] = {
            overheal = 1.1,
            players = {},
        },
    },
})

local libHC = AceLibrary("HealComm-1.0")
local libIB = AceLibrary("ItemBonusLib-1.0")
local libSC = AceLibrary("SpellCache-1.0")

local _pfUIQuickCast_OnHeal_orig
function SmartHealer:OnEnable()
    if Clique and Clique.CastSpell then
        self:Hook(Clique, "CastSpell", "Clique_CastSpell")
    end

    if CM and CM.CastSpell then
        self:Hook(CM, "CastSpell", "CM_CastSpell")
    end

    if pfUI and pfUI.uf and pfUI.uf.ClickAction then
        self:Hook(pfUI.uf, "ClickAction", "pfUI_ClickAction")
    end

    if SlashCmdList and SlashCmdList.PFCAST then
        self:Hook(SlashCmdList, "PFCAST", "pfUI_PFCast")
    end

    if pfUIQuickCast and pfUIQuickCast.OnHeal then
        self:Hook(pfUIQuickCast, "OnHeal", "pfUIQuickCast_OnHeal")

        _pfUIQuickCast_OnHeal_orig = self.hooks[pfUIQuickCast]["OnHeal"]
    end

    self:RegisterChatCommand({ "/heal" }, function(arg)
        SmartHealer:CastHeal(arg)
    end)

    self:RegisterChatCommand({ "/sh_overheal" }, function(arg)
        local category, substitutionsCount1 = string.gsub(arg, "^%s*(%S+)%s+(%S+)%s*$", "%1")
        local overheal, substitutionsCount2 = string.gsub(arg, "^%s*(%S+)%s+(%S+)%s*$", "%2")

        if substitutionsCount1 == 1 then
            category = string.gsub(category, "^%s*(.-)%s*$", "%1") -- trim leading and trailing spaces
            SmartHealer:ConfigureOverhealing(category, overheal)
            return
        end

        category = nil
        overheal, substitutionsCount2 = string.gsub(arg, "^%s*(%S+)%s*$", "%1")
        if substitutionsCount2 == 1 then
            SmartHealer:ConfigureOverhealing(overheal) -- set the default overhealing multiplier
            return
        end

        SmartHealer:PrintCurrentConfiguration()
    end)

    self:RegisterChatCommand({ "/sh_toggle_player_in_category" }, function(arg)
        local category, substitutionsCount1 = string.gsub(arg, "^%s*(%S+)%s+(%S+)%s*$", "%1")
        local playerName, substitutionsCount2 = string.gsub(arg, "^%s*(%S+)%s+(%S+)%s*$", "%2")

        if substitutionsCount1 == 1 then
            SmartHealer:TogglePlayerInCategory(category, playerName)
            return
        end

        SmartHealer:TogglePlayerInCategory(arg) -- will get the player name from the mouseover target
    end)

    self:RegisterChatCommand({ "/sh_reset_all_categories" }, function()
        SmartHealer:ResetAllCategoriesToDefaultOnes()
    end)

    self:RegisterChatCommand({ "/sh_delete_category" }, function(category)
        SmartHealer:DeleteCategory(category)
    end)

    self:RegisterChatCommand({ "/sh_clear_registry" }, function(optionalCategory)
        SmartHealer:ClearRegistry(optionalCategory)
    end)

    self:Print('loaded')
end

-------------------------------------------------------------------------------
-- Handler function for /heal <spell_name>[, overheal_multiplier]
-------------------------------------------------------------------------------
-- Function automatically choose which rank of heal will be casted based on
-- amount of missing life.
--
-- NOTE: Argument "spellName" should be always heal and shouldn't contain rank.
-- If there is a rank, function won't scale it. It means that "Healing Wave"
-- will use rank as needed, but "Healing Wave(Rank 3)" will always cast rank 3.
-- Argument "spellName" can contain overheal multiplier information separated
-- by "," or ";" and it should be either number (1.1) or percentage (110%).
--
-- Examples:
-- SmartHealer:CastSpell("Healing Wave")			--/heal Healing Wave
-- SmartHealer:CastSpell("Healing Wave, 1.15")		--/heal Healing Wave, 1.15
-- SmartHealer:CastSpell("Healing Wave;120%")		--/heal Healing Wave;120%
-------------------------------------------------------------------------------
function SmartHealer:CastHeal(spellName)
    local possibleExplicitOverheal

    -- self:Print("spellname: ", spellName, type(spellName), string.len(spellName))
    if not spellName or string.len(spellName) == 0 or type(spellName) ~= "string" then
        return
    end

    spellName = string.gsub(spellName, "^%s*(.-)%s*$", "%1")     --strip leading and trailing space characters
    spellName = string.gsub(spellName, "%s+", " ")               --replace all space character with actual space

    local _, _, arg = string.find(spellName, "[,;]%s*(.-)$")     --tries to find overheal multiplier (number after spell name, separated by "," or ";")
    if arg then
        local _, _, percent = string.find(arg, "(%d+)%%")
        if percent then
            possibleExplicitOverheal = tonumber(percent) / 100
        else
            possibleExplicitOverheal = tonumber(arg)
        end

        spellName = string.gsub(spellName, "[,;].*", "")     --removes everything after first "," or ";"
    end

    local spell, rank = libSC:GetRanklessSpellName(spellName)
    local unit, onSelf

    if UnitExists("target") and UnitCanAssist("player", "target") then
        unit = "target"
    end

    if unit == nil then
        if GetCVar("autoSelfCast") == "1" then
            unit = "player"
            onSelf = true
        else
            return
        end
    end

    if spell and rank == nil and libHC.Spells[spell] then
        rank = self:GetOptimalRank(spell, unit, possibleExplicitOverheal)
        if rank then
            spellName = libSC:GetSpellNameText(spell, rank)
        end
    end

    -- self:Print("spellname: ", spellName)

    CastSpellByName(spellName, onSelf)

    if UnitIsUnit("player", unit) then
        if SpellIsTargeting() then
            SpellTargetUnit(unit)
        end
        if SpellIsTargeting() then
            SpellStopTargeting()
        end
    end
end

-------------------------------------------------------------------------------------------
-- Handler function for /sh_toggle_player_in_category <category> [<optional_player_name>]
-------------------------------------------------------------------------------------------
-- PLaces the given player in the specified category (if the player is already in another
-- category he will get removed from that one).
--
-- If the player is already in the category specified then he's removed from it.
--
-- If no player name is specified, then the player that's currently being hovered over is
-- selected and if no player is hovered over then the player that's currently targeted is selected.
--
-------------------------------------------------------------------------------
function SmartHealer:TogglePlayerInCategory(category, optionalPlayerName)
    if not category or category == '' then
        self:Print(" [Error] Category name not specified")
        return
    end

    category = string.gsub(category, "^%s*(.-)%s*$", "%1") -- trim leading and trailing spaces
    local categoryConfig = self.db.account.categories[category]
    if not categoryConfig then
        self:Print(" [Error] Category '", category, "' not found")
        return
    end

    local playerName = optionalPlayerName
    playerName = string.gsub(playerName or "", "^%s*(.-)%s*$", "%1") -- trim leading and trailing spaces
    if not playerName or playerName == '' then
        playerName = UnitName("mouseover") or UnitName("target")
    end

    if not playerName or playerName == '' then
        self:Print(" [Error] Player not specified")
        return
    end

    local playerGetsMoved = false
    for cat in pairs(self.db.account.categories) do
        local gotRemoved = SmartHealer:TryRemovePlayerFromCategory(cat, playerName)
        if gotRemoved then
            if cat == category then
                -- if the player was in the category then we just toggled him off and we are done
                self:Print("Removed '", playerName, "' from category '", category, "'")
                return
            end

            playerGetsMoved = true
            break -- if the player was in another category then we need to add/move him to the new category
        end
    end

    table.insert(categoryConfig.players, playerName)
    if playerGetsMoved then
        self:Print("Moved '", playerName, "' to category '", category, "'")
        return
    end

    self:Print("Added '", playerName, "' into category '", category, "'")
end

-- utility function to remove a player from a category
function SmartHealer:TryRemovePlayerFromCategory(category, playerName)
    if not category or category == '' then
        self:Print(" [Error] Category name not specified")
        return false
    end

    category = string.gsub(category, "^%s*(.-)%s*$", "%1") -- trim leading and trailing spaces
    local categoryConfig = self.db.account.categories[category]
    if not categoryConfig then
        self:Print(" [Error] Category '", category, "' not found")
        return false
    end

    if not playerName or playerName == '' then
        self:Print(" [Error] Player name not specified")
        return false
    end

    for index, existingPlayerName in ipairs(categoryConfig.players) do
        if playerName == existingPlayerName then
            table.remove(categoryConfig.players, index)
            return true
        end
    end

    return false
end

-------------------------------------------------------------------------------
-- Handler function for /sh_overheal [<category>] <overheal_multiplier>
-------------------------------------------------------------------------------
-- Sets the overheal multiplier% for the specified category of players. If only the
-- multiplier% is specified then it sets the default overheal-multiplier%.
-- If no argument is specified, it prints the current overheal multiplier%.
--
-- Examples:
--
-- /sh_overheal 1.15   -- sets the default overheal multiplier to 115%
-- /sh_overheal 115%   -- same as above
--
-- /sh_overheal tanks 1.15   -- sets the overheal multiplier for tanks to 115%
-- /sh_overheal tanks 115%   -- same as above
--
-- /sh_overheal     -- prints the current overheal multiplier for all categories
--
-------------------------------------------------------------------------------
function SmartHealer:ConfigureOverhealing(category, overheal)
    if not overheal or overheal == '' then
        overheal = category
    end

    if overheal and type(overheal) == "string" then
        overheal = string.gsub(overheal, "^%s*(.-)%s*$", "%1")

        local _, _, percent = string.find(overheal, "(%d+)%%")
        if percent then
            overheal = tonumber(percent) / 100
        else
            overheal = tonumber(overheal)
        end
    end

    if type(overheal) ~= "number" then
        self:Print(" [Error] Invalid overheal multiplier supplied (type '", type(overheal), "' is not a number)")
        return
    end

    overheal = math.floor(overheal * 1000 + 0.5) / 1000
    if category == nil then
        self.db.account.overheal = overheal
        return
    end

    self.db.account.categories[category] = self.db.account.categories[category] or {
        players = {},
        overheal = 1
    }

    self.db.account.categories[category].overheal = overheal
end

-------------------------------------------------------------------------------
-- Handler function for /sh_overheal (without any parameters)
-------------------------------------------------------------------------------
function SmartHealer:PrintCurrentConfiguration()
    self:Print("Overheal multipliers:")
    self:Print("- default: ", self.db.account.overheal, "(", self.db.account.overheal * 100, "%)")
    for cat, config in pairs(self.db.account.categories) do
        self:Print("- category '", cat, "': ", config.overheal, "(", config.overheal * 100, "%) -> ", table.getn(config.players) == 0 and "(no players registered)" or table.concat(config.players, ", "))
    end
end

-------------------------------------------------------------------------------
-- Handler function for /sh_reset_all_categories
-------------------------------------------------------------------------------
function SmartHealer:ResetAllCategoriesToDefaultOnes()
    self.db.account.categories = {
        ["tanks"] = {
            overheal = 1.25,
            players = {},
        },
        ["melees"] = {
            overheal = 1.1,
            players = {},
        },
    }
end

-------------------------------------------------------------------------------
-- Handler function for /sh_delete_category <category>
-------------------------------------------------------------------------------
function SmartHealer:DeleteCategory(category)
    if not category or category == '' then
        self:Print(" [Error] Category name not specified")
        return
    end

    category = string.gsub(category, "^%s*(.-)%s*$", "%1") -- trim leading and trailing spaces

    self.db.account.categories[category] = nil
end

-------------------------------------------------------------------------------
-- Handler function for /sh_clear_registry [<category>]
-------------------------------------------------------------------------------
function SmartHealer:ClearRegistry(optionalCategory)
    if not optionalCategory or optionalCategory == '' then
        -- clear all registered players in all categories
        for _, config in pairs(self.db.account.categories) do
            config.players = {}
        end
        return
    end

    optionalCategory = string.gsub(optionalCategory, "^%s*(.-)%s*$", "%1") -- trim leading and trailing spaces
    local categoryConfig = self.db.account.categories[optionalCategory]
    if not categoryConfig then
        self:Print(" [Error] Category '", optionalCategory, "' not found")
        return
    end

    categoryConfig.players = {}
end

-------------------------------------------------------------------------------
-- Function selects optimal spell rank to cast based on unit's missing HP
-------------------------------------------------------------------------------
-- spell	- spell name to cast ("Healing Wave")
-- unit	 	- unitId ("player", "target", ...)
-- overheal	- overheal multiplier. If nil, then using self.db.account.overheal.
-------------------------------------------------------------------------------
function SmartHealer:GetOptimalRank(spell, unit, possibleExplicitOverheal)
    if not libSC.data[spell] then
        self:Print('smartheal rank not found')
        return
    end

    local bonus, power, mod
    if TheoryCraft == nil then
        bonus = tonumber(libIB:GetBonus("HEAL"))
        power, mod = libHC:GetUnitSpellPower(unit, spell)
        local buffpower, buffmod = libHC:GetBuffSpellPower()
        bonus = bonus + buffpower
        mod = mod * buffmod
    end
    
    local missing = UnitHealthMax(unit) - UnitHealth(unit)
    local max_rank = tonumber(libSC.data[spell].Rank)
    local rank = max_rank

    local overheal = possibleExplicitOverheal
    if not overheal then
        local category = nil
        local unitName = UnitName(unit)
        if unitName then
            for cat, config in pairs(self.db.account.categories) do -- todo   this can be optimized by using something like self.db.account.registeredPlayers[unitName]  
                if table.contains(config.players, unitName) then
                    category = cat
                    break
                end
            end
        end

        if category then
            overheal = self.db.account.categories[category].overheal
        else
            overheal = self.db.account.overheal
        end
    end

    local mana = UnitMana("player")
    for i = max_rank, 1, -1 do
        spellData = TheoryCraft ~= nil and TheoryCraft_GetSpellDataByName(spell, i)
        if spellData then
            if mana >= spellData.manacost then
                if spellData.averagehealnocrit > (missing * overheal) then
                    rank = i
                else
                    break
                end
            else
                rank = i > 1 and i - 1 or 1
            end
        else
            local heal = (libHC.Spells[spell][i](bonus) + power) * mod
            if heal > (missing * overheal) then
                rank = i
            else
                break
            end
        end
    end
    --[[
    self:Print(spell
            .. ' rank ' .. rank
            .. ' hp ' .. math.floor(spellData.averagehealnocrit)
            .. ' hpm ' .. (spellData.averagehealnocrit / spellData.manacost)
            .. ' mana ' .. spellData.manacost )
    ]]
    return rank
end

-------------------------------------------------------------------------------
-- Support for Clique
-------------------------------------------------------------------------------
function SmartHealer:Clique_CastSpell(clique, spellName, unit)
    unit = unit or clique.unit

    if UnitExists(unit) then
        local spell, rank = libSC:GetRanklessSpellName(spellName)

        if spell and rank == nil and libHC.Spells[spell] then
            rank = self:GetOptimalRank(spellName, unit)
            if rank then
                spellName = libSC:GetSpellNameText(spell, rank)
            end
        end
    end

    self.hooks[Clique]["CastSpell"](clique, spellName, unit)
end

-------------------------------------------------------------------------------
-- Support for ClassicMouseover
-------------------------------------------------------------------------------
function SmartHealer:CM_CastSpell(cm, spellName, unit)
    if UnitExists(unit) then
        local spell, rank = libSC:GetRanklessSpellName(spellName)

        if spell and rank == nil and libHC.Spells[spell] then
            rank = self:GetOptimalRank(spellName, unit)
            if rank then
                spellName = libSC:GetSpellNameText(spell, rank)
            end
        end
    end

    self.hooks[CM]["CastSpell"](cm, spellName, unit)
end

-------------------------------------------------------------------------------
-- Support for pfUI Click-Casting
-------------------------------------------------------------------------------
function SmartHealer:pfUI_ClickAction(pfui_uf, button)
    local spellName = ""
    local key = "clickcast"

    if button == "LeftButton" then
        local unit = (this.label or "") .. (this.id or "")

        if UnitExists(unit) then
            if this.config.clickcast == "1" then
                if IsShiftKeyDown() then
                    key = key .. "_shift"
                elseif IsAltKeyDown() then
                    key = key .. "_alt"
                elseif IsControlKeyDown() then
                    key = key .. "_ctrl"
                end

                spellName = pfUI_config.unitframes[key]

                if spellName ~= "" then
                    local spell, maxDesiredRank = libSC:GetRanklessSpellName(spellName)

                    if spell and maxDesiredRank == nil and libHC.Spells[spell] then
                        local optimalRank = self:GetOptimalRank(spellName, unit)
                        if optimalRank then
                            if maxDesiredRank ~= nil then
                                -- if the user has specified a rank then consider it as the max possible rank
                                optimalRank = math.min(optimalRank, maxDesiredRank)
                            end

                            pfUI_config.unitframes[key] = libSC:GetSpellNameText(spell, optimalRank)
                        end
                    end
                end
            end
        end
    end

    self.hooks[pfUI.uf]["ClickAction"](pfui_uf, button)

    if spellName ~= "" then
        pfUI_config.unitframes[key] = spellName
    end
end

-------------------------------------------------------------------------------
-- Support for pfUI /pfcast and /pfmouse commands
-------------------------------------------------------------------------------

-- Inspired by how pfui deduces the intended target inside the implementation of /pfcast
-- Must be kept in sync with the pfui codebase   otherwise there might be cases where the
-- wrong target is assumed here thus leading to wrong healing rank calculations

-- Prepare a list of units that can be used via SpellTargetUnit
local st_units = { [1] = "player", [2] = "target", [3] = "mouseover" }
for i = 1, MAX_PARTY_MEMBERS do
    table.insert(st_units, "party" .. i)
end
for i = 1, MAX_RAID_MEMBERS do
    table.insert(st_units, "raid" .. i)
end

-- Try to find a valid (friendly) unitstring that can be used for
-- SpellTargetUnit(unit) to avoid another target switch
local function getUnitString(unit)
    for _, unitstr in pairs(st_units) do
        if UnitIsUnit(unit, unitstr) then
            return unitstr
        end
    end

    return nil
end

local function getProperTargetBasedOnMouseOver()
    local unit = "mouseover"
    if not UnitExists(unit) then
        local frame = GetMouseFocus()
        if frame.label and frame.id then
            unit = frame.label .. frame.id
        elseif UnitExists("target") then
            unit = "target"
        elseif GetCVar("autoSelfCast") == "1" then
            unit = "player"
        else
            return
        end
    end

    -- If target and mouseover are friendly units, we can't use spell target as it
    -- would cast on the target instead of the mouseover. However, if the mouseover
    -- is friendly and the target is not, we can try to obtain the best unitstring
    -- for the later SpellTargetUnit() call.
    return ((not UnitCanAssist("player", "target") and UnitCanAssist("player", unit) and getUnitString(unit)) or "player")
end

function SmartHealer:pfUI_PFCast(msg)
    local spell, maxDesiredRank = libSC:GetRanklessSpellName(msg)
    if spell and maxDesiredRank == nil and libHC.Spells[spell] then
        local unitstr = getProperTargetBasedOnMouseOver()
        if unitstr == nil then
            return
        end

        local optimalRank = SmartHealer:GetOptimalRank(msg, unitstr)
        if optimalRank then
            if maxDesiredRank ~= nil then
                -- if the user has specified a rank then consider it as the max possible rank
                optimalRank = math.min(optimalRank, maxDesiredRank)
            end

            local optimalHeal = libSC:GetSpellNameText(spell, optimalRank)
            SmartHealer.hooks[SlashCmdList]["PFCAST"](optimalHeal) -- mission accomplished
            return
        end
    end

    SmartHealer.hooks[SlashCmdList]["PFCAST"](msg) -- fallback if we can't find optimal rank
end

--------------------------------------------------------------------------------------------------------------------------------------------
-- Support for /pfquickcast:heal* family of commands - these commands are provided by the pfUI-QuickCast addon which is separate from pfUI
--------------------------------------------------------------------------------------------------------------------------------------------

local _pfGetSpellIndex = pfUI
        and pfUI.api
        and pfUI.api.libspell
        and pfUI.api.libspell.GetSpellIndex

local function tryGetOptimalSpell(spellNameRaw, maxDesiredRank, intendedTarget)
    if not spellNameRaw or not libHC.Spells[spellNameRaw] then
        return nil, nil, nil -- fallback if the spell doesnt exist in the spellbook because for example the player hasnt specced for it 
    end

    local optimalRank = SmartHealer:GetOptimalRank(spellNameRaw, intendedTarget)
    -- print("** [SmartHealer:pfUIQuickCast_OnHeal] maxDesiredRank='" .. tostring(maxDesiredRank) .. "'")

    if not optimalRank then
        return nil, nil, nil -- fallback if we can't find optimal rank
    end

    if maxDesiredRank ~= nil then
        -- if the user has specified a rank then consider it as the max possible rank
        optimalRank = math.min(optimalRank, maxDesiredRank)
    end

    local rankedSpell = libSC:GetSpellNameText(spellNameRaw, optimalRank)

    local rankedSpellId, spellBookType = _pfGetSpellIndex(spellNameRaw, "Rank " .. optimalRank)

    return rankedSpell, rankedSpellId, spellBookType
end

function SmartHealer:pfUIQuickCast_OnHeal(spell, spellId, spellBookType, proper_target)
    local spellNameRaw, maxDesiredRank = libSC:GetRanklessSpellName(spell)

    local rankedSpell, rankedSpellId, rankedSpellBookType = tryGetOptimalSpell(
            spellNameRaw,
            maxDesiredRank,
            proper_target
    )

    _pfUIQuickCast_OnHeal_orig(
            rankedSpell or spell,
            rankedSpellId or spellId,
            rankedSpellBookType or spellBookType,
            proper_target
    )
end
