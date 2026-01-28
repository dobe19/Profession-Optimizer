-- Core/BagScanner.lua
-- Scans player bags and bank for materials

local BagScanner = {}

function BagScanner:New()
    local obj = setmetatable({}, {__index = BagScanner})
    obj.inventory = {}
    obj.lastScan = 0
    obj.scanInProgress = false
    return obj
end

-- ============================================
-- INVENTORY SCANNING
-- ============================================

function BagScanner:ScanInventory(includeBank)
    self.scanInProgress = true
    self.inventory = {}
    
    -- Scan all bags (0-4)
    for bag = 0, 4 do
        self:ScanBag(bag)
    end
    
    -- Scan bank if requested and available
    if includeBank then
        -- Bank bags are 5-11 (deprecated, now uses -1, 6-12)
        -- Use modern API
        if C_Bank and C_Bank.FetchNumPurchasedBankTabs then
            -- Scan main bank (-1)
            self:ScanBag(-1)
            
            -- Scan purchased bank tabs (6-12)
            for bag = 6, 12 do
                self:ScanBag(bag)
            end
        else
            -- Fallback for older API
            for bag = 5, 11 do
                self:ScanBag(bag)
            end
        end
    end
    
    -- Scan reagent bank if available
    if IsReagentBankUnlocked and IsReagentBankUnlocked() then
        self:ScanReagentBank()
    end
    
    self.lastScan = GetTime()
    self.scanInProgress = false
    
    -- Save to character cache
    local charKey = self:GetCharacterKey()
    if ProfessionOptimizerDB then
        ProfessionOptimizerDB.inventoryCache[charKey] = {
            inventory = self.inventory,
            timestamp = self.lastScan,
        }
    end
    
    return self.inventory
end

function BagScanner:ScanBag(bagID)
    local numSlots = C_Container.GetContainerNumSlots(bagID)
    
    if not numSlots or numSlots == 0 then
        return
    end
    
    for slot = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        
        if info and info.itemID then
            local itemID = info.itemID
            local stackCount = info.stackCount or 1
            
            -- Add to inventory
            if not self.inventory[itemID] then
                self.inventory[itemID] = {
                    total = 0,
                    locations = {}
                }
            end
            
            self.inventory[itemID].total = self.inventory[itemID].total + stackCount
            
            table.insert(self.inventory[itemID].locations, {
                bag = bagID,
                slot = slot,
                count = stackCount
            })
        end
    end
end

function BagScanner:ScanReagentBank()
    -- Reagent bank is bag -3
    if not C_Container.GetContainerNumSlots then
        return
    end
    
    local numSlots = C_Container.GetContainerNumSlots(Enum.BagIndex.Reagentbank) or 98
    
    for slot = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(Enum.BagIndex.Reagentbank, slot)
        
        if info and info.itemID then
            local itemID = info.itemID
            local stackCount = info.stackCount or 1
            
            if not self.inventory[itemID] then
                self.inventory[itemID] = {
                    total = 0,
                    locations = {}
                }
            end
            
            self.inventory[itemID].total = self.inventory[itemID].total + stackCount
            
            table.insert(self.inventory[itemID].locations, {
                bag = "reagent",
                slot = slot,
                count = stackCount
            })
        end
    end
end

-- ============================================
-- QUERY FUNCTIONS
-- ============================================

function BagScanner:GetItemCount(itemID)
    if not self.inventory[itemID] then
        return 0
    end
    
    return self.inventory[itemID].total
end

function BagScanner:HasItem(itemID, requiredCount)
    local count = self:GetItemCount(itemID)
    return count >= (requiredCount or 1)
end

function BagScanner:GetMissingMaterials(shoppingList)
    -- Returns items that need to be bought
    local missing = {}
    
    for itemID, needed in pairs(shoppingList) do
        local inBags = self:GetItemCount(itemID)
        local stillNeeded = math.max(0, needed - inBags)
        
        if stillNeeded > 0 then
            missing[itemID] = stillNeeded
        end
    end
    
    return missing
end

function BagScanner:GenerateShoppingListWithInventory(path)
    -- Generate shopping list accounting for what player already has
    local totalNeeded = {}
    
    -- Calculate total materials needed
    for _, step in ipairs(path.steps or {}) do
        for itemID, quantity in pairs(step.recipe.materials or {}) do
            totalNeeded[itemID] = (totalNeeded[itemID] or 0) + (quantity * step.craftsNeeded)
        end
    end
    
    -- Subtract what player already has
    local toBuy = {}
    local have = {}
    
    for itemID, needed in pairs(totalNeeded) do
        local inBags = self:GetItemCount(itemID)
        
        have[itemID] = inBags
        
        if inBags < needed then
            toBuy[itemID] = needed - inBags
        end
    end
    
    return {
        totalNeeded = totalNeeded,
        inInventory = have,
        toBuy = toBuy,
    }
