-- Multi-dimensional L-system
--[[
  Build a melody using an L-system.

  Help:
  - Input 1: Clock Input
  - Input 2: Reset Trigger
  - Pot 1: Controls the number of iterations
--]] -- Optional: Local variables specific to this script instance
-- local myStateVariable = 0
-- local myTable = {}
-- LSystemSequencer
local LSystemSequencer = {}

-- Compatibility shim for Lua 5.1 / 5.4
local unpack = table.unpack or unpack

-- Default scale: C major (semitone offsets)
LSystemSequencer.default_scale = {0, 2, 4, 5, 7, 9, 11}

----------------------------------------------------------------------
-- Musical Scale Library
-- (Semitone offsets from root)
----------------------------------------------------------------------
local MusicalScales = {
    ["Major"] = {0, 2, 4, 5, 7, 9, 11},
    ["Natural Minor"] = {0, 2, 3, 5, 7, 8, 10},
    ["Harmonic Minor"] = {0, 2, 3, 5, 7, 8, 11},
    ["Melodic Minor"] = {0, 2, 3, 5, 7, 9, 11}, -- Ascending
    ["Major Pentatonic"] = {0, 2, 4, 7, 9},
    ["Minor Pentatonic"] = {0, 3, 5, 7, 10},
    ["Blues"] = {0, 3, 5, 6, 7, 10},
    ["Dorian"] = {0, 2, 3, 5, 7, 9, 10},
    ["Phrygian"] = {0, 1, 3, 5, 7, 8, 10},
    ["Lydian"] = {0, 2, 4, 6, 7, 9, 11},
    ["Mixolydian"] = {0, 2, 4, 5, 7, 9, 10},
    ["Locrian"] = {0, 1, 3, 5, 6, 8, 10},
    ["Whole Tone"] = {0, 2, 4, 6, 8, 10},
    ["Diminished (HW)"] = {0, 1, 3, 4, 6, 7, 9, 10},
    ["Diminished (WH)"] = {0, 2, 3, 5, 6, 8, 9, 11},
    ["Augmented"] = {0, 3, 4, 7, 8, 11}, -- Hexatonic
    ["Chromatic"] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11},
    ["Bebop Dominant"] = {0, 2, 4, 5, 7, 9, 10, 11},
    ["Hungarian Minor"] = {0, 2, 3, 6, 7, 8, 11},
    ["Phrygian Dominant"] = {0, 1, 4, 5, 7, 8, 10},
    ["Hirajoshi"] = {0, 2, 3, 7, 8}, -- Japanese
    ["Insen"] = {0, 1, 5, 7, 10}, -- Japanese
    ["Iwato"] = {0, 1, 5, 6, 10}, -- Japanese
    ["Prometheus"] = {0, 2, 4, 6, 9, 10}, -- Scriabin
    ["Yo"] = {0, 2, 5, 7, 9} -- Japanese Pentatonic
}

