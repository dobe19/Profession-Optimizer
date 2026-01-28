-- Core/ProgressTracker.lua
-- Tracks and persists progress through leveling paths

local ProgressTracker = {}

function ProgressTracker:New()
    local obj = setmetatable({}, {__index = ProgressTracker})
    obj.currentPath = nil
    obj.currentStep = 0
    obj.completedSteps = {}
    obj.craftedItems = {}
    return obj
end

-- ============================================
-- PATH MANAGEMENT
-- ============================================

function ProgressTracker:StartNewPath(profession, expansion, path)
    local charKey = self:GetCharacterKey()
    
    self.currentPath = {
        profession = profession,
        expansion = expansion,
        path = path,
        startTime = time(),
        startSkill = path.steps[1] and path.steps[1].skillBefore or 1,
        targetSkill = path.steps[#path.steps] and path.steps[#path.steps].skillAfter or 75,
        totalSteps = #path.steps,
        currentStep = 1,
        completedSteps = {},
        craftedItems = {},
        materialsUsed = {},
    }
    
    -- Save to DB
    self:SaveProgress()
    
    print("|cFF00FF00Started new path:|r " .. profession .. " (" .. expansion .. ")")
    print("  Steps: " .. self.currentPath.totalSteps)
    print("  Goal: " .. self.currentPath.startSkill .. " → " .. self.currentPath.targetSkill)
end

function ProgressTracker:LoadSavedPath(profession)
    local charKey = self:GetCharacterKey()
    
    if not ProfessionOptimizerDB or not ProfessionOptimizerDB.savedPaths then
        return false
    end
    
    local saved = ProfessionOptimizerDB.savedPaths[charKey]
    
    if not saved or not saved[profession] then
        return false
    end
    
    self.currentPath = saved[profession]
    
    print("|cFF00FF00Loaded saved path:|r " .. profession)
    print("  Progress: Step " .. self.currentPath.currentStep .. "/" .. self.currentPath.totalSteps)
    print("  Completed: " .. #self.currentPath.completedSteps .. " steps")
    
    return true
end

function ProgressTracker:SaveProgress()
    if not self.currentPath then
        return
    end
    
    local charKey = self:GetCharacterKey()
    
    if not ProfessionOptimizerDB.savedPaths[charKey] then
        ProfessionOptimizerDB.savedPaths[charKey] = {}
    end
    
    ProfessionOptimizerDB.savedPaths[charKey][self.currentPath.profession] = self.currentPath
end

function ProgressTracker:ClearPath(profession)
    local charKey = self:GetCharacterKey()
    
    if profession then
        -- Clear specific profession
        if ProfessionOptimizerDB.savedPaths[charKey] then
            ProfessionOptimizerDB.savedPaths[charKey][profession] = nil
        end
        
        if self.currentPath and self.currentPath.profession == profession then
            self.currentPath = nil
        end
    else
        -- Clear current path
        if self.currentPath then
            if ProfessionOptimizerDB.savedPaths[charKey] then
                ProfessionOptimizerDB.savedPaths[charKey][self.currentPath.profession] = nil
            end
            self.currentPath = nil
        end
    end
    
    print("|cFFFFAA00Cleared saved path|r")
end

-- ============================================
-- STEP TRACKING
-- ============================================

function ProgressTracker:CompleteStep(stepNumber)
    if not self.currentPath then
        return false
    end
    
    stepNumber = stepNumber or self.currentPath.currentStep
    
    if stepNumber > self.currentPath.totalSteps then
        print("|cFF00FF00Path complete!|r")
        self:OnPathComplete()
        return true
    end
    
    -- Mark step as completed
    if not self.currentPath.completedSteps[stepNumber] then
        table.insert(self.currentPath.completedSteps, stepNumber)
    end
    
    -- Move to next step
    self.currentPath.currentStep = math.min(stepNumber + 1, self.currentPath.totalSteps)
    
    -- Save progress
    self:SaveProgress()
    
    -- Show progress
    local step = self.currentPath.path.steps[stepNumber]
    if step then
        print(string.format("|cFF00FF00✓ Completed:|r %s (Step %d/%d)", 
            step.recipe.name, 
            stepNumber, 
            self.currentPath.totalSteps))
    end
    
    -- Check if path is complete
    if #self.currentPath.completedSteps >= self.currentPath.totalSteps then
        self:OnPathComplete()
    end
    
    return true
end

function ProgressTracker:MarkStepComplete(stepNumber)
    return self:CompleteStep(stepNumber)
end

function ProgressTracker:GetCurrentStep()
    if not self.currentPath then
        return nil
    end
    
    local stepNum = self.currentPath.currentStep
    
    if stepNum > self.currentPath.totalSteps then
        return nil
    end
    
    return self.currentPath.path.steps[stepNum], stepNum
end

function ProgressTracker:GetNextStep()
    if not self.currentPath then
        return nil
    end
    
    local nextStepNum = self.currentPath.currentStep + 1
    
    if nextStepNum > self.currentPath.totalSteps then
        return nil
    end
    
    return self.currentPath.path.steps[nextStepNum], nextStepNum
end

function ProgressTracker:GoToStep(stepNumber)
    if not self.currentPath then
        return false
    end
    
    if stepNumber < 1 or stepNumber > self.currentPath.totalSteps then
        return false
    end
    
    self.currentPath.currentStep = stepNumber
    self:SaveProgress()
    
    print("|cFF00FFFFJumped to step|r " .. stepNumber .. "/" .. self.currentPath.totalSteps)
    return true
end

-- ============================================
-- CRAFTING TRACKING
-- ============================================

function ProgressTracker:RecordCraft(spellID, itemID, quantity)
    if not self.currentPath then
        return
    end
    
    quantity = quantity or 1
    
    -- Track by spell
    if not self.currentPath.craftedItems[spellID] then
        self.currentPath.craftedItems[spellID] = {
            total = 0,
            crafts = {}
        }
    end
    
    self.currentPath.craftedItems[spellID].total = 
        self.currentPath.craftedItems[spellID].total + quantity
    
    table.insert(self.currentPath.craftedItems[spellID].crafts, {
        timestamp = time(),
        quantity = quantity,
        itemID = itemID,
    })
    
    self:SaveProgress()
end

function ProgressTracker:GetCraftCount(spellID)
    if not self.currentPath or not self.currentPath.craftedItems[spellID] then
        return 0
    end
    
    return self.currentPath.craftedItems[spellID].total
end

function ProgressTracker:CheckStepProgress(stepNumber)
    if not self.currentPath then
        return 0, 0
    end
    
    local step = self.currentPath.path.steps[stepNumber]
    
    if not step then
        return 0, 0
    end
    
    local crafted = self:GetCraftCount(step.spellId)
    local needed = step.craftsNeeded
    
    return crafted, needed
end

-- ============================================
-- MATERIAL TRACKING
-- ============================================

function ProgressTracker:RecordMaterialsUsed(materials)
    if not self.currentPath then
        return
    end
    
    for itemID, quantity in pairs(materials) do
        if not self.currentPath.materialsUsed[itemID] then
            self.currentPath.materialsUsed[itemID] = 0
        end
        
        self.currentPath.materialsUsed[itemID] = 
            self.currentPath.materialsUsed[itemID] + quantity
    end
    
    self:SaveProgress()
end

function ProgressTracker:GetRemainingMaterials()
    if not self.currentPath then
        return {}
    end
    
    local remaining = {}
    local bagScanner = _G.ProfessionOptimizerBagScanner
    
    -- Calculate total needed for remaining steps
    for i = self.currentPath.currentStep, self.currentPath.totalSteps do
        local step = self.currentPath.path.steps[i]
        
        if step then
            for itemID, quantity in pairs(step.recipe.materials or {}) do
                local needed = quantity * step.craftsNeeded
                remaining[itemID] = (remaining[itemID] or 0) + needed
            end
        end
    end
    
    -- Subtract what's in bags
    if bagScanner then
        for itemID, needed in pairs(remaining) do
            local inBags = bagScanner:GetItemCount(itemID)
            remaining[itemID] = math.max(0, needed - inBags)
        end
    end
    
    return remaining
end

-- ============================================
-- COMPLETION
-- ============================================

function ProgressTracker:OnPathComplete()
    if not self.currentPath then
        return
    end
    
    local duration = time() - self.currentPath.startTime
    local hours = math.floor(duration / 3600)
    local minutes = math.floor((duration % 3600) / 60)
    
    print("|cFF00FF00" .. string.rep("=", 50) .. "|r")
    print("|cFF00FF00🎉 PROFESSION PATH COMPLETE! 🎉|r")
    print("|cFF00FF00" .. string.rep("=", 50) .. "|r")
    print(string.format("  %s: %d → %d", 
        self.currentPath.profession,
        self.currentPath.startSkill,
        self.currentPath.targetSkill))
    print(string.format("  Time: %dh %dm", hours, minutes))
    print(string.format("  Steps completed: %d", #self.currentPath.completedSteps))
    
    -- Save to history
    self:SaveToHistory()
    
    -- Show completion dialog
    self:ShowCompletionDialog()
end

function ProgressTracker:SaveToHistory()
    if not self.currentPath then
        return
    end
    
    local charKey = self:GetCharacterKey()
    
    if not ProfessionOptimizerDB.progress[charKey] then
        ProfessionOptimizerDB.progress[charKey] = {}
    end
    
    table.insert(ProfessionOptimizerDB.progress[charKey], {
        profession = self.currentPath.profession,
        expansion = self.currentPath.expansion,
        startSkill = self.currentPath.startSkill,
        endSkill = self.currentPath.targetSkill,
        startTime = self.currentPath.startTime,
        endTime = time(),
        duration = time() - self.currentPath.startTime,
        stepsCompleted = #self.currentPath.completedSteps,
        totalSteps = self.currentPath.totalSteps,
    })
    
    -- Clear current path after saving to history
    self:ClearPath(self.currentPath.profession)
end

function ProgressTracker:ShowCompletionDialog()
    StaticPopupDialogs["PROFOPT_PATH_COMPLETE"] = {
        text = "|cFF00FF00Path Complete!|r\n\nCongratulations on leveling your profession!\n\nWhat would you like to do?",
        button1 = "Start New Path",
        button2 = "View History",
        button3 = "Close",
        OnAccept = function()
            -- Open main UI
            if _G.ProfessionOptimizerUI then
                _G.ProfessionOptimizerUI:Toggle()
            end
        end,
        OnCancel = function()
            -- Show history
            ProgressTracker:ShowHistory()
        end,
        timeout = 0,
        whileDead = false,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    
    StaticPopup_Show("PROFOPT_PATH_COMPLETE")
end

-- ============================================
-- HISTORY & STATISTICS
-- ============================================

function ProgressTracker:ShowHistory()
    local charKey = self:GetCharacterKey()
    
    if not ProfessionOptimizerDB.progress[charKey] then
        print("No history found")
        return
    end
    
    local history = ProfessionOptimizerDB.progress[charKey]
    
    print("|cFFFFD700=== Profession Leveling History ===|r")
    
    for i, record in ipairs(history) do
        local hours = math.floor(record.duration / 3600)
        local minutes = math.floor((record.duration % 3600) / 60)
        
        print(string.format("[%d] %s (%s): %d → %d | %dh %dm",
            i,
            record.profession,
            record.expansion or "Unknown",
            record.startSkill,
            record.endSkill,
            hours,
            minutes))
    end
end

function ProgressTracker:GetStatistics()
    local charKey = self:GetCharacterKey()
    
    if not ProfessionOptimizerDB.progress[charKey] then
        return {}
    end
    
    local stats = {
        totalPaths = 0,
        totalTime = 0,
        totalSkillPoints = 0,
        byProfession = {},
    }
    
    for _, record in ipairs(ProfessionOptimizerDB.progress[charKey]) do
        stats.totalPaths = stats.totalPaths + 1
        stats.totalTime = stats.totalTime + record.duration
        stats.totalSkillPoints = stats.totalSkillPoints + (record.endSkill - record.startSkill)
        
        if not stats.byProfession[record.profession] then
            stats.byProfession[record.profession] = {
                count = 0,
                totalTime = 0,
                totalSkill = 0,
            }
        end
        
        stats.byProfession[record.profession].count = 
            stats.byProfession[record.profession].count + 1
        stats.byProfession[record.profession].totalTime = 
            stats.byProfession[record.profession].totalTime + record.duration
        stats.byProfession[record.profession].totalSkill = 
            stats.byProfession[record.profession].totalSkill + (record.endSkill - record.startSkill)
    end
    
    return stats
end

-- ============================================
-- PROGRESS DISPLAY
-- ============================================

function ProgressTracker:GetProgressText()
    if not self.currentPath then
        return "No active path"
    end
    
    local step, stepNum = self:GetCurrentStep()
    
    if not step then
        return "Path complete!"
    end
    
    local text = string.format("|cFFFFD700Current Progress|r\n")
    text = text .. string.format("  Profession: %s\n", self.currentPath.profession)
    text = text .. string.format("  Step: %d/%d\n", stepNum, self.currentPath.totalSteps)
    text = text .. string.format("  Current: %s\n", step.recipe.name)
    
    local crafted, needed = self:CheckStepProgress(stepNum)
    text = text .. string.format("  Crafted: %d/%d\n", crafted, needed)
    
    local completed = #self.currentPath.completedSteps
    local percent = math.floor((completed / self.currentPath.totalSteps) * 100)
    text = text .. string.format("  Overall: %d%% complete", percent)
    
    return text
end

function ProgressTracker:PrintProgress()
    print(self:GetProgressText())
end

-- ============================================
-- UTILITIES
-- ============================================

function ProgressTracker:GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm
end

function ProgressTracker:HasSavedPath(profession)
    local charKey = self:GetCharacterKey()
    
    if not ProfessionOptimizerDB or not ProfessionOptimizerDB.savedPaths then
        return false
    end
    
    local saved = ProfessionOptimizerDB.savedPaths[charKey]
    
    return saved and saved[profession] ~= nil
end

-- ============================================
-- SLASH COMMANDS
-- ============================================

SLASH_PROFOPTPROGRESS1 = "/profoptprogress"
SLASH_PROFOPTPROGRESS2 = "/pop"
SlashCmdList["PROFOPTPROGRESS"] = function(msg)
    local tracker = _G.ProfessionOptimizerProgress
    if not tracker then
        print("Progress tracker not loaded")
        return
    end
    
    if msg == "show" or msg == "" then
        tracker:PrintProgress()
    elseif msg == "history" then
        tracker:ShowHistory()
    elseif msg == "clear" then
        tracker:ClearPath()
    elseif msg:match("^complete %d+$") then
        local stepNum = tonumber(msg:match("%d+"))
        tracker:CompleteStep(stepNum)
    elseif msg:match("^goto %d+$") then
        local stepNum = tonumber(msg:match("%d+"))
        tracker:GoToStep(stepNum)
    else
        print("Usage:")
        print("  /profoptprogress - Show current progress")
        print("  /profoptprogress history - Show completion history")
        print("  /profoptprogress clear - Clear current path")
        print("  /profoptprogress complete [step] - Mark step complete")
        print("  /profoptprogress goto [step] - Jump to step")
    end
end

-- ============================================
-- EXPORT
-- ============================================

_G.ProfessionOptimizerProgress = ProgressTracker

return ProgressTracker
