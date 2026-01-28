-- Core/PathOptimizer.lua
-- Dynamic Programming algorithm for optimal profession leveling paths
-- Supports farm vs buy comparison and async execution

local PathOptimizer = {}
PathOptimizer.__index = PathOptimizer

-- State for async calculation
local currentCalculation = nil

function PathOptimizer:New()
    local obj = setmetatable({}, self)
    obj.recipes = nil
    obj.auctionPrices = {}
    obj.farmConfig = nil
    return obj
end

-- ============================================
-- INITIALIZATION
-- ============================================

function PathOptimizer:Initialize(profession, currentSkill, targetSkill, options)
    self.profession = profession
    self.currentSkill = currentSkill
    self.targetSkill = targetSkill
    
    -- Options
    self.options = options or {}
    self.options.allowFarming = self.options.allowFarming or false
    self.options.showBothPaths = self.options.showBothPaths or true
    self.options.goldPerHour = self.options.goldPerHour or 5000
    
    -- Get recipes for this profession
    self.recipes = YourAddonDB.Recipes[profession]
    if not self.recipes then
        error("No recipe data for profession: " .. profession)
    end
    
    -- Get farm config
    self.farmConfig = YourAddonDB.FarmConfig
    
    return true
end

-- ============================================
-- RECIPE FILTERING & PREPROCESSING
-- ============================================

function PathOptimizer:GetAvailableRecipes(skillLevel)
    local available = {}
    
    for spellId, recipe in pairs(self.recipes) do
        -- Recipe must be learnable at current skill
        if recipe.skillRequired <= skillLevel then
            -- Must still give skill points
            local skillGain = recipe.skillGain or {skillLevel, skillLevel + 25, skillLevel + 50, skillLevel + 75}
            if skillLevel < skillGain[4] then -- Grey threshold
                table.insert(available, {
                    spellId = spellId,
                    recipe = recipe
                })
            end
        end
    end
    
    return available
end

function PathOptimizer:CalculateExpectedSkillGain(recipe, currentSkill)
    local skillGain = recipe.skillGain or {1, 25, 50, 75}
    local orange, yellow, green, grey = skillGain[1], skillGain[2], skillGain[3], skillGain[4]
    
    if currentSkill < orange then
        return 1.0 -- 100% chance, always 1 skill point
    elseif currentSkill < yellow then
        return 0.75 -- ~75% chance
    elseif currentSkill < green then
        return 0.33 -- ~33% chance
    elseif currentSkill < grey then
        return 0.1 -- ~10% chance
    else
        return 0 -- No skill gain (grey)
    end
end

-- ============================================
-- COST CALCULATION
-- ============================================

function PathOptimizer:CalculateRecipeCost(recipe, includeBoP)
    local totalGoldCost = 0
    local totalFarmTime = 0
    local hasUnavailableMats = false
    local bopMats = {}
    
    for itemId, quantity in pairs(recipe.materials or {}) do
        local matInfo = recipe.material_info and recipe.material_info[itemId]
        local binding = matInfo and matInfo.binding or "none"
        
        if binding == "bop" then
            if not includeBoP then
                -- User doesn't want to farm, recipe is unavailable
                return nil, nil, true
            end
            
            -- Calculate farm time and gold equivalent
            local sourceType = matInfo.source_type or "unknown"
            local sourceInfo = matInfo.source_info or ""
            
            local farmTime = self.farmConfig:GetFarmTime(itemId, quantity, sourceType, sourceInfo)
            local farmGoldValue = self.farmConfig:GetFarmGoldCost(farmTime)
            
            totalFarmTime = totalFarmTime + farmTime
            totalGoldCost = totalGoldCost + farmGoldValue
            
            table.insert(bopMats, {
                itemId = itemId,
                quantity = quantity,
                farmTime = farmTime,
                farmGoldValue = farmGoldValue,
                name = matInfo.name or ("Item " .. itemId),
                sourceInfo = sourceInfo
            })
        else
            -- BoE or tradeable - get AH price
            local ahPrice = self.auctionPrices[itemId]
            
            if not ahPrice or ahPrice == 0 then
                -- Not on AH or price unknown
                hasUnavailableMats = true
                ahPrice = 999999 -- Penalty for unavailable items
            end
            
            totalGoldCost = totalGoldCost + (ahPrice * quantity)
        end
    end
    
    return totalGoldCost, totalFarmTime, hasUnavailableMats, bopMats