-- Ordered list of scale names for parameter mapping
local ScaleNames = {}
do -- Populate ScaleNames in a consistent order
    local keys = {}
    for k in pairs(MusicalScales) do table.insert(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do table.insert(ScaleNames, k) end
end

-- Root note names for parameter mapping
local RootNoteNames = {
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
}

-- Default scale: C major (semitone offsets)
-- LSystemSequencer.default_scale = {0, 2, 4, 5, 7, 9, 11} -- No longer used directly

----------------------------------------------------------------------
-- Utility helpers
----------------------------------------------------------------------

-- Pick one key from a `{ value = weight, ... }` table
-- Now a method using the stored deterministic generator
function LSystemSequencer:weighted_choice(tbl)
    local total, acc = 0, 0
    for _, w in pairs(tbl) do total = total + w end
    -- Use math.random() instead of the custom LCG
    local r = math.random() * total
    for k, w in pairs(tbl) do
        acc = acc + w
        if r <= acc then return k end
    end
end

-- Favour stepwise motion – weights can be tweaked to taste
local STEP_WEIGHTS = {[-2] = 1, [-1] = 3, [0] = 4, [1] = 3, [2] = 1}
-- Now a method using self:weighted_choice
function LSystemSequencer:weighted_step()
    return self:weighted_choice(STEP_WEIGHTS)
end

-- Triangular‑ish random number between a & b (closer to middle on average)
local function triangular_rand(a, b)
    -- Sum of two uniforms gives triangular PDF
    local u = math.random() + math.random()
    return a + (b - a) * u * 0.5 -- scale to [0,1], peak at centre
end

----------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------

function LSystemSequencer.new(config)
    local self = {}
    setmetatable(self, {__index = LSystemSequencer}) -- Allow calling methods

    ------------------------------------------------------------------
    -- Config
    ------------------------------------------------------------------
    self.axiom = config.axiom or "P"
    self.iterations = config.iterations or 3
    self.scale = config.scale or LSystemSequencer.default_scale
    self.base_note = config.base_note or 60 -- MIDI middle C
    self.velocity_range = config.velocity_range or {60, 127}
    self.duration_range = config.duration_range or {0.125, 0.5}

    -- Parameterised rule probabilities (unchanged interface)
    self.probabilities = config.probabilities or
                             {
            P = {PRP = 0.6, PV = 0.4},
            R = {RV = 0.7, RR = 0.3},
            V = {VP = 1.0}
        }

    ------------------------------------------------------------------
    -- L‑system expansion rules
    ------------------------------------------------------------------
    -- These now implicitly call self:weighted_choice via the metatable
    self.rules = {
        P = function(seq) return seq:weighted_choice(seq.probabilities.P) end,
        R = function(seq) return seq:weighted_choice(seq.probabilities.R) end,
        V = function(seq) return seq:weighted_choice(seq.probabilities.V) end
    }
    -- Store the initial generator based on config or default seed (will be overwritten by _update_sequencer_config in init)

    ------------------------------------------------------------------
    -- Expand axiom for N iterations
    ------------------------------------------------------------------
    function self:expand()
        local current = self.axiom
        for _ = 1, self.iterations do
            local next_expansion = {} -- Renamed to avoid conflict
            for i = 1, #current do
                local sym = current:sub(i, i)
                -- Pass 'self' (the sequencer object) to the rule function
                local repl = self.rules[sym] and self.rules[sym](self) or sym
                next_expansion[#next_expansion + 1] = repl
            end
            current = table.concat(next_expansion)
        end
        return current
    end

    ------------------------------------------------------------------
    -- Turn expanded symbol string into { note‑event, … }
    ------------------------------------------------------------------
    function self:interpret(symbols)
        local events = {}

        local pitch_idx = 1 -- position in scale
        local velocity = (self.velocity_range[1] + self.velocity_range[2]) / 2
        local duration = (self.duration_range[1] + self.duration_range[2]) / 2

        local scale_len = #self.scale

        for i = 1, #symbols do
            local sym = symbols:sub(i, i)

            if sym == "P" then
                ------------------------------------------------------------------
                -- Choose next scale step (mostly stepwise, occasional leaps)
                ------------------------------------------------------------------
                pitch_idx = pitch_idx + self:weighted_step() -- Call as method
                if pitch_idx < 1 then pitch_idx = 1 end

                -- Wrap into octaves for musical continuity
                local octave = math.floor((pitch_idx - 1) / scale_len)
                local degree = ((pitch_idx - 1) % scale_len) + 1
                local note = self.base_note + octave * 12 + self.scale[degree]

                -- Clamp to valid MIDI range just in case
                if note < 0 then
                    note = 0
                elseif note > 127 then
                    note = 127
                end

                ------------------------------------------------------------------
                events[#events + 1] = {
                    type = "note",
                    pitch = note,
                    velocity = math.floor(velocity),
                    duration = duration
                }

            elseif sym == "R" then
                ------------------------------------------------------------------
                -- Pick one of three quantised durations (short / mid / long)
                ------------------------------------------------------------------
                local min_d, max_d = unpack(self.duration_range)
                local mid_d = (min_d + max_d) * 0.5
                local choices = {min_d, mid_d, max_d}
                duration = choices[math.random(#choices)]

            elseif sym == "V" then
                ------------------------------------------------------------------
                -- Choose velocity with triangular distribution (natural feel)
                ------------------------------------------------------------------
                local vmin, vmax = unpack(self.velocity_range)
                velocity = triangular_rand(vmin, vmax)
            end
        end

        return events
    end

    return self
end

-- return LSystemSequencer

-- score_draw.lua ------------------------------------------------------------
-- Converts a list of note events into drawing primitives for a 256×64 display
-- Author: ChatGPT (2025‑04‑20)

local ScoreDraw = {}

--------------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------------
local DEFAULTS = {
    -- Canvas dimensions
    width = 255, -- total pixels horizontally
    height = 64, -- total pixels vertically
    left_margin = 8, -- px before the first staff line starts
    right_margin = 8, -- px after last note

    -- Staff layout
    staff_top = 22, -- y‑pixel of the top staff line
    staff_spacing = 4, -- distance in px between adjacent staff lines
    semitone_px = 2, -- vertical distance per semitone
    ledger_limit = 2, -- how many ledger lines above/below before clipping

    -- Note appearance
    ledger_line_extent_w = 5, -- width of ledger line extensions in px
    note_head_h = 3 -- height of a note head in px
}

--------------------------------------------------------------------------------
-- Utility helpers
--------------------------------------------------------------------------------
local function merge(a, b)
    local t = {}
    for k, v in pairs(a) do t[k] = v end
    if b then for k, v in pairs(b) do t[k] = v end end
    return t
end

local function max(a, b) return (a > b) and a or b end
local function min(a, b) return (a < b) and a or b end

local function ensure_times(tbl)
    if tbl[1] and tbl[1].time ~= nil then return end -- nothing to do
    for i, ev in ipairs(tbl) do
        ev.time = i - 1 -- 0‑based timeline
        ev.duration = ev.duration or 1
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
---@param events table[]  -- {time,duration,pitch,velocity}
---@param opts   table?   -- override DEFAULTS
---@return table[]        -- list of drawing instruction tables
function ScoreDraw.generate(events, opts)
    opts = merge(DEFAULTS, opts or {})
    ensure_times(events) -- Add sequential times if the user didn't supply them
    assert(#events > 0, "events table may not be empty")

    --------------------------------------------------------------------------
    -- 1. Determine time & pitch range
    --------------------------------------------------------------------------
    local last_beat, lo_pitch, hi_pitch = 0, events[1].pitch, events[1].pitch
    for _, ev in ipairs(events) do
        last_beat = max(last_beat, ev.time + ev.duration)
        lo_pitch = min(lo_pitch, ev.pitch)
        hi_pitch = max(hi_pitch, ev.pitch)
    end

    -- Expand pitch range so the outermost note sits nicely inside the staff
    local mid_pitch = math.floor((lo_pitch + hi_pitch) / 2 + 0.5)
    local staff_middle = mid_pitch -- MIDI number

    --------------------------------------------------------------------------
    -- 2. Mapping helpers
    --------------------------------------------------------------------------
    local usable_w = opts.width - opts.left_margin - opts.right_margin
    local function time2x(t)
        return opts.left_margin + (t / last_beat) * usable_w
    end

    -- Calculate the Y coordinate of the actual middle staff line (line index 2)
    local middle_line_y = opts.staff_top + (opts.staff_spacing * 2)

    local function pitch2y(p)
        -- Positive direction: down the screen

        -- 1. Calculate raw vertical offset based on semitones from middle pitch
        local raw_offset = (staff_middle - p) * opts.semitone_px

        -- 2. Calculate how many "half-spaces" this offset represents
        --    (A half-space is the distance from a line to a space center, or vice-versa)
        local half_space_distance = opts.staff_spacing / 2
        local half_space_steps = raw_offset / half_space_distance

        -- 3. Round to the nearest integer number of half-steps
        local quantized_steps = math.floor(half_space_steps + 0.5)

        -- 4. Calculate the final Y based on the middle line and quantized steps
        local final_y = middle_line_y + quantized_steps * half_space_distance

        return final_y
    end

    --------------------------------------------------------------------------
    -- 3. Start drawing list with staff lines
    --------------------------------------------------------------------------
    local inst = {}
    local staff_y0 = opts.staff_top
    for i = 0, 4 do
        local y = staff_y0 + i * opts.staff_spacing
        inst[#inst + 1] = {
            type = "line",
            x1 = opts.left_margin,
            y1 = y,
            x2 = opts.width - opts.right_margin,
            y2 = y
        }
    end

    --------------------------------------------------------------------------
    -- 4. Notes & ledger lines
    --------------------------------------------------------------------------
    for _, ev in ipairs(events) do
        -- Calculate screen coordinates and dimensions
        local start_x = time2x(ev.time)
        local end_x = time2x(ev.time + ev.duration)
        local y = pitch2y(ev.pitch)
        local head_h = opts.note_head_h
        local note_width = max(1, end_x - start_x) -- Ensure minimum width of 1px

        -- Map velocity (0-127) to grayscale (1 to 14)
        -- Maps 0 -> 1 (dark), 127 -> 14 (light gray)
        -- Higher velocity = lighter color (higher index)
        local color_val = 1 + math.floor(ev.velocity * 14 / 128)
        -- Clamp to range [1, 14] (redundant now but safe)
        color_val = max(1, min(14, color_val))

        -- Add instruction to draw the filled note rectangle with color 'c'
        inst[#inst + 1] = {
            type = "filled_rect",
            x = start_x,
            y = y - head_h / 2,
            w = note_width,
            h = head_h,
            c = color_val -- Use calculated grayscale color
        }

        ----------------------------------------------------------------------
        -- Ledger lines if needed (adjust x reference)
        ----------------------------------------------------------------------
        local ledger_pitch = ev.pitch -- Keep using pitch for calculation relative to middle
        local ledger_x = start_x -- Use start_x for ledger line horizontal position
        local ledger_half_w = opts.ledger_line_extent_w / 2 -- Use renamed option for ledger line extent

        -- Calculate the Y positions of the top and bottom staff lines
        local staff_y0 = opts.staff_top
        local staff_y4 = staff_y0 + 4 * opts.staff_spacing

        -- Check if the note's Y position is outside the main staff lines
        if y < staff_y0 or y > staff_y4 then
            -- Determine if the note's Y position corresponds to a line or a space
            -- Relative to the middle line, lines occur at even numbers of half_space_steps
            local raw_offset_check = (staff_middle - ledger_pitch) *
                                         opts.semitone_px
            local half_space_steps_check = raw_offset_check /
                                               (opts.staff_spacing / 2)
            local quantized_steps_check = math.floor(
                                              half_space_steps_check + 0.5)

            -- Only draw ledger lines if the note is supposed to be ON a line (even steps from middle)
            if quantized_steps_check % 2 == 0 then
                local lines_drawn = 0
                local current_line_y

                if y < staff_y0 then -- Note is above the staff
                    current_line_y = staff_y0 - opts.staff_spacing -- Start checking from the line above the top staff line
                    while current_line_y >= y and lines_drawn <
                        opts.ledger_limit do
                        -- Check if this ledger line's Y position is close enough to the note's Y
                        if math.abs(current_line_y - y) <
                            (opts.staff_spacing / 4) then
                            inst[#inst + 1] = {
                                type = "line",
                                x1 = ledger_x - ledger_half_w,
                                y1 = current_line_y,
                                x2 = ledger_x + ledger_half_w,
                                y2 = current_line_y,
                                c = 15 -- White color for ledger lines
                            }
                        end
                        lines_drawn = lines_drawn + 1
                        current_line_y = current_line_y - opts.staff_spacing -- Move to the next potential ledger line up
                    end
                else -- Note is below the staff
                    current_line_y = staff_y4 + opts.staff_spacing -- Start checking from the line below the bottom staff line
                    while current_line_y <= y and lines_drawn <
                        opts.ledger_limit do
                        -- Check if this ledger line's Y position is close enough to the note's Y
                        if math.abs(current_line_y - y) <
                            (opts.staff_spacing / 4) then
                            inst[#inst + 1] = {
                                type = "line",
                                x1 = ledger_x - ledger_half_w,
                                y1 = current_line_y,
                                x2 = ledger_x + ledger_half_w,
                                y2 = current_line_y,
                                c = 15 -- White color for ledger lines
                            }
                        end
                        lines_drawn = lines_drawn + 1
                        current_line_y = current_line_y + opts.staff_spacing -- Move to the next potential ledger line down
                    end
                end
            end
        end
    end

    return inst, time2x, pitch2y, opts -- Return mapping functions and options too
end
-- end of score_draw.lua ------------------------------------------------------

-- Helper function to update sequencer config based on parameters
-- This is defined outside the returned table so it can be called by init and step
local function _update_sequencer_config(self) -- Removed seed_changed parameter
    if not self.parameters or not self.param_indices or not self.sequencer then
        -- Not fully initialized yet
        return false -- Indicate no update was performed
    end

    local needs_reinterpretation_for_ranges = false -- Track if ranges changed
    local needs_reexpansion_for_probs = false -- Track if probabilities changed requiring re-expansion

    -- 1. Velocity Range (Pot 1 / Macro)
    -- Macro controls the spread around a central point.
    local vel_macro = self.parameters[self.param_indices.velocity_macro] -- 0 to 100
    local base_vel_min, base_vel_max = 0, 127
    local mid_vel = (base_vel_min + base_vel_max) / 2 -- 63.5
    local min_vel_width = 1 -- Minimum width of the range (at macro = 0)
    local max_vel_width = base_vel_max - base_vel_min -- 127 (at macro = 100)
    local current_vel_width = min_vel_width + (max_vel_width - min_vel_width) *
                                  (vel_macro / 100)
    local half_vel_width = current_vel_width / 2
    local new_vel_min = math.floor(math.max(base_vel_min,
                                            mid_vel - half_vel_width))
    local new_vel_max = math.floor(math.min(base_vel_max,
                                            mid_vel + half_vel_width))
    local new_vel_range = {new_vel_min, new_vel_max}

    if self.sequencer.velocity_range[1] ~= new_vel_range[1] or
        self.sequencer.velocity_range[2] ~= new_vel_range[2] then
        self.sequencer.velocity_range = new_vel_range
        needs_reinterpretation_for_ranges = true
    end

    -- 2. Duration Range (Pot 2 / Macro)
    -- Macro controls the spread around a central point.
    local dur_macro = self.parameters[self.param_indices.duration_macro] -- 0 to 100
    -- Center = Quarter note @ 120bpm = 0.5s
    -- Min    = 32nd note @ 120bpm = 0.0625s
    -- Max    = Whole note @ 120bpm = 2.0s
    local mid_dur = 0.5
    local base_dur_min = 0.0625
    local base_dur_max = 2.0
    local min_dur_width = 0.01 -- Minimum width of the range (at macro = 0)
    local max_dur_width = base_dur_max - base_dur_min -- 1.9375 (at macro = 100)
    local current_dur_width = min_dur_width + (max_dur_width - min_dur_width) *
                                  (dur_macro / 100)
    local half_dur_width = current_dur_width / 2
    local new_dur_min = math.max(base_dur_min, mid_dur - half_dur_width)
    local new_dur_max = math.min(base_dur_max, mid_dur + half_dur_width)
    -- Ensure min is strictly less than max, especially at low widths
    if new_dur_min >= new_dur_max then
        new_dur_max = new_dur_min + 0.001 -- Add a tiny gap
    end
    local new_dur_range = {new_dur_min, new_dur_max}

    if self.sequencer.duration_range[1] ~= new_dur_range[1] or
        self.sequencer.duration_range[2] ~= new_dur_range[2] then
        self.sequencer.duration_range = new_dur_range
        needs_reinterpretation_for_ranges = true
    end

    -- 3. Probabilities (Pot 3 Parameter - now direct control)
    local prob_param_idx = self.param_indices.probability_mix -- Use renamed index
    local prob_param_val = self.parameters[prob_param_idx] -- 0 to 127
    local normalized_prob = prob_param_val / 127.0 -- Map to 0.0 - 1.0

    -- Apply this normalized value to both P and R rules for simplicity
    local new_prob_p = {PRP = normalized_prob, PV = 1.0 - normalized_prob}
    local new_prob_r = {RV = normalized_prob, RR = 1.0 - normalized_prob}
    local new_probabilities = {P = new_prob_p, R = new_prob_r, V = {VP = 1.0}} -- V is fixed

    -- Check if probabilities actually changed (deep compare needed)
    local probs_changed = false
    -- Handle initial call where probabilities might be nil
    if not self.sequencer.probabilities or self.sequencer.probabilities.P.PRP ~=
        new_probabilities.P.PRP or self.sequencer.probabilities.R.RV ~=
        new_probabilities.R.RV then probs_changed = true end

    if probs_changed then
        self.sequencer.probabilities = new_probabilities
        -- Rule probability change requires re-expansion
        self.expanded = self.sequencer:expand()
        needs_reexpansion_for_probs = true
    end

    -- Return true if ranges changed OR probabilities led to re-expansion
    return needs_reinterpretation_for_ranges or needs_reexpansion_for_probs
end

-- Helper function to randomize the sequence
local function _randomize_sequence(self)
    print(self.name .. ": Randomizing sequence")
    -- Explicitly update the stored random generator based on current seed
    -- local prob_seed = self.parameters[self.param_indices.probability_seed] -- REMOVED
    -- self.sequencer.rand_gen = lcg(prob_seed) -- Recreate the generator -- REMOVED

    self.expanded = self.sequencer:expand()
    self.events = self.sequencer:interpret(self.expanded)
    -- Regenerate draw list and store mapping functions/options
    if #self.events > 0 then -- Avoid error if interpretation yields nothing
        self.drawlist, self.time2x, self.pitch2y, self.drawOpts =
            ScoreDraw.generate(self.events)
    else
        self.drawlist = {} -- Clear drawlist if no events
        self.events = {} -- Ensure events table is empty
    end
    self.eventIdx = 1 -- Restart playback from the first event
end

-- The main table returned by the script
return {
    -- == Required Metadata ==
    name = "L-system", -- Short name, often matches the first comment line
    author = "Thorinside", -- Your name or alias

    -- == Initialization Function (Called once on script load) ==
    init = function(self)
        print(self.name .. ": init called") -- Use self.name for consistency

        -- Default values for parameters if not loaded from state
        local initial_iterations = 3
        local initial_randomize = 1 -- Off
        local initial_root_note_idx = 1 -- C (index 1 in RootNoteNames)
        local initial_scale_idx = 1 -- Default to first scale if Major not found
        for i, name in ipairs(ScaleNames) do
            if name == "Major" then
                initial_scale_idx = i
                break
            end
        end
        local initial_base_midi = 48 -- Default base MIDI note (C3)
        local initial_velocity_macro = 50 -- Default middle range
        local initial_duration_macro = 50 -- Default middle range
        local initial_probability_mix = 64 -- Default mid-point (0.5 probability, 0-127 range)

        -- Access state loaded from preset (if serialise is used)
        if self.state then
            print(self.name .. ": Found saved state")
            initial_iterations = self.state.iterations or initial_iterations
            initial_randomize = self.state.randomize or initial_randomize
            initial_root_note_idx = self.state.root_note_idx or
                                        initial_root_note_idx
            initial_scale_idx = self.state.scale_idx or initial_scale_idx
            initial_velocity_macro = self.state.velocity_macro or
                                         initial_velocity_macro
            initial_duration_macro = self.state.duration_macro or
                                         initial_duration_macro
            initial_probability_mix = self.state.probability_mix or
                                          initial_probability_mix -- Load saved mix value
            -- Note: We calculate base_midi from root_note_idx, don't need to save it directly
        end

        -- Store parameter indices for later use in step/trigger/etc.
        -- Ensure these are defined *before* parameters table and _update_sequencer_config call
        self.param_indices = {
            iterations = 1,
            root_note = 2,
            scale = 3,
            velocity_macro = 4, -- New Pot 1
            duration_macro = 5, -- New Pot 2
            probability_mix = 6, -- Renamed index for Pot 3
            randomize = 7 -- Moved to last
        }

        -- Store current parameters locally for _update_sequencer_config
        -- We need this because self.parameters is not fully populated until the return
        local current_params = {}
        current_params[self.param_indices.iterations] = initial_iterations
        current_params[self.param_indices.root_note] = initial_root_note_idx
        current_params[self.param_indices.scale] = initial_scale_idx
        current_params[self.param_indices.velocity_macro] =
            initial_velocity_macro
        current_params[self.param_indices.duration_macro] =
            initial_duration_macro
        current_params[self.param_indices.probability_mix] =
            initial_probability_mix -- Use renamed index
        current_params[self.param_indices.randomize] = initial_randomize
        self.parameters = current_params -- Temporarily assign for helper

        -- Calculate base MIDI note (e.g., C3 + root note offset)
        local root_offset = initial_root_note_idx - 1
        local base_midi_note = initial_base_midi + root_offset

        -- Get selected scale pattern
        local selected_scale_name = ScaleNames[initial_scale_idx]
        local selected_scale = MusicalScales[selected_scale_name]

        -- Create a temporary config table based on initial parameters
        -- The sequencer object will be configured by the helper function
        local temp_config = {
            axiom = "P",
            iterations = initial_iterations,
            base_note = base_midi_note,
            scale = selected_scale
            -- probability_seed removed
            -- velocity_range, duration_range, probabilities will be set by helper
        }
        self.sequencer = LSystemSequencer.new(temp_config)

        -- Now call the helper to calculate and apply ranges/probabilities
        _update_sequencer_config(self) -- No longer needs seed_changed flag

        -- Initial expansion and interpretation (uses the just-set rand_gen and probabilities)
        self.events = self.sequencer:interpret(self.expanded)

        -- Generate draw list and store mapping functions/options
        if #self.events > 0 then -- Handle empty interpretation result
            self.drawlist, self.time2x, self.pitch2y, self.drawOpts =
                ScoreDraw.generate(self.events)
        else
            self.drawlist = {} -- Ensure drawlist is empty if no events
            self.events = {} -- Ensure events is empty
            -- Assign dummy functions/opts to avoid errors later if needed
            self.time2x = function() return 0 end
            self.pitch2y = function() return 0 end
            self.drawOpts = {}
        end

        -- Store name tables for use in draw function
        self.RootNoteNames = RootNoteNames
        self.ScaleNames = ScaleNames

        -- Store initial parameters to detect changes in step()
        self.last_parameters = {}
        for k, v in pairs(self.parameters) do self.last_parameters[k] = v end
        -- Restore self.parameters to nil so the framework populates it correctly upon return
        self.parameters = nil

        -- Define Inputs, Outputs, and Parameters
        return {
            inputs = {kGate, kTrigger, kTrigger},
            inputNames = {[1] = "Clock", [2] = "Reset", [3] = "Randomize"},

            outputs = {kGate, kStepped, kStepped},
            outputNames = {"Gate Output", "Pitch Output", "Velocity Output"},

            parameters = {
                [self.param_indices.iterations] = {
                    "Iterations", 1, 5, initial_iterations
                },
                [self.param_indices.root_note] = {
                    "Root Note", RootNoteNames, initial_root_note_idx
                },
                [self.param_indices.scale] = {
                    "Scale", ScaleNames, initial_scale_idx
                },
                [self.param_indices.velocity_macro] = {
                    "Velocity Macro", 0, 100, initial_velocity_macro
                },
                [self.param_indices.duration_macro] = {
                    "Duration Macro", 0, 100, initial_duration_macro
                },
                [self.param_indices.probability_mix] = { -- Renamed parameter and index
                    "Probability Mix", 0, 127, initial_probability_mix
                },
                [self.param_indices.randomize] = {
                    "Randomize", {"Off", "On"}, initial_randomize
                }
            }
        }
    end,

    ----------------------------------------------------------------------
    --  Gate‑driven L‑system playback
    --  • Input 1  : kGate clock
    --  • Output 1 : Gate  (0 / 5 V)
    --  • Output 2 : Pitch (V/Oct, 0 V = C3)
    --  • Output 3 : Velocity (0‑10 V)
    ----------------------------------------------------------------------

    gate = function(self, input, rising)
        --------------------------------------------------------------------
        -- Ignore any gate that isn't our clock on input #1
        --------------------------------------------------------------------
        if input ~= 1 then return end

        -- Only act on the rising edge
        if not rising then return end

        --------------------------------------------------------------------
        -- Check if Randomize parameter is On (index 4, value 2 = "On")
        --------------------------------------------------------------------
        if self.parameters[self.param_indices.randomize] == 2 then
            -- Randomize sequence using the helper function
            _randomize_sequence(self)
            -- Reset Randomize parameter back to "Off" (value 1)
            setParameter(getCurrentAlgorithm(),
                         self.parameterOffset + self.param_indices.randomize, 1)
        end

        --------------------------------------------------------------------
        -- Lazy state initialisation
        --------------------------------------------------------------------
        self.eventIdx = self.eventIdx or 1
        self.outState = self.outState or {0, 0, 0} -- {gate, pitch, vel}

        if not (self.events and #self.events > 0) -- nothing to play
        then return end

        --------------------------------------------------------------------
        -- Fetch next event and convert to voltages
        --------------------------------------------------------------------
        local ev = self.events[self.eventIdx]
        self.eventIdx = (self.eventIdx % #self.events) + 1 -- wrap

        local gateV = 5.0
        local pitchV = (ev.pitch - 48) / 12 -- 0 V =C3
        local velV = ev.velocity / 127 * 10 -- 0‑10 V

        self.outState[1], self.outState[2], self.outState[3] = gateV, pitchV,
                                                               velV

        self.gateTimer = ev.duration or 0.25 -- seconds high
    end,

    ----------------------------------------------------------------------
    --  Regular per‑frame housekeeping
    ----------------------------------------------------------------------

    step = function(self, dt, inputs)
        local needs_update = false
        local needs_reinterpretation = false

        --------------------------------------------------------------------
        -- 1. Check for parameter changes that require sequence update
        --------------------------------------------------------------------
        -- Check Iterations (requires re-expansion)
        local iterations_idx = self.param_indices.iterations
        if self.parameters[iterations_idx] ~=
            self.last_parameters[iterations_idx] then
            self.sequencer.iterations = self.parameters[iterations_idx]
            self.expanded = self.sequencer:expand() -- Re-expand here for iteration changes
            needs_reinterpretation = true -- Re-interpretation follows re-expansion
            self.last_parameters[iterations_idx] =
                self.parameters[iterations_idx]
        end

        -- Check Root Note (requires re-interpretation)
        local root_note_idx_param = self.param_indices.root_note
        if self.parameters[root_note_idx_param] ~=
            self.last_parameters[root_note_idx_param] then
            local current_root_idx = self.parameters[root_note_idx_param]
            local root_offset = current_root_idx - 1
            local base_midi_note = 48 + root_offset -- Assuming C3 (48) as the base octave
            if base_midi_note ~= self.sequencer.base_note then
                self.sequencer.base_note = base_midi_note
                needs_reinterpretation = true
            end
            self.last_parameters[root_note_idx_param] =
                self.parameters[root_note_idx_param]
        end

        -- Check Scale (requires re-interpretation)
        local scale_idx_param = self.param_indices.scale
        if self.parameters[scale_idx_param] ~=
            self.last_parameters[scale_idx_param] then
            local current_scale_idx = self.parameters[scale_idx_param]
            local current_scale_name = ScaleNames[current_scale_idx]
            local current_scale = MusicalScales[current_scale_name]
            -- Deep compare tables (simple reference compare won't work)
            local scale_changed = (#current_scale ~= #self.sequencer.scale)
            if not scale_changed then
                for i = 1, #current_scale do
                    if current_scale[i] ~= self.sequencer.scale[i] then
                        scale_changed = true
                        break
                    end
                end
            end
            if scale_changed then
                self.sequencer.scale = current_scale
                needs_reinterpretation = true
            end
            self.last_parameters[scale_idx_param] =
                self.parameters[scale_idx_param]
        end

        -- Check Velocity Macro, Duration Macro, Probability Mix
        local velocity_macro_idx = self.param_indices.velocity_macro
        local duration_macro_idx = self.param_indices.duration_macro
        local probability_mix_idx = self.param_indices.probability_mix

        local config_params_changed = false

        if self.parameters[velocity_macro_idx] ~=
            self.last_parameters[velocity_macro_idx] then
            config_params_changed = true
        end
        if self.parameters[duration_macro_idx] ~=
            self.last_parameters[duration_macro_idx] then
            config_params_changed = true
        end
        if self.parameters[probability_mix_idx] ~=
            self.last_parameters[probability_mix_idx] then
            config_params_changed = true
        end

        if config_params_changed then
            -- Call helper to update sequencer ranges/probabilities/generator
            if _update_sequencer_config(self) then
                -- Helper returned true, meaning re-interpretation (and maybe re-expansion) is needed
                needs_reinterpretation = true
            end
            -- Update last known values AFTER calling the helper
            self.last_parameters[velocity_macro_idx] =
                self.parameters[velocity_macro_idx]
            self.last_parameters[duration_macro_idx] =
                self.parameters[duration_macro_idx]
            self.last_parameters[probability_mix_idx] =
                self.parameters[probability_mix_idx]
        end

        --------------------------------------------------------------------
        -- 2. If any relevant parameter changed, update events and drawing
        --------------------------------------------------------------------
        if needs_reinterpretation then
            -- expand() is now called *inside* _update_sequencer_config if probabilities changed.
            -- We only need to call interpret() here using the (potentially updated) self.expanded string.
            self.events = self.sequencer:interpret(self.expanded)
            -- Regenerate draw list and store mapping functions/options
            if #self.events > 0 then -- Avoid error if interpretation yields nothing
                self.drawlist, self.time2x, self.pitch2y, self.drawOpts =
                    ScoreDraw.generate(self.events)
            else
                self.drawlist = {} -- Clear drawlist if no events
                self.events = {} -- Ensure events table is empty
                -- Assign dummy functions/opts to avoid errors later if needed
                self.time2x = function() return 0 end
                self.pitch2y = function() return 0 end
                self.drawOpts = {}
            end
            self.eventIdx = 1 -- Restart sequence from the beginning
        end

        --------------------------------------------------------------------
        -- 3. Handle gate-off timing (moved down)
        --------------------------------------------------------------------
        if self.gateTimer and self.gateTimer > 0 then
            self.gateTimer = self.gateTimer - dt
            if self.gateTimer <= 0 and self.outState and self.outState[1] ~= 0 then
                self.outState[1] = 0 -- gate LOW
            end
        end

        return self.outState -- only outputs that changed
    end,

    ----------------------------------------------------------------------
    --  kTrigger handler – resets the play‑head to the first event
    --  (Wire a rising‑edge pulse into Input 2.)
    ----------------------------------------------------------------------

    trigger = function(self, input)
        if input == 3 then
            -- Randomize sequence using the helper function
            _randomize_sequence(self)
        end

        -- Restart playback from the first event
        self.eventIdx = 1

        -- Kill any gate that might still be high
        self.gateTimer = 0

        if self.outState and self.outState[1] ~= 0 then
            self.outState[1] = 0 -- gate LOW
        end
    end,

    -- == Drawing Function (Called every ~33ms / 30fps if defined) ==
    draw = function(self)

        drawTinyText(8, 12, "L-System Sequencer")

        -- Draw current Root Note and Scale
        if self.parameters and self.param_indices and self.RootNoteNames and
            self.ScaleNames and self.sequencer then
            local root_idx = self.parameters[self.param_indices.root_note]
            local scale_idx = self.parameters[self.param_indices.scale]

            local root_name = self.RootNoteNames[root_idx]
            local scale_name = self.ScaleNames[scale_idx]
            local base_midi = self.sequencer.base_note
            local octave = math.floor(base_midi / 12) - 1

            local display_str = root_name .. octave .. " " .. scale_name
            local text_width = #display_str * 4 -- Tiny text character width
            local screen_width = 255 -- Fixed screen width
            local margin = 8
            local x_pos = screen_width - text_width - margin

            drawTinyText(x_pos, 12, display_str)

            -- Draw macro values below the root/scale
            local vel_macro = self.parameters[self.param_indices.velocity_macro]
            local dur_macro = self.parameters[self.param_indices.duration_macro]
            local prob_seed =
                self.parameters[self.param_indices.probability_mix]

            -- Format the string (ensure values are rounded/integers for display)
            local macro_str = string.format("V:%d D:%d P:%d", vel_macro,
                                            dur_macro, prob_seed)
            local macro_text_width = #macro_str * 4
            local macro_x_pos = screen_width - macro_text_width - margin

            drawTinyText(macro_x_pos, 20, macro_str) -- Draw on the next line (y=20)
        end

        -- 1. Draw the static score elements
        if self.drawlist then
            for _, d in ipairs(self.drawlist) do
                local color = d.c or 3
                if d.type == "line" then
                    drawLine(d.x1, d.y1, d.x2, d.y2, color)
                elseif d.type == "filled_rect" then
                    drawRectangle(d.x, d.y, d.x + d.w, d.y + d.h, color)
                    drawBox(d.x, d.y, d.x + d.w, d.y + d.h,
                            math.min(color + 6, 15))
                elseif d.type == "rect" then
                    drawBox(d.x, d.y, d.x + d.w, d.y + d.h, color)
                elseif d.type == "circle" then
                    drawCircle(d.x, d.y, d.r, color)
                end
                -- No need for setColor() handling
            end
        end

        -- 2. Highlight the current event
        if self.eventIdx and self.events and self.time2x and self.pitch2y and
            self.drawOpts then
            local ev = self.events[self.eventIdx]
            if ev then
                local x = self.time2x(ev.time)
                local y = self.pitch2y(ev.pitch)
                local r = self.drawOpts.note_head_h + 1 -- Slightly larger radius

                -- Use default color (white=1) for highlight circle, offset x by +1
                drawCircle(x + 1, y, r, 15)
            end
        end

        return true
    end,

    ui = function(self)
        -- Return true if this script handles UI events directly
        -- (pots, encoders, buttons) via the functions below.
        -- If true, setupUi and the relevant handlers should usually be defined.
        return true
    end,

    encoder1Turn = function(self, delta)
        local algIdx = getCurrentAlgorithm()
        local paramIdx = self.param_indices.root_note
        local currentVal = self.parameters[paramIdx]
        local numOptions = #self.RootNoteNames
        local newVal = currentVal + delta
        -- Clamp the value
        newVal = math.max(1, math.min(newVal, numOptions))
        if newVal ~= currentVal then
            setParameter(algIdx, self.parameterOffset + paramIdx, newVal)
        end
    end,

    encoder2Turn = function(self, delta)
        local algIdx = getCurrentAlgorithm()
        local paramIdx = self.param_indices.scale
        local currentVal = self.parameters[paramIdx]
        local numOptions = #self.ScaleNames
        local newVal = currentVal + delta
        -- Clamp the value
        newVal = math.max(1, math.min(newVal, numOptions))
        if newVal ~= currentVal then
            setParameter(algIdx, self.parameterOffset + paramIdx, newVal)
        end
    end,

    encoder2Push = function(self)
        -- Randomize sequence using the helper function
        _randomize_sequence(self)
    end,

    setupUi = function(self)
        -- Called when the UI is focused on this script if ui() returns true.
        -- Returns the current normalized values for the parameters controlled by pots
        -- to synchronize the hardware display/behavior.
        print(self.name .. ": setupUi called")
        local pot_values = {}
        if self.parameters and self.param_indices then
            local vel_macro = self.parameters[self.param_indices.velocity_macro]
            local dur_macro = self.parameters[self.param_indices.duration_macro]
            local prob_seed =
                self.parameters[self.param_indices.probability_mix]

            -- Normalize values (0-100 for macros, 0-127 for seed)
            pot_values[1] = math.max(0.0, math.min(1.0, vel_macro / 100.0))
            pot_values[2] = math.max(0.0, math.min(1.0, dur_macro / 100.0))
            pot_values[3] = math.max(0.0, math.min(1.0, prob_seed / 127.0)) -- Prob Macro normalized
        else
            -- Return defaults (e.g., 0.5) if parameters aren't ready yet
            pot_values[1] = 0.5
            pot_values[2] = 0.5
            pot_values[3] = 0.5
        end
        return pot_values -- Return { [1]=norm_val1, [2]=norm_val2, [3]=norm_val3 }
    end,

    -- Pot handlers
    pot1Turn = function(self, value) -- Controls Velocity Macro (0-100)
        local algIdx = getCurrentAlgorithm()
        local paramIdx = self.param_indices.velocity_macro
        -- Map pot 0.0-1.0 to parameter 0-100
        local newVal = value * 100
        newVal = math.max(0, math.min(newVal, 100)) -- Clamp 0-100
        setParameter(algIdx, self.parameterOffset + paramIdx, newVal)
    end,

    pot2Turn = function(self, value) -- Controls Duration Macro (0-100)
        local algIdx = getCurrentAlgorithm()
        local paramIdx = self.param_indices.duration_macro
        -- Map pot 0.0-1.0 to parameter 0-100
        local newVal = value * 100
        newVal = math.max(0, math.min(newVal, 100)) -- Clamp 0-100
        setParameter(algIdx, self.parameterOffset + paramIdx, newVal)
    end,

    pot3Turn = function(self, value) -- Controls Probability Mix (0-127)
        local algIdx = getCurrentAlgorithm()
        local paramIdx = self.param_indices.probability_mix -- Use renamed index
        -- Map pot 0.0-1.0 to parameter 0-127
        local newVal = value * 127
        newVal = math.max(0, math.min(newVal, 127)) -- Clamp 0-127
        setParameter(algIdx, self.parameterOffset + paramIdx, newVal)
    end,

    -- Add serialise function to save state
    serialise = function(self)
        local state = {}
        if self.parameters and self.param_indices then
            state.iterations = self.parameters[self.param_indices.iterations]
            state.root_note_idx = self.parameters[self.param_indices.root_note]
            state.scale_idx = self.parameters[self.param_indices.scale]
            state.velocity_macro = self.parameters[self.param_indices
                                       .velocity_macro]
            state.duration_macro = self.parameters[self.param_indices
                                       .duration_macro]
            state.probability_mix = self.parameters[self.param_indices
                                        .probability_mix] -- Save mix value
            state.randomize = self.parameters[self.param_indices.randomize]
            print(self.name .. ": Serialising state")
        else
            print(self.name .. ": Cannot serialise, parameters not available")
        end
        return state
    end

} -- End of main return table
