-- AE Sequencer
-- A simple generative sequencer with independent voltage and gate sequences.
--[[
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the
software to the public domain. We make this dedication for the benefit
of the public at large and to the detriment of our heirs and
successors. We intend this dedication to be an overt act of
relinquishment in perpetuity of all present and future rights to this
software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <https://unlicense.org>
]] --
local NUM_SEQUENCES = 20
local MAX_STEPS = 32

local OUTPUT_BUFFER = {0, 0} -- Preallocated output buffer for step()
local lastActiveVoltIndex = 1 -- Tracks last active voltage sequence index

-- Mode and Favorites state
local editMode = "parameter" -- Can be "parameter" or "favorites"
local selectedFavoriteSlot = 1
local queuedFavorite = nil
local favorites = {nil, nil, nil, nil} -- NEW: Stores full state snapshots (parameters, voltageSequences, gateSequences)

-- Tables to hold 20 voltage sequences and 20 gate sequences.
local voltageSequences = {}
local gateSequences = {}

-- Generate a random 16-bit raw value in the range [-32768, 32767]
local function generateRandomRawValue() return math.random(-32768, 32767) end

-- Randomize a voltage sequence by filling its steps with raw values.
local function randomizeVoltageSequence(seq)
    for i = 1, seq.stepCount do seq.steps[i] = generateRandomRawValue() end
end

-- Randomize a gate sequence.
local function randomizeGateSequence(seq)
    for i = 1, MAX_STEPS do seq.steps[i] = math.random(100) end
end

-- Compute the effective voltage range based on polarity.
-- Polarity: 1 = Positive, 2 = Bipolar, 3 = Negative.
local function getEffectiveRange(minV, maxV, polarity)
    if polarity == 1 then
        return 0, maxV
    elseif polarity == 3 then
        return minV, 0
    else
        return minV, maxV
    end
end

-- Quantize a voltage value to the specified resolution.
local function quantizeVoltage(value, resolutionBits, effectiveMin, effectiveMax)
    local levels = (2 ^ resolutionBits) - 1
    local rangeEffective = effectiveMax - effectiveMin
    local stepSize = rangeEffective / levels
    local index = math.floor((value - effectiveMin) / stepSize + 0.5)
    local quantizedValue = index * stepSize + effectiveMin
    if quantizedValue < effectiveMin then quantizedValue = effectiveMin end
    if quantizedValue > effectiveMax then quantizedValue = effectiveMax end
    return quantizedValue
end

-- Update the cached voltage for the current step by mapping the raw value.
local function updateVoltageCached(seq, resolution, minV, maxV, polarity)
    local raw = seq.steps[seq.currentStep]
    local effectiveMin, effectiveMax = getEffectiveRange(minV, maxV, polarity)
    local fraction
    if polarity == 2 then
        fraction = (raw + 32768) / 65535
    elseif polarity == 1 then
        local clamped = raw < 0 and 0 or raw
        fraction = clamped / 32767
    elseif polarity == 3 then
        local clamped = raw > 0 and 0 or raw
        fraction = (clamped + 32768) / 32768
    end
    local value = fraction * (effectiveMax - effectiveMin) + effectiveMin
    seq.cachedVoltage = quantizeVoltage(value, resolution, effectiveMin,
                                        effectiveMax)
end

-- Initialize the 20 sequences if not already done.
local function initSequences()
    if #voltageSequences < NUM_SEQUENCES then
        for i = 1, NUM_SEQUENCES do
            voltageSequences[i] = {
                currentStep = 1,
                stepCount = 8,
                cachedVoltage = 0,
                steps = {}
            }
            for j = 1, MAX_STEPS do
                voltageSequences[i].steps[j] = generateRandomRawValue()
            end
            updateVoltageCached(voltageSequences[i], 16, -1, 1, 2)

            gateSequences[i] = {
                stepIndex = 1,
                numSteps = 16,
                gateRemainingSteps = 0,
                steps = {}
            }
            for j = 1, MAX_STEPS do
                gateSequences[i].steps[j] = math.random(100)
            end
        end
    end