end

-- ============================================
-- DYNAMIC PROGRAMMING CORE
-- ============================================

function PathOptimizer:StartCalculation(callback, progressCallback)
    currentCalculation = {
        currentSkill = self.currentSkill,
        targetSkill = self.targetSkill,
        profession = self.profession,
        
        -- DP tables (one for AH-only, one for AH+Farm)
        dpTableAH = {},      -- AH-only path
        dpTableFarm = {},    -- Allow farming path
        
        -- State tracking
        state = self.currentSkill,
        
        -- Callbacks
        callback = callback,
        progressCallback = progressCallback,
        
        -- Reference to optimizer
        optimizer = self,
        
        -- Start time
        startTime = GetTime()
    }
    
    -- Initialize DP base case
    currentCalculation.dpTableAH[self.targetSkill] = {
        cost = 0,
        farmTime = 0,
        recipe = nil,
        path = {}
    }
    currentCalculation.dpTableFarm[self.targetSkill] = {
        cost = 0,
        farmTime = 0,
        recipe = nil,
        path = {}
    }
    
    -- Start async processing
    self:ScheduleNextChunk()
end

function PathOptimizer:ScheduleNextChunk()
    C_Timer.After(0, function()
        self:ProcessChunk()
    end)
end

function PathOptimizer:ProcessChunk()
    if not currentCalculation then return end
    
    local maxTimeMs = 16 -- One frame at 60fps
    local startTime = debugprofilestop()
    
    -- Process skill levels in reverse (target -> current)
    while (debugprofilestop() - startTime) < maxTimeMs do
        local done = self:CalculateNextSkillLevel(currentCalculation)
        
        if done then
            -- Calculation complete!
            local result = self:BuildFinalResult(currentCalculation)
            currentCalculation.callback(result)
            currentCalculation = nil
            return
        end
    end
    
    -- Report progress
    if currentCalculation.progressCallback then
        local progress = (currentCalculation.targetSkill - currentCalculation.state) / 
                        (currentCalculation.targetSkill - currentCalculation.currentSkill)
        currentCalculation.progressCallback(progress)
    end
    
    -- Schedule next chunk
    self:ScheduleNextChunk()
end

function PathOptimizer:CalculateNextSkillLevel(calc)
    -- Working backwards from target to current
    local skillLevel = calc.state
    
    if skillLevel < calc.currentSkill then
        return true -- Done!
    end
    
    -- Get all recipes available at this skill level
    local available = calc.optimizer:GetAvailableRecipes(skillLevel)
    
    -- Calculate optimal choice for AH-only path
    calc.dpTableAH[skillLevel] = calc.optimizer:FindOptimalRecipe(
        skillLevel, 
        available, 
        calc.dpTableAH, 
        false -- No farming
    )
    
    -- Calculate optimal choice for AH+Farm path
    calc.dpTableFarm[skillLevel] = calc.optimizer:FindOptimalRecipe(
        skillLevel, 
        available, 
        calc.dpTableFarm, 
        true -- Allow farming
    )
    
    -- Move to next skill level
    calc.state = calc.state - 1
    
    return false -- Not done yet
end

