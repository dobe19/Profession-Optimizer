-- Core/Init.lua
-- Initialization, validation, and database setup

local AddonName = "ProfessionOptimizer"
local Init = {}

-- ============================================
-- DATABASE INITIALIZATION
-- ============================================

function Init:InitializeDatabase()
    -- Create global SavedVariables table
    if not ProfessionOptimizerDB then
        ProfessionOptimizerDB = {
            -- AH price cache
            priceCache = {},
            lastAHScan = 0,
            
            -- User settings
            settings = {
                goldPerHour = 50000,
                allowFarming = true,
                autoScan = true,
                showBothPaths = true,
                debugMode = false,
            },
            
            -- Saved paths (per character)
            savedPaths = {},
            
            -- Progress tracking (per character)
            progress = {},
            
            -- Bag inventory cache
            inventoryCache = {},
            lastInventoryScan = 0,
            
            -- Version info
            version = "1.0.0",
            lastUpdated = date("%Y-%m-%d"),
        }
    end
    
    -- Migration/upgrade logic
    if not ProfessionOptimizerDB.version or ProfessionOptimizerDB.version < "1.0.0" then
        self:MigrateDatabase()
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

function Init:MigrateDatabase()
    -- Handle version upgrades here
    print("|cFFFFAA00Profession Optimizer|r: Upgrading database...")
    
    -- Example: Add new fields that didn't exist in older versions
    ProfessionOptimizerDB.inventoryCache = ProfessionOptimizerDB.inventoryCache or {}
    ProfessionOptimizerDB.progress = ProfessionOptimizerDB.progress or {}
    
    ProfessionOptimizerDB.version = "1.0.0"
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
        
        -- Check if recipes table is valid
        if type(recipes) ~= "table" then
            return false, "Invalid recipe data for " .. profession
        end
        
        local recipeCount = 0
        for _ in pairs(recipes) do
            recipeCount = recipeCount + 1
        end
        
        if recipeCount == 0 then
            print("|cFFFFAA00Warning|r: No recipes found for " .. profession)
        end
    end
    
    if professionCount == 0 then
        return false, "No profession data loaded"
    end
    
    return true, professionCount .. " professions loaded"
end

function Init:ValidateProfessionSelection(profession)
    if not profession or profession == "" then
        return false, "Please select a profession"
    end
    
    if not YourAddonDB or not YourAddonDB.Recipes then
        return false, "Recipe database not loaded"
    end
    
    if not YourAddonDB.Recipes[profession] then
        return false, "No recipe data for " .. profession
    end
    
    -- Count recipes
    local count = 0
    for _ in pairs(YourAddonDB.Recipes[profession]) do
        count = count + 1
    end
    
    if count == 0 then
        return false, "No recipes available for " .. profession
    end
    
    return true, count .. " recipes available"
end

function Init:ValidateSkillRange(currentSkill, targetSkill)
    if not currentSkill or not targetSkill then
        return false, "Please enter valid skill levels"
    end
    
    if currentSkill < 1 then
        return false, "Current skill must be at least 1"
    end
    
    if targetSkill > 1000 then
        return false, "Target skill seems unrealistic (>1000)"
    end
    
    if currentSkill >= targetSkill then
        return false, "Target skill must be higher than current skill"
    end
    
    if targetSkill - currentSkill > 500 then
        return false, "Skill range too large (>500 points). Try smaller increments."
    end
    
    return true, "Valid skill range: " .. currentSkill .. " → " .. targetSkill
end

function Init:ValidateAuctionHouseAccess()
    -- Check if player is at AH
    if not C_AuctionHouse or not C_AuctionHouse.HasMaxFavorites then
        return false, "Auction House API not available"
    end
    
    return true, "AH access available"
end

-- ============================================
-- ERROR HANDLING
-- ============================================

function Init:SafeExecute(func, errorContext)
    local success, result = pcall(func)
    
    if not success then
        self:HandleError(result, errorContext)
        return false, result
    end
    
    return true, result
end

function Init:HandleError(error, context)
    local errorMsg = tostring(error)
    
    -- Log to saved variables
    if not ProfessionOptimizerDB.errorLog then
        ProfessionOptimizerDB.errorLog = {}
    end
    
    table.insert(ProfessionOptimizerDB.errorLog, {
        timestamp = time(),
        context = context or "Unknown",
        error = errorMsg,
        stack = debugstack(2)
    })
    
    -- Keep only last 20 errors
    while #ProfessionOptimizerDB.errorLog > 20 do
        table.remove(ProfessionOptimizerDB.errorLog, 1)
    end
    
    -- Display to user
    if ProfessionOptimizerDB.settings.debugMode then
        print("|cFFFF0000Error|r [" .. (context or "Unknown") .. "]: " .. errorMsg)
    else
        print("|cFFFF0000Error|r: Something went wrong. Enable debug mode for details.")
    end
end

