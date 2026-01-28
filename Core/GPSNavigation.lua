-- Core/GPSNavigation.lua
-- TomTom integration for navigating to trainers, vendors, and recipe sources

local GPS = {}

function GPS:Initialize()
    self.waypointList = {}
    self.currentWaypointIndex = 1
    return true
end

-- ============================================
-- WAYPOINT GENERATION
-- ============================================

function GPS:GenerateWaypointList(path, profession, expansion)
    self.waypointList = {}
    self.currentWaypointIndex = 1
    
    if not path or not path.steps then
        return false
    end
    
    -- Get trainer location
    local trainer, trainerId = YourAddonDB:GetTrainer(profession, expansion)
    
    if trainer then
        table.insert(self.waypointList, {
            type = "trainer",
            npcId = trainerId,
            name = trainer.name,
            zone = trainer.zone,
            coords = trainer.coords,
            mapID = trainer.mapID,
            description = string.format("Learn %s recipes", profession),
            recipes = {} -- Could list specific recipes
        })
    end
    
    -- Add waypoints for each step that requires visiting a vendor
    for i, step in ipairs(path.steps) do
        local recipe = step.recipe
        
        if recipe.source == "vendor" and recipe.vendorId then
            -- Look up vendor
            local vendor = YourAddonDB.Vendors[profession]
            if vendor and vendor[expansion] and vendor[expansion][recipe.vendorId] then
                local vendorInfo = vendor[expansion][recipe.vendorId]
                
                table.insert(self.waypointList, {
                    type = "vendor",
                    npcId = recipe.vendorId,
                    name = vendorInfo.name,
                    zone = vendorInfo.zone,
                    coords = vendorInfo.coords,
                    mapID = vendorInfo.mapID,
                    description = string.format("Buy recipe: %s", recipe.name),
                    stepNumber = i
                })
            end
        end
        
        -- Add crafting checkpoints every 5 steps
        if i % 5 == 0 then
            table.insert(self.waypointList, {
                type = "checkpoint",
                stepNumber = i,
                description = string.format("Craft recipes 1-%d (Skill %d → %d)", 
                    i, 
                    path.steps[1].skillBefore,
                    step.skillAfter
                )
            })
        end
    end
    
    return true
end

-- ============================================
-- TOMTOM WAYPOINT CREATION
-- ============================================

function GPS:SetWaypoint(waypointData)
    if not TomTom then
        print("|cFFFF0000TomTom not found!|r Please install TomTom addon for GPS navigation.")
        print("You can still use this addon without it, but won't have automatic navigation.")
        return false
    end
    
    if waypointData.type == "checkpoint" then
        -- Checkpoints don't have coordinates, just print info
        print("|cFF00FFFF=== Crafting Checkpoint ===|r")
        print(waypointData.description)
        return true
    end
    
    local coords = waypointData.coords
    local mapID = waypointData.mapID
    
    if not coords or not mapID then
        print("Invalid waypoint data")
        return false
    end
    
    -- Add waypoint using TomTom
    local uid = TomTom:AddWaypoint(mapID, coords.x / 100, coords.y / 100, {
        title = waypointData.name,
        persistent = false,
        minimap = true,
        world = true,
        crazy = true
    })
    
    if uid then
        print(string.format("|cFF00FF00📍 Waypoint set:|r %s in %s", 
            waypointData.name, 
            waypointData.zone
        ))
        
        if waypointData.description then
            print("|cFF888888   " .. waypointData.description .. "|r")
        end
        
        return true
    else
        print("|cFFFF0000Failed to create waypoint|r")
        return false
    end
end

function GPS:ClearAllWaypoints()
    if not TomTom then
        return
    end
    
    -- Clear all TomTom waypoints
    TomTom:RemoveAllWaypoints()
    print("All waypoints cleared")
end

-- ============================================
-- NAVIGATION CONTROLS
-- ============================================

