local DieInstance = require('ge_tts.DieInstance')
local Json = require('ge_tts.Json')
local Object = require('ge_tts.Object')
local ObjectUtils = require('ge_tts.ObjectUtils')
local SaveManager = require('ge_tts.SaveManager')
local TableUtils = require('ge_tts.TableUtils')

local REPEATS_PER_TEST = 25
local TESTS_PER_DIE = 10

---@shape TestResults
---@field rollsCompleted number
---@field rolledValues number[]

---@shape DieOrigin
---@field position tts__Vector
---@field rotation tts__Vector

local Test = {}

---@type table<tts__StandardDieName, number>
local DieFaceCounts = {
    [Object.Name.Die4] = 4,
    [Object.Name.Die4] = 4,
    [Object.Name.Die6] = 6,
    [Object.Name.Die6Rounded] = 6,
    [Object.Name.Die8] = 8,
    [Object.Name.Die10] = 10,
    [Object.Name.Die12] = 12,
    [Object.Name.Die20] = 20,
}

local DieNames = TableUtils.keys(DieFaceCounts)

---@type ge_tts__DieInstance[]
local dieInstances = {}

---@param dieName tts__StandardDieName
---@param x number
---@param z number
---@param rotation number
---@return tts__DieState
local function dieState(dieName, x, z, rotation)
    return {
        Name = dieName,
        Transform = ObjectUtils.transformState({
            position = {x, 5, z},
            rotation = {0, rotation, 0},
            scale = {1, 1, 1},
        }),
    }
end

---@param dieName tts__StandardDieName
---@return TestResults
local function createResults(dieName)
    ---@type number[]
    local values = {}

    for i = 1, DieFaceCounts[dieName] do
        values[i] = 0
    end

    return {
        rollsCompleted = 0,
        rolledValues = values,
    }
end

---@param dieCount number
---@param results TestResults[]
---@return number, TestResults
local function aggregateResults(results)
    ---@type TestResults
    local aggregated = {
        rollsCompleted = 0,
        rolledValues = TableUtils.map(results[1].rolledValues, function()
            ---@type number
            return 0
        end),
    }

    for _, result in ipairs(results) do
        for value, occurrences in ipairs(result.rolledValues) do
            aggregated.rolledValues[value] = aggregated.rolledValues[value] + occurrences
        end

        aggregated.rollsCompleted = aggregated.rollsCompleted + result.rollsCompleted
    end

    local totalValue = 0

    for value, occurrences in ipairs(aggregated.rolledValues) do
        totalValue = totalValue + value * occurrences
    end

    local average = totalValue / aggregated.rollsCompleted

    return average, aggregated
end

local dieNameIndex = 0
local testIndex = 0
local repeatIndex = 0

local rollsInProgress = 0

---@type table<tts__StandardDieName, TestResults[]>
local dieResults = {}

---@type table<ge_tts__DieInstance, DieOrigin>
local dieOrigins = {}

---@param value number | string
local function onDieRolled(value)
    local rolledValue = --[[---@type number]] value

    local currentResults = dieResults[DieNames[dieNameIndex]][testIndex]
    currentResults.rollsCompleted = currentResults.rollsCompleted + 1
    currentResults.rolledValues[rolledValue] = currentResults.rolledValues[rolledValue] + 1

    rollsInProgress = rollsInProgress - 1

    if rollsInProgress == 0 then
        Test.nextRepeat()
    end
end

---@param dieName tts__StandardDieName
function Test.spawnDice(dieName)
    for _, dieInstance in ipairs(dieInstances) do
        dieInstance.destroy()
    end

    dieInstances = {}
    dieOrigins = {}

    -- Position/rotate the die randomly to better assure that the results aren't somehow
    -- determined by starting positions.

    local xOffset = math.random(0.05) - 0.025
    local zOffset = math.random(0.05) - 0.025
    local rotation = math.random(-180, 180) + math.random(0.5) - 0.25

    local awaitingDieCount = 0

    local layoutSize = -46
    local layoutStep = layoutSize / 14
    local layoutStart = -layoutSize / 2

    local x = layoutStart

    for column = 1, 15 do
        local z = layoutStart

        for row = 1, 15 do
            local data = dieState(dieName, x + xOffset, z + zOffset, rotation)
            local dieObject = spawnObjectData({data = data})

            local dieInstance = DieInstance(dieObject)
            dieInstance.onRolled = onDieRolled

            table.insert(dieInstances, dieInstance)

            awaitingDieCount = awaitingDieCount + 1

            Wait.frames(function()
                Wait.condition(function()
                    awaitingDieCount = awaitingDieCount - 1

                    dieOrigins[dieInstance] = {
                        position = dieObject.getPosition(),
                        rotation = dieObject.getRotation(),
                    }

                    if awaitingDieCount == 0 then
                        Test.nextRepeat()
                    end
                end, function()
                    return not dieObject.spawning and dieObject.resting
                end)
            end, 5)

            z = z + layoutStep
        end

        x = x + layoutStep
    end
end

function Test.nextRepeat()
    repeatIndex = repeatIndex + 1

    if repeatIndex > REPEATS_PER_TEST then
        repeatIndex = 0
        Test.nextTest()
        return
    end

    rollsInProgress = #dieInstances

    for _, dieInstance in ipairs(dieInstances) do
        local origin = dieOrigins[dieInstance]
        local dieObject = dieInstance.getObject()
        dieObject.setPosition(origin.position)
        dieObject.setRotation(origin.rotation)
        Wait.frames(function()
            dieObject.randomize('White')
        end)
    end
end

function Test.nextTest()
    local dieName = DieNames[dieNameIndex]

    if testIndex > 0 then
        local testResults = dieResults[dieName][testIndex]

        print("----- " .. dieName .. " - # " .. testIndex .. " -----")
        print(logString(testResults))
        print("Average = " .. (aggregateResults({ testResults })))
    end

    testIndex = testIndex + 1

    if testIndex > TESTS_PER_DIE then
        testIndex = 0
        Test.nextDie()
        return
    end

    dieResults[dieName][testIndex] = createResults(DieNames[dieNameIndex])

    Test.spawnDice(DieNames[dieNameIndex])
end

function Test.nextDie()
    if dieNameIndex > 0 then
        local finishedDieName = DieNames[dieNameIndex]
        local finishedDieResults = dieResults[finishedDieName]

        local average, aggregated = aggregateResults(finishedDieResults)

        print("----- " .. finishedDieName .. " Aggregated -----")
        print(logString(aggregated))
        print("Average = " .. average)
    end

    dieNameIndex = dieNameIndex + 1

    if dieNameIndex > #DieNames then
        for i = 1, #DieNames do
            local dieName = DieNames[i]
            local results = dieResults[dieName]

            local average, aggregated = aggregateResults(results)

            print("----- " .. dieName .. " Aggregated -----")
            print("Average = " .. average)
        end

        log(Json.encode(dieResults))

        print("***** Done *****")
        return
    end

    dieResults[DieNames[dieNameIndex]] = {}

    Test.nextTest()
end

SaveManager.registerOnLoad(Test.nextDie)