function PathOptimizer:FindOptimalRecipe(skillLevel, availableRecipes, dpTable, allowFarming)
    local bestCost = math.huge
    local bestEntry = nil
    
    for _, recipeData in ipairs(availableRecipes) do
        local recipe = recipeData.recipe
        local spellId = recipeData.spellId
        
        -- Calculate cost of this recipe
        local recipeCost, farmTime, unavailable, bopMats = self:CalculateRecipeCost(recipe, allowFarming)
        
        if recipeCost and not unavailable then
            -- Calculate expected skill gain
            local expectedGain = self:CalculateExpectedSkillGain(recipe, skillLevel)
            
            if expectedGain > 0 then
                -- Estimate how many crafts needed to reach next level
                local craftsNeeded = math.ceil(1 / expectedGain)
                local costForCrafts = recipeCost * craftsNeeded
                local farmTimeForCrafts = (farmTime or 0) * craftsNeeded
                
                -- Expected next skill level
                local nextSkill = math.min(skillLevel + craftsNeeded, self.targetSkill)
                
                -- Get future cost from DP table
                local futureCost = dpTable[nextSkill] and dpTable[nextSkill].cost or 0
                local futureFarmTime = dpTable[nextSkill] and dpTable[nextSkill].farmTime or 0
                
                -- Total cost
                local totalCost = costForCrafts + futureCost
                local totalFarmTime = farmTimeForCrafts + futureFarmTime
                
                if totalCost < bestCost then
                    bestCost = totalCost
                    bestEntry = {
                        cost = totalCost,
                        farmTime = totalFarmTime,
                        recipe = recipe,
                        spellId = spellId,
                        craftsNeeded = craftsNeeded,
                        bopMats = bopMats,
                        nextSkill = nextSkill
                    }
                end
            end
        end
    end
    
    -- Return best option (or expensive fallback if nothing viable)
    return bestEntry or {
        cost = math.huge,
        farmTime = 0,
        recipe = nil,
        spellId = nil
    }
end

-- ============================================
-- RESULT BUILDING
-- ============================================

function PathOptimizer:BuildFinalResult(calc)
    local result = {
        ahPath = self:BacktrackPath(calc.currentSkill, calc.targetSkill, calc.dpTableAH),
        farmPath = self:BacktrackPath(calc.currentSkill, calc.targetSkill, calc.dpTableFarm),
        calculationTime = GetTime() - calc.startTime
    }
    
    return result
end

function PathOptimizer:BacktrackPath(startSkill, targetSkill, dpTable)
    local path = {}
    local currentSkill = startSkill
    local totalCost = 0
    local totalFarmTime = 0
    
    while currentSkill < targetSkill do
        local entry = dpTable[currentSkill]
        
        if not entry or not entry.recipe then
            break -- No path found
        end
        
        table.insert(path, {
            recipe = entry.recipe,
            spellId = entry.spellId,
            craftsNeeded = entry.craftsNeeded,
            bopMats = entry.bopMats,
            skillBefore = currentSkill,
            skillAfter = entry.nextSkill
        })
        
        totalCost = entry.cost
        totalFarmTime = entry.farmTime
        currentSkill = entry.nextSkill
    end
    
    return {
        steps = path,
        totalCost = totalCost,
        totalFarmTime = totalFarmTime,
        goldEquivalent = totalCost, -- Already includes farm cost as gold
        success = (currentSkill >= targetSkill)
    }
end

-- ============================================
-- SHOPPING LIST GENERATION
-- ============================================

function PathOptimizer:GenerateShoppingList(path)
    local materials = {}
    
    for _, step in ipairs(path.steps) do
        for itemId, quantity in pairs(step.recipe.materials or {}) do
            materials[itemId] = (materials[itemId] or 0) + (quantity * step.craftsNeeded)
        end
    end
    
    -- Separate BoP from BoE
    local ahList = {}
    local farmList = {}
    
    for itemId, quantity in pairs(materials) do
        -- Need to check binding
        -- This is simplified - in real code, look up material_info
        local isBoP = false -- TODO: Check material_info from recipe
        
        if isBoP then
            table.insert(farmList, {itemId = itemId, quantity = quantity})
        else
            table.insert(ahList, {itemId = itemId, quantity = quantity})
        end
    end
    
    return {
        ahMaterials = ahList,
        farmMaterials = farmList,
        totalItems = #ahList + #farmList
    }
end

-- ============================================
-- EXPORT
-- ============================================

return PathOptimizer