function GPS:GoToFirstWaypoint()
    if #self.waypointList == 0 then
        print("No waypoints in list")
        return false
    end
    
    self.currentWaypointIndex = 1
    local waypoint = self.waypointList[1]
    
    print("|cFFFFD700=== Starting GPS Navigation ===|r")
    print(string.format("Total stops: %d", #self.waypointList))
    
    return self:SetWaypoint(waypoint)
end

function GPS:GoToNextWaypoint()
    if #self.waypointList == 0 then
        print("No waypoints in list")
        return false
    end
    
    self.currentWaypointIndex = self.currentWaypointIndex + 1
    
    if self.currentWaypointIndex > #self.waypointList then
        print("|cFF00FF00✅ All waypoints complete!|r")
        print("You've reached all trainers and vendors.")
        self.currentWaypointIndex = #self.waypointList
        return false
    end
    
    local waypoint = self.waypointList[self.currentWaypointIndex]
    
    print(string.format("|cFF00FFFF[%d/%d]|r Next stop:", 
        self.currentWaypointIndex, 
        #self.waypointList
    ))
    
    return self:SetWaypoint(waypoint)
end

function GPS:GoToPreviousWaypoint()
    if #self.waypointList == 0 then
        return false
    end
    
    self.currentWaypointIndex = math.max(1, self.currentWaypointIndex - 1)
    local waypoint = self.waypointList[self.currentWaypointIndex]
    
    print(string.format("|cFF00FFFF[%d/%d]|r Previous stop:", 
        self.currentWaypointIndex, 
        #self.waypointList
    ))
    
    return self:SetWaypoint(waypoint)
end

function GPS:GetCurrentWaypoint()
    if #self.waypointList == 0 or self.currentWaypointIndex > #self.waypointList then
        return nil
    end
    
    return self.waypointList[self.currentWaypointIndex]
end

function GPS:GetWaypointList()
    return self.waypointList
end

-- ============================================
-- ROUTE DISPLAY
-- ============================================

function GPS:PrintRoute()
    if #self.waypointList == 0 then
        print("No route generated")
        return
    end
    
    print("|cFFFFD700=== GPS Route ===|r")
    
    for i, waypoint in ipairs(self.waypointList) do
        local icon = ""
        if waypoint.type == "trainer" then
            icon = "👨‍🏫"
        elseif waypoint.type == "vendor" then
            icon = "🛒"
        elseif waypoint.type == "checkpoint" then
            icon = "✓"
        end
        
        local current = (i == self.currentWaypointIndex) and "|cFF00FF00 ← YOU ARE HERE|r" or ""
        
        print(string.format("%s [%d] %s - %s%s", 
            icon,
            i,
            waypoint.name or waypoint.description,
            waypoint.zone or "",
            current
        ))
    end
end

-- ============================================
-- MACRO SUPPORT
-- ============================================

function GPS:GenerateMacro()
    -- Generate a macro that cycles through waypoints
    local macroName = "ProfOptGPS"
    local macroBody = "/run ProfessionOptimizerGPS:GoToNextWaypoint()"
    
    -- Check if macro exists
    local macroIndex = GetMacroIndexByName(macroName)
    
    if macroIndex == 0 then
        -- Create new macro
        local numGlobalMacros, numCharacterMacros = GetNumMacros()
        
        if numGlobalMacros < 36 then
            CreateMacro(macroName, "INV_Misc_Map02", macroBody, nil)
            print("|cFF00FF00Created macro:|r " .. macroName)
            print("Place it on your action bar for easy navigation!")
        else
            print("|cFFFF0000Cannot create macro:|r You have too many global macros (36/36)")
        end
    else
        -- Update existing macro
        EditMacro(macroIndex, macroName, "INV_Misc_Map02", macroBody)
        print("|cFF00FF00Updated macro:|r " .. macroName)
    end
end

-- ============================================
-- DISTANCE CALCULATION
-- ============================================

function GPS:GetDistanceToWaypoint(waypoint)
    if not waypoint or not waypoint.coords or not waypoint.mapID then
        return nil
    end
    
    local mapID = C_Map.GetBestMapForUnit("player")
    
    if mapID ~= waypoint.mapID then
        return nil, "Different zone"
    end
    
    local playerPos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not playerPos then
        return nil
    end
    
    local px, py = playerPos:GetXY()
    local wx, wy = waypoint.coords.x / 100, waypoint.coords.y / 100
    
    -- Calculate distance (rough approximation)
    local dx = (wx - px) * 100
    local dy = (wy - py) * 100
    local distance = math.sqrt(dx*dx + dy*dy)
    
    return distance
end

function GPS:CheckProximity()
    local waypoint = self:GetCurrentWaypoint()
    if not waypoint then
        return
    end
    
    local distance = self:GetDistanceToWaypoint(waypoint)
    
    if distance and distance < 5 then -- Within 5 yards
        print("|cFF00FF00✅ Arrived at waypoint!|r")
        print("   " .. (waypoint.description or waypoint.name))
        
        -- Auto-advance after 3 seconds
        C_Timer.After(3, function()
            if self.currentWaypointIndex < #self.waypointList then
                print("|cFF888888Auto-advancing to next waypoint...|r")
                self:GoToNextWaypoint()
            end
        end)
    end
end

-- ============================================
-- PROXIMITY TRACKING
-- ============================================

function GPS:StartProximityTracking()
    if self.proximityTimer then
        return -- Already tracking
    end
    
    self.proximityTimer = C_Timer.NewTicker(2, function()
        self:CheckProximity()
    end)
    
    print("GPS proximity tracking enabled")
end

function GPS:StopProximityTracking()
    if self.proximityTimer then
        self.proximityTimer:Cancel()
        self.proximityTimer = nil
    end
end

-- ============================================
-- INITIALIZATION
-- ============================================

GPS:Initialize()

_G.ProfessionOptimizerGPS = GPS

print("Profession Optimizer: GPS Navigation loaded")
