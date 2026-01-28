-- Data/FarmTimeConfig.lua
-- Configuration for farm time calculations

YourAddonDB = YourAddonDB or {}
YourAddonDB.FarmConfig = {}

-- ============================================
-- GOLD VALUE SETTINGS
-- ============================================

-- How much is your time worth? (gold per hour)
-- Adjust this based on your gold-making capabilities
YourAddonDB.FarmConfig.goldPerHour = 5000

-- Multiplier for BoP materials (to account for annoyance factor)
-- 1.0 = treat farm time exactly as gold value
-- 1.5 = add 50% penalty for having to farm
YourAddonDB.FarmConfig.bopCostMultiplier = 1.2

-- ============================================
-- GATHERING RATES (items per hour)
-- ============================================

YourAddonDB.FarmConfig.farmRates = {
    -- Gathering professions
    Mining = 120,        -- Ore nodes per hour
    Herbalism = 150,     -- Herb nodes per hour
    Skinning = 200,      -- Leather per hour
    
    -- Drop rates by source type
    drop = {
        common = 80,     -- Common mob drops
        uncommon = 40,   -- Uncommon mob drops
        rare = 20,       -- Rare mob drops
        boss = 5,        -- Boss drops (per lockout)
        dungeon = 15,    -- Dungeon drops
        raid = 3,        -- Raid drops
        defaultRate = 50 -- Default if not specified
    },
    
    -- Vendor items (travel time)
    vendor = {
        nearby = 120,    -- Vendor in same zone
        far = 60,        -- Vendor in different zone
        rare = 30,       -- Limited supply vendor
        defaultRate = 80
    },
    
    -- Quest rewards
    quest = {
        short = 20,      -- Quick quest (5-10 min)
        medium = 10,     -- Normal quest (20-30 min)
        long = 5,        -- Long quest chain (1 hour+)
        defaultRate = 10
    },
}

-- ============================================
-- ITEM-SPECIFIC OVERRIDES
-- ============================================

-- For items that have known farm rates different from defaults
YourAddonDB.FarmConfig.itemOverrides = {
    -- Example: Rare crafting reagents
    -- [itemID] = items_per_hour
    
    -- The War Within specific examples:
    -- [223512] = 30,  -- Hypothetical rare crystal
    -- [223513] = 60,  -- Hypothetical common ore
}

-- ============================================
-- SOURCE TYPE KEYWORDS
-- ============================================

-- Keywords in source_info to determine farm rate
YourAddonDB.FarmConfig.sourceKeywords = {
    Mining = {"Mining", "mine", "ore", "vein"},
    Herbalism = {"Herbalism", "herb", "flower", "plant"},
    Skinning = {"Skinning", "skin", "leather", "hide"},
    
    -- Drop rarities
    rare_drop = {"rare", "elite", "boss"},
    common_drop = {"common", "normal", "Various mobs"},
    dungeon = {"dungeon", "instance"},
    raid = {"raid"},
    
    -- Vendor types
    vendor_nearby = {"vendor", "sells"},
    vendor_rare = {"limited", "limited supply"},
    
    -- Quest
    quest = {"quest", "reward"},
}

-- ============================================
-- CALCULATION FUNCTIONS
-- ============================================

function YourAddonDB.FarmConfig:GetFarmTime(itemID, quantity, sourceType, sourceInfo)
    -- Check for item-specific override
    if self.itemOverrides[itemID] then
        local rate = self.itemOverrides[itemID]
        return quantity / rate -- Returns hours
    end
    
    -- Determine rate based on source type and info
    local rate = self:GetFarmRate(sourceType, sourceInfo)
    
    -- Calculate time in hours
    local hours = quantity / rate
    
    return hours
end

function YourAddonDB.FarmConfig:GetFarmRate(sourceType, sourceInfo)
    sourceInfo = sourceInfo or ""
    sourceType = sourceType or "unknown"
    
    -- Check by source type first
    if sourceType == "gathered" then
        -- Check keywords for gathering profession
        for profession, keywords in pairs(self.sourceKeywords) do
            if profession == "Mining" or profession == "Herbalism" or profession == "Skinning" then
                for _, keyword in ipairs(keywords) do
                    if sourceInfo:lower():find(keyword:lower()) then
                        return self.farmRates[profession]
                    end
                end
            end
        end
        
        return self.farmRates.Mining -- Default to mining rate
    
    elseif sourceType == "drop" then
        -- Check drop rarity
        for rarity, keywords in pairs(self.sourceKeywords) do
            if rarity:find("drop") or rarity == "dungeon" or rarity == "raid" then
                for _, keyword in ipairs(keywords) do
                    if sourceInfo:lower():find(keyword:lower()) then
                        -- Extract rate from farmRates.drop table
                        local rateKey = rarity:gsub("_drop", "")
                        return self.farmRates.drop[rateKey] or self.farmRates.drop.defaultRate
                    end
                end
            end
        end
        
        return self.farmRates.drop.defaultRate
    
    elseif sourceType == "vendor" then
        -- Check vendor type
        for vendorType, keywords in pairs(self.sourceKeywords) do
            if vendorType:find("vendor") then
                for _, keyword in ipairs(keywords) do
                    if sourceInfo:lower():find(keyword:lower()) then
                        local rateKey = vendorType:gsub("vendor_", "")
                        return self.farmRates.vendor[rateKey] or self.farmRates.vendor.defaultRate
                    end
                end
            end
        end
        
        return self.farmRates.vendor.defaultRate
    
    elseif sourceType == "quest" then
        -- Check quest length
        if sourceInfo:lower():find("chain") or sourceInfo:lower():find("long") then
            return self.farmRates.quest.long
        elseif sourceInfo:lower():find("quick") or sourceInfo:lower():find("short") then
            return self.farmRates.quest.short
        else
            return self.farmRates.quest.medium
        end
    
    else
        -- Unknown source, use conservative estimate
        return 50 -- 50 items per hour
    end
