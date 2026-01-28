-- UI/AHIntegration.lua
-- Adds buttons to the Auction House window for scanning and buying materials

local AHIntegration = {}

function AHIntegration:Initialize()
    -- Wait for AH to be ready
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("AUCTION_HOUSE_SHOW")
    frame:SetScript("OnEvent", function(self, event)
        AHIntegration:OnAuctionHouseOpened()
    end)
end

function AHIntegration:OnAuctionHouseOpened()
    if self.buttonsCreated then
        return -- Already added buttons
    end
    
    -- Find the AH frame
    local ahFrame = AuctionHouseFrame
    if not ahFrame then
        print("Could not find Auction House frame")
        return
    end
    
    self:CreateScanButton(ahFrame)
    self:CreateBuyButton(ahFrame)
    
    self.buttonsCreated = true
end

-- ============================================
-- SCAN BUTTON
-- ============================================

function AHIntegration:CreateScanButton(ahFrame)
    local button = CreateFrame("Button", "ProfOptAHScanButton", ahFrame, "UIPanelButtonTemplate")
    button:SetSize(180, 30)
    button:SetPoint("BOTTOMLEFT", ahFrame, "BOTTOMLEFT", 10, 10)
    button:SetText("📊 Scan Path Materials")
    
    button:SetScript("OnClick", function()
        AHIntegration:OnScanClicked()
    end)
    
    -- Tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Scan Auction House", 1, 1, 1)
        GameTooltip:AddLine("Scans all materials needed for your optimized path", nil, nil, nil, true)
        GameTooltip:AddLine(" ", nil, nil, nil, true)
        GameTooltip:AddLine("This may take 10-15 seconds", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    self.scanButton = button
end

function AHIntegration:OnScanClicked()
    local ui = _G.ProfessionOptimizerUI
    
    if not ui or not ui.optimizedPath then
        print("Please optimize a path first (/profopt)")
        return
    end
    
    print("Scanning materials for optimized path...")
    
    -- Get all materials from path
    local materials = self:GetMaterialsFromPath(ui.optimizedPath)
    
    print(string.format("Found %d unique materials to scan", #materials))
    
    -- Scan them
    local scanner = _G.ProfessionOptimizerScanner
    if not scanner then
        print("ERROR: Scanner not loaded")
        return
    end
    
    scanner:ScanMaterials(
        materials,
        function(scanned, total)
            print(string.format("Scanning: %d/%d", scanned, total))
        end,
        function(priceCache, failedItems)
            if not ProfessionOptimizerDB then
                ProfessionOptimizerDB = {}
            end
            
            ProfessionOptimizerDB.priceCache = priceCache
            ProfessionOptimizerDB.lastAHScan = GetTime()
            
            print("|cFF00FF00Scan complete!|r")
            print(string.format("  Scanned: %d items", #materials))
            print(string.format("  Unavailable: %d items", #failedItems))
            
            -- Enable buy button
            if self.buyButton then
                self.buyButton:Enable()
            end
        end
    )
end

function AHIntegration:GetMaterialsFromPath(path)
    local materialSet = {}
    local materials = {}
    
    for _, step in ipairs(path.steps) do
        for itemId, quantity in pairs(step.recipe.materials or {}) do
            if not materialSet[itemId] then
                materialSet[itemId] = true
                table.insert(materials, itemId)
            end
        end
    end
    
    return materials
end

-- ============================================
-- BUY BUTTON
-- ============================================

function AHIntegration:CreateBuyButton(ahFrame)
    local button = CreateFrame("Button", "ProfOptAHBuyButton", ahFrame, "UIPanelButtonTemplate")
    button:SetSize(180, 30)
    button:SetPoint("LEFT", self.scanButton, "RIGHT", 10, 0)
    button:SetText("💰 Buy All Materials")
    button:Disable() -- Enable after scan
    
    button:SetScript("OnClick", function()
        AHIntegration:OnBuyClicked()
    end)
    
    -- Tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Buy All Materials", 1, 1, 1)
        GameTooltip:AddLine("Automatically purchases all materials needed for your path", nil, nil, nil, true)
        GameTooltip:AddLine(" ", nil, nil, nil, true)
        GameTooltip:AddLine("Scan first to get current prices", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    self.buyButton = button
end

function AHIntegration:OnBuyClicked()
    local ui = _G.ProfessionOptimizerUI
    
    if not ui or not ui.optimizedPath then
        print("No optimized path found")
        return
    end
    
    -- Generate shopping list from path
    local shoppingList = self:GenerateShoppingList(ui.optimizedPath)
    
    if #shoppingList == 0 then
        print("No materials to buy (all are BoP or already owned)")
        return
    end
    
    -- Show confirmation
    self:ShowBuyConfirmation(shoppingList)
end

function AHIntegration:GenerateShoppingList(path)
    local materials = {}
    
    -- Aggregate all materials
    for _, step in ipairs(path.steps) do
        local recipe = step.recipe
        for itemId, quantity in pairs(recipe.materials or {}) do
            materials[itemId] = (materials[itemId] or 0) + (quantity * step.craftsNeeded)
        end
    end
    
    -- Convert to list and filter BoP
    local shoppingList = {}
    local priceCache = ProfessionOptimizerDB and ProfessionOptimizerDB.priceCache or {}
    
    for itemId, quantity in pairs(materials) do
        local priceData = priceCache[itemId]
        
        -- Check if BoP (simplified - should check material_info)
        -- local isBoP = false -- TODO: proper BoP check
        
        if priceData and priceData.available then
            table.insert(shoppingList, {
                itemId = itemId,
                quantity = quantity,
                unitPrice = priceData.price,
                totalCost = priceData.price * quantity,
                available = priceData.quantity
            })
        end
    end
    
    return shoppingList
end

function AHIntegration:ShowBuyConfirmation(shoppingList)
    -- Calculate total cost
    local totalCost = 0
    for _, item in ipairs(shoppingList) do
        totalCost = totalCost + item.totalCost
    end
    
    local goldCost = math.floor(totalCost / 10000)
    local silverCost = math.floor((totalCost % 10000) / 100)
    
    -- Build item list text
    local itemText = ""
    for i, item in ipairs(shoppingList) do
        if i <= 5 then -- Show first 5
            itemText = itemText .. string.format("\n  %dx Item %d @ %dg", 
                item.quantity, 
                item.itemId, 
                math.floor(item.unitPrice / 10000)
            )
        end
    end
    
    if #shoppingList > 5 then
        itemText = itemText .. string.format("\n  ... and %d more items", #shoppingList - 5)
    end
    
    -- Confirmation dialog
    StaticPopupDialogs["PROFOPT_BUY_CONFIRM"] = {
        text = string.format(
            "Buy all materials?\n\nItems: %d\nTotal Cost: %dg %ds%s\n\nThis will automatically purchase from the AH.",
            #shoppingList,
            goldCost,
            silverCost,
            itemText
        ),
        button1 = "Buy All",
        button2 = "Cancel",
        OnAccept = function()
            AHIntegration:ExecutePurchases(shoppingList)
        end,
        timeout = 0,
        whileDead = false,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    
    StaticPopup_Show("PROFOPT_BUY_CONFIRM")
end

function AHIntegration:ExecutePurchases(shoppingList)
    print("|cFFFFD700Starting bulk purchase...|r")
    
    local purchased = 0
    local failed = 0
    local totalSpent = 0
    
    -- Purchase with delays to avoid rate limiting
    for i, item in ipairs(shoppingList) do
        C_Timer.After((i-1) * 0.3, function() -- 300ms between purchases
            local success = self:BuyItem(item)
            
            if success then
                purchased = purchased + 1
                totalSpent = totalSpent + item.totalCost
                print(string.format("|cFF00FF00✓|r Bought %dx Item %d", item.quantity, item.itemId))
            else
                failed = failed + 1
                print(string.format("|cFFFF0000✗|r Failed to buy Item %d", item.itemId))
            end
            
            -- Report when done
            if purchased + failed >= #shoppingList then
                print("|cFFFFD700Purchase complete!|r")
                print(string.format("  Purchased: %d items", purchased))
                print(string.format("  Failed: %d items", failed))
                print(string.format("  Total spent: %dg", math.floor(totalSpent / 10000)))
            end
        end)
    end
end

function AHIntegration:BuyItem(item)
    -- Use WoW API to purchase commodity
    local itemKey = C_AuctionHouse.MakeItemKey(item.itemId)
    
    -- Check if we have enough gold
    local playerGold = GetMoney()
    if playerGold < item.totalCost then
        print(string.format("Not enough gold for Item %d", item.itemId))
        return false
    end
    
    -- Place buy order
    C_AuctionHouse.PlaceCommodityBuyOrder(
        item.itemId,
        item.quantity,
        item.unitPrice
    )
    
    return true
end

-- ============================================
-- MATERIAL LIST PANEL (Optional)
-- ============================================

function AHIntegration:CreateMaterialListPanel(ahFrame)
    -- Small panel showing what materials are needed
    local panel = CreateFrame("Frame", "ProfOptMaterialPanel", ahFrame, "BackdropTemplate")
    panel:SetSize(200, 150)
    panel:SetPoint("BOTTOMRIGHT", ahFrame, "BOTTOMRIGHT", -10, 50)
    panel:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    panel:SetBackdropColor(0, 0, 0, 0.9)
    
    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", panel, "TOP", 0, -8)
    title:SetText("Shopping List")
    
    -- Scroll for materials
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 8)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(160, 100)
    scrollFrame:SetScrollChild(content)
    
    local text = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -5)
    text:SetWidth(150)
    text:SetJustifyH("LEFT")
    text:SetText("No path selected")
    
    panel.text = text
    self.materialPanel = panel
end

function AHIntegration:UpdateMaterialPanel()
    if not self.materialPanel then
        return
    end
    
    local ui = _G.ProfessionOptimizerUI
    if not ui or not ui.optimizedPath then
        self.materialPanel.text:SetText("No path selected\n\nOptimize a path in\n/profopt first")
        return
    end
    
    -- Generate shopping list
    local shoppingList = self:GenerateShoppingList(ui.optimizedPath)
    
    if #shoppingList == 0 then
        self.materialPanel.text:SetText("No materials needed!")
        return
    end
    
    -- Build text
    local text = ""
    local totalCost = 0
    
    for i, item in ipairs(shoppingList) do
        if i <= 8 then -- Limit display
            text = text .. string.format("%dx Item %d\n", item.quantity, item.itemId)
            totalCost = totalCost + item.totalCost
        end
    end
    
    if #shoppingList > 8 then
        text = text .. string.format("...%d more", #shoppingList - 8)
    end
    
    text = text .. string.format("\n\nTotal: %dg", math.floor(totalCost / 10000))
    
    self.materialPanel.text:SetText(text)
end

-- ============================================
-- INITIALIZATION
-- ============================================

AHIntegration:Initialize()

_G.ProfessionOptimizerAH = AHIntegration

print("Profession Optimizer: AH Integration loaded")