end

-- ============================================
-- AUTO-SCAN TRIGGERS
-- ============================================

function BagScanner:EnableAutoScan()
    if self.autoScanFrame then
        return -- Already enabled
    end
    
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("BAG_UPDATE")
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("BANKFRAME_OPENED")
    frame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    
    frame:SetScript("OnEvent", function(self, event, ...)
        -- Debounce: only scan once per second
        if not BagScanner.nextScanTime then
            BagScanner.nextScanTime = GetTime() + 1
        end
        
        if GetTime() >= BagScanner.nextScanTime then
            BagScanner:ScanInventory(false) -- Don't include bank unless at bank
            BagScanner.nextScanTime = GetTime() + 1
        end
    end)
    
    self.autoScanFrame = frame
    print("Profession Optimizer: Auto-scan enabled")
end

function BagScanner:DisableAutoScan()
    if self.autoScanFrame then
        self.autoScanFrame:UnregisterAllEvents()
        self.autoScanFrame = nil
        print("Profession Optimizer: Auto-scan disabled")
    end
end

-- ============================================
-- CACHE MANAGEMENT
-- ============================================

function BagScanner:GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm
end

function BagScanner:LoadCachedInventory()
    local charKey = self:GetCharacterKey()
    
    if ProfessionOptimizerDB and ProfessionOptimizerDB.inventoryCache[charKey] then
        local cached = ProfessionOptimizerDB.inventoryCache[charKey]
        
        -- Use cache if less than 5 minutes old
        if cached.timestamp and (GetTime() - cached.timestamp) < 300 then
            self.inventory = cached.inventory or {}
            self.lastScan = cached.timestamp
            return true
        end
    end
    
    return false
end

function BagScanner:InvalidateCache()
    local charKey = self:GetCharacterKey()
    
    if ProfessionOptimizerDB and ProfessionOptimizerDB.inventoryCache[charKey] then
        ProfessionOptimizerDB.inventoryCache[charKey] = nil
    end
    
    self.inventory = {}
    self.lastScan = 0
end

-- ============================================
-- DISPLAY FUNCTIONS
-- ============================================

function BagScanner:PrintInventorySummary()
    local itemCount = 0
    local totalStacks = 0
    
    for itemID, data in pairs(self.inventory) do
        itemCount = itemCount + 1
        totalStacks = totalStacks + #data.locations
    end
    
    print("|cFFFFD700Inventory Summary|r")
    print("  Unique items: " .. itemCount)
    print("  Total stacks: " .. totalStacks)
    print("  Last scan: " .. (self.lastScan > 0 and (math.floor((GetTime() - self.lastScan)) .. " seconds ago") or "Never"))
end

function BagScanner:PrintMaterialAvailability(shoppingList)
    print("|cFFFFD700Material Availability|r")
    
    local haveAll = true
    
    for itemID, needed in pairs(shoppingList) do
        local inBags = self:GetItemCount(itemID)
        local itemName = C_Item.GetItemNameByID(itemID) or ("Item " .. itemID)
        
        if inBags >= needed then
            print(string.format("  |cFF00FF00✓|r %s: %d/%d", itemName, inBags, needed))
        else
            print(string.format("  |cFFFF0000✗|r %s: %d/%d (need %d more)", 
                itemName, inBags, needed, needed - inBags))
            haveAll = false
        end
    end
    
    if haveAll then
        print("|cFF00FF00You have all materials!|r")
    else
        print("|cFFFFAA00Some materials still needed|r")
    end
end

-- ============================================
-- WARBAND BANK SUPPORT (TWW Feature)
-- ============================================

function BagScanner:ScanWarbandBank()
    -- The War Within introduced account-wide Warband Bank
    -- Bank slots are now account-wide and accessible anywhere
    
    if not C_Bank or not C_Bank.HasMaxBankTabs then
        return -- Not available in this version
    end
    
    -- Warband bank is bag index 13 (if available)
    if C_Bank.CanUseBank() then
        self:ScanBag(13)
    end
end

function BagScanner:GetWarbandMaterials(itemID)
    -- Check if item is in warband bank
    -- Warbound items can be shared between characters
    
    if not self.inventory[itemID] then
        return 0
    end
    
    local warbandCount = 0
    
    for _, location in ipairs(self.inventory[itemID].locations) do
        if location.bag == 13 or location.bag == "warband" then
            warbandCount = warbandCount + location.count
        end
    end
    
    return warbandCount
end

-- ============================================
-- EXPORT
-- ============================================

_G.ProfessionOptimizerBagScanner = BagScanner

return BagScanner
