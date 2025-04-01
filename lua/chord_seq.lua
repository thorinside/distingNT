--[[
Markov Chord Seq v1.16
Generates 4-note (7th) chord progressions using Markov chains.
Key changes trigger transition chord on NEXT clock pulse, resolve on subsequent clock.
Moved chord/voltage calculations out of step() into gate()/trigger().
Outputs V/Oct on A/B/C/D with SATB voicing.
Uses kGate Clock (Input 1) and kTrigger Reset (Input 2).

Scales: Major, Nat Minor, Harm Minor, Dorian, Phrygian, Phrygian Dom, etc.
Matrices: Standard, Resolving, Wandering, Ambient, Minimal Cycle, etc.
Transitions: V7, iv, bVII, dim7, Random
]] -- Helper function: MIDI note to V/Oct
local function midi_note_to_volts(note) return (note - 60.0) / 12.0 end

-- Helper function: Note name from MIDI note
local note_names = {
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
}
local function get_note_name(note)
    if note == nil then return "---" end
    local o = math.floor(note / 12) - 1;
    local n = note_names[(note % 12) + 1];
    return n .. o
end

-- Helper function: Choose next Markov state
local function select_next_state(probs)
    local r = math.random();
    local c = 0.0;
    for next_s, p in pairs(probs) do
        c = c + p;
        if r < c then return next_s end
    end
    local lk = 1;
    for k, _ in pairs(probs) do lk = k end
    return lk
end

-- Helper function: Apply Voicing and Inversion
local function apply_voicing(self, chord_tones)
    -- Remove diagnostic checks

    if not chord_tones or #chord_tones ~= 4 then return {60, 60, 60, 60} end

    if type(self) ~= "table" or type(self.parameters) ~= "table" then
        -- Should not happen if called correctly, but safety return
        return {60, 60, 60, 60}
    end

    local inversion = self.parameters[6] -- Get inversion param (1=Root, 2=1st, 3=2nd, 4=3rd)
    if inversion == nil or inversion < 1 or inversion > 4 then inversion = 1 end -- Default to root, handle nil

    -- 1. Select the bass note based on inversion
    local bass_note_idx = inversion -- 1=Root, 2=3rd, 3=5th, 4=7th
    local bass_note = chord_tones[bass_note_idx]

    -- 2. Place the bass note in a lower octave (e.g., around MIDI 48 / C3)
    -- Adjust bass_note octave
    while bass_note >= 60 do bass_note = bass_note - 12 end
    while bass_note < 48 do bass_note = bass_note + 12 end

    -- 3. Arrange remaining notes above the bass note
    local remaining_notes = {}
    local ri = 1
    for i = 1, 4 do
        if i ~= bass_note_idx then
            remaining_notes[ri] = chord_tones[i]
            ri = ri + 1
        end
    end

    -- 4. Sort remaining notes and adjust octaves to be above the previous note
    table.sort(remaining_notes)
    local voiced_notes = {bass_note}
    local prev_note = bass_note
    for i = 1, 3 do
        local current_note = remaining_notes[i]
        -- Adjust octave to be >= previous note
        while current_note < prev_note do
            current_note = current_note + 12
        end
        -- Optional refinement: Could try to minimize leaps here later
        voiced_notes[i + 1] = current_note
        prev_note = current_note
    end

    -- Ensure final output matches SATB order (Bass, Tenor, Alto, Soprano)
    -- We need to re-sort the upper 3 voices based on final pitch
    local upper_voices = {voiced_notes[2], voiced_notes[3], voiced_notes[4]}
    table.sort(upper_voices)

    -- Return final voiced chord {Bass, Tenor, Alto, Soprano}
    return {voiced_notes[1], upper_voices[1], upper_voices[2], upper_voices[3]}
end