end

function YourAddonDB.FarmConfig:GetFarmGoldCost(farmTimeHours)
    -- Convert farm time to gold equivalent
    local baseCost = farmTimeHours * self.goldPerHour
    
    -- Apply BoP multiplier (farming is annoying)
    local totalCost = baseCost * self.bopCostMultiplier
    
    return totalCost
end

function YourAddonDB.FarmConfig:FormatFarmTime(hours)
    if hours < 0.1 then
        local minutes = math.ceil(hours * 60)
        return minutes .. " minutes"
    elseif hours < 1 then
        local minutes = math.floor(hours * 60)
        return string.format("%.1f hours (~%d min)", hours, minutes)
    else
        return string.format("%.1f hours", hours)
    end
end

-- ============================================
-- SETTINGS UI HELPERS
-- ============================================

function YourAddonDB.FarmConfig:SetGoldPerHour(gold)
    self.goldPerHour = math.max(1000, math.min(100000, gold))
    
    if ProfessionOptimizerDB then
        ProfessionOptimizerDB.settings.goldPerHour = self.goldPerHour
    end
    
    print("|cFF00FF00Farm value updated:|r " .. self.goldPerHour .. "g/hour")
end

function YourAddonDB.FarmConfig:SetBoPMultiplier(multiplier)
    self.bopCostMultiplier = math.max(1.0, math.min(3.0, multiplier))
    
    if ProfessionOptimizerDB then
        ProfessionOptimizerDB.settings.bopMultiplier = self.bopCostMultiplier
    end
    
    print("|cFF00FF00BoP multiplier updated:|r " .. self.bopCostMultiplier .. "x")
end

function YourAddonDB.FarmConfig:LoadSettings()
    if ProfessionOptimizerDB and ProfessionOptimizerDB.settings then
        if ProfessionOptimizerDB.settings.goldPerHour then
            self.goldPerHour = ProfessionOptimizerDB.settings.goldPerHour
        end
        
        if ProfessionOptimizerDB.settings.bopMultiplier then
            self.bopCostMultiplier = ProfessionOptimizerDB.settings.bopMultiplier
        end
    end
end

function YourAddonDB.FarmConfig:PrintSettings()
    print("|cFFFFD700Farm Time Settings|r")
    print("  Gold per hour: " .. self.goldPerHour .. "g")
    print("  BoP multiplier: " .. self.bopCostMultiplier .. "x")
    print("")
    print("|cFF888888Use /profoptfarm to adjust|r")
end

-- ============================================
-- EXAMPLE CALCULATIONS
-- ============================================

function YourAddonDB.FarmConfig:ShowExamples()
    print("|cFFFFD700Farm Time Examples|r")
    print("")
    
    -- Example 1: Mining ore
    local miningTime = self:GetFarmTime(0, 50, "gathered", "Mining")
    local miningCost = self:GetFarmGoldCost(miningTime)
    print(string.format("50x Ore (Mining): %s = %.0fg", 
        self:FormatFarmTime(miningTime), miningCost / 10000))
    
    -- Example 2: Common drop
    local dropTime = self:GetFarmTime(0, 20, "drop", "Drops from: Various mobs")
    local dropCost = self:GetFarmGoldCost(dropTime)
    print(string.format("20x Common Drop: %s = %.0fg",
        self:FormatFarmTime(dropTime), dropCost / 10000))
    
    -- Example 3: Rare drop
    local rareTime = self:GetFarmTime(0, 5, "drop", "Drops from: Rare Elite")
    local rareCost = self:GetFarmGoldCost(rareTime)
    print(string.format("5x Rare Drop: %s = %.0fg",
        self:FormatFarmTime(rareTime), rareCost / 10000))
    
    print("")
    print("|cFF888888These are estimates based on your settings|r")
end

-- ============================================
-- SLASH COMMAND
-- ============================================

SLASH_PROFOPTFARM1 = "/profoptfarm"
SlashCmdList["PROFOPTFARM"] = function(msg)
    local config = YourAddonDB.FarmConfig
    
    if msg == "show" or msg == "" then
        config:PrintSettings()
    
    elseif msg == "examples" then
        config:ShowExamples()
    
    elseif msg:match("^gold %d+$") then
        local gold = tonumber(msg:match("%d+"))
        config:SetGoldPerHour(gold)
    
    elseif msg:match("^multiplier [%d%.]+$") then
        local mult = tonumber(msg:match("[%d%.]+"))
        config:SetBoPMultiplier(mult)
    
    else
        print("Usage:")
        print("  /profoptfarm - Show current settings")
        print("  /profoptfarm gold [amount] - Set gold/hour value")
        print("  /profoptfarm multiplier [value] - Set BoP multiplier")
        print("  /profoptfarm examples - Show example calculations")
    end
end

-- ============================================
-- INITIALIZATION
-- ============================================

-- Load settings on startup
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "ProfessionOptimizer" then
        YourAddonDB.FarmConfig:LoadSettings()
    end
end)

print("Profession Optimizer: Farm time config loaded")
