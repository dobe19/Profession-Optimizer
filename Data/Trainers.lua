-- Data/Trainers.lua
-- Trainer and vendor location database for TomTom waypoints

YourAddonDB = YourAddonDB or {}
YourAddonDB.Trainers = {
    
    -- ============================================
    -- ENGINEERING TRAINERS
    -- ============================================
    
    Engineering = {
        -- The War Within
        tww = {
            [223644] = {
                name = "Rukku",
                zone = "Dornogal",
                coords = {x = 54.0, y = 56.0},
                faction = "both",
                mapID = 2339, -- Dornogal
                continent = "Khaz Algar",
            },
        },
        
        -- Dragonflight
        dragonflight = {
            [194627] = {
                name = "Azley",
                zone = "Valdrakken",
                coords = {x = 60.0, y = 38.0},
                faction = "both",
                mapID = 2112,
                continent = "Dragon Isles",
            },
        },
        
        -- Shadowlands
        shadowlands = {
            [175133] = {
                name = "Machinist Au'gur",
                zone = "Oribos",
                coords = {x = 39.0, y = 40.0},
                faction = "both",
                mapID = 1670,
                continent = "Shadowlands",
            },
        },
        
        -- Classic/Retail trainers
        classic = {
            -- Alliance
            [5174] = {
                name = "Springspindle Fizzlegear",
                zone = "Ironforge",
                coords = {x = 68.0, y = 43.0},
                faction = "alliance",
                mapID = 1455,
            },
            
            [29513] = {
                name = "Binkie Brightgear",
                zone = "Stormwind City",
                coords = {x = 63.0, y = 33.0},
                faction = "alliance",
                mapID = 1453,
            },
            
            -- Horde
            [3290] = {
                name = "Deek Fizzlebizz",
                zone = "Orgrimmar",
                coords = {x = 75.0, y = 25.0},
                faction = "horde",
                mapID = 1454,
            },
        },
    },
    
    -- ============================================
    -- BLACKSMITHING TRAINERS
    -- ============================================
    
    Blacksmithing = {
        tww = {
            [223645] = {
                name = "Metalworker Kronin",
                zone = "Dornogal",
                coords = {x = 47.0, y = 59.0},
                faction = "both",
                mapID = 2339,
            },
        },
    },
    
    -- ============================================
    -- ALCHEMY TRAINERS
    -- ============================================
    
    Alchemy = {
        tww = {
            [223646] = {
                name = "Alchemist Zina",
                zone = "Dornogal",
                coords = {x = 59.0, y = 62.0},
                faction = "both",
                mapID = 2339,
            },
        },
    },
    
    -- Add more professions and expansions as needed...
}

-- ============================================
-- VENDOR DATABASE
-- ============================================

YourAddonDB.Vendors = {
    
    Engineering = {
        tww = {
            [223650] = {
                name = "Engineering Supplies Vendor",
                zone = "Dornogal",
                coords = {x = 54.2, y = 56.5},
                faction = "both",
                mapID = 2339,
                sellsItems = {
                    [223460] = true, -- Example vendor part
                },
            },
        },
    },
    
    -- Add more vendors...
}

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

function YourAddonDB:GetTrainer(profession, expansion)
    local trainers = self.Trainers[profession]
    if not trainers then
        return nil
    end
    
    local expansionTrainers = trainers[expansion]
    if not expansionTrainers then
        return nil
    end
    
    -- Get player faction
    local playerFaction = UnitFactionGroup("player"):lower()
    
    -- Find appropriate trainer
    for npcId, trainer in pairs(expansionTrainers) do
        if trainer.faction == "both" or trainer.faction == playerFaction then
            return trainer, npcId
        end
    end
    
    return nil
end

function YourAddonDB:GetVendor(profession, expansion, itemId)
    local vendors = self.Vendors[profession]
    if not vendors then
        return nil
    end
    
    local expansionVendors = vendors[expansion]
    if not expansionVendors then
        return nil
    end
    
    -- Find vendor that sells this item
    for npcId, vendor in pairs(expansionVendors) do
        if vendor.sellsItems[itemId] then
            return vendor, npcId
        end
    end
    
    return nil
end