-- =======================
-- Main Script Table
-- =======================
return {
    name = "Markov Chord Seq",
    author = "AI Assistant & User",
    SCRIPT_VERSION = 1, -- Version for state compatibility

    init = function(self)
        -- Define state locally for easier access, handling nil case
        local state = self.state
        local use_loaded_state = false

        -- Check state version compatibility and LOG CONTENTS
        if state and type(state) == "table" then
            if state.script_version and state.script_version ==
                self.SCRIPT_VERSION then
                use_loaded_state = true
                -- Keep state as is
            elseif state.script_version then
                state = {} -- Discard incompatible state
            else
                state = {} -- Discard unversioned state
            end
        elseif state then
            state = {} -- Discard invalid state
        else
            state = {} -- Ensure state is an empty table if self.state was nil
        end

        -- Scale Definitions (Same)
        self.scales = {
            ["Major"] = {0, 2, 4, 5, 7, 9, 11},
            ["Dorian"] = {0, 2, 3, 5, 7, 9, 10},
            ["Phrygian"] = {0, 1, 3, 5, 7, 8, 10},
            ["Lydian"] = {0, 2, 4, 6, 7, 9, 11},
            ["Mixolydian"] = {0, 2, 4, 5, 7, 9, 10},
            ["Nat Minor"] = {0, 2, 3, 5, 7, 8, 10},
            ["Locrian"] = {0, 1, 3, 5, 6, 8, 10},
            ["Harm Minor"] = {0, 2, 3, 5, 7, 8, 11},
            ["Phrygian Dom"] = {0, 1, 4, 5, 7, 8, 10},
            ["Hungarian Min"] = {0, 2, 3, 6, 7, 8, 11},
            ["Blues Hexa"] = {0, 3, 5, 6, 7, 10},
            ["Hirajoshi"] = {0, 2, 3, 7, 8},
            ["Miyako Bushi"] = {0, 1, 5, 7, 8},
            ["Prometheus"] = {0, 2, 4, 6, 9, 10},
            ["Whole Tone"] = {0, 2, 4, 6, 8, 10},
            ["Octatonic H-W"] = {0, 1, 3, 4, 6, 7, 9, 10}
        }
        self.scale_names = {};
        local i = 1;
        for name, _ in pairs(self.scales) do
            self.scale_names[i] = name;
            i = i + 1;
        end
        table.sort(self.scale_names)

        -- Markov Matrices (Same)
        self.matrices = {
            ["Standard"] = {
                [1] = {[4] = 0.4, [5] = 0.3, [2] = 0.15, [6] = 0.15},
                [2] = {[5] = 0.6, [7] = 0.3, [3] = 0.1},
                [3] = {[6] = 0.6, [4] = 0.3, [1] = 0.1},
                [4] = {[5] = 0.5, [1] = 0.2, [7] = 0.15, [2] = 0.15},
                [5] = {[1] = 0.6, [6] = 0.2, [3] = 0.1, [4] = 0.1},
                [6] = {[2] = 0.5, [4] = 0.3, [5] = 0.2},
                [7] = {[1] = 0.7, [5] = 0.3}
            },
            ["Resolving"] = {
                [1] = {[4] = 0.5, [5] = 0.3, [2] = 0.2},
                [2] = {[5] = 0.8, [7] = 0.2},
                [3] = {[6] = 0.7, [4] = 0.3},
                [4] = {[1] = 0.4, [5] = 0.4, [2] = 0.2},
                [5] = {[1] = 0.8, [6] = 0.1, [3] = 0.1},
                [6] = {[2] = 0.6, [5] = 0.4},
                [7] = {[1] = 0.9, [5] = 0.1}
            },
            ["Wandering"] = {
                [1] = {[2] = 0.3, [7] = 0.3, [4] = 0.2, [6] = 0.2},
                [2] = {[3] = 0.4, [1] = 0.3, [5] = 0.2, [4] = 0.1},
                [3] = {[4] = 0.4, [2] = 0.3, [6] = 0.2, [1] = 0.1},
                [4] = {[5] = 0.4, [3] = 0.3, [1] = 0.15, [2] = 0.15},
                [5] = {[6] = 0.4, [4] = 0.3, [1] = 0.1, [7] = 0.2},
                [6] = {[7] = 0.4, [5] = 0.3, [2] = 0.15, [3] = 0.15},
                [7] = {[1] = 0.4, [6] = 0.3, [5] = 0.15, [2] = 0.15}
            },
            ["Ambient"] = {
                [1] = {[1] = 0.3, [4] = 0.3, [2] = 0.2, [6] = 0.2},
                [2] = {[2] = 0.3, [5] = 0.3, [4] = 0.2, [1] = 0.2},
                [3] = {[3] = 0.4, [6] = 0.3, [4] = 0.3},
                [4] = {[4] = 0.3, [1] = 0.3, [5] = 0.2, [2] = 0.2},
                [5] = {[5] = 0.3, [1] = 0.2, [4] = 0.3, [6] = 0.2},
                [6] = {[6] = 0.3, [2] = 0.3, [4] = 0.2, [5] = 0.2},
                [7] = {[7] = 0.4, [1] = 0.3, [5] = 0.3}
            },
            ["Minimal Cycle"] = {
                [1] = {[7] = 0.4, [4] = 0.4, [6] = 0.2},
                [2] = {[5] = 0.9, [1] = 0.1},
                [3] = {[6] = 0.9, [1] = 0.1},
                [4] = {[5] = 0.5, [7] = 0.3, [1] = 0.2},
                [5] = {[1] = 0.6, [6] = 0.4},
                [6] = {[7] = 0.5, [2] = 0.5},
                [7] = {[1] = 0.5, [6] = 0.5}
            },
            ["Jazzish Cycle"] = {
                [1] = {[4] = 0.5, [2] = 0.3, [6] = 0.2},
                [2] = {[5] = 0.8, [1] = 0.1, [7] = 0.1},
                [3] = {[6] = 0.7, [2] = 0.3},
                [4] = {[7] = 0.5, [5] = 0.2, [1] = 0.15, [3] = 0.15},
                [5] = {[1] = 0.7, [3] = 0.15, [6] = 0.15},
                [6] = {[2] = 0.7, [5] = 0.3},
                [7] = {[3] = 0.6, [1] = 0.2, [4] = 0.2}
            },
            ["Techno Minor"] = {
                [1] = {[6] = 0.4, [7] = 0.4, [4] = 0.1, [1] = 0.1},
                [2] = {[1] = 0.8, [5] = 0.2},
                [3] = {[6] = 0.8, [1] = 0.2},
                [4] = {[1] = 0.5, [7] = 0.4, [5] = 0.1},
                [5] = {[1] = 0.9, [6] = 0.1},
                [6] = {[7] = 0.5, [1] = 0.4, [6] = 0.1},
                [7] = {[1] = 0.5, [6] = 0.4, [7] = 0.1}
            },
            ["House Minor"] = {
                [1] = {[4] = 0.5, [7] = 0.3, [2] = 0.1, [1] = 0.1},
                [2] = {[5] = 0.7, [1] = 0.3},
                [3] = {[1] = 0.8, [6] = 0.2},
                [4] = {[5] = 0.4, [7] = 0.4, [1] = 0.2},
                [5] = {[1] = 0.8, [4] = 0.2},
                [6] = {[2] = 0.6, [7] = 0.4},
                [7] = {[1] = 0.6, [4] = 0.3, [7] = 0.1}
            },
            ["Deep Modal"] = {
                [1] = {[2] = 0.4, [4] = 0.4, [7] = 0.1, [1] = 0.1},
                [2] = {[5] = 0.7, [4] = 0.2, [1] = 0.1},
                [3] = {[2] = 0.8, [6] = 0.2},
                [4] = {[5] = 0.5, [2] = 0.3, [1] = 0.2},
                [5] = {[1] = 0.6, [2] = 0.2, [4] = 0.2},
                [6] = {[2] = 0.7, [5] = 0.3},
                [7] = {[1] = 0.6, [4] = 0.4}
            },
            ["Static Drone"] = {
                [1] = {
                    [1] = 0.8,
                    [4] = 0.05,
                    [5] = 0.05,
                    [7] = 0.05,
                    [2] = 0.05
                },
                [2] = {[1] = 0.9, [2] = 0.1},
                [3] = {[1] = 0.9, [3] = 0.1},
                [4] = {[1] = 0.9, [4] = 0.1},
                [5] = {[1] = 0.9, [5] = 0.1},
                [6] = {[1] = 0.9, [6] = 0.1},
                [7] = {[1] = 0.9, [7] = 0.1}
            }
        }
        self.matrix_names = {};
        i = 1;
        for name, _ in pairs(self.matrices) do
            self.matrix_names[i] = name;
            i = i + 1;
        end
        table.sort(self.matrix_names)

        -- Clock Div Options
        self.clock_division_options = {
            "1", "2", "3", "4", "6", "8", "12", "16", "24", "32"
        };
        self.clock_division_values = {1, 2, 3, 4, 6, 8, 12, 16, 24, 32};

        -- Transition Type Options
        self.transition_options_param = {"V7", "iv", "bVII", "dim7", "Random"};
        self.transition_options = {"V7", "iv", "bVII", "dim7"};

        -- Inversion Options
        local inversion_options = {"Root", "1st", "2nd", "3rd"} -- Define locally for param def

        -- Parameter Defaults (Used ONLY for the definition table)
        local default_root = 0
        local default_scale_idx = 1
        local default_matrix_idx = 1
        local default_clock_div_idx = 4
        local default_transition_idx = 5
        local default_inversion_idx = 1

        -- --- Load or Set Parameter INDICES ---
        -- Use loaded index from state, or fallback to default index
        local loaded_root = state.current_root or default_root -- Root itself is stored
        local loaded_scale_idx = state.scale_index or default_scale_idx
        local loaded_matrix_idx = state.matrix_index or default_matrix_idx
        local loaded_clock_div_idx = state.clock_division_index or
                                         default_clock_div_idx
        local loaded_transition_idx = state.transition_index or
                                          default_transition_idx
        local loaded_inversion_idx = state.inversion_index or
                                         default_inversion_idx

        -- Validate loaded indices (prevent errors if saved state is somehow invalid)
        if loaded_scale_idx < 1 or loaded_scale_idx > #self.scale_names then
            loaded_scale_idx = default_scale_idx
        end
        if loaded_matrix_idx < 1 or loaded_matrix_idx > #self.matrix_names then
            loaded_matrix_idx = default_matrix_idx
        end
        if loaded_clock_div_idx < 1 or loaded_clock_div_idx >
            #self.clock_division_values then
            loaded_clock_div_idx = default_clock_div_idx
        end
        if loaded_transition_idx < 1 or loaded_transition_idx >
            #self.transition_options_param then
            loaded_transition_idx = default_transition_idx
        end
        if loaded_inversion_idx < 1 or loaded_inversion_idx > #inversion_options then
            loaded_inversion_idx = default_inversion_idx
        end
        if loaded_root < 0 or loaded_root > 11 then
            loaded_root = default_root
        end

        -- --- Initialize Internal State Variables ---
        -- Use the effective loaded/default values
        self.current_root = loaded_root
        self.target_root = state.target_root or self.current_root -- Target might differ if saved mid-change

        self.current_scale_name = self.scale_names[loaded_scale_idx]
        self.target_scale_idx = loaded_scale_idx
        self.scale_change_pending = state.scale_change_pending or false

        self.current_matrix_name = self.matrix_names[loaded_matrix_idx]
        self.current_scale_intervals = self.scales[self.current_scale_name]
        self.current_matrix = self.matrices[self.current_matrix_name]
        self.current_scale_degree = state.current_scale_degree or 1

        self.key_change_pending = state.key_change_pending or false
        self.is_playing_transition_chord =
            state.is_playing_transition_chord or false;
        self.root_after_transition = state.root_after_transition

        self.clock_division_steps =
            self.clock_division_values[loaded_clock_div_idx];
        self.internal_clock_count = state.internal_clock_count or 0;

        self.transition_type =
            self.transition_options_param[loaded_transition_idx]

        -- --- Initialize Previous Parameter Tracker ---
        -- This MUST reflect the parameter values the script is starting with
        self.previous_parameters = {
            [1] = self.target_root, -- Reflects Param 1 value on load
            [2] = loaded_scale_idx,
            [3] = loaded_matrix_idx,
            [4] = loaded_clock_div_idx,
            [5] = loaded_transition_idx,
            [6] = loaded_inversion_idx
        }

        -- --- Initialize Outputs ---
        self.output_voltages = state.output_voltages or {0.0, 0.0, 0.0, 0.0}
        self.voltages_updated = true -- Assume update needed initially
        self.current_notes_voiced = state.current_notes_voiced or
                                        {60, 60, 60, 60}

        -- Calculate initial chord IF NOT loaded from state (using loaded state vars)
        if not state.output_voltages then
            local initial_chord_tones = self:calculate_chord_tones(
                                            self.current_scale_degree, false)
            if initial_chord_tones then
                local initial_notes_voiced = apply_voicing(self,
                                                           initial_chord_tones)
                self.current_notes_voiced = initial_notes_voiced
                for i = 1, 4 do
                    self.output_voltages[i] = midi_note_to_volts(
                                                  initial_notes_voiced[i] or 60)
                end
            else
                self.output_voltages = {0.0, 0.0, 0.0, 0.0}
                self.current_notes_voiced = {60, 60, 60, 60}
            end
        end

        -- --- Return I/O and Parameter DEFINITIONS ---
        return {
            inputs = {kGate, kTrigger},
            outputs = {kLinear, kLinear, kLinear, kLinear},
            inputNames = {[1] = "Clock", [2] = "Reset"},
            outputNames = {
                [1] = "Note 1 (Bass)",
                [2] = "Note 2 (Tenor)",
                [3] = "Note 3 (Alto)",
                [4] = "Note 4 (Soprano)"
            },
            parameters = {
                -- Use loaded state values as the "default" sent to the host
                {"Root Note", 0, 11, loaded_root, kMIDINote},
                {"Scale", self.scale_names, loaded_scale_idx},
                {"Matrix", self.matrix_names, loaded_matrix_idx},
                {"Clock Div", self.clock_division_options, loaded_clock_div_idx},
                {
                    "Transition", self.transition_options_param,
                    loaded_transition_idx
                }, {"Inversion", inversion_options, loaded_inversion_idx}
            }
        }
    end,

    -- =======================
    -- Central Chord Calculation Function - Returns UNVOICED chord tones {root, 3rd, 5th, 7th}
    -- =======================
    calculate_chord_tones = function(self, degree_or_root_midi,
                                     is_transition_chord_root)
        local chord_tones = {}
        local base_midi;

        if is_transition_chord_root then
            local chord_root_midi = degree_or_root_midi
            local tt = self.transition_type -- Use local copy for checks
            if tt == "V7" then
                base_midi = chord_root_midi -- Root of the V7 chord
                chord_tones = {
                    base_midi + 0, base_midi + 4, base_midi + 7, base_midi + 10
                }
            elseif tt == "iv" then
                base_midi = chord_root_midi -- Root of the iv chord
                chord_tones = {
                    base_midi + 0, base_midi + 3, base_midi + 7, base_midi + 10
                } -- Minor 7th
            elseif tt == "bVII" then
                base_midi = chord_root_midi -- Root of the bVII chord
                chord_tones = {
                    base_midi + 0, base_midi + 4, base_midi + 7, base_midi + 10
                } -- Dominant 7th (common function)
            elseif tt == "dim7" then
                base_midi = chord_root_midi -- Root of the dim7 chord
                chord_tones = {
                    base_midi + 0, base_midi + 3, base_midi + 6, base_midi + 9
                }
            else -- Fallback V7
                base_midi = chord_root_midi
                chord_tones = {
                    base_midi + 0, base_midi + 4, base_midi + 7, base_midi + 10
                }
            end
        else -- Calculate diatonic 7th chord tones
            local degree = degree_or_root_midi;
            local scale = self.current_scale_intervals;
            local scale_len = #scale;
            if scale_len == 0 then return {60, 64, 67, 71} end -- Fallback Cmaj7
            if degree < 1 or degree > scale_len then degree = 1 end

            local notes = {}
            local base_note = self.current_root + scale[degree] -- Root note of the chord in the scale
            local base_midi = 60 + base_note -- Base MIDI near C4

            -- Calculate intervals relative to the degree's note in the scale
            for i = 1, 4 do
                local scale_idx = ((degree - 1) + (i - 1) * 2) % scale_len + 1
                local octave_offset = math.floor(
                                          ((degree - 1) + (i - 1) * 2) /
                                              scale_len)
                local interval = scale[scale_idx] - scale[degree] -- Interval relative to chord root
                chord_tones[i] = base_midi + interval + octave_offset * 12
            end
            -- Ensure root is first element for clarity, even if not lowest MIDI
            chord_tones = {
                chord_tones[1], chord_tones[2], chord_tones[3], chord_tones[4]
            }
        end
        return chord_tones -- Returns {Root, 3rd, 5th, 7th} MIDI notes (not necessarily sorted/voiced)
    end,

    -- =======================
    -- Gate Function - Handles Clock, Immediate Transition Triggering & Resolution
    -- =======================
    gate = function(self, input, rising)
        if input == 1 and rising then -- Clock Input Rising Edge
            self.internal_clock_count = self.internal_clock_count + 1

            -- Check if clock division met
            if self.internal_clock_count >= self.clock_division_steps then
                self.internal_clock_count = 0 -- Reset division counter

                local new_notes_calculated = false
                local notes_close;
                local notes_voiced;

                -- === Handle Key Change Resolution & Transition Start ===
                if self.is_playing_transition_chord then
                    -- We WERE playing a transition chord. Resolve it NOW.
                    self.current_root = self.root_after_transition
                    self.is_playing_transition_chord = false
                    self.root_after_transition = nil
                    self.current_scale_degree = 1 -- Always resolve to I

                    -- *** Apply pending scale change BEFORE calculating resolved chord ***
                    if self.scale_change_pending then
                        self.current_scale_name =
                            self.scale_names[self.target_scale_idx]
                        self.current_scale_intervals =
                            self.scales[self.current_scale_name]
                        self.scale_change_pending = false
                    end

                    -- Use calculate_chord_tones
                    local chord_tones = self:calculate_chord_tones(
                                            self.current_scale_degree, false)
                    -- FIX: Call apply_voicing as a local function, passing self
                    local notes_voiced = apply_voicing(self, chord_tones)
                    self.current_notes_voiced = notes_voiced
                    for i = 1, 4 do
                        self.output_voltages[i] = midi_note_to_volts(
                                                      notes_voiced[i] or 60)
                    end
                    new_notes_calculated = true
                    self.voltages_updated = true

                    -- *** After resolving, check if another key change is already pending ***
                    if self.key_change_pending then
                        -- Determine the transition root MIDI note first
                        local target_tonic_midi = 60 + self.target_root
                        local trans_chord_root_midi;
                        local tt = self.transition_type
                        if tt == "Random" then
                            tt = self.transition_options[math.random(
                                     #self.transition_options)]
                        end

                        if tt == "V7" then
                            trans_chord_root_midi = target_tonic_midi + 7;
                        elseif tt == "iv" then
                            trans_chord_root_midi = target_tonic_midi + 5;
                        elseif tt == "bVII" then
                            trans_chord_root_midi = target_tonic_midi - 2;
                        elseif tt == "dim7" then
                            trans_chord_root_midi = target_tonic_midi - 1;
                        else
                            trans_chord_root_midi = target_tonic_midi + 7;
                        end -- Fallback V7

                        -- Use calculate_chord_tones with the calculated root MIDI
                        local trans_chord_tones =
                            self:calculate_chord_tones(trans_chord_root_midi,
                                                       true)
                        if trans_chord_tones then
                            -- FIX: Call apply_voicing as a local function, passing self
                            local trans_notes_voiced = apply_voicing(self,
                                                                     trans_chord_tones)
                            self.current_notes_voiced = trans_notes_voiced
                            for i = 1, 4 do
                                self.output_voltages[i] = midi_note_to_volts(
                                                              trans_notes_voiced[i] or
                                                                  60)
                            end
                            self.is_playing_transition_chord = true
                            self.root_after_transition = self.target_root
                            self.key_change_pending = false
                        else
                            self.is_playing_transition_chord = false
                            self.key_change_pending = false -- Clear flag anyway
                            -- Let the code below handle the normal progression
                            new_notes_calculated = false -- Ensure normal progression runs
                        end
                    end -- End immediate re-transition check

                elseif self.key_change_pending then
                    -- A key change IS pending, start the transition NOW.
                    -- Scale change is NOT applied before the transition chord itself.
                    -- Determine the transition root MIDI note first
                    local target_tonic_midi = 60 + self.target_root
                    local trans_chord_root_midi;
                    local tt = self.transition_type
                    if tt == "Random" then
                        tt = self.transition_options[math.random(
                                 #self.transition_options)]
                    end

                    if tt == "V7" then
                        trans_chord_root_midi = target_tonic_midi + 7;
                    elseif tt == "iv" then
                        trans_chord_root_midi = target_tonic_midi + 5;
                    elseif tt == "bVII" then
                        trans_chord_root_midi = target_tonic_midi - 2;
                    elseif tt == "dim7" then
                        trans_chord_root_midi = target_tonic_midi - 1;
                    else
                        trans_chord_root_midi = target_tonic_midi + 7;
                    end -- Fallback V7

                    -- Use calculate_chord_tones with the calculated root MIDI
                    local trans_chord_tones =
                        self:calculate_chord_tones(trans_chord_root_midi, true)
                    if trans_chord_tones then
                        -- FIX: Call apply_voicing as a local function, passing self
                        local trans_notes_voiced = apply_voicing(self,
                                                                 trans_chord_tones)
                        self.current_notes_voiced = trans_notes_voiced
                        for i = 1, 4 do
                            self.output_voltages[i] = midi_note_to_volts(
                                                          trans_notes_voiced[i] or
                                                              60)
                        end
                        self.is_playing_transition_chord = true -- Flag that we're mid-transition
                        self.root_after_transition = self.target_root -- Store the root we WILL resolve to
                        self.key_change_pending = false -- Consumed the pending flag
                        new_notes_calculated = true
                        self.voltages_updated = true
                    else
                        self.key_change_pending = false -- Clear flag even if failed
                        -- Fall through to normal progression if calculation fails
                    end
                end

                -- === Normal Chord Progression (Only if no transition logic occurred above) ===
                if not new_notes_calculated then
                    -- *** Apply pending scale change BEFORE calculating next chord ***
                    if self.scale_change_pending then
                        self.current_scale_name =
                            self.scale_names[self.target_scale_idx]
                        self.current_scale_intervals =
                            self.scales[self.current_scale_name]
                        self.scale_change_pending = false
                    end

                    local matrix = self.current_matrix
                    local scale_len = #self.current_scale_intervals
                    local probs = matrix[self.current_scale_degree]
                    if probs and scale_len > 0 then
                        local valid_probs = {}
                        local total_prob = 0
                        for d, p in pairs(probs) do
                            if d >= 1 and d <= scale_len then
                                valid_probs[d] = p
                                total_prob = total_prob + p
                            end
                        end
                        if total_prob > 0 and math.abs(total_prob - 1.0) > 0.001 then
                            for d, p in pairs(valid_probs) do
                                valid_probs[d] = p / total_prob
                            end
                        end
                        if next(valid_probs) ~= nil then
                            self.current_scale_degree = select_next_state(
                                                            valid_probs)
                        else
                            self.current_scale_degree = 1
                        end
                        notes_close = self:calculate_chord_tones(
                                          self.current_scale_degree, false)
                        -- FIX: Call apply_voicing as a local function, passing self
                        notes_voiced = apply_voicing(self, notes_close)
                        self.current_notes_voiced = notes_voiced
                        for i = 1, 4 do
                            self.output_voltages[i] = midi_note_to_volts(
                                                          notes_voiced[i] or 60)
                        end
                        new_notes_calculated = true
                        self.voltages_updated = true
                    end
                end

                -- If voltages were updated in this call, set the flag for step()
                if new_notes_calculated then
                    self.voltages_updated = true -- Use consistent flag
                end

            end -- End clock division check
        end -- End rising edge check
    end,

    -- =======================
    -- Trigger Function (Reset) - Calculates voltages directly
    -- =======================
    trigger = function(self, input)
        if input == 2 then -- Reset Input
            -- Reset state to current parameters
            self.current_root = self.parameters[1] -- Use current param value
            self.target_root = self.current_root -- Sync target to current
            self.key_change_pending = false
            self.is_playing_transition_chord = false
            self.root_after_transition = nil

            -- Apply pending scale change immediately on reset
            if self.scale_change_pending then
                self.current_scale_name =
                    self.scale_names[self.target_scale_idx]
                self.current_scale_intervals =
                    self.scales[self.current_scale_name]
                self.scale_change_pending = false
            end
            -- If no scale change pending, ensure target reflects current
            self.target_scale_idx = self.parameters[2]
            self.previous_parameters[2] = self.target_scale_idx

            self.current_scale_degree = 1
            self.internal_clock_count = 0 -- Reset clock division counter

            -- Sync previous params to current param values
            self.previous_parameters[1] = self.target_root
            self.previous_parameters[3] = self.parameters[3]
            self.previous_parameters[4] = self.parameters[4]
            self.previous_parameters[5] = self.parameters[5]
            self.previous_parameters[6] = self.parameters[6] -- Sync inversion param

            -- Calculate tonic chord voltages and store immediately
            local chord_tones = self:calculate_chord_tones(
                                    self.current_scale_degree, false)
            -- FIX: Call apply_voicing as a local function, passing self
            local notes_voiced = apply_voicing(self, chord_tones)
            self.current_notes_voiced = notes_voiced
            for i = 1, 4 do
                self.output_voltages[i] =
                    midi_note_to_volts(notes_voiced[i] or 60)
            end
            self.voltages_updated = true
        end
    end,

    -- =======================
    -- Step Function - Minimal work: Parameter check & return cached voltages
    -- =======================
    step = function(self, dt, inputs)
        -- Check Parameters
        local root_param = self.parameters[1]
        local scale_param_idx = self.parameters[2]
        local matrix_param_idx = self.parameters[3]
        local clock_div_param_idx = self.parameters[4]
        local transition_param_idx = self.parameters[5]
        local inversion_param_idx = self.parameters[6] -- Read new param

        -- Update target_root immediately and flag if change occurred
        -- Ensure root_param is not nil before comparing or assigning
        if root_param ~= nil and root_param ~= self.target_root then
            local old_target = self.target_root
            self.target_root = root_param
            if not self.is_playing_transition_chord then
                self.key_change_pending = true
            end
            self.previous_parameters[1] = self.target_root
        end

        -- Handle scale change (flag pending)
        if scale_param_idx ~= self.target_scale_idx then
            self.target_scale_idx = scale_param_idx
            self.scale_change_pending = true
            self.previous_parameters[2] = self.target_scale_idx
        end

        -- Handle matrix change (update immediately)
        if matrix_param_idx ~= self.previous_parameters[3] then
            self.current_matrix_name = self.matrix_names[matrix_param_idx]
            self.current_matrix = self.matrices[self.current_matrix_name]
            self.previous_parameters[3] = matrix_param_idx
        end

        -- Handle clock div change (update immediately)
        if clock_div_param_idx ~= self.previous_parameters[4] then
            self.clock_division_steps =
                self.clock_division_values[clock_div_param_idx]
            self.internal_clock_count = 0
            self.previous_parameters[4] = clock_div_param_idx
        end

        -- Handle transition type change (update immediately)
        if transition_param_idx ~= self.previous_parameters[5] then
            self.transition_type =
                self.transition_options_param[transition_param_idx]
            self.previous_parameters[5] = transition_param_idx
        end

        -- Handle inversion change (update immediately, handled by apply_voicing)
        if inversion_param_idx ~= self.previous_parameters[6] then
            self.previous_parameters[6] = inversion_param_idx
            -- No internal state changes needed here, apply_voicing uses param directly
        end

        -- Output Logic: Return cached voltages if they were updated
        if self.voltages_updated then
            self.voltages_updated = false;
            return self.output_voltages
        else
            return nil
        end
    end,

    -- Draw Function (Updated display logic for faster transitions)
    draw = function(self)
        -- Proceed with drawing logic
        -- Ensure basic state exists, fallback if needed
        if type(self) ~= "table" or type(self.parameters) ~= "table" or
            type(self.current_root) ~= "number" then
            -- Draw minimal error message if core state is broken
            drawText(10, 10, "Draw Error: Invalid state!", 15)
            return true
        end

        local root_name = note_names[self.current_root + 1];
        local scale_name = self.current_scale_name or "?? Scale";
        local matrix_name = self.current_matrix_name or "?? Matrix";
        local degree = self.current_scale_degree or 1;
        local y = 18;
        local x = 10;
        local lh = 9;
        local root_display = root_name;
        local degree_display;
        local roman_map = {
            [1] = "I",
            [2] = "II",
            [3] = "III",
            [4] = "IV",
            [5] = "V",
            [6] = "VI",
            [7] = "VII"
        };
        local deg_rom = roman_map[degree] or tostring(degree);

        -- Display logic based on transition state
        if self.is_playing_transition_chord and self.root_after_transition ~=
            nil then
            root_display = root_name .. " >" ..
                               note_names[self.root_after_transition + 1];
            local tt = self.transition_type;
            if tt == "V7" then
                degree_display = "V7/I"
            elseif tt == "iv" then
                degree_display = "iv/I"
            elseif tt == "bVII" then
                degree_display = "bVII/I"
            elseif tt == "dim7" then
                degree_display = "vii°7/I"
            else
                degree_display = "?/I"
            end
        elseif self.key_change_pending then
            local target_root_name = "???"
            if self.target_root ~= nil then
                target_root_name = note_names[self.target_root + 1]
            end
            root_display = root_name .. " (->" .. target_root_name .. ")";
            degree_display = deg_rom .. " (Pending Key)";
        else
            degree_display = deg_rom
        end

        -- Display scale transition state
        local scale_display = scale_name
        if self.scale_change_pending then
            scale_display = scale_name .. " (->" ..
                                (self.scale_names[self.target_scale_idx] or "?") ..
                                ")"
        end

        drawText(x, y, "Root: " .. root_display .. " Scale: " .. scale_display);
        y = y + lh;

        -- Clock Div and Transition Type Display
        local clock_param_val = self.parameters[4]
        local trans_param_val = self.parameters[5]
        local clk_txt = type(clock_param_val) == 'number' and
                            self.clock_division_options[clock_param_val] or
                            "Err"
        local trans_txt = type(trans_param_val) == 'number' and
                              self.transition_options_param[trans_param_val] or
                              "Err"

        drawText(x, y, "Matrix: " .. matrix_name .. " Div: 1/" .. clk_txt ..
                     " Tr: " .. trans_txt);
        y = y + lh;
        drawText(x, y, "Degree: " .. degree_display);
        y = y + lh + 2;

        drawText(x, y, "Chord:");
        -- Use cached MIDI notes instead of converting from voltage
        local notes_to_draw = self.current_notes_voiced;
        if notes_to_draw then
            for i = 1, 4 do
                local note_midi = notes_to_draw[i] or 60
                local nd = get_note_name(note_midi);
                drawText(x + 50 + (i - 1) * 45, y, nd, 12);
            end
        else
            drawText(x + 50, y, "...", 10);
        end
        return false; -- Show default param line
    end,

    serialise = function(self)
        local state = {
            script_version = self.SCRIPT_VERSION, -- Save current version

            -- Core state
            current_root = self.current_root,
            target_root = self.target_root,
            scale_index = self.target_scale_idx,
            matrix_index = self.previous_parameters[3],
            current_scale_degree = self.current_scale_degree,

            -- Key Change State
            key_change_pending = self.key_change_pending,
            is_playing_transition_chord = self.is_playing_transition_chord,
            root_after_transition = self.root_after_transition,

            -- Scale Change State
            scale_change_pending = self.scale_change_pending,

            -- Clock Div State
            clock_division_index = self.previous_parameters[4],
            internal_clock_count = self.internal_clock_count,

            -- Transition Type State
            transition_index = self.previous_parameters[5],

            -- Inversion State
            inversion_index = self.previous_parameters[6],

            -- Output State
            output_voltages = self.output_voltages,
            current_notes_voiced = self.current_notes_voiced
        }
        return state
    end
} -- End of main returned table
