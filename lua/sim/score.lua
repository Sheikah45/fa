historyInterval = 10
scoreInterval = 1
alliesScore = true

local ArmyScore = {}
local scoreOption = ScenarioInfo.Options.Score or "no"
scoreData = {interval = historyInterval, current = ArmyScore, history = {}}

local victory = import('/lua/victory.lua')
-- Some of these values pre-existed and are used in other places, that's why their naming is not consistent
local categoriesToCollect = {
    land = categories.LAND,
    air = categories.AIR,
    naval = categories.NAVAL,
    cdr = categories.COMMAND,
    sacu = categories.SUBCOMMANDER,
    engineer = categories.ENGINEER,
    tech1 = categories.TECH1,
    tech2 = categories.TECH2,
    tech3 = categories.TECH3,
    experimental = categories.EXPERIMENTAL,
    structures = categories.STRUCTURE,
    transportation = categories.TRANSPORTATION
}

function CalculateBrainScore(brain)
    local commanderKills = brain:GetArmyStat("Enemies_Commanders_Destroyed", 0).Value
    local massSpent = brain:GetArmyStat("Economy_TotalConsumed_Mass", 0).Value
    local energySpent = brain:GetArmyStat("Economy_TotalConsumed_Energy", 0).Value
    local massValueDestroyed = brain:GetArmyStat("Enemies_MassValue_Destroyed", 0).Value
    local massValueLost = brain:GetArmyStat("Units_MassValue_Lost", 0).Value
    local energyValueDestroyed = brain:GetArmyStat("Enemies_EnergyValue_Destroyed", 0).Value
    local energyValueLost = brain:GetArmyStat("Units_EnergyValue_Lost", 0).Value

    -- helper variables to make equation more clear
    local energyValueCoefficient = 20

    -- score components calculated
    local resourceProduction = (massSpent + (energySpent / energyValueCoefficient)) / 2
    local battleResults = math.max(0, ((massValueDestroyed - massValueLost - (commanderKills * 2000)) +
        ((energyValueDestroyed - energyValueLost - (commanderKills * 5000000)) / energyValueCoefficient)) / 2)

    -- score calculated
    return math.floor(resourceProduction + battleResults + (commanderKills * 5000))
end

local function ScoreHistoryThread()
    while not victory.gameOver do
        WaitSeconds(scoreData.interval)
        local data = {}
        for index, brain in ArmyBrains do
            local Score = scoreData.current[index]
            if ArmyIsCivilian(index) then continue end
            if (Score.Defeated ~= nil) and (Score.Defeated < 0) then continue end
            if (Score.Defeated ~= nil) and (Score.Defeated < GetGameTimeSeconds()) then
                Score.Defeated = -1
            end
            data[index] = table.deepcopy(Score)
        end
        table.insert(scoreData.history, data)
    end
end

