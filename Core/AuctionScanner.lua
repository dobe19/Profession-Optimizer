-- Core/AuctionScanner.lua
-- Fixed version with proper module initialization

local AuctionScanner = {}
AuctionScanner.__index = AuctionScanner

function AuctionScanner:New()
    local obj = setmetatable({}, self)
    obj.priceCache = {}
    obj.scanCallbacks = {}
    obj.frame = nil
    return obj
end

function AuctionScanner:Initialize()
    self.frame = CreateFrame("Frame")
    self.frame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
    self.frame:SetScript("OnEvent", function(frame, event, itemID)
        self:OnCommodityDataReceived(itemID)
    end)
    return true
end

function AuctionScanner:GetItemPrice(itemID)
    local cached = self.priceCache[itemID]
    if cached and (GetTime() - cached.timestamp) < 300 then
        return cached.price, cached.quantity, cached.available
    end
    
    if cached then
        return cached.price, cached.quantity, cached.available
    end
    
    return nil, 0, false
end

function AuctionScanner:RequestPrice(itemID, callback)
    if not self.scanCallbacks[itemID] then
        self.scanCallbacks[itemID] = {}
    end
    table.insert(self.scanCallbacks[itemID], callback)
    
    local itemKey = C_AuctionHouse.MakeItemKey(itemID)
    C_AuctionHouse.RequestMoreCommoditySearchResults(itemKey)
    
    C_Timer.After(5, function()
        if self.scanCallbacks[itemID] then
            self:OnCommodityDataReceived(itemID, true)
        end
    end)
end

function AuctionScanner:OnCommodityDataReceived(itemID, forceUnavailable)
    local numResults = 0
    
    if not forceUnavailable then
        numResults = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    end
    
    if numResults == 0 then
        self.priceCache[itemID] = {
            available = false,
            price = 0,
            quantity = 0,
            timestamp = GetTime()
        }
    else
        local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
        
        if result then
            self.priceCache[itemID] = {
                available = true,
                price = result.unitPrice,
                quantity = result.quantity,
                numAuctions = numResults,
                timestamp = GetTime()
            }
        end
    end
    
    local callbacks = self.scanCallbacks[itemID]
    if callbacks then
        local priceData = self.priceCache[itemID]
        for _, callback in ipairs(callbacks) do
            callback(itemID, priceData)
        end
        self.scanCallbacks[itemID] = nil
    end
end

function AuctionScanner:ScanMaterials(itemList, progressCallback, completeCallback)
    local totalItems = #itemList
    local scannedCount = 0
    local failedItems = {}
    
    local function onItemScanned(itemID, priceData)
        scannedCount = scannedCount + 1
        
        if not priceData or not priceData.available then
            table.insert(failedItems, itemID)
        end
        
        if progressCallback then
            progressCallback(scannedCount, totalItems)
        end
        
        if scannedCount >= totalItems then
            if completeCallback then
                completeCallback(self.priceCache, failedItems)
            end
        end
    end
    
    for i, itemID in ipairs(itemList) do
        C_Timer.After((i-1) * 0.2, function()
            self:RequestPrice(itemID, onItemScanned)
        end)
    end
end

function AuctionScanner:GetAllMaterialsForProfession(profession)
    local materials = {}
    local materialSet = {}
    
    if not YourAddonDB or not YourAddonDB.Recipes then
        return materials
    end
    
    local recipes = YourAddonDB.Recipes[profession]
    if not recipes then
        return materials
    end
    
    for spellId, recipe in pairs(recipes) do
        for itemId, quantity in pairs(recipe.materials or {}) do
            if not materialSet[itemId] then
                materialSet[itemId] = true
                table.insert(materials, itemId)
            end
        end
    end
    
    return materials
end

-- Create and export global instance
if not _G.ProfessionOptimizerScanner then
    local scanner = AuctionScanner:New()
    scanner:Initialize()
    _G.ProfessionOptimizerScanner = scanner
    print("Profession Optimizer: AuctionScanner initialized")
end
