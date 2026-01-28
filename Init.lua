-- Init.lua
-- Initialization and database setup

local AddonName = "ProfessionOptimizer"
local Init = {}

-- ============================================
-- DATABASE INITIALIZATION
-- ============================================

function Init:InitializeDatabase()
    -- Create global SavedVariables table
    if not ProfessionOptimizerDB then
        ProfessionOptimizerDB = {
            priceCache = {},
            lastAHScan = 0,
            
            settings = {
                goldPerHour = 5000,
                allowFarming = true,
                autoScan = true,
                showBothPaths = true,
                debugMode = false,
            },
            
            savedPaths = {},
            progress = {},
            inventoryCache = {},
            lastInventoryScan = 0,
            
            version = "1.1.0",
            lastUpdated = date("%Y-%m-%d"),
        }
    end
    
    -- Character-specific initialization
    local charKey = self:GetCharacterKey()
    
    if not ProfessionOptimizerDB.savedPaths[charKey] then
        ProfessionOptimizerDB.savedPaths[charKey] = {}
    end
    
    if not ProfessionOptimizerDB.progress[charKey] then
        ProfessionOptimizerDB.progress[charKey] = {}
    end
    
    if not ProfessionOptimizerDB.inventoryCache[charKey] then
        ProfessionOptimizerDB.inventoryCache[charKey] = {}
    end
    
    print("|cFF00FF00Profession Optimizer|r: Database initialized")
end

function Init:GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm
end

-- ============================================
-- VALIDATION FUNCTIONS
-- ============================================

function Init:ValidateRecipeData()
    if not YourAddonDB then
        return false, "Recipe database not loaded"
    end
    
    if not YourAddonDB.Recipes then
        return false, "No recipe data found"
    end
    
    local professionCount = 0
    for profession, recipes in pairs(YourAddonDB.Recipes) do
        professionCount = professionCount + 1
        
        if type(recipes) ~= "table" then
            return false, "Invalid recipe data for " .. profession
        end
    end
    
    if professionCount == 0 then
        return false, "No profession data loaded"
    end
    
    return true, professionCount .. " professions loaded"
end

function Init:ValidateSkillRange(currentSkill, targetSkill)
    if not currentSkill or not targetSkill then
        return false, "Please enter valid skill levels"
    end
    
    if currentSkill < 1 then
        return false, "Current skill must be at least 1"
    end
    
    if currentSkill >= targetSkill then
        return false, "Target skill must be higher than current skill"
    end
    
    return true
end

-- ============================================
-- ERROR HANDLING
-- ============================================

function Init:HandleError(error, context)
    local errorMsg = tostring(error)
    
    if not ProfessionOptimizerDB.errorLog then
        ProfessionOptimizerDB.errorLog = {}
    end
    
    table.insert(ProfessionOptimizerDB.errorLog, {
        timestamp = time(),
        context = context or "Unknown",
        error = errorMsg,
    })
    
    -- Keep only last 20 errors
    while #ProfessionOptimizerDB.errorLog > 20 do
        table.remove(ProfessionOptimizerDB.errorLog, 1)
    end
    
    if ProfessionOptimizerDB.settings.debugMode then
        print("|cFFFF0000Error|r [" .. (context or "Unknown") .. "]: " .. errorMsg)
    end
end

-- ============================================
-- DEPENDENCY CHECKS
-- ============================================

function Init:CheckDependencies()
    local warnings = {}
    
    if not TomTom then
        table.insert(warnings, "TomTom not found - GPS navigation unavailable")
    end
    
    if not YourAddonDB or not YourAddonDB.Recipes then
        table.insert(warnings, "Recipe data not loaded - addon will not work!")
    end
    
    if #warnings > 0 then
        C_Timer.After(2, function()
            print("|cFFFFAA00Profession Optimizer Warnings:|r")
            for _, warning in ipairs(warnings) do
                print("  • " .. warning)
            end
        end)
    end
    
    return #warnings == 0
end

-- ============================================
-- INITIALIZATION ON LOAD
-- ============================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == AddonName then
        Init:InitializeDatabase()
        Init:CheckDependencies()
        
        -- Initialize modules with proper globals
        if not _G.ProfessionOptimizerScanner then
            local AuctionScanner = {} -- Placeholder until loaded
            AuctionScanner.__index = AuctionScanner
            function AuctionScanner:New()
                return setmetatable({
                    priceCache = {},
                    scanCallbacks = {},
                }, self)
            end
            _G.ProfessionOptimizerScanner = AuctionScanner:New()
        end
        
    elseif event == "PLAYER_LOGIN" then
        local valid, message = Init:ValidateRecipeData()
        if not valid then
            print("|cFFFF0000Profession Optimizer Error:|r " .. message)
        else
            print("|cFF00FF00Profession Optimizer loaded!|r Type /profopt to open")
        end
    end
end)

-- Export
_G.ProfessionOptimizerInit = Init

-- ============================================
-- SLASH COMMANDS
-- ============================================

SLASH_PROFOPT1 = "/profopt"
SLASH_PROFOPT2 = "/po"
SlashCmdList["PROFOPT"] = function(msg)
    local cmd = msg:lower()

    if cmd == "status" then
        if Init.ValidateRecipeData then
            local valid, message = Init:ValidateRecipeData()
            print("Recipe Data: " .. (valid and "|cFF00FF00OK|r" or "|cFFFF0000" .. message .. "|r"))
        end
        
    elseif cmd == "debug" then
        ProfessionOptimizerDB.settings.debugMode = not ProfessionOptimizerDB.settings.debugMode
        print("Debug mode: " .. (ProfessionOptimizerDB.settings.debugMode and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
        
    else
        if _G.ProfessionOptimizerUI then
            _G.ProfessionOptimizerUI:Toggle()
        else
            print("UI not loaded yet. Type /profopt status to check addon state")
        end
    end
end