local function ScoreThread()
    for index, brain in ArmyBrains do
        if ArmyIsCivilian(index) then continue end
        ArmyScore[index] = {
            faction = brain:GetFactionIndex(),
            name = brain.Nickname,
            type = '',
            general = {
                score = 0,
                lastupdatetime = 0,
                kills = {
                    count = 0,
                    mass = 0,
                    energy = 0
                },
                built = {
                    count = 0,
                    mass = 0,
                    energy = 0
                },
                lost = {
                    count = 0,
                    mass = 0,
                    energy = 0
                },
                currentunits = 0,
                currentcap = 0
            },
            blueprints = {}, -- filled dynamically below
            units = {},      -- filled dynamically below
            resources = {
                massin = {
                    total = 0,
                    rate = 0,
                    reclaimed = 0,
                    reclaimRate = 0
                },
                massout = {
                    total = 0,
                    rate = 0,
                    excess = 0
                },
                energyin = {
                    total = 0,
                    rate = 0,
                    reclaimed = 0,
                    reclaimRate = 0
                },
                energyout = {
                    total = 0,
                    rate = 0,
                    excess = 0
                },
                storage = {
                    storedMass = 0,
                    storedEnergy = 0,
                    maxMass = 0,
                    maxEnergy = 0
                }
            }
        }
        for categoryName, category in categoriesToCollect do
            ArmyScore[index].units[categoryName] = {
                kills = 0,
                built = 0,
                lost = 0
            }
        end
    end
    ForkThread(ScoreHistoryThread)

    local NextTime = 0
    local lastTotalMass = 0
    local lastTotalEnergy = 0
    local lastReclaimedMass = 0
    local lastReclaimedEnergy = 0
    local lastConsumedMass = 0
    local lastConsumedEnergy = 0
    local estimatedTicksSinceLastUpdate = 0
    local simFrequency = 10
    while not victory.gameOver do
        local updInterval = scoreInterval / table.getsize(ArmyBrains)
        for index, brain in ArmyBrains do
            local CurTime = GetGameTimeSeconds()
            if CurTime < NextTime then
                WaitSeconds(updInterval)
            end
            NextTime = NextTime + updInterval
            local Score = ArmyScore[index]
            if ArmyIsCivilian(index) then continue end
            if (Score.Defeated ~= nil) and (Score.Defeated < 0) then continue end
            if (Score.Defeated == nil) and brain:IsDefeated() then
                Score.Defeated = CurTime + 15
            end
            estimatedTicksSinceLastUpdate = (CurTime - Score.general.lastupdatetime) * simFrequency
            Score.type = brain.BrainType
            Score.general.score = CalculateBrainScore(brain)
            Score.general.lastupdatetime = CurTime

            Score.general.currentunits = brain:GetArmyStat("UnitCap_Current", 0).Value
            Score.general.currentcap = brain:GetArmyStat("UnitCap_MaxCap", 0).Value

            Score.general.kills.count = brain:GetArmyStat("Enemies_Killed", 0).Value
            Score.general.kills.mass = brain:GetArmyStat("Enemies_MassValue_Destroyed", 0).Value
            Score.general.kills.energy = brain:GetArmyStat("Enemies_EnergyValue_Destroyed", 0).Value

            Score.general.built.count = brain:GetArmyStat("Units_History", 0).Value
            Score.general.built.mass = brain:GetArmyStat("Units_MassValue_Built", 0).Value
            Score.general.built.energy = brain:GetArmyStat("Units_EnergyValue_Built", 0).Value
            Score.general.lost.count = brain:GetArmyStat("Units_Killed", 0).Value
            Score.general.lost.mass = brain:GetArmyStat("Units_MassValue_Lost", 0).Value
            Score.general.lost.energy = brain:GetArmyStat("Units_EnergyValue_Lost", 0).Value

            lastReclaimedMass = Score.resources.massin.reclaimed
            Score.resources.massin.reclaimed = brain:GetArmyStat("Economy_Reclaimed_Mass", 0).Value
            Score.resources.massin.reclaimRate = (Score.resources.massin.reclaimed - lastReclaimedMass) / estimatedTicksSinceLastUpdate
            lastTotalMass = Score.resources.massin.total
            Score.resources.massin.total = brain:GetArmyStat("Economy_TotalProduced_Mass", 0).Value
            Score.resources.massin.rate = (Score.resources.massin.total - lastTotalMass) / estimatedTicksSinceLastUpdate - Score.resources.massin.reclaimRate
            lastConsumedMass = Score.resources.massout.total
            Score.resources.massout.total = brain:GetArmyStat("Economy_TotalConsumed_Mass", 0).Value
            Score.resources.massout.rate = (Score.resources.massout.total - lastConsumedMass) / estimatedTicksSinceLastUpdate
            Score.resources.massout.excess = brain:GetArmyStat("Economy_AccumExcess_Mass", 0).Value

            lastReclaimedEnergy = Score.resources.energyin.reclaimed
            Score.resources.energyin.reclaimed = brain:GetArmyStat("Economy_Reclaimed_Energy", 0).Value
            Score.resources.energyin.reclaimRate = (Score.resources.energyin.reclaimed - lastReclaimedEnergy) / estimatedTicksSinceLastUpdate
            lastTotalEnergy = Score.resources.energyin.total
            Score.resources.energyin.total = brain:GetArmyStat("Economy_TotalProduced_Energy", 0).Value
            Score.resources.energyin.rate = (Score.resources.energyin.total - lastTotalEnergy) / estimatedTicksSinceLastUpdate - Score.resources.energyin.reclaimRate
            lastConsumedEnergy = Score.resources.energyout.total
            Score.resources.energyout.total = brain:GetArmyStat("Economy_TotalConsumed_Energy", 0).Value
            Score.resources.energyout.rate = (Score.resources.energyout.total - lastConsumedEnergy) / estimatedTicksSinceLastUpdate
            Score.resources.energyout.excess = brain:GetArmyStat("Economy_AccumExcess_Energy", 0).Value

            Score.resources.storage.storedMass = brain:GetEconomyStored('MASS')
            Score.resources.storage.storedEnergy = brain:GetEconomyStored('ENERGY')

            Score.resources.storage.maxMass = brain:GetArmyStat("Economy_MaxStorage_Mass", 0).Value
            Score.resources.storage.maxEnergy = brain:GetArmyStat("Economy_MaxStorage_Energy", 0).Value

            for unitId, stats in brain.UnitStats do
                if Score.blueprints[unitId] == nil then
                    Score.blueprints[unitId] = {}
                end

                for statName, value in stats do
                    Score.blueprints[unitId][statName] = value
                end
            end

            for categoryName, category in categoriesToCollect do
                Score.units[categoryName]['kills'] = brain:GetBlueprintStat("Enemies_Killed", category)
                Score.units[categoryName]['built'] = brain:GetBlueprintStat("Units_History", category)
                Score.units[categoryName]['lost'] = brain:GetBlueprintStat("Units_Killed", category)
            end
        end

        local myArmyIndex = GetFocusArmy()
        local observer = myArmyIndex == -1

        if observer or SessionIsReplay() then
            Sync.Score = ArmyScore
        else
            for index, brain in ArmyBrains do
                if ArmyIsCivilian(index) then continue end
                if brain:IsDefeated() then
                    Sync.Score[index] = {Defeated = true, general = {}}
                else
                    if (myArmyIndex == index) or (alliesScore and IsAlly(myArmyIndex, index)) then
                        Sync.Score[index] = table.deepcopy(ArmyScore[index])
                    else
                        Sync.Score[index] = {general = {}}
                    end
                end

                if scoreOption ~= 'no' then
                    Sync.Score[index].general.score = ArmyScore[index].general.score
                else
                    Sync.Score[index].general.score = -1
                end
            end
        end
    end
end

function init()
    ForkThread(ScoreThread)
    table.insert(GameOverListeners, function()
        Sync.ScoreAccum = scoreData
        if victory.gameOver then
            Sync.StatsToSend = ArmyScore
        end
    end)
end
