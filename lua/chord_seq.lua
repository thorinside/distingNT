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

-- Helper function: Apply SATB-style voicing
local function apply_voicing(close_notes)
    if not close_notes or #close_notes ~= 4 then return {60, 60, 60, 60} end
    local v = {};
    v[1] = close_notes[1] - 12;
    v[2] = close_notes[3];
    v[3] = close_notes[2];
    v[4] = close_notes[4];
    if v[3] < v[2] then v[3] = v[3] + 12 end
    if v[4] < v[3] then v[4] = v[4] + 12 end
    return v
end

-- =======================
-- Main Script Table
-- =======================
return {
    name = "Markov Chord Seq",
    author = "AI Assistant & User",

    init = function(self)
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

        -- State Variables
        self.current_root = 0;
        self.current_scale_name = self.scale_names[1];
        self.current_matrix_name = self.matrix_names[1];
        self.current_scale_intervals = self.scales[self.current_scale_name];
        self.current_matrix = self.matrices[self.current_matrix_name];
        self.current_scale_degree = 1;
        self.clock_step = 0;

        -- Key Change State
        self.target_root = nil;
        self.transition_type = "V7";
        self.key_change_armed = false; -- Now just arms the transition for next clock
        self.is_playing_transition_chord = false; -- Tracks if V7/etc. is active, waiting for resolution

        -- Clock Div Stuff
        self.clock_division_options = {
            "1", "2", "3", "4", "6", "8", "12", "16", "24", "32"
        };
        self.clock_division_values = {1, 2, 3, 4, 6, 8, 12, 16, 24, 32};
        self.clock_division_steps = self.clock_division_values[4];

        -- Previous Parameter Values Store
        self.previous_parameters = {[1] = 0, [2] = 1, [3] = 1, [4] = 4, [5] = 5}

        -- Transition Type Definitions
        self.transition_options_param = {"V7", "iv", "bVII", "dim7", "Random"};
        self.transition_options = {"V7", "iv", "bVII", "dim7"};

        -- Output Voltages Store & Flag
        self.output_voltages = {0.0, 0.0, 0.0, 0.0}
        self.voltages_updated_in_gate = true

        -- Calculate initial chord voltages
        local initial_notes_close = self.calculate_close_notes(self,
                                                               self.current_scale_degree,
                                                               false)
        local initial_notes_voiced = apply_voicing(initial_notes_close)
        for i = 1, 4 do
            self.output_voltages[i] = midi_note_to_volts(
                                          initial_notes_voiced[i] or 60)
        end

        -- I/O & Parameter Definitions
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
                {"Root Note", 0, 11, 0, kMIDINote},
                {"Scale", self.scale_names, 1},
                {"Matrix", self.matrix_names, 1},
                {"Clock Div", self.clock_division_options, 4},
                {"Transition", self.transition_options_param, 5}
            }
        }
    end,

    -- =======================
    -- Central Chord Calculation Function - Returns CLOSE notes for voicing
    -- =======================
    calculate_close_notes = function(self, degree_or_root_midi,
                                     is_transition_chord_root)
        local close_notes = {}
        if is_transition_chord_root then
            local chord_root_midi = degree_or_root_midi
            local tt = self.transition_type -- Use local copy for checks
            if tt == "V7" then
                close_notes = {
                    chord_root_midi + 0, chord_root_midi + 4,
                    chord_root_midi + 7, chord_root_midi + 10
                }
            elseif tt == "iv" then
                close_notes = {
                    chord_root_midi + 0, chord_root_midi + 3,
                    chord_root_midi + 7, chord_root_midi + 12
                }
            elseif tt == "bVII" then
                close_notes = {
                    chord_root_midi + 0, chord_root_midi + 4,
                    chord_root_midi + 7, chord_root_midi + 12
                }
            elseif tt == "dim7" then
                close_notes = {
                    chord_root_midi + 0, chord_root_midi + 3,
                    chord_root_midi + 6, chord_root_midi + 9
                }
            else
                close_notes = {
                    chord_root_midi + 0, chord_root_midi + 4,
                    chord_root_midi + 7, chord_root_midi + 10
                }
            end -- Fallback V7
        else -- Calculate diatonic 7th close notes
            local degree = degree_or_root_midi;
            local scale = self.current_scale_intervals;
            local scale_len = #scale;
            if scale_len == 0 then return {60, 64, 67, 71} end
            if degree < 1 or degree > scale_len then degree = 1 end
            local root_i = scale[degree];
            local idx3 = (degree + 2 - 1) % scale_len + 1;
            local idx5 = (degree + 4 - 1) % scale_len + 1;
            local idx7 = (degree + 6 - 1) % scale_len + 1;
            local i3 = scale[idx3];
            local i5 = scale[idx5];
            local i7 = scale[idx7];
            if i3 < root_i then i3 = i3 + 12 end
            if i5 < root_i then i5 = i5 + 12 end
            if i7 < root_i then i7 = i7 + 12 end
            local base = 60 + self.current_root;
            close_notes = {base + root_i, base + i3, base + i5, base + i7}
        end
        return close_notes
    end,

    -- =======================
    -- Helper: Calculate TRANSITION Chord Notes (CLOSE voicing)
    -- =======================
    calculate_transition_notes = function(self)
        if self.target_root == nil then
            print(self.name ..
                      ": Error - calculate_transition_notes called with nil target_root.")
            return nil
        end

        local trans_type = self.transition_type
        if trans_type == "Random" then
            local rand_idx = math.random(1, #self.transition_options)
            trans_type = self.transition_options[rand_idx]
            print(self.name .. ": Random transition type chosen: " .. trans_type)
        end

        local new_root_midi = 60 + self.target_root -- Target root MIDI value (around C4)
        local chord_notes = {} -- MIDI notes, close voicing base

        if trans_type == "V7" then -- V7 of the target key
            local dominant_root_midi = new_root_midi + 7
            chord_notes = {
                dominant_root_midi, dominant_root_midi + 4,
                dominant_root_midi + 7, dominant_root_midi + 10
            }
        elseif trans_type == "iv" then -- iv relative to the target key (minor subdominant)
            local subdom_root_midi = new_root_midi + 5
            chord_notes = {
                subdom_root_midi, subdom_root_midi + 3, subdom_root_midi + 7,
                subdom_root_midi + 10
            } -- Minor 7th chord
        elseif trans_type == "bVII" then -- bVII relative to the target key (borrowed subtonic)
            local subtonic_root_midi = new_root_midi - 2 -- Same as +10, but clearer relationship
            chord_notes = {
                subtonic_root_midi, subtonic_root_midi + 4,
                subtonic_root_midi + 7, subtonic_root_midi + 10
            } -- Major 7th chord (often dominant 7th is used, but let's start here)
        elseif trans_type == "dim7" then -- dim7 resolving up by semitone to target root
            local leading_root_midi = new_root_midi - 1
            chord_notes = {
                leading_root_midi, leading_root_midi + 3, leading_root_midi + 6,
                leading_root_midi + 9
            }
        else -- Default to V7 if type is unknown
            print(self.name .. ": Unknown transition type '" .. trans_type ..
                      "', defaulting to V7.")
            local dominant_root_midi = new_root_midi + 7
            chord_notes = {
                dominant_root_midi, dominant_root_midi + 4,
                dominant_root_midi + 7, dominant_root_midi + 10
            }
        end

        -- Ensure notes are sorted for apply_voicing base
        table.sort(chord_notes)
        return chord_notes
    end,

    -- =======================
    -- Gate Function - Handles Clock, Immediate Transition Triggering & Resolution
    -- =======================
    gate = function(self, input, rising)
        if input == 1 and rising then -- Clock Input Rising Edge
            local new_notes_calculated = false
            local notes_close;
            local notes_voiced;

            -- Priority 1: Is a key change armed to start *now*?
            if self.key_change_armed then
                -- Trigger Transition Chord Calculation
                local target_tonic_midi = 60 + self.target_root;
                local trans_chord_root;
                -- Determine root of transition chord based on type
                if self.transition_type == "V7" then
                    trans_chord_root = target_tonic_midi + 7;
                elseif self.transition_type == "iv" then
                    trans_chord_root = target_tonic_midi + 5;
                elseif self.transition_type == "bVII" then
                    trans_chord_root = target_tonic_midi + 10;
                elseif self.transition_type == "dim7" then
                    trans_chord_root = target_tonic_midi - 1;
                else
                    trans_chord_root = target_tonic_midi + 7;
                    self.transition_type = "V7";
                end -- Fallback
                -- Calculate and store voltages
                notes_close = self.calculate_close_notes(self, trans_chord_root,
                                                         true); -- true = is transition root MIDI
                notes_voiced = apply_voicing(notes_close);
                for i = 1, 4 do
                    self.output_voltages[i] = midi_note_to_volts(
                                                  notes_voiced[i] or 60)
                end
                -- Update state for next clock
                self.is_playing_transition_chord = true;
                self.key_change_armed = false;
                new_notes_calculated = true;

                -- Priority 2: Was a transition chord playing? Resolve to new tonic *now*.
            elseif self.is_playing_transition_chord then
                -- Resolve Key Change: Calculate new tonic chord
                self.current_root = self.target_root;
                self.target_root = nil;
                self.is_playing_transition_chord = false;
                self.key_change_armed = false; -- Clear fully
                self.current_scale_degree = 1;
                self.clock_step = 0; -- Reset degree and clock step
                notes_close = self.calculate_close_notes(self,
                                                         self.current_scale_degree,
                                                         false); -- false = is diatonic
                notes_voiced = apply_voicing(notes_close);
                for i = 1, 4 do
                    self.output_voltages[i] = midi_note_to_volts(
                                                  notes_voiced[i] or 60)
                end
                new_notes_calculated = true;

                -- Priority 3: Normal chord clock advancement
            else
                self.clock_step = self.clock_step + 1;
                local chord_change_due = false;
                if self.clock_step >= self.clock_division_steps then
                    self.clock_step = 0;
                    chord_change_due = true;
                end

                if chord_change_due then
                    -- Normal Markov Step: Calculate next diatonic chord
                    local scale_len = #self.current_scale_intervals;
                    if self.current_scale_degree < 1 or
                        self.current_scale_degree > scale_len then
                        self.current_scale_degree = 1
                    end
                    local probs_raw =
                        self.current_matrix[self.current_scale_degree];
                    local valid_probs = {};
                    local total_prob = 0;
                    if probs_raw and scale_len > 0 then
                        for d, p in pairs(probs_raw) do
                            if d >= 1 and d <= scale_len then
                                valid_probs[d] = p;
                                total_prob = total_prob + p;
                            end
                        end
                    end
                    if total_prob > 0 and math.abs(total_prob - 1.0) > 0.001 then
                        for d, p in pairs(valid_probs) do
                            valid_probs[d] = p / total_prob;
                        end
                    end
                    if next(valid_probs) ~= nil then
                        self.current_scale_degree = select_next_state(
                                                        valid_probs);
                    else
                        self.current_scale_degree = 1;
                    end
                    notes_close = self.calculate_close_notes(self,
                                                             self.current_scale_degree,
                                                             false); -- false = is diatonic
                    notes_voiced = apply_voicing(notes_close);
                    for i = 1, 4 do
                        self.output_voltages[i] = midi_note_to_volts(
                                                      notes_voiced[i] or 60)
                    end
                    new_notes_calculated = true;
                end
            end

            -- If voltages were updated in this call, set the flag for step()
            if new_notes_calculated then
                self.voltages_updated_in_gate = true
            end
        end
    end,

    -- =======================
    -- Trigger Function (Reset) - Calculates voltages directly
    -- =======================
    trigger = function(self, input)
        if input == 2 then -- Reset Input
            self.target_root = nil;
            self.key_change_armed = false;
            self.is_playing_transition_chord = false;
            self.current_scale_degree = 1;
            self.clock_step = 0;
            -- Calculate tonic chord voltages and store immediately
            local notes_close = self.calculate_close_notes(self,
                                                           self.current_scale_degree,
                                                           false)
            local notes_voiced = apply_voicing(notes_close)
            for i = 1, 4 do
                self.output_voltages[i] =
                    midi_note_to_volts(notes_voiced[i] or 60)
            end
            self.voltages_updated_in_gate = true
        end
    end,

    -- =======================
    -- Step Function - Minimal work: Parameter check & return cached voltages
    -- =======================
    step = function(self, dt, inputs)
        -- === Check for Parameter Changes (Update state, ARM key changes) ===
        local param_changed = false;
        local current_root_param = self.parameters[1];
        if current_root_param ~= self.previous_parameters[1] then
            if self.target_root == nil and not self.key_change_armed and
                not self.is_playing_transition_chord then
                self.target_root = current_root_param;
                local trans_idx = self.parameters[5];
                local sel_trans = self.transition_options_param[trans_idx];
                if sel_trans == "Random" then
                    local rand_idx = math.random(#self.transition_options);
                    self.transition_type = self.transition_options[rand_idx];
                else
                    self.transition_type = sel_trans;
                end
                self.key_change_armed = true;
            end
            self.previous_parameters[1] = current_root_param;
            param_changed = true;
        end
        local current_scale_idx = self.parameters[2];
        if current_scale_idx ~= self.previous_parameters[2] then
            self.current_scale_name = self.scale_names[current_scale_idx];
            self.current_scale_intervals = self.scales[self.current_scale_name];
            if self.target_root == nil and self.current_scale_degree >
                #self.current_scale_intervals then
                self.current_scale_degree = 1
            end
            self.previous_parameters[2] = current_scale_idx;
            param_changed = true;
        end -- Note: Chord won't update until next clock trigger if change occurs mid-transition
        local current_matrix_idx = self.parameters[3];
        if current_matrix_idx ~= self.previous_parameters[3] then
            self.current_matrix_name = self.matrix_names[current_matrix_idx];
            self.current_matrix = self.matrices[self.current_matrix_name];
            self.previous_parameters[3] = current_matrix_idx;
            param_changed = true;
        end
        local current_clock_div_idx = self.parameters[4];
        if current_clock_div_idx ~= self.previous_parameters[4] then
            local idx = current_clock_div_idx;
            if idx and idx >= 1 and idx <= #self.clock_division_values then
                self.clock_division_steps = self.clock_division_values[idx];
            else
                self.clock_division_steps = self.clock_division_values[4];
            end
            self.clock_step = 0;
            self.previous_parameters[4] = current_clock_div_idx;
            param_changed = true;
        end
        local current_transition_idx = self.parameters[5];
        if current_transition_idx ~= self.previous_parameters[5] then
            self.previous_parameters[5] = current_transition_idx;
            param_changed = true;
            if self.transition_options_param[current_transition_idx] ~= "Random" then
                self.transition_type =
                    self.transition_options_param[current_transition_idx];
            end
        end

        -- === Output Logic ===
        if self.voltages_updated_in_gate then
            self.voltages_updated_in_gate = false;
            return self.output_voltages
        else
            return nil
        end
    end,

    -- Draw Function (Updated display logic for faster transitions)
    draw = function(self)
        local root_name = note_names[self.current_root + 1];
        local scale_name = self.current_scale_name;
        local matrix_name = self.current_matrix_name;
        local degree = self.current_scale_degree;
        local chord_notes_volts = self.output_voltages;
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
        if self.key_change_armed then
            root_display = root_name .. " Arm>" ..
                               note_names[self.target_root + 1];
            degree_display = deg_rom .. " (Next)"; -- Changed display
        elseif self.is_playing_transition_chord then
            root_display = root_name .. " >" .. note_names[self.target_root + 1];
            local tt = self.transition_type;
            if tt == "V7" then
                degree_display = "V7/" .. roman_map[1]
            elseif tt == "iv" then
                degree_display = "iv/" .. roman_map[1]
            elseif tt == "bVII" then
                degree_display = "bVII/" .. roman_map[1]
            elseif tt == "dim7" then
                degree_display = "vii°7/" .. roman_map[1]
            else
                degree_display = "?/" .. roman_map[1]
            end
        else
            degree_display = deg_rom
        end
        drawText(x, y, "Root: " .. root_display .. " Scale: " .. scale_name);
        y = y + lh;
        local clk_idx = self.parameters[4];
        local clk_txt = "???";
        if clk_idx and type(clk_idx) == "number" and clk_idx >= 1 and clk_idx <=
            #self.clock_division_options then
            clk_txt = self.clock_division_options[clk_idx];
        else
            local def_idx = 4;
            if def_idx >= 1 and def_idx <= #self.clock_division_options then
                clk_txt = self.clock_division_options[def_idx] .. "?";
            end
        end
        local trans_idx = self.parameters[5];
        local trans_txt = self.transition_options_param[trans_idx] or "???";
        drawText(x, y, "Matrix: " .. matrix_name .. " Div: 1/" .. clk_txt ..
                     " Tr: " .. trans_txt);
        y = y + lh;
        drawText(x, y, "Degree: " .. degree_display);
        y = y + lh + 2; -- Removed master clock display
        drawText(x, y, "Chord:");
        if chord_notes_volts then
            local notes_to_draw = {};
            for i = 1, 4 do
                notes_to_draw[i] = math.floor(chord_notes_volts[i] * 12 + 60.5)
            end
            for i = 1, 4 do
                local nd = get_note_name(notes_to_draw[i]);
                drawText(x + 50 + (i - 1) * 45, y, nd, 12);
            end
        else
            drawText(x + 50, y, "...", 10);
        end
        return false;
    end
} -- End of main returned table