function Init:ShowError(message, details)
    -- User-friendly error dialog
    StaticPopupDialogs["PROFOPT_ERROR"] = {
        text = "|cFFFF0000Error|r\n\n" .. message .. 
               (details and ("\n\n|cFF888888Details:|r\n" .. details) or ""),
        button1 = "OK",
        button2 = "Report Bug",
        OnAccept = function()
            -- Close dialog
        end,
        OnCancel = function()
            -- Open bug report window or copy error to clipboard
            print("Please report this error on CurseForge or GitHub")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    
    StaticPopup_Show("PROFOPT_ERROR")
end

-- ============================================
-- DEPENDENCY CHECKS
-- ============================================

function Init:CheckDependencies()
    local warnings = {}
    
    -- Check for TomTom (optional)
    if not TomTom then
        table.insert(warnings, "TomTom not found - GPS navigation will be unavailable")
    end
    
    -- Check for recipe data
    if not YourAddonDB or not YourAddonDB.Recipes then
        table.insert(warnings, "Recipe data not loaded - addon will not work!")
    end
    
    -- Check WoW version
    local version, build, date, tocVersion = GetBuildInfo()
    if tocVersion < 110002 then
        table.insert(warnings, "Old WoW version detected - some features may not work")
    end
    
    -- Display warnings
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
-- SYSTEM STATUS
-- ============================================

function Init:GetSystemStatus()
    local status = {
        recipeDataLoaded = false,
        recipeCount = 0,
        ahDataAge = 0,
        ahDataValid = false,
        tomTomAvailable = false,
        errors = {},
    }
    
    -- Check recipe data
    if YourAddonDB and YourAddonDB.Recipes then
        status.recipeDataLoaded = true
        for profession, recipes in pairs(YourAddonDB.Recipes) do
            for _ in pairs(recipes) do
                status.recipeCount = status.recipeCount + 1
            end
        end
    end
    
    -- Check AH data
    if ProfessionOptimizerDB and ProfessionOptimizerDB.lastAHScan then
        status.ahDataAge = GetTime() - ProfessionOptimizerDB.lastAHScan
        status.ahDataValid = status.ahDataAge < (15 * 60) -- 15 minutes
    end
    
    -- Check TomTom
    status.tomTomAvailable = (TomTom ~= nil)
    
    -- Check for errors
    if ProfessionOptimizerDB and ProfessionOptimizerDB.errorLog then
        status.errors = ProfessionOptimizerDB.errorLog
    end
    
    return status
end

function Init:PrintSystemStatus()
    local status = self:GetSystemStatus()
    
    print("|cFFFFD700=== Profession Optimizer Status ===|r")
    print("Recipe Data: " .. (status.recipeDataLoaded and "|cFF00FF00Loaded|r" or "|cFFFF0000Not Loaded|r"))
    
    if status.recipeDataLoaded then
        print("  Total Recipes: " .. status.recipeCount)
    end
    
    print("AH Data: " .. (status.ahDataValid and "|cFF00FF00Fresh|r" or "|cFFFFAA00Stale|r"))
    
    if status.ahDataAge > 0 then
        print("  Last Scan: " .. math.floor(status.ahDataAge / 60) .. " minutes ago")
    else
        print("  Last Scan: Never")
    end
    
    print("TomTom: " .. (status.tomTomAvailable and "|cFF00FF00Available|r" or "|cFF888888Not Installed|r"))
    
    if #status.errors > 0 then
        print("Recent Errors: |cFFFF0000" .. #status.errors .. " errors logged|r")
    end
end

-- ============================================
-- SLASH COMMAND FOR DEBUGGING
-- ============================================

SLASH_PROFOPTSTATUS1 = "/profoptstatus"
SlashCmdList["PROFOPTSTATUS"] = function(msg)
    Init:PrintSystemStatus()
end

SLASH_PROFOPTDEBUG1 = "/profoptdebug"
SlashCmdList["PROFOPTDEBUG"] = function(msg)
    if not ProfessionOptimizerDB then
        print("Database not initialized")
        return
    end
    
    ProfessionOptimizerDB.settings.debugMode = not ProfessionOptimizerDB.settings.debugMode
    print("Debug mode: " .. (ProfessionOptimizerDB.settings.debugMode and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
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
		
		if _G.ProgressTracker and not _G.ProfessionOptimizerProgress then
            _G.ProfessionOptimizerProgress = _G.ProgressTracker:New()
        end
		
    elseif event == "PLAYER_LOGIN" then
        -- Validate after everything is loaded
        local valid, message = Init:ValidateRecipeData()
        if not valid then
            Init:ShowError("Recipe data validation failed", message)
        end
    end
end)

-- Export
_G.ProfessionOptimizerInit = Init

return Init

-- ============================================
-- GLOBAL SLASH COMMANDS
-- ============================================

SLASH_PROFOPT1 = "/profopt"
SLASH_PROFOPT2 = "/po"
SlashCmdList["PROFOPT"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "gps" then
        -- Toggle GPS proximity tracking
        if ProfessionOptimizerGPS.proximityTimer then
            ProfessionOptimizerGPS:StopProximityTracking()
            print("GPS Tracking: |cFFFF0000OFF|r")
        else
            ProfessionOptimizerGPS:StartProximityTracking()
            print("GPS Tracking: |cFF00FF00ON|r")
        end
    elseif cmd == "ui" or cmd == "" then
        -- This will open your MainFrame once we finalize it
        if ProfessionOptimizerUI and ProfessionOptimizerUI.MainFrame then
            if ProfessionOptimizerUI.MainFrame:IsShown() then
                ProfessionOptimizerUI.MainFrame:Hide()
            else
                ProfessionOptimizerUI.MainFrame:Show()
            end
        else
            print("UI not yet loaded. Use /pop to see text-based progress.")
        end
    else
        print("Profession Optimizer Commands:")
        print("  /po - Toggle UI")
        print("  /po gps - Toggle GPS proximity tracking")
        print("  /pop - View character progress (ProgressTracker)")
    end
end