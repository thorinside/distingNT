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
local selectedFavoriteSlot = 1
local queuedFavorite = nil
local favorites = {nil, nil, nil, nil} -- Stores parameter snapshots

-- Tables to hold 20 voltage sequences and 20 gate sequences.
local voltageSequences = {}
local gateSequences = {}

-- Helper function to calculate the effective step index based on slide
local function getEffectiveIndex(currentIndex, numSteps, slidePercent)
    if numSteps <= 0 then return currentIndex end -- Avoid division by zero
    local slideAmount = math.floor(numSteps * (slidePercent / 100.0))
    -- Calculate the effective index using modulo arithmetic
    -- Ensure the result is 1-based index
    local effectiveIndex = (currentIndex - 1 - slideAmount + numSteps) %
                               numSteps + 1
    return effectiveIndex
end

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
local function updateVoltageCached(seq, resolution, minV, maxV, polarity,
                                   slidePercent) -- Added slidePercent
    local numSteps = seq.stepCount
    local effectiveStep = getEffectiveIndex(seq.currentStep, numSteps,
                                            slidePercent)
    local raw = seq.steps[effectiveStep] -- Use effectiveStep index
    if raw == nil then
        -- Handle potential nil value if sequence data is inconsistent
        -- This can happen if stepCount changes before steps table is fully populated/resized
        -- or if effectiveStep calculation results in an index temporarily out of bounds
        -- during sequence modifications. Setting to 0 is a safe fallback.
        seq.cachedVoltage = 0
        return
    end
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
            updateVoltageCached(voltageSequences[i], 16, -1, 1, 2, 0)

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
                            self.parameters[6], self.parameters[11]) -- Pass slide
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
        local NUM_PARAMS = 11 -- Updated parameter count

        if self.state then
            -- Restore state if available (moved from deserialise)
            local state = self.state -- Use the state provided in self

            -- Restore parameters first, as they are needed for updateVoltageCached
            if state.parameters then
                -- Initialize self.parameters table if it doesn't exist (shouldn't happen ideally, but safe)
                if not self.parameters then self.parameters = {} end
                -- Use NUM_PARAMS to ensure we load/initialize the correct number
                for i = 1, NUM_PARAMS do
                    -- Load from state if available, otherwise initialize to default from return structure
                    self.parameters[i] =
                        state.parameters[i] or ({
                            1, 1, 8, -1, 1, 2, 16, 16, 50, 100, 0 -- Add default for slide
                        })[i]
                end
            else
                -- If no parameters in state, we need some defaults before returning the structure
                -- Initialize with all defaults if parameters key is missing
                self.parameters = {
                    1, 1, 8, -1, 1, 2, 16, 16, 50, 100, 0 -- Add default for slide
                }
            end

            -- Restore voltage sequences
            if state.voltageSequences then
                voltageSequences = {} -- Clear existing global sequences
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
                -- Crucially, update cached voltage for the loaded active sequence
                local voltIdx = self.parameters[1] -- Get index from restored params
                if voltageSequences[voltIdx] then -- Check sequence exists
                    updateVoltageCached(voltageSequences[voltIdx],
                                        self.parameters[7], self.parameters[4],
                                        self.parameters[5], self.parameters[6],
                                        self.parameters[11]) -- Pass slide
                    lastActiveVoltIndex = voltIdx -- Update the tracker
                end
            else
                initSequences() -- Fallback if sequence data is missing in state
            end

            -- Restore gate sequences
            if state.gateSequences then
                gateSequences = {} -- Clear existing global sequences
                for i = 1, #state.gateSequences do
                    gateSequences[i] = {
                        stepIndex = state.gateSequences[i].stepIndex,
                        numSteps = state.gateSequences[i].numSteps,
                        gateRemainingSteps = state.gateSequences[i]
                            .gateRemainingSteps,
                        steps = {}
                    }
                    for j = 1, MAX_STEPS do
                        gateSequences[i].steps[j] =
                            state.gateSequences[i].steps[j]
                    end
                end
            else
                -- Only initialize gates if voltages also needed initializing
                -- Assuming state is usually all-or-nothing regarding sequences
                if not state.voltageSequences then
                    initSequences()
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

            -- Restore selected favorite slot
            if state.selectedFavoriteSlot then
                selectedFavoriteSlot = state.selectedFavoriteSlot
            else
                -- Default if not found in state (handles older saves)
                selectedFavoriteSlot = 1
            end

        else
            -- No state provided, initialize everything to defaults
            initSequences()
            -- Initialize self.parameters with defaults if state wasn't loaded
            -- The return structure below defines defaults, but let's ensure self.parameters exists
            -- Note: initSequences() doesn't touch self.parameters
            self.parameters = {
                1, 1, 8, -1, 1, 2, 16, 16, 50, 100, 0 -- Default values including slide
            } -- Default values matching the return structure
            -- Update cache for default sequence 1
            updateVoltageCached(voltageSequences[1], self.parameters[7],
                                self.parameters[4], self.parameters[5],
                                self.parameters[6], self.parameters[11]) -- Pass slide
            lastActiveVoltIndex = 1
        end

        -- Initialize visual blink toggle state
        self.blinkToggle = true
        self.pot3JustPushed = false -- Initialize the new flag

        -- Return the required structure (parameter defaults are fixed here)
        return {
            inputs = {kGate, kTrigger, kTrigger},
            outputs = {kStepped, kGate},
            inputNames = {"Clock", "Reset", "Randomize"},
            outputNames = {"CV Output", "Gate Output"},
            parameters = {
                {"CV Sequence", 1, NUM_SEQUENCES, 1, kInt}, -- Default: 1
                {"Gate Sequence", 1, NUM_SEQUENCES, 1, kInt}, -- Default: 1
                {"CV Steps", 1, MAX_STEPS, 8, kInt}, -- Default: 8
                {"Min CV", -10, 10, -1, kVolts}, -- Default: -1
                {"Max CV", -10, 10, 1, kVolts}, -- Default: 1
                {"Polarity", {"Positive", "Bipolar", "Negative"}, 2, kEnum}, -- Default: Bipolar (2)
                {"Bit Depth (CV)", 2, 16, 16, kInt}, -- Default: 16
                {"Gate Steps", 1, MAX_STEPS, 16, kInt}, -- Default: 16
                {"Threshold", 1, 100, 50, kPercent}, -- Default: 50
                {"Gate Length", 5, 1000, 100, kMs}, -- Default: 100ms
                {"Slide", 0, 100, 0, kPercent} -- New Slide parameter
            }
        }
    end,

    gate = function(self, input, rising)
        local voltIdx = self.parameters[1]
        local gateIdx = self.parameters[2]
        local slidePercent = self.parameters[11] -- Get slide value

        -- Check if a favorite is queued and sequences are at step 1
        if queuedFavorite ~= nil then
            local currentGateSeq = gateSequences[gateIdx]

            -- Launch when the gate sequence hits step 1
            if currentGateSeq.stepIndex == 1 then
                local snapshot = favorites[queuedFavorite]
                if snapshot then
                    -- Restore parameters only
                    local alg = getCurrentAlgorithm()
                    for i = 1, #snapshot.parameters do
                        -- Apply parameter via API
                        setParameter(alg, self.parameterOffset + i,
                                     snapshot.parameters[i])
                        -- Immediately update internal state for consistency
                        self.parameters[i] = snapshot.parameters[i]
                    end

                    -- Update slidePercent in case it was loaded from the favorite
                    slidePercent = self.parameters[11]

                    -- Update cached state based on restored parameters and the *new* active sequence index
                    local restoredVoltIdx = self.parameters[1] -- Get index from restored params
                    lastActiveVoltIndex = restoredVoltIdx -- Update tracker
                    if voltageSequences[restoredVoltIdx] then -- Check sequence exists
                        updateVoltageCached(voltageSequences[restoredVoltIdx],
                                            self.parameters[7],
                                            self.parameters[4],
                                            self.parameters[5],
                                            self.parameters[6], slidePercent) -- Use restored params including slide
                    end

                    -- Update voltIdx and gateIdx in case they were changed by loading the favorite
                    voltIdx = self.parameters[1]
                    gateIdx = self.parameters[2]
                end
                queuedFavorite = nil -- Clear the queue after attempting load
                self.blinkToggle = true -- Ensure the indicator becomes solid white immediately after loading
            end
        end

        -- Toggle blink state on clock input *only* if a favorite is queued
        if queuedFavorite ~= nil and input == 1 and rising then
            self.blinkToggle = not self.blinkToggle
        end

        if input == 1 and rising then
            -- Advance voltage sequence.
            local voltSeq = voltageSequences[voltIdx]
            voltSeq.stepCount = self.parameters[3]
            voltSeq.currentStep = voltSeq.currentStep + 1
            if voltSeq.currentStep > voltSeq.stepCount then
                voltSeq.currentStep = 1
            end
            updateVoltageCached(voltSeq, self.parameters[7], self.parameters[4],
                                self.parameters[5], self.parameters[6],
                                slidePercent) -- Pass slide

            -- Advance gate sequence.
            local gateSeq = gateSequences[gateIdx]
            gateSeq.numSteps = self.parameters[8]
            gateSeq.stepIndex = gateSeq.stepIndex + 1
            if gateSeq.stepIndex > gateSeq.numSteps then
                gateSeq.stepIndex = 1
            end
            -- Calculate effective gate index using slide
            local effectiveGateIndex = getEffectiveIndex(gateSeq.stepIndex,
                                                         gateSeq.numSteps,
                                                         slidePercent)
            -- Check threshold using effective index
            if gateSeq.steps[effectiveGateIndex] and -- Check if step exists before accessing
                gateSeq.steps[effectiveGateIndex] <= self.parameters[9] then
                gateSeq.gateRemainingSteps = self.parameters[10]
            end
        end
    end,

    trigger = function(self, input)
        local voltIdx = self.parameters[1]
        local gateIdx = self.parameters[2]
        local slidePercent = self.parameters[11] -- Get slide value
        if input == 2 then
            -- Reset active voltage sequence.
            voltageSequences[voltIdx].currentStep = 1
            updateVoltageCached(voltageSequences[voltIdx], self.parameters[7],
                                self.parameters[4], self.parameters[5],
                                self.parameters[6], slidePercent) -- Pass slide
            -- Reset active gate sequence.
            gateSequences[gateIdx].stepIndex = 1
        elseif input == 3 then
            -- Global randomize all sequences.
            globalRandomize(self)
            -- The globalRandomize function now handles updating cache with slide
            -- but we still need to ensure the *currently selected* sequence's cache
            -- is updated immediately after randomization, in case it wasn't the last one updated.
            if voltageSequences[voltIdx] then
                updateVoltageCached(voltageSequences[voltIdx],
                                    self.parameters[7], self.parameters[4],
                                    self.parameters[5], self.parameters[6],
                                    slidePercent) -- Pass slide
            end
        end
    end,

    step = function(self, dt, inputs)
        local voltIdx = self.parameters[1]
        local gateIdx = self.parameters[2]
        local slidePercent = self.parameters[11] -- Get slide value

        -- Check if pot 3 was just pushed to queue a favorite
        if self.pot3JustPushed then
            if selectedFavoriteSlot >= 1 and selectedFavoriteSlot <= 4 and
                favorites[selectedFavoriteSlot] then
                queuedFavorite = selectedFavoriteSlot
                self.blinkToggle = true -- Start indicator solid white before first blink
            else
                queuedFavorite = nil -- Clear queue if slot is empty/invalid
            end
            self.pot3JustPushed = false -- Reset the flag
        end

        -- Normal step operation: Update cached voltage if the active index changed
        if voltIdx ~= lastActiveVoltIndex then
            lastActiveVoltIndex = voltIdx
            updateVoltageCached(voltageSequences[voltIdx], self.parameters[7],
                                self.parameters[4], self.parameters[5],
                                self.parameters[6], slidePercent) -- Pass slide
        end

        OUTPUT_BUFFER[1] = voltageSequences[lastActiveVoltIndex].cachedVoltage -- Use lastActiveVoltIndex
        local gateSeq = gateSequences[gateIdx] -- Use current parameter for gate index
        if gateSeq.gateRemainingSteps > 0 then
            gateSeq.gateRemainingSteps = gateSeq.gateRemainingSteps - 1
            OUTPUT_BUFFER[2] = 5
        else
            OUTPUT_BUFFER[2] = 0
        end

        return OUTPUT_BUFFER
    end,

    ui = function(self) return true end,

    setupUi = function(self)
        ensureInitialized(self)
        return {
            (self.parameters[9] - 1) / 99.0, -- Threshold normalized to 0-1 (Now controlled by Pot 1)
            (self.parameters[7] - 2) / 14.0, -- Bit Depth normalized to 0-1 (Now controlled by Pot 2)
            (selectedFavoriteSlot - 1) / 3.0 -- Selected favorite slot normalized 0-1
        }
    end,

    pot3Push = function(self)
        -- Load selected favorite immediately if the slot has been saved (is not nil)
        -- Only queue if the selected slot has been saved (is not nil)
        -- if selectedFavoriteSlot >= 1 and selectedFavoriteSlot <= 4 and
        --     favorites[selectedFavoriteSlot] then
        --     queuedFavorite = selectedFavoriteSlot
        -- else
        --     queuedFavorite = nil -- Explicitly clear queue if slot is empty/invalid
        -- end
        self.pot3JustPushed = true -- Signal that the push event occurred
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
        local algorithm = getCurrentAlgorithm()
        -- Now controls Threshold - Map 0-1 to range 1-100
        local threshold = math.floor(1 + value * 99)
        setParameter(algorithm, self.parameterOffset + 9, threshold)
    end,

    pot2Turn = function(self, value)
        local algorithm = getCurrentAlgorithm()
        -- Now controls Bit Depth (CV) - Map 0-1 to range 2-16
        local bitDepth = math.floor(2 + value * 14)
        setParameter(algorithm, self.parameterOffset + 7, bitDepth)
    end,

    pot3Turn = function(self, value)
        -- Always control favorite selection
        -- Select favorite slot 1-4 based on pot value 0-1
        local newSelectedFavoriteSlot = 1 + math.floor(value * 3.99)

        -- Only clear the queue if a favorite is queued AND the pot turn
        -- results in selecting a DIFFERENT slot than the one queued.
        if queuedFavorite ~= nil and newSelectedFavoriteSlot ~= queuedFavorite then
            queuedFavorite = nil
        end

        -- Update the selected slot regardless, for UI feedback
        selectedFavoriteSlot = newSelectedFavoriteSlot
        -- queuedFavorite = nil -- Clear queue if user scrolls while selecting -- OLD LOGIC
    end,

    encoder2Push = function(self)
        -- Save current *parameters*, managing favorites like a 4-slot stack
        local currentState = {parameters = {}}
        -- Copy all parameters, including the new 'Slide' parameter
        for i = 1, #self.parameters do
            currentState.parameters[i] = self.parameters[i]
        end

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

        -- Save all parameters, including the new slide parameter
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

        -- Save selected favorite slot
        state.selectedFavoriteSlot = selectedFavoriteSlot

        return state
    end,

    draw = function(self)
        ensureInitialized(self)
        local voltIdx = self.parameters[1]
        local gateIdx = self.parameters[2]
        local slidePercent = self.parameters[11] -- Still need this for calculations

        -- Draw title and info
        drawTinyText(8, 10, "AE Sequencer")

        -- Draw parameters section (Moved down 5px)
        local textX = 140
        local textY = 30 -- Changed from 25 to 30
        drawTinyText(textX, textY,
                     "Gate Seq: " .. gateIdx .. "/" .. NUM_SEQUENCES)
        drawTinyText(textX, textY + 8,
                     "Threshold: " .. self.parameters[9] .. "%")
        drawTinyText(textX, textY + 16,
                     "CV Seq: " .. voltIdx .. "/" .. NUM_SEQUENCES)
        drawTinyText(textX, textY + 24, "Bit Depth: " .. self.parameters[7])

        -- Draw Persistent Favorites Stack (Moved up 3px)
        local favStackX = 204
        local favStackY = 14 -- Changed from 17 to 14
        local favHeight = 8
        local favWidth = 253 - favStackX
        local favGap = 2

        for i = 1, 4 do
            local currentY = favStackY + (i - 1) * (favHeight + favGap)
            local snapshot = favorites[i]
            local borderColor = 8
            local isEmpty = (snapshot == nil)
            local bgColor = isEmpty and 2 or 5

            -- Selection/Queue indicators (unchanged)
            if i == selectedFavoriteSlot then
                borderColor = 15
                if queuedFavorite == nil then
                    local indicatorColor = 15
                    local indicatorX1 = favStackX - 4;
                    local indicatorY1 = currentY
                    local indicatorX2 = favStackX - 2;
                    local indicatorY2 = currentY + favHeight - 1
                    drawRectangle(indicatorX1, indicatorY1, indicatorX2,
                                  indicatorY2, indicatorColor)
                end
            end
            if i == queuedFavorite then
                borderColor = 15
                local indicatorColor = self.blinkToggle and 15 or 2
                local indicatorX1 = favStackX - 4;
                local indicatorY1 = currentY
                local indicatorX2 = favStackX - 2;
                local indicatorY2 = currentY + favHeight - 1
                drawRectangle(indicatorX1, indicatorY1, indicatorX2,
                              indicatorY2, indicatorColor)
            end

            -- Slot border/background (unchanged)
            drawRectangle(favStackX, currentY, favStackX + favWidth,
                          currentY + favHeight, bgColor)
            local bx1, by1 = favStackX - 1, currentY - 1
            local bx2, by2 = favStackX + favWidth + 1, currentY + favHeight + 1
            drawLine(bx1, by1, bx2, by1, borderColor);
            drawLine(bx1, by2, bx2, by2, borderColor)
            drawLine(bx1, by1, bx1, by2, borderColor);
            drawLine(bx2, by1, bx2, by2, borderColor)

            if not isEmpty then
                -- Mini pattern drawing logic (KEEP effective index calculations)
                local miniSteps = 8
                local miniBlockHeight = 3
                local miniGateY = currentY + 1
                local miniCvY = currentY + 1 + miniBlockHeight -- Removed miniGap

                local favParams = snapshot.parameters
                local favSlidePercent = favParams[11] or 0 -- Use slide from snapshot
                local favCvIdx = favParams[1];
                local favGateIdx = favParams[2]
                local favThreshold = favParams[9];
                local favNumGate = favParams[8]
                local favNumVolt = favParams[3]

                local favVoltSeq = voltageSequences[favCvIdx]
                local favGateSeq = gateSequences[favGateIdx]

                if favVoltSeq and favGateSeq then
                    local miniBlockWidth = favWidth / miniSteps

                    -- Mini Gate Pattern (Top Row) - Use effective index
                    for s = 1, miniSteps do
                        local displayIndex = s
                        local effectiveStepIndex = getEffectiveIndex(
                                                       displayIndex, favNumGate,
                                                       favSlidePercent)
                        local miniX = favStackX + 1 + (s - 1) * miniBlockWidth
                        local miniEndX = miniX + miniBlockWidth - 1
                        local gateColor = 5
                        if favGateSeq.steps[effectiveStepIndex] and
                            favGateSeq.steps[effectiveStepIndex] <= favThreshold then
                            gateColor = 15
                        end
                        if miniEndX < miniX then
                            miniEndX = miniX
                        end
                        drawRectangle(math.floor(miniX), miniGateY,
                                      math.floor(miniEndX),
                                      miniGateY + miniBlockHeight - 1, gateColor)
                    end

                    -- Mini CV Pattern (Bottom Row) - Use effective index
                    local favEffectiveMin, favEffectiveMax = getEffectiveRange(
                                                                 favParams[4],
                                                                 favParams[5],
                                                                 favParams[6])
                    local favResolutionBits = favParams[7]
                    local favRangeEffective = favEffectiveMax - favEffectiveMin

                    for s = 1, miniSteps do
                        local displayIndex = s
                        local effectiveStepIndex = getEffectiveIndex(
                                                       displayIndex, favNumVolt,
                                                       favSlidePercent)
                        local miniX = favStackX + 1 + (s - 1) * miniBlockWidth
                        local miniEndX = miniX + miniBlockWidth - 1
                        local raw = favVoltSeq.steps[effectiveStepIndex] -- Use effective index
                        local cvColor = 1
                        if raw then
                            local voltage -- Calculate unquantized voltage (code omitted for brevity, same as before)
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
                            local quantizedVoltage =
                                quantizeVoltage(voltage, favResolutionBits,
                                                favEffectiveMin, favEffectiveMax)
                            local norm = 0
                            if favRangeEffective ~= 0 then
                                norm = (quantizedVoltage - favEffectiveMin) /
                                           favRangeEffective
                            end
                            norm = math.max(0, math.min(1, norm))
                            cvColor = math.floor(norm * 14) + 1
                        end
                        if miniEndX < miniX then
                            miniEndX = miniX
                        end
                        drawRectangle(math.floor(miniX), miniCvY,
                                      math.floor(miniEndX),
                                      miniCvY + miniBlockHeight - 1, cvColor)
                    end
                else
                    drawTinyText(favStackX + 2, currentY + 1, "idx err")
                end
            end
        end

        -- Calculate maximum available width for sequence displays
        local availableWidth = textX - 13

        -- Draw gate sequence visualization - Reverted Y position, keep effective index
        local gateSeq = gateSequences[gateIdx]
        local numGate = self.parameters[8]
        local gateBlockWidthFloat = availableWidth / numGate
        local gateBlockHeight = 10
        local gateY = 25 -- Reverted Y position
        local startX = 8.0

        drawTinyText(startX, gateY - 2, "Gate Pattern") -- Reverted Y adjustment

        for i = 1, numGate do
            local effectiveIndex = getEffectiveIndex(i, numGate, slidePercent) -- Keep this
            local currentX = startX + (i - 1) * gateBlockWidthFloat
            local nextX = startX + i * gateBlockWidthFloat
            local drawStartX = math.floor(currentX);
            local drawEndX = math.floor(nextX - 1)
            if drawEndX < drawStartX then drawEndX = drawStartX end

            local gateColor = 3
            if gateSeq.steps[effectiveIndex] and gateSeq.steps[effectiveIndex] <=
                self.parameters[9] then -- Keep using effectiveIndex
                gateColor = 15
            end
            drawRectangle(drawStartX, gateY, drawEndX,
                          gateY + gateBlockHeight - 2, gateColor)

            -- Indicator still tracks raw index
            if i == gateSeq.stepIndex then
                local lineY1 = gateY + gateBlockHeight - 1;
                local lineY2 = gateY + gateBlockHeight
                drawRectangle(drawStartX, lineY1, drawEndX, lineY2, 15)
            end
        end

        -- Draw voltage sequence visualization - Reverted Y position, keep effective index
        local voltSeq = voltageSequences[voltIdx]
        local numVolt = self.parameters[3]
        local voltBlockWidthFloat = availableWidth / numVolt
        local voltBlockHeight = 10
        local voltY = 45 -- Reverted Y position

        drawTinyText(startX, voltY - 2, "CV Pattern") -- Reverted Y adjustment

        local effectiveMin, effectiveMax =
            getEffectiveRange(self.parameters[4], self.parameters[5],
                              self.parameters[6])
        local resolutionBits = self.parameters[7]
        local rangeEffective = effectiveMax - effectiveMin

        for i = 1, numVolt do
            local effectiveIndex = getEffectiveIndex(i, numVolt, slidePercent) -- Keep this
            local currentX = startX + (i - 1) * voltBlockWidthFloat
            local nextX = startX + i * voltBlockWidthFloat
            local drawStartX = math.floor(currentX);
            local drawEndX = math.floor(nextX - 1)
            if drawEndX < drawStartX then drawEndX = drawStartX end

            local raw = voltSeq.steps[effectiveIndex] -- Keep using effectiveIndex
            local colorIndex = 1

            if raw then
                local voltage -- Calculate unquantized voltage (code omitted, same as before)
                if self.parameters[6] == 2 then
                    voltage = (raw + 32768) / 65535 *
                                  (effectiveMax - effectiveMin) + effectiveMin
                elseif self.parameters[6] == 1 then
                    voltage = (raw < 0 and 0 or raw) / 32767 *
                                  (effectiveMax - effectiveMin) + effectiveMin
                else
                    voltage = ((raw > 0 and 0 or raw) + 32768) / 32768 *
                                  (effectiveMax - effectiveMin) + effectiveMin
                end
                local quantizedVoltage =
                    quantizeVoltage(voltage, resolutionBits, effectiveMin,
                                    effectiveMax)
                local norm = 0
                if rangeEffective ~= 0 then
                    norm = (quantizedVoltage - effectiveMin) / rangeEffective
                end
                norm = math.max(0, math.min(1, norm))
                colorIndex = math.floor(norm * 14) + 1
            end

            drawRectangle(drawStartX, voltY, drawEndX,
                          voltY + voltBlockHeight - 2, colorIndex)

            -- Indicator still tracks raw index
            if i == voltSeq.currentStep then
                local lineY1 = voltY + voltBlockHeight - 1;
                local lineY2 = voltY + voltBlockHeight
                drawRectangle(drawStartX, lineY1, drawEndX, lineY2, 15)
            end
        end
        return true
    end
}