end

-- Global randomize function to randomize all sequences.
local function globalRandomize(self)
    for i = 1, NUM_SEQUENCES do
        randomizeVoltageSequence(voltageSequences[i])
        updateVoltageCached(voltageSequences[i], self.parameters[7],
                            self.parameters[4], self.parameters[5],
                            self.parameters[6])
        randomizeGateSequence(gateSequences[i])
    end
end

-- Ensure all sequences are properly initialized
local function ensureInitialized(self)
    if #voltageSequences < NUM_SEQUENCES then initSequences() end
end

-- Helper function for deep copying tables
local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        -- Copy metatable if needed (likely not critical here but good practice)
        -- setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, function, nil, etc.
        copy = orig
    end
    return copy
end

return {
    name = "AE Sequencer",
    author = "Andras Eichstaedt / Thorinside / 4o",

    init = function(self)
        initSequences()
        return {
            -- Three inputs:
            -- 1 = clock (stepping), 2 = reset trigger, 3 = global randomize trigger
            inputs = {kGate, kTrigger, kTrigger},
            outputs = {kStepped, kGate},
            inputNames = {"Clock", "Reset", "Randomize"},
            outputNames = {"CV Output", "Gate Output"},
            parameters = {
                {"CV Sequence", 1, NUM_SEQUENCES, 1, kInt},
                {"Gate Sequence", 1, NUM_SEQUENCES, 1, kInt},
                {"CV Steps", 1, MAX_STEPS, 8, kInt},
                {"Min CV", -10, 10, -1, kVolts}, {"Max CV", -10, 10, 1, kVolts},
                {"Polarity", {"Positive", "Bipolar", "Negative"}, 2, kEnum},
                {"Bit Depth (CV)", 2, 16, 16, kInt},
                {"Gate Steps", 1, MAX_STEPS, 16, kInt},
                {"Threshold", 1, 100, 50, kPercent},
                {"Gate Length", 5, 1000, 100, kMs}
            }
        }
    end,

    gate = function(self, input, rising)
        local voltIdx = self.parameters[1]
        local gateIdx = self.parameters[2]
        if input == 1 and rising then
            -- Advance voltage sequence.
            local voltSeq = voltageSequences[voltIdx]
            voltSeq.stepCount = self.parameters[3]
            voltSeq.currentStep = voltSeq.currentStep + 1
            if voltSeq.currentStep > voltSeq.stepCount then
                voltSeq.currentStep = 1
            end
            updateVoltageCached(voltSeq, self.parameters[7], self.parameters[4],
                                self.parameters[5], self.parameters[6])

            -- Advance gate sequence.
            local gateSeq = gateSequences[gateIdx]
            gateSeq.numSteps = self.parameters[8]
            gateSeq.stepIndex = gateSeq.stepIndex + 1
            if gateSeq.stepIndex > gateSeq.numSteps then
                gateSeq.stepIndex = 1
            end
            if gateSeq.steps[gateSeq.stepIndex] >= self.parameters[9] then
                gateSeq.gateRemainingSteps = self.parameters[10]
            end
        end
    end,

    trigger = function(self, input)
        local voltIdx = self.parameters[1]
        local gateIdx = self.parameters[2]
        if input == 2 then
            -- Reset active voltage sequence.
            voltageSequences[voltIdx].currentStep = 1
            updateVoltageCached(voltageSequences[voltIdx], self.parameters[7],
                                self.parameters[4], self.parameters[5],
                                self.parameters[6])
            -- Reset active gate sequence.
            gateSequences[gateIdx].stepIndex = 1
        elseif input == 3 then
            -- Global randomize all sequences.
            globalRandomize(self)
        end
    end,

    step = function(self, dt, inputs)
        local voltIdx = self.parameters[1]
        local gateIdx = self.parameters[2]
        if voltIdx ~= lastActiveVoltIndex then
            lastActiveVoltIndex = voltIdx
            updateVoltageCached(voltageSequences[voltIdx], self.parameters[7],
                                self.parameters[4], self.parameters[5],
                                self.parameters[6])
        end
        OUTPUT_BUFFER[1] = voltageSequences[voltIdx].cachedVoltage
        local gateSeq = gateSequences[gateIdx]
        if gateSeq.gateRemainingSteps > 0 then
            gateSeq.gateRemainingSteps = gateSeq.gateRemainingSteps - 1
            OUTPUT_BUFFER[2] = 5
        else
            OUTPUT_BUFFER[2] = 0
        end

        -- If a favorite change is queued, apply it at the start of the volt sequence
        if queuedFavorite ~= nil and voltageSequences[voltIdx].currentStep == 1 then
            local snapshot = favorites[queuedFavorite]
            -- Check if the favorite slot is valid and not nil
            if snapshot then
                -- Restore sequences (deep copy)
                voltageSequences = deepcopy(snapshot.voltageSequences)
                gateSequences = deepcopy(snapshot.gateSequences)

                -- Restore parameters
                local alg = getCurrentAlgorithm()
                for i = 1, #snapshot.parameters do
                    -- Apply parameter via API
                    setParameter(alg, self.parameterOffset + i,
                                 snapshot.parameters[i])
                    -- Immediately update internal state for consistency
                    self.parameters[i] = snapshot.parameters[i]
                end

                -- Update cached state based on restored active sequences
                local restoredVoltIdx = self.parameters[1]
                lastActiveVoltIndex = restoredVoltIdx
                if voltageSequences[restoredVoltIdx] then
                    updateVoltageCached(voltageSequences[restoredVoltIdx],
                                        self.parameters[7], self.parameters[4],
                                        self.parameters[5], self.parameters[6])
                end
            end
            queuedFavorite = nil -- Clear the queue
        end

        return OUTPUT_BUFFER
    end,

    ui = function(self) return true end,

    setupUi = function(self)
        ensureInitialized(self)
        return {
            (self.parameters[7] - 2) / 14.0, -- Bit Depth normalized to 0-1
            (self.parameters[9] - 1) / 99.0, -- Threshold normalized to 0-1
            (self.parameters[10] - 5) / 995.0 -- Gate Length normalized to 0-1
        }
    end,

    pot1Push = function(self)
        if editMode == "parameter" then
            editMode = "favorites"
        else
            editMode = "parameter"
        end
        -- Reset selection when changing mode
        selectedFavoriteSlot = 1
        queuedFavorite = nil
    end,

    pot3Push = function(self)
        -- Only queue if the selected slot has been saved (is not nil)
        if selectedFavoriteSlot >= 1 and selectedFavoriteSlot <= 4 and
            favorites[selectedFavoriteSlot] then
            queuedFavorite = selectedFavoriteSlot
        else
            queuedFavorite = nil -- Explicitly clear queue if slot is empty/nil
        end
    end,

    encoder1Turn = function(self, value)
        -- Always control Gate Sequence (Parameter 2)
        local algorithm = getCurrentAlgorithm()
        setParameter(algorithm, self.parameterOffset + 2,
                     self.parameters[2] + value)
    end,

    encoder2Turn = function(self, value)
        -- Always control CV Sequence (Parameter 1)
        local algorithm = getCurrentAlgorithm()
        setParameter(algorithm, self.parameterOffset + 1,
                     self.parameters[1] + value)
    end,

    pot1Turn = function(self, value)
        if editMode == "parameter" then
            local algorithm = getCurrentAlgorithm()
            -- Bit Depth (CV) - Map 0-1 to range 2-16
            local bitDepth = math.floor(2 + value * 14)
            setParameter(algorithm, self.parameterOffset + 7, bitDepth)
        end
    end,

    pot2Turn = function(self, value)
        if editMode == "parameter" then
            local algorithm = getCurrentAlgorithm()
            -- Threshold - Map 0-1 to range 1-100
            local threshold = math.floor(1 + value * 99)
            setParameter(algorithm, self.parameterOffset + 9, threshold)
        end
    end,

    pot3Turn = function(self, value)
        if editMode == "parameter" then
            local algorithm = getCurrentAlgorithm()
            -- Gate Length - Map 0-1 to range 5-1000
            local gateLength = math.floor(5 + value * 995)
            setParameter(algorithm, self.parameterOffset + 10, gateLength)
        else -- favorites mode
            -- Select favorite slot 1-4 based on pot value 0-1
            selectedFavoriteSlot = 1 + math.floor(value * 3.99)
            queuedFavorite = nil -- Clear queue if user scrolls
        end
    end,

    encoder2Push = function(self)
        -- Save current *full state*, managing favorites like a 4-slot stack
        local currentState = {
            parameters = deepcopy(self.parameters),
            voltageSequences = deepcopy(voltageSequences),
            gateSequences = deepcopy(gateSequences)
        }

        local saved = false
        -- Try to save in the first empty slot
        for i = 1, 4 do
            if favorites[i] == nil then
                favorites[i] = currentState
                saved = true
                break
            end
        end

        -- If all slots were full, shift and save in the last slot
        if not saved then
            favorites[1] = favorites[2]
            favorites[2] = favorites[3]
            favorites[3] = favorites[4]
            favorites[4] = currentState
        end

        -- Optional: Visual feedback?
    end,

    serialise = function(self)
        local state = {
            voltageSequences = {},
            gateSequences = {},
            parameters = {},
            favorites = {}
        }

        -- Save all parameters
        for i = 1, #self.parameters do
            state.parameters[i] = self.parameters[i]
        end

        -- Save voltage sequences
        for i = 1, #voltageSequences do
            state.voltageSequences[i] = {
                currentStep = voltageSequences[i].currentStep,
                stepCount = voltageSequences[i].stepCount,
                cachedVoltage = voltageSequences[i].cachedVoltage,
                steps = {}
            }
            for j = 1, MAX_STEPS do
                state.voltageSequences[i].steps[j] =
                    voltageSequences[i].steps[j]
            end
        end

        -- Save gate sequences
        for i = 1, #gateSequences do
            state.gateSequences[i] = {
                stepIndex = gateSequences[i].stepIndex,
                numSteps = gateSequences[i].numSteps,
                gateRemainingSteps = gateSequences[i].gateRemainingSteps,
                steps = {}
            }
            for j = 1, MAX_STEPS do
                state.gateSequences[i].steps[j] = gateSequences[i].steps[j]
            end
        end

        -- Save favorites (array of snapshots)
        -- Use deepcopy to ensure nested tables are fully copied
        state.favorites = deepcopy(favorites)

        return state
    end,

    deserialise = function(self, state)
        if not state then return end

        -- Restore parameters
        if state.parameters then
            for i = 1, #state.parameters do
                self.parameters[i] = state.parameters[i]
            end
        end

        -- Restore voltage sequences
        if state.voltageSequences then
            voltageSequences = {}
            for i = 1, #state.voltageSequences do
                voltageSequences[i] = {
                    currentStep = state.voltageSequences[i].currentStep,
                    stepCount = state.voltageSequences[i].stepCount,
                    cachedVoltage = state.voltageSequences[i].cachedVoltage,
                    steps = {}
                }
                for j = 1, MAX_STEPS do
                    voltageSequences[i].steps[j] =
                        state.voltageSequences[i].steps[j]
                end
            end
        end

        -- Restore gate sequences
        if state.gateSequences then
            gateSequences = {}
            for i = 1, #state.gateSequences do
                gateSequences[i] = {
                    stepIndex = state.gateSequences[i].stepIndex,
                    numSteps = state.gateSequences[i].numSteps,
                    gateRemainingSteps = state.gateSequences[i]
                        .gateRemainingSteps,
                    steps = {}
                }
                for j = 1, MAX_STEPS do
                    gateSequences[i].steps[j] = state.gateSequences[i].steps[j]
                end
            end
        end

        -- Restore favorites (array of snapshots)
        if state.favorites then
            -- Use deepcopy to restore fully
            favorites = deepcopy(state.favorites)
            -- Ensure favorites table has exactly 4 elements, pad with nil if needed
            for i = #favorites + 1, 4 do favorites[i] = nil end
        else
            -- If no favorites in save file, initialize as empty
            favorites = {nil, nil, nil, nil}
        end
    end,

    draw = function(self)
        ensureInitialized(self)
        local voltIdx = self.parameters[1]
        local gateIdx = self.parameters[2]

        -- Draw title and info
        drawTinyText(8, 10, "AE Sequencer")

        -- Draw parameters section
        local textX = 140
        local textY = 25
        drawTinyText(textX, textY, "CV Seq: " .. voltIdx .. "/" .. NUM_SEQUENCES)
        drawTinyText(textX, textY + 8,
                     "Gate Seq: " .. gateIdx .. "/" .. NUM_SEQUENCES)
        drawTinyText(textX, textY + 16, "Bit Depth: " .. self.parameters[7])
        drawTinyText(textX, textY + 24,
                     "Threshold: " .. self.parameters[9] .. "%")
        drawTinyText(textX, textY + 32,
                     "Gate Len: " .. self.parameters[10] .. "ms")

        -- Draw Persistent Favorites Stack
        local favStackX = 204 -- Moved right 4 pixels (smaller on the left)
        local favStackY = 17 -- Moved down 2 pixels
        local favHeight = 8
        local favWidth = 253 - favStackX -- Calculate width for 2px right margin (255 - 2 - favStackX)
        local favGap = 2

        for i = 1, 4 do
            local currentY = favStackY + (i - 1) * (favHeight + favGap)
            local snapshot = favorites[i]
            local borderColor = 8 -- Default border
            local isEmpty = (snapshot == nil)
            local bgColor

            if isEmpty then
                bgColor = 2 -- Set background to 2 for empty slots
            else
                bgColor = 5 -- Slightly brighter default bg for saved slots
            end

            if editMode == "favorites" and i == selectedFavoriteSlot then
                borderColor = 15 -- Highlight selected slot border
            end
            if i == queuedFavorite then
                -- Indicate queued favorite (works even if empty, though queueing empty is prevented)
                bgColor = 10
                borderColor = 15
            end

            -- Draw background and border for the slot
            drawRectangle(favStackX, currentY, favStackX + favWidth,
                          currentY + favHeight, bgColor) -- Background (filled)
            -- Draw border using drawLine
            local bx1, by1 = favStackX - 1, currentY - 1
            local bx2, by2 = favStackX + favWidth + 1, currentY + favHeight + 1
            drawLine(bx1, by1, bx2, by1, borderColor) -- Top
            drawLine(bx1, by2, bx2, by2, borderColor) -- Bottom
            drawLine(bx1, by1, bx1, by2, borderColor) -- Left
            drawLine(bx2, by1, bx2, by2, borderColor) -- Right

            if isEmpty then
                -- drawTinyText(favStackX + 2, currentY + 1, "(empty)") -- Removed this line
            else
                -- Draw abstract tiny gate bars representation
                -- local miniSteps = 16 -- Try to show more steps in the width
                -- local barHeight = favHeight - 2 -- Leave 1px top/bottom margin

                -- New Two-Row Representation
                local miniSteps = 8 -- Represent 8 steps
                local miniBlockHeight = 3
                local miniGap = 0 -- No gap between rows needed if height is 3 in 8px total
                local miniGateY = currentY + 1
                local miniCvY = currentY + 1 + miniBlockHeight + miniGap

                local favParams = snapshot.parameters
                local favVoltSeqTable = snapshot.voltageSequences
                local favGateSeqTable = snapshot.gateSequences
                local favCvIdx = favParams[1]
                local favGateIdx = favParams[2]
                local favThreshold = favParams[9] -- Saved threshold

                if favVoltSeqTable and favGateSeqTable and
                    favVoltSeqTable[favCvIdx] and favGateSeqTable[favGateIdx] then
                    local favVoltSeq = favVoltSeqTable[favCvIdx]
                    local favGateSeq = favGateSeqTable[favGateIdx]
                    local favNumGate = favParams[8] -- Saved gate steps param
                    local favNumVolt = favParams[3] -- Saved CV steps param
                    local miniBlockWidth = favWidth / miniSteps

                    -- Mini Gate Pattern (Top Row)
                    for s = 1, miniSteps do
                        local stepIdx = ((s - 1) % favNumGate) + 1
                        local miniX = favStackX + 1 + (s - 1) * miniBlockWidth
                        local miniEndX = miniX + miniBlockWidth - 1
                        local gateColor = 5 -- Dim color for off steps
                        if favGateSeq.steps[stepIdx] and
                            favGateSeq.steps[stepIdx] >= favThreshold then
                            gateColor = 15 -- Bright color for on steps
                        end
                        -- Ensure end >= start for drawing
                        if miniEndX < miniX then
                            miniEndX = miniX
                        end
                        drawRectangle(math.floor(miniX), miniGateY,
                                      math.floor(miniEndX),
                                      miniGateY + miniBlockHeight - 1, gateColor)
                    end

                    -- Mini CV Pattern (Bottom Row)
                    local favEffectiveMin, favEffectiveMax = getEffectiveRange(
                                                                 favParams[4],
                                                                 favParams[5],
                                                                 favParams[6]) -- Use saved range params
                    for s = 1, miniSteps do
                        local stepIdx = ((s - 1) % favNumVolt) + 1
                        local miniX = favStackX + 1 + (s - 1) * miniBlockWidth
                        local miniEndX = miniX + miniBlockWidth - 1
                        local raw = favVoltSeq.steps[stepIdx]
                        local cvColor = 1 -- Default color if raw is nil
                        if raw then
                            local voltage
                            if favParams[6] == 2 then
                                voltage =
                                    (raw + 32768) / 65535 *
                                        (favEffectiveMax - favEffectiveMin) +
                                        favEffectiveMin
                            elseif favParams[6] == 1 then
                                voltage =
                                    (raw < 0 and 0 or raw) / 32767 *
                                        (favEffectiveMax - favEffectiveMin) +
                                        favEffectiveMin
                            else
                                voltage =
                                    ((raw > 0 and 0 or raw) + 32768) / 32768 *
                                        (favEffectiveMax - favEffectiveMin) +
                                        favEffectiveMin
                            end
                            local norm =
                                (voltage - favEffectiveMin) /
                                    (favEffectiveMax - favEffectiveMin)
                            if norm < 0 then
                                norm = 0
                            elseif norm > 1 then
                                norm = 1
                            end
                            cvColor = math.floor(norm * 14) + 1
                        end
                        -- Ensure end >= start for drawing
                        if miniEndX < miniX then
                            miniEndX = miniX
                        end
                        drawRectangle(math.floor(miniX), miniCvY,
                                      math.floor(miniEndX),
                                      miniCvY + miniBlockHeight - 1, cvColor)
                    end
                else
                    -- Draw placeholder if sequence data is missing (shouldn't happen with snapshots)
                    drawTinyText(favStackX + 2, currentY + 1, "err")
                end

                -- Remove old gate bar drawing code (already replaced)
                --[[ 
                local barWidth = favWidth / miniSteps

                for s = 1, miniSteps do
                    local stepIdx = ((s - 1) % favNumGate) + 1
                    local barX = favStackX + 1 + (s - 1) * barWidth
                    local barEndX = barX + barWidth - 1
                    local barColor = 5 -- Dim color for off steps
                    if favGateSeq.steps[stepIdx] and favGateSeq.steps[stepIdx] >= favThreshold then
                        barColor = 15 -- Bright color for on steps
                    end
                    drawRectangle(math.floor(barX), currentY + 1, math.floor(barEndX), currentY + barHeight, barColor)
                end
                ]] --
            end
        end

        -- Calculate maximum available width for sequence displays
        local availableWidth = textX - 13 -- 8px left margin + 5px right margin

        -- Draw gate sequence visualization
        local gateSeq = gateSequences[gateIdx]
        local numGate = self.parameters[8]
        local gateBlockWidthFloat = availableWidth / numGate -- Use floating point for precise width
        local gateBlockHeight = 10 -- Fixed height
        local gateY = 25
        local startX = 8.0 -- Use float for start position

        drawTinyText(8, gateY - 2, "Gate Pattern")

        for i = 1, numGate do
            local currentX = startX + (i - 1) * gateBlockWidthFloat
            local nextX = startX + i * gateBlockWidthFloat
            local drawStartX = math.floor(currentX)
            local drawEndX = math.floor(nextX - 1) -- Leave 1px gap

            -- Ensure minimum width of 1px for drawing
            if drawEndX < drawStartX then drawEndX = drawStartX end

            -- If this is the active gate step, draw a white border (around the block)
            if i == gateSeq.stepIndex then
                drawRectangle(drawStartX - 1, gateY - 1, drawEndX + 1,
                              gateY + gateBlockHeight - 2 + 1, 15) -- Adjusted border height
            end
            -- Draw the block
            if gateSeq.steps[i] >= self.parameters[9] then
                drawRectangle(drawStartX, gateY, drawEndX,
                              gateY + gateBlockHeight - 2, 15) -- Adjusted block height
            else
                drawRectangle(drawStartX, gateY, drawEndX,
                              gateY + gateBlockHeight - 2, 3) -- Adjusted block height
            end
        end

        -- Draw voltage sequence visualization
        local voltSeq = voltageSequences[voltIdx]
        local numVolt = self.parameters[3]
        local voltBlockWidthFloat = availableWidth / numVolt -- Use floating point for precise width
        local voltBlockHeight = 10 -- Fixed height
        local voltY = 45

        drawTinyText(8, voltY - 2, "CV Pattern")

        local effectiveMin, effectiveMax =
            getEffectiveRange(self.parameters[4], self.parameters[5],
                              self.parameters[6])
        for i = 1, numVolt do
            local currentX = startX + (i - 1) * voltBlockWidthFloat
            local nextX = startX + i * voltBlockWidthFloat
            local drawStartX = math.floor(currentX)
            local drawEndX = math.floor(nextX - 1) -- Leave 1px gap

            -- Ensure minimum width of 1px for drawing
            if drawEndX < drawStartX then drawEndX = drawStartX end

            local raw = voltSeq.steps[i]
            local voltage
            if self.parameters[6] == 2 then
                voltage =
                    (raw + 32768) / 65535 * (effectiveMax - effectiveMin) +
                        effectiveMin
            elseif self.parameters[6] == 1 then
                voltage = (raw < 0 and 0 or raw) / 32767 *
                              (effectiveMax - effectiveMin) + effectiveMin
            elseif self.parameters[6] == 3 then
                voltage = ((raw > 0 and 0 or raw) + 32768) / 32768 *
                              (effectiveMax - effectiveMin) + effectiveMin
            end
            local norm = (voltage - effectiveMin) /
                             (effectiveMax - effectiveMin)
            if norm < 0 then norm = 0 end
            if norm > 1 then norm = 1 end
            local colorIndex = math.floor(norm * 14) + 1

            -- If this is the active step, draw a white border (around the block)
            if i == voltSeq.currentStep then
                drawRectangle(drawStartX - 1, voltY - 1, drawEndX + 1,
                              voltY + voltBlockHeight - 2 + 1, 15) -- Adjusted border height
            end
            -- Draw the block
            drawRectangle(drawStartX, voltY, drawEndX,
                          voltY + voltBlockHeight - 2, colorIndex) -- Adjusted block height
        end
    end
}
