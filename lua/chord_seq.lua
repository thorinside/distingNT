-- Markov Chord Seq v1.18
--[[
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
    if not chord_tones or #chord_tones ~= 4 then return {60, 60, 60, 60} end -- Fallback if tones are invalid

    -- Access inversion parameter safely from self.parameters
    local inversion = (self and self.parameters and self.parameters[6]) or 1 -- Default to Root (1) if param missing
    if type(inversion) ~= "number" or inversion < 1 or inversion > 4 then
        inversion = 1
    end -- Ensure valid number

    -- 1. Select the bass note index based on inversion
    local bass_note_idx = inversion -- 1=Root, 2=3rd, 3=5th, 4=7th

    -- Check if chord_tones has the required index
    if not chord_tones[bass_note_idx] then return {60, 60, 60, 60} end -- Fallback if index invalid
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
            -- Check if chord_tones[i] exists before adding
            if chord_tones[i] then
                remaining_notes[ri] = chord_tones[i]
                ri = ri + 1
            else
                -- Handle case where a chord tone is missing (unlikely but safe)
                return {60, 60, 60, 60} -- Fallback
            end
        end
    end

    -- Ensure we still have 3 remaining notes
    if #remaining_notes ~= 3 then return {60, 60, 60, 60} end -- Fallback

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
    SCRIPT_VERSION = 1.17, -- Updated version

    init = function(self)
        -- Define state locally for easier access, handling nil case
        local state = self.state
        local use_loaded_state = false

        -- Check state version compatibility
        if state and type(state) == "table" then
            -- Allow loading from 1.0 or 1.17 for now
            if state.script_version and
                (state.script_version == 1 or state.script_version ==
                    self.SCRIPT_VERSION) then
                use_loaded_state = true
            else -- Discard incompatible or unversioned state
                state = {}
            end
        elseif state then -- Discard invalid state type
            state = {}
        else -- Ensure state is an empty table if self.state was nil
            state = {}
        end

        -- Scale Definitions
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

        -- Markov Matrices
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
            ["Static Drone"] = { -- Unchanged
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
            },
            ["Berlin"] = { -- REFINED: More i/iv drone, less v
                [1] = {[1] = 0.4, [4] = 0.3, [6] = 0.15, [7] = 0.1, [3] = 0.05}, -- i -> i, iv, VI, VII, III (v rare)
                [2] = {[5] = 0.5, [7] = 0.3, [1] = 0.2}, -- ii° -> v, VII, i
                [3] = {[6] = 0.5, [4] = 0.4, [1] = 0.1}, -- III -> VI, iv, i
                [4] = {[4] = 0.3, [1] = 0.4, [7] = 0.2, [6] = 0.1}, -- iv -> iv, i, VII, VI
                [5] = {[1] = 0.7, [6] = 0.2, [4] = 0.1}, -- v -> i (reluctantly), VI, iv
                [6] = {[1] = 0.3, [7] = 0.3, [4] = 0.2, [3] = 0.1, [6] = 0.1}, -- VI -> i, VII, iv, III, VI
                [7] = {[1] = 0.5, [6] = 0.3, [4] = 0.1, [7] = 0.1} -- VII -> i, VI, iv, VII
            },
            ["Trance Minor"] = { -- REFINED: Stronger common loops i-VI-VII, i-iv-VII
                [1] = {[6] = 0.4, [4] = 0.3, [7] = 0.2, [1] = 0.1}, -- i -> VI, iv, VII, i
                [2] = {[5] = 0.7, [7] = 0.3}, -- ii° -> v, VII
                [3] = {[6] = 0.7, [1] = 0.3}, -- III -> VI, i (less common path)
                [4] = {[7] = 0.5, [1] = 0.3, [5] = 0.2}, -- iv -> VII, i, v
                [5] = {[1] = 0.7, [6] = 0.3}, -- v -> i, VI
                [6] = {[7] = 0.6, [1] = 0.2, [3] = 0.2}, -- VI -> VII, i, III
                [7] = {[1] = 0.6, [4] = 0.3, [6] = 0.1} -- VII -> i, iv, VI
            },
            ["Psy Minor"] = { -- REFINED: Even stronger i focus
                [1] = {[1] = 0.9, [4] = 0.05, [7] = 0.05}, -- i -> i (overwhelmingly), iv, VII
                [2] = {[1] = 1.0}, -- ii° -> i
                [3] = {[1] = 1.0}, -- III -> i
                [4] = {[1] = 0.95, [4] = 0.05}, -- iv -> i (mostly), iv
                [5] = {[1] = 1.0}, -- v -> i
                [6] = {[1] = 1.0}, -- VI -> i
                [7] = {[1] = 0.95, [7] = 0.05} -- VII -> i (mostly), VII
            },
            ["Trance Major"] = { -- REFINED: Stronger I-IV-V-I, I-vi-IV-V loops
                [1] = {[4] = 0.35, [6] = 0.3, [5] = 0.2, [1] = 0.15}, -- I -> IV, vi, V, I
                [2] = {[5] = 0.8, [4] = 0.2}, -- ii -> V, IV
                [3] = {[6] = 0.7, [4] = 0.3}, -- iii -> vi, IV
                [4] = {[5] = 0.5, [1] = 0.3, [2] = 0.2}, -- IV -> V, I, ii
                [5] = {[1] = 0.6, [6] = 0.3, [4] = 0.1}, -- V -> I, vi, IV
                [6] = {[4] = 0.4, [5] = 0.3, [2] = 0.3}, -- vi -> IV, V, ii
                [7] = {[1] = 0.7, [5] = 0.3} -- vii° -> I, V
            },
            ["Psy Major"] = { -- REFINED: Even stronger I focus
                [1] = {[1] = 0.9, [4] = 0.05, [5] = 0.05}, -- I -> I (overwhelmingly), IV, V
                [2] = {[1] = 1.0}, -- ii -> I
                [3] = {[1] = 1.0}, -- iii -> I
                [4] = {[1] = 0.95, [4] = 0.05}, -- IV -> I (mostly), IV
                [5] = {[1] = 0.95, [5] = 0.05}, -- V -> I (mostly), V
                [6] = {[1] = 1.0}, -- vi -> I
                [7] = {[1] = 1.0} -- vii° -> I
            },
            ["Berlin Major"] = { -- REFINED: More I/IV drone, less V
                [1] = {[1] = 0.4, [4] = 0.3, [6] = 0.15, [2] = 0.1, [3] = 0.05}, -- I -> I, IV, vi, ii, iii (V rare)
                [2] = {[5] = 0.5, [4] = 0.3, [1] = 0.2}, -- ii -> V, IV, I
                [3] = {[6] = 0.5, [4] = 0.4, [1] = 0.1}, -- iii -> vi, IV, I
                [4] = {[4] = 0.3, [1] = 0.4, [5] = 0.2, [2] = 0.1}, -- IV -> IV, I, V, ii
                [5] = {[1] = 0.7, [6] = 0.2, [4] = 0.1}, -- V -> I (reluctantly), vi, IV
                [6] = {[1] = 0.3, [2] = 0.3, [4] = 0.2, [5] = 0.1, [6] = 0.1}, -- vi -> I, ii, IV, V, vi
                [7] = {[1] = 0.6, [3] = 0.3, [5] = 0.1} -- vii° -> I, iii, V
            },
            ["Disco Major"] = { -- REFINED: Stronger ii-V-I, more flow
                [1] = {[2] = 0.3, [4] = 0.25, [6] = 0.2, [5] = 0.15, [1] = 0.1}, -- I -> ii, IV, vi, V, I
                [2] = {[5] = 0.8, [7] = 0.1, [4] = 0.1}, -- ii -> V (very strong!), vii°, IV
                [3] = {[6] = 0.6, [4] = 0.4}, -- iii -> vi, IV
                [4] = {[5] = 0.6, [1] = 0.2, [2] = 0.1, [7] = 0.1}, -- IV -> V (strong), I, ii, vii°
                [5] = {[1] = 0.7, [6] = 0.15, [4] = 0.1, [3] = 0.05}, -- V -> I (very strong!), vi, IV, iii
                [6] = {[2] = 0.5, [4] = 0.2, [5] = 0.2, [1] = 0.1}, -- vi -> ii (strong), IV, V, I
                [7] = {[1] = 0.7, [3] = 0.2, [5] = 0.1} -- vii° -> I, iii, V
            },
            ["Beatles Major"] = { -- REFINED: More iii/vi, deceptive V->vi, less V->I focus
                [1] = {
                    [4] = 0.25,
                    [6] = 0.25,
                    [2] = 0.2,
                    [3] = 0.15,
                    [5] = 0.1,
                    [1] = 0.05
                }, -- I -> IV, vi, ii, iii, V, I
                [2] = {[5] = 0.6, [4] = 0.2, [6] = 0.1, [1] = 0.1}, -- ii -> V, IV, vi, I
                [3] = {[6] = 0.5, [4] = 0.3, [1] = 0.1, [2] = 0.1}, -- iii -> vi, IV, I, ii
                [4] = {[1] = 0.3, [5] = 0.3, [2] = 0.2, [6] = 0.1, [4] = 0.1}, -- IV -> I, V, ii, vi, IV
                [5] = {[6] = 0.4, [1] = 0.3, [4] = 0.2, [2] = 0.1}, -- V -> vi (strong deceptive!), I, IV, ii
                [6] = {
                    [2] = 0.35,
                    [4] = 0.25,
                    [5] = 0.15,
                    [3] = 0.15,
                    [1] = 0.1
                }, -- vi -> ii, IV, V, iii, I
                [7] = {[1] = 0.5, [6] = 0.3, [3] = 0.2} -- vii° -> I, vi, iii
            },
            ["Icelandic Mood"] = { -- REFINED: More drone, slower feel
                [1] = {[1] = 0.5, [4] = 0.2, [6] = 0.15, [7] = 0.1, [3] = 0.05}, -- i -> i (very often), iv, VI, VII, III
                [2] = {[5] = 0.6, [7] = 0.2, [1] = 0.2}, -- ii° -> v, VII, i
                [3] = {[6] = 0.6, [4] = 0.3, [1] = 0.1}, -- III -> VI, iv, i
                [4] = {[4] = 0.5, [1] = 0.3, [6] = 0.1, [7] = 0.1}, -- iv -> iv (very often), i, VI, VII
                [5] = {[1] = 0.7, [6] = 0.2, [4] = 0.1}, -- v -> i, VI, iv (weak function)
                [6] = {[6] = 0.4, [1] = 0.3, [4] = 0.15, [7] = 0.15}, -- VI -> VI (often), i, iv, VII
                [7] = {[7] = 0.4, [1] = 0.4, [6] = 0.1, [4] = 0.1} -- VII -> VII (often), i, VI, iv
            },
            ["Liquid Minor"] = { -- REFINED: Smoother, more ii°-v-i and cycles
                [1] = {[4] = 0.3, [6] = 0.25, [2] = 0.2, [7] = 0.15, [1] = 0.1}, -- i -> iv, VI, ii°, VII, i
                [2] = {[5] = 0.7, [7] = 0.15, [4] = 0.1, [1] = 0.05}, -- ii° -> v (very strong), VII, iv, i
                [3] = {[6] = 0.6, [7] = 0.2, [4] = 0.2}, -- III -> VI, VII, iv
                [4] = {[7] = 0.4, [5] = 0.3, [1] = 0.2, [2] = 0.1}, -- iv -> VII, v, i, ii°
                [5] = {[1] = 0.6, [6] = 0.2, [4] = 0.1, [7] = 0.1}, -- v -> i, VI, iv, VII
                [6] = {[2] = 0.4, [7] = 0.3, [4] = 0.2, [1] = 0.1}, -- VI -> ii°, VII, iv, i
                [7] = {[1] = 0.4, [6] = 0.3, [4] = 0.2, [2] = 0.1} -- VII -> i, VI, iv, ii°
            },
            ["Liquid Major"] = { -- REFINED: Smoother, stronger ii-V-I, more vi->ii
                [1] = {[2] = 0.35, [4] = 0.3, [6] = 0.2, [1] = 0.1, [5] = 0.05}, -- I -> ii, IV, vi, I, V
                [2] = {[5] = 0.8, [4] = 0.1, [7] = 0.1}, -- ii -> V (very strong!), IV, vii°
                [3] = {[6] = 0.7, [2] = 0.3}, -- iii -> vi, ii
                [4] = {[5] = 0.6, [2] = 0.2, [1] = 0.1, [7] = 0.1}, -- IV -> V (strong), ii, I, vii°
                [5] = {[1] = 0.6, [6] = 0.25, [4] = 0.1, [2] = 0.05}, -- V -> I (strong), vi, IV, ii
                [6] = {[2] = 0.6, [4] = 0.2, [5] = 0.1, [1] = 0.1}, -- vi -> ii (very strong!), IV, V, I
                [7] = {[1] = 0.7, [3] = 0.2, [5] = 0.1} -- vii° -> I, iii, V
            }
        }
        self.matrix_names = {};
        i = 1;
        for name, _ in pairs(self.matrices) do
            self.matrix_names[i] = name;
            i = i + 1;
        end
        table.sort(self.matrix_names) -- Ensure the list used for parameters is sorted

        -- Clock Div Options
        self.clock_division_options = {
            "1", "2", "3", "4", "6", "8", "12", "16", "24", "32"
        };
        self.clock_division_values = {1, 2, 3, 4, 6, 8, 12, 16, 24, 32};

        -- Transition Type Options
        self.transition_options_param = {"V7", "iv", "bVII", "dim7", "Random"};
        self.transition_options = {"V7", "iv", "bVII", "dim7"};

        -- *** CORRECTED: Inversion Options as part of self ***
        self.inversion_options = {"Root", "1st", "2nd", "3rd"}

        -- Gate Gap Options
        self.gate_gap_options = {
            "0ms", "1ms", "2ms", "10ms", "25ms", "50ms", "100ms", "250ms",
            "500ms"
        }
        self.gate_gap_values = {
            0.0, 0.001, 0.002, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5
        } -- seconds

        -- Octave Shift Options
        self.octave_shift_options = {"-2", "-1", "0", "+1", "+2"}
        self.octave_shift_values = {-24, -12, 0, 12, 24} -- semitones

        -- Parameter Defaults
        local default_root = 0
        local default_scale_idx = 1
        local default_matrix_idx = 1
        local default_clock_div_idx = 4 -- Index for "4"
        local default_transition_idx = 5 -- Index for "Random"
        local default_inversion_idx = 1 -- Index for "Root"
        local default_gate_gap_idx = 4 -- Index for "10ms" (updated index)
        local default_octave_shift_idx = 3 -- Index for "0"

        -- Load or Set Parameter INDICES from state or defaults
        local loaded_root =
            (state.current_root ~= nil) and state.current_root or default_root
        local loaded_scale_idx = state.scale_index or default_scale_idx
        local loaded_matrix_idx = state.matrix_index or default_matrix_idx
        local loaded_clock_div_idx = state.clock_division_index or
                                         default_clock_div_idx
        local loaded_transition_idx = state.transition_index or
                                          default_transition_idx
        local loaded_inversion_idx = state.inversion_index or
                                         default_inversion_idx
        local loaded_gate_gap_idx = state.gate_gap_index or default_gate_gap_idx
        local loaded_octave_shift_idx = state.octave_shift_index or
                                            default_octave_shift_idx

        -- Validate loaded indices against current definitions
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
        -- *** CORRECTED: Use self.inversion_options for validation ***
        if loaded_inversion_idx < 1 or loaded_inversion_idx >
            #self.inversion_options then
            loaded_inversion_idx = default_inversion_idx
        end
        if loaded_gate_gap_idx < 1 or loaded_gate_gap_idx >
            #self.gate_gap_values then
            loaded_gate_gap_idx = default_gate_gap_idx
        end
        if loaded_octave_shift_idx < 1 or loaded_octave_shift_idx >
            #self.octave_shift_values then
            loaded_octave_shift_idx = default_octave_shift_idx
        end
        if type(loaded_root) ~= "number" or loaded_root < 0 or loaded_root > 11 then
            loaded_root = default_root
        end

        -- Initialize Internal State Variables
        self.current_root = loaded_root
        self.target_root = (state.target_root ~= nil) and state.target_root or
                               self.current_root
        self.scale_change_pending = state.scale_change_pending or false
        self.key_change_pending = state.key_change_pending or false
        self.is_playing_transition_chord =
            state.is_playing_transition_chord or false;
        self.root_after_transition = state.root_after_transition

        -- Set effective scale and matrix based on loaded index
        self.target_scale_idx = loaded_scale_idx -- Store the param index we start with
        self.current_scale_name = self.scale_names[self.target_scale_idx]
        self.current_scale_intervals = self.scales[self.current_scale_name]

        self.current_matrix_name = self.matrix_names[loaded_matrix_idx]
        self.current_matrix = self.matrices[self.current_matrix_name]
        self.current_scale_degree = state.current_scale_degree or 1

        self.clock_division_steps =
            self.clock_division_values[loaded_clock_div_idx];
        self.internal_clock_count = state.internal_clock_count or 0;
        self.transition_type =
            self.transition_options_param[loaded_transition_idx]
        self.gate_gap_duration = self.gate_gap_values[loaded_gate_gap_idx] -- Store duration in seconds
        self.octave_shift_semitones =
            self.octave_shift_values[loaded_octave_shift_idx] -- Store shift in semitones

        -- Initialize Previous Parameter Tracker
        self.previous_parameters = {
            [1] = self.target_root, -- Track target root (param 1)
            [2] = self.target_scale_idx, -- Track target scale idx (param 2)
            [3] = loaded_matrix_idx,
            [4] = loaded_clock_div_idx,
            [5] = loaded_transition_idx,
            [6] = loaded_inversion_idx,
            [7] = loaded_gate_gap_idx,
            [8] = loaded_octave_shift_idx -- Track octave shift index
        }

        -- Initialize Outputs & Gate State
        self.output_voltages = state.output_voltages or {0.0, 0.0, 0.0, 0.0}
        self.current_notes_voiced = state.current_notes_voiced or
                                        {60, 60, 60, 60}
        self.chord_gate_value = 0.0 -- Initialize Gate State to Low
        self.gap_timer_remaining = 0.0 -- Initialize Gap Timer

        -- Calculate initial chord IF NOT loaded from state
        if not state.output_voltages then
            local initial_chord_tones = self:calculate_chord_tones(
                                            self.current_scale_degree, false)
            if initial_chord_tones then
                -- Pass current parameters to apply_voicing implicitly via self
                local initial_notes_voiced = apply_voicing(self,
                                                           initial_chord_tones)
                self.current_notes_voiced = initial_notes_voiced
                for j = 1, 4 do
                    self.output_voltages[j] = midi_note_to_volts(
                                                  initial_notes_voiced[j] or 60)
                end
                self.chord_gate_value = 5.0 -- Set gate high for initial chord
            else
                self.output_voltages = {0.0, 0.0, 0.0, 0.0}
                self.current_notes_voiced = {60, 60, 60, 60}
                -- Gate remains low if initial calculation fails
            end
        else
            -- If loading state, ensure gate reflects the loaded chord initially
            if state.output_voltages then self.chord_gate_value = 5.0 end
        end

        -- Return I/O and Parameter DEFINITIONS
        return {
            inputs = {kGate, kTrigger},
            outputs = {kLinear, kLinear, kLinear, kLinear, kGate}, -- Added kGate
            inputNames = {[1] = "Clock", [2] = "Reset"},
            outputNames = {
                [1] = "Note 1 (Bass)",
                [2] = "Note 2 (Tenor)",
                [3] = "Note 3 (Alto)",
                [4] = "Note 4 (Soprano)",
                [5] = "Chord Gate Output" -- Added Gate Name
            },
            parameters = {
                {"Root Note", 0, 11, loaded_root, kMIDINote},
                {"Scale", self.scale_names, loaded_scale_idx},
                {"Matrix", self.matrix_names, loaded_matrix_idx},
                {"Clock Div", self.clock_division_options, loaded_clock_div_idx},
                {
                    "Transition", self.transition_options_param,
                    loaded_transition_idx
                }, {"Inversion", self.inversion_options, loaded_inversion_idx},
                {"Gate Gap", self.gate_gap_options, loaded_gate_gap_idx},
                {
                    "Octave Shift", self.octave_shift_options,
                    loaded_octave_shift_idx
                } -- Added Octave Shift Param
            }
        }
    end,

    calculate_chord_tones = function(self, degree_or_root_midi,
                                     is_transition_chord_root)
        local chord_tones = {}
        local base_midi;

        if is_transition_chord_root then
            local chord_root_midi = degree_or_root_midi
            local octave_shift = self.octave_shift_semitones or 0 -- Get octave shift
            local tt = self.transition_type -- Use local copy for checks
            if tt == "V7" then
                base_midi = chord_root_midi -- Root of the V7 chord
                chord_tones = {
                    base_midi + 0 + octave_shift, base_midi + 4 + octave_shift,
                    base_midi + 7 + octave_shift, base_midi + 10 + octave_shift
                }
            elseif tt == "iv" then
                base_midi = chord_root_midi -- Root of the iv chord
                chord_tones = {
                    base_midi + 0 + octave_shift, base_midi + 3 + octave_shift,
                    base_midi + 7 + octave_shift, base_midi + 10 + octave_shift
                } -- Minor 7th
            elseif tt == "bVII" then
                base_midi = chord_root_midi -- Root of the bVII chord
                chord_tones = {
                    base_midi + 0 + octave_shift, base_midi + 4 + octave_shift,
                    base_midi + 7 + octave_shift, base_midi + 10 + octave_shift
                } -- Dominant 7th (common function)
            elseif tt == "dim7" then
                base_midi = chord_root_midi -- Root of the dim7 chord
                chord_tones = {
                    base_midi + 0 + octave_shift, base_midi + 3 + octave_shift,
                    base_midi + 6 + octave_shift, base_midi + 9 + octave_shift
                }
            else -- Fallback V7 (could happen if transition_type is Random initially)
                base_midi = chord_root_midi
                chord_tones = {
                    base_midi + 0 + octave_shift, base_midi + 4 + octave_shift,
                    base_midi + 7 + octave_shift, base_midi + 10 + octave_shift
                }
            end
        else -- Calculate diatonic chord tones
            local degree = degree_or_root_midi;
            local scale = self.current_scale_intervals;
            local scale_len = #scale;
            local octave_shift = self.octave_shift_semitones or 0 -- Get octave shift, default 0

            if scale_len == 0 then
                -- Apply octave shift to fallback chord
                return {
                    60 + octave_shift, 64 + octave_shift, 67 + octave_shift,
                    71 + octave_shift
                }
            end
            if degree < 1 or degree > scale_len then degree = 1 end

            -- Get the MIDI note for the root of the chord based on the scale degree
            local root_note_in_scale = self.current_root + scale[degree]
            local base_midi = 60 + root_note_in_scale + octave_shift -- Apply Octave Shift HERE

            if scale_len < 7 then
                -- Handle scales with fewer than 7 notes (e.g., Pentatonic, Hexatonic)
                -- Build Root, 3rd, 5th using scale wrapping, and double the Root.
                local third_idx = ((degree - 1) + 2) % scale_len + 1
                local fifth_idx = ((degree - 1) + 4) % scale_len + 1

                local third_interval = scale[third_idx] - scale[degree]
                if scale[third_idx] < scale[degree] then
                    third_interval = third_interval + 12
                end

                local fifth_interval = scale[fifth_idx] - scale[degree]
                if scale[fifth_idx] < scale[degree] then
                    fifth_interval = fifth_interval + 12
                end

                local root_midi = base_midi
                local third_midi = base_midi + third_interval
                local fifth_midi = base_midi + fifth_interval

                -- Ensure 3rd and 5th are higher than root (adjust octave if necessary)
                while third_midi < root_midi do
                    third_midi = third_midi + 12
                end
                while fifth_midi < third_midi do
                    fifth_midi = fifth_midi + 12
                end -- Check against 3rd now

                chord_tones = {root_midi, third_midi, fifth_midi, root_midi} -- Double the root

            else
                -- Original logic for scales with 7 or more notes (calculate 7th chord)
                local notes = {}
                -- Calculate intervals relative to the degree's note in the scale
                for i = 1, 4 do
                    local scale_idx = ((degree - 1) + (i - 1) * 2) % scale_len +
                                          1
                    local octave_offset = math.floor(
                                              ((degree - 1) + (i - 1) * 2) /
                                                  scale_len)
                    local interval = scale[scale_idx] - scale[degree] -- Interval relative to chord root
                    -- Adjust interval if it crosses octave boundary relative to scale root
                    if scale[scale_idx] < scale[degree] then
                        interval = interval + 12
                    end
                    -- Note: base_midi already includes octave shift
                    notes[i] = base_midi + interval + octave_offset * 12
                end

                -- Reorder based on interval size for {Root, 3rd, 5th, 7th} structure (approx)
                local root_midi = notes[1]
                local third_midi = notes[2]
                local fifth_midi = notes[3]
                local seventh_midi = notes[4]

                -- Basic check: Ensure 3rd, 5th, 7th are higher than root (adjust octave if necessary)
                while third_midi < root_midi do
                    third_midi = third_midi + 12
                end
                while fifth_midi < third_midi do
                    fifth_midi = fifth_midi + 12
                end
                while seventh_midi < fifth_midi do
                    seventh_midi = seventh_midi + 12
                end

                chord_tones = {root_midi, third_midi, fifth_midi, seventh_midi}
            end
        end
        return chord_tones -- Returns {Root, 3rd, 5th, 7th or Root} MIDI notes (unvoiced)
    end,

    gate = function(self, input, rising)
        if input == 1 and rising then -- Clock Input Rising Edge
            self.internal_clock_count = self.internal_clock_count + 1

            -- Check if clock division met
            if self.internal_clock_count >= self.clock_division_steps then
                self.internal_clock_count = 0 -- Reset division counter
                self.chord_gate_value = 0.0 -- Set gate low initially

                local new_notes_calculated = false
                local notes_close;
                local notes_voiced;

                -- === Handle Key Change Resolution & Transition Start ===
                if self.is_playing_transition_chord then
                    -- Resolve transition: set new root, clear flags
                    self.current_root = self.root_after_transition
                    self.is_playing_transition_chord = false
                    self.root_after_transition = nil
                    self.current_scale_degree = 1 -- Always resolve to I

                    -- Apply pending scale change BEFORE calculating resolved chord
                    if self.scale_change_pending then
                        self.current_scale_name =
                            self.scale_names[self.target_scale_idx]
                        self.current_scale_intervals =
                            self.scales[self.current_scale_name]
                        self.scale_change_pending = false
                        -- Update previous parameter tracker for scale AFTER change applies
                        if self.previous_parameters then
                            self.previous_parameters[2] = self.target_scale_idx
                        end
                    end

                    local chord_tones = self:calculate_chord_tones(
                                            self.current_scale_degree, false)
                    notes_voiced = apply_voicing(self, chord_tones) -- Pass self
                    self.current_notes_voiced = notes_voiced
                    for i = 1, 4 do
                        self.output_voltages[i] = midi_note_to_volts(
                                                      notes_voiced[i] or 60)
                    end
                    new_notes_calculated = true
                    self.chord_gate_value = 5.0 -- Set gate high
                    self.gap_timer_remaining = 0.0 -- Reset gap timer

                    -- After resolving, check if ANOTHER key/scale change is pending immediately
                    if self.key_change_pending or self.scale_change_pending then
                        -- If root change is pending, start transition immediately
                        if self.key_change_pending then
                            -- Determine transition chord root MIDI
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

                            local trans_chord_tones =
                                self:calculate_chord_tones(
                                    trans_chord_root_midi, true)
                            if trans_chord_tones then
                                local trans_notes_voiced = apply_voicing(self,
                                                                         trans_chord_tones) -- Pass self
                                self.current_notes_voiced = trans_notes_voiced
                                for i = 1, 4 do
                                    self.output_voltages[i] =
                                        midi_note_to_volts(
                                            trans_notes_voiced[i] or 60)
                                end
                                self.is_playing_transition_chord = true
                                self.root_after_transition = self.target_root
                                self.key_change_pending = false -- Consumed flag
                                -- Update previous parameter tracker for root AFTER change is initiated
                                if self.previous_parameters then
                                    self.previous_parameters[1] =
                                        self.target_root
                                end
                                self.chord_gate_value = 5.0 -- Set gate high for transition chord
                                self.gap_timer_remaining = 0.0 -- Reset gap timer

                                -- Apply immediate scale change *with* the transition if also pending
                                if self.scale_change_pending then
                                    self.current_scale_name =
                                        self.scale_names[self.target_scale_idx]
                                    self.current_scale_intervals =
                                        self.scales[self.current_scale_name]
                                    self.scale_change_pending = false
                                    if self.previous_parameters then
                                        self.previous_parameters[2] =
                                            self.target_scale_idx
                                    end
                                    self.chord_gate_value = 5.0 -- Set gate high for transition chord
                                    self.gap_timer_remaining = 0.0 -- Reset gap timer
                                end

                            else -- Transition calculation failed
                                self.is_playing_transition_chord = false
                                self.key_change_pending = false
                                self.scale_change_pending = false -- Clear scale flag too
                                -- Fall through to normal progression using the *already resolved* root/scale
                                new_notes_calculated = false -- Allow normal progression logic below
                            end
                            -- If ONLY scale change is pending (no root change)
                        elseif self.scale_change_pending then
                            self.current_scale_name =
                                self.scale_names[self.target_scale_idx]
                            self.current_scale_intervals =
                                self.scales[self.current_scale_name]
                            self.scale_change_pending = false
                            if self.previous_parameters then
                                self.previous_parameters[2] =
                                    self.target_scale_idx
                            end
                            -- Recalculate current chord in new scale (degree stays same)
                            chord_tones =
                                self:calculate_chord_tones(
                                    self.current_scale_degree, false)
                            notes_voiced = apply_voicing(self, chord_tones) -- Pass self
                            self.current_notes_voiced = notes_voiced
                            for i = 1, 4 do
                                self.output_voltages[i] = midi_note_to_volts(
                                                              notes_voiced[i] or
                                                                  60)
                            end
                            new_notes_calculated = true
                            self.chord_gate_value = 5.0 -- Set gate high
                            self.gap_timer_remaining = 0.0 -- Reset gap timer
                        end
                    end -- End immediate re-transition/scale change check

                elseif self.key_change_pending or self.scale_change_pending then
                    -- Key change IS pending, start transition NOW. Scale applies AFTER transition resolves.
                    if self.key_change_pending then
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

                        local trans_chord_tones =
                            self:calculate_chord_tones(trans_chord_root_midi,
                                                       true)
                        if trans_chord_tones then
                            local trans_notes_voiced = apply_voicing(self,
                                                                     trans_chord_tones) -- Pass self
                            self.current_notes_voiced = trans_notes_voiced
                            for i = 1, 4 do
                                self.output_voltages[i] = midi_note_to_volts(
                                                              trans_notes_voiced[i] or
                                                                  60)
                            end
                            self.is_playing_transition_chord = true
                            self.root_after_transition = self.target_root
                            self.key_change_pending = false -- Consumed flag
                            if self.previous_parameters then
                                self.previous_parameters[1] = self.target_root
                            end
                            new_notes_calculated = true
                            self.chord_gate_value = 5.0 -- Set gate high
                            self.gap_timer_remaining = 0.0 -- Reset gap timer
                        else -- Calculation failed
                            self.key_change_pending = false
                            self.scale_change_pending = false -- Clear scale flag too if root change failed
                            -- Fall through to normal progression in current key/scale
                        end
                        -- Only scale change pending
                    elseif self.scale_change_pending then
                        self.current_scale_name =
                            self.scale_names[self.target_scale_idx]
                        self.current_scale_intervals =
                            self.scales[self.current_scale_name]
                        self.scale_change_pending = false
                        if self.previous_parameters then
                            self.previous_parameters[2] = self.target_scale_idx
                        end
                        -- Calculate next chord using Markov chain in new scale
                        new_notes_calculated = false -- Allow normal progression below
                    end
                end

                -- === Normal Chord Progression (Only if no transition/resolution logic occurred above) ===
                if not new_notes_calculated then
                    -- If scale change was just applied without key change, we still need next chord
                    -- If key change failed, we proceed normally in old key/scale

                    local matrix = self.current_matrix
                    local scale_len = #self.current_scale_intervals
                    local probs = matrix[self.current_scale_degree]
                    if probs and scale_len > 0 then
                        local valid_probs = {}
                        local total_prob = 0
                        for d, p in pairs(probs) do
                            if d >= 1 and d <= scale_len then
                                valid_probs[d] = p;
                                total_prob = total_prob + p;
                            end
                        end

                        if total_prob > 0 then
                            -- Normalize probabilities if needed (handle potential rounding errors)
                            if math.abs(total_prob - 1.0) > 0.001 then
                                for d, p in pairs(valid_probs) do
                                    valid_probs[d] = p / total_prob
                                end
                            end
                            if next(valid_probs) ~= nil then -- Check if there are valid next states
                                self.current_scale_degree = select_next_state(
                                                                valid_probs)
                            else
                                self.current_scale_degree = 1 -- Fallback to tonic if no valid transitions defined
                            end
                        else
                            self.current_scale_degree = 1 -- Fallback if current degree has no defined transitions
                        end

                        notes_close = self:calculate_chord_tones(
                                          self.current_scale_degree, false)
                        notes_voiced = apply_voicing(self, notes_close) -- Pass self
                        self.current_notes_voiced = notes_voiced
                        for i = 1, 4 do
                            self.output_voltages[i] = midi_note_to_volts(
                                                          notes_voiced[i] or 60)
                        end
                        new_notes_calculated = true
                        self.chord_gate_value = 5.0 -- Set gate high
                        self.gap_timer_remaining = 0.0 -- Reset gap timer
                    else -- Fallback if matrix/scale invalid
                        self.current_scale_degree = 1
                        notes_close = self:calculate_chord_tones(1, false)
                        notes_voiced = apply_voicing(self, notes_close) -- Pass self
                        self.current_notes_voiced = notes_voiced
                        for i = 1, 4 do
                            self.output_voltages[i] = midi_note_to_volts(
                                                          notes_voiced[i] or 60)
                        end
                        new_notes_calculated = true
                        self.chord_gate_value = 5.0 -- Set gate high
                        self.gap_timer_remaining = 0.0 -- Reset gap timer
                    end
                end

            end -- End clock division check
        end -- End rising edge check
    end,

    trigger = function(self, input)
        if input == 2 then -- Reset Input
            -- Reset state to CURRENT parameter values
            self.current_root = self.parameters[1] -- Use current param value
            self.target_root = self.current_root -- Sync target to current
            self.key_change_pending = false
            self.is_playing_transition_chord = false
            self.root_after_transition = nil

            -- Apply current scale parameter immediately
            self.target_scale_idx = self.parameters[2]
            self.current_scale_name = self.scale_names[self.target_scale_idx]
            self.current_scale_intervals = self.scales[self.current_scale_name]
            self.scale_change_pending = false

            -- Apply current matrix parameter immediately
            local matrix_idx = self.parameters[3]
            self.current_matrix_name = self.matrix_names[matrix_idx]
            self.current_matrix = self.matrices[self.current_matrix_name]

            -- Apply other parameters immediately
            self.clock_division_steps =
                self.clock_division_values[self.parameters[4]];
            self.transition_type =
                self.transition_options_param[self.parameters[5]]

            self.current_scale_degree = 1
            self.internal_clock_count = 0 -- Reset clock division counter

            -- Sync previous params to current param values on reset
            if self.previous_parameters then
                self.previous_parameters[1] = self.target_root
                self.previous_parameters[2] = self.target_scale_idx
                self.previous_parameters[3] = self.parameters[3]
                self.previous_parameters[4] = self.parameters[4]
                self.previous_parameters[5] = self.parameters[5]
                self.previous_parameters[6] = self.parameters[6] -- Sync inversion param
                self.previous_parameters[7] = self.parameters[7] -- Sync gate gap index
                self.previous_parameters[8] = self.parameters[8] -- Sync octave shift index
            end

            -- Calculate tonic chord voltages and store immediately
            local chord_tones = self:calculate_chord_tones(
                                    self.current_scale_degree, false)
            local notes_voiced = apply_voicing(self, chord_tones) -- Pass self
            self.current_notes_voiced = notes_voiced
            for i = 1, 4 do
                self.output_voltages[i] =
                    midi_note_to_volts(notes_voiced[i] or 60)
            end
            self.chord_gate_value = 5.0 -- Set gate high on reset
            self.gap_timer_remaining = 0.0 -- Reset gap timer
        end
    end,

    -- *** CORRECTED: Step Function ***
    step = function(self, dt, inputs)
        -- Safety check for parameters table existence
        if not self.parameters then return nil end

        -- Read current parameter values
        local root_param = self.parameters[1]
        local scale_param_idx = self.parameters[2]
        local matrix_param_idx = self.parameters[3]
        local clock_div_param_idx = self.parameters[4]
        local transition_param_idx = self.parameters[5]
        local inversion_param_idx = self.parameters[6]
        local gate_gap_param_idx = self.parameters[7]
        local octave_shift_param_idx = self.parameters[8]

        -- Safety check for previous_parameters table existence
        local prev_params_exist = (self.previous_parameters ~= nil)

        -- --- Parameter Change Detection and State Update ---

        -- Handle Root Note change (Param 1)
        if root_param ~= nil and root_param ~= self.target_root then
            local old_target = self.target_root
            self.target_root = root_param
            -- Set pending flag if not already mid-transition OR if target root changes again
            if not self.is_playing_transition_chord or self.target_root ~=
                old_target then self.key_change_pending = true end
            -- Update tracker only if it exists
            if prev_params_exist then
                self.previous_parameters[1] = self.target_root
            end
        end

        -- Handle Scale change (Param 2)
        if scale_param_idx ~= nil and scale_param_idx ~= self.target_scale_idx then
            self.target_scale_idx = scale_param_idx
            self.scale_change_pending = true
            -- Update tracker only if it exists
            if prev_params_exist then
                self.previous_parameters[2] = self.target_scale_idx
            end
        end

        -- Handle Matrix change (Param 3) - Update immediately
        if prev_params_exist and matrix_param_idx ~= nil and matrix_param_idx ~=
            self.previous_parameters[3] then
            -- Validate index before using
            if matrix_param_idx >= 1 and matrix_param_idx <= #self.matrix_names then
                self.current_matrix_name = self.matrix_names[matrix_param_idx]
                self.current_matrix = self.matrices[self.current_matrix_name]
                self.previous_parameters[3] = matrix_param_idx
            end
        end

        -- Handle Clock Division change (Param 4) - Update immediately
        if prev_params_exist and clock_div_param_idx ~= nil and
            clock_div_param_idx ~= self.previous_parameters[4] then
            -- Validate index before using
            if clock_div_param_idx >= 1 and clock_div_param_idx <=
                #self.clock_division_values then
                self.clock_division_steps =
                    self.clock_division_values[clock_div_param_idx]
                self.internal_clock_count = 0 -- Reset count on division change
                self.previous_parameters[4] = clock_div_param_idx
            end
        end

        -- Handle Transition Type change (Param 5) - Update immediately
        if prev_params_exist and transition_param_idx ~= nil and
            transition_param_idx ~= self.previous_parameters[5] then
            -- Validate index before using
            if transition_param_idx >= 1 and transition_param_idx <=
                #self.transition_options_param then
                self.transition_type =
                    self.transition_options_param[transition_param_idx]
                self.previous_parameters[5] = transition_param_idx
            end
        end

        -- Handle Inversion change (Param 6) - Update tracker immediately
        -- (Actual voicing change happens in apply_voicing called by gate/trigger)
        if prev_params_exist and inversion_param_idx ~= nil and
            inversion_param_idx ~= self.previous_parameters[6] then
            -- Validate index before storing
            if inversion_param_idx >= 1 and inversion_param_idx <=
                #self.inversion_options then
                self.previous_parameters[6] = inversion_param_idx
                -- Re-calculate voltages immediately if inversion changes? Optional, but makes UI smoother.
                -- If we want immediate update:
                -- local current_chord_tones = self:calculate_chord_tones(self.current_scale_degree, self.is_playing_transition_chord) -- Need correct args
                -- if current_chord_tones then
                --    local notes_voiced = apply_voicing(self, current_chord_tones)
                --    self.current_notes_voiced = notes_voiced
                --    for i = 1, 4 do self.output_voltages[i] = midi_note_to_volts(notes_voiced[i] or 60) end
                --    self.voltages_updated = true
                -- end
            end
        end

        -- Handle Gate Gap change (Param 7) - Update immediately
        if prev_params_exist and gate_gap_param_idx ~= nil and
            gate_gap_param_idx ~= self.previous_parameters[7] then
            -- Validate index before using
            if gate_gap_param_idx >= 1 and gate_gap_param_idx <=
                #self.gate_gap_values then
                self.gate_gap_duration =
                    self.gate_gap_values[gate_gap_param_idx]
                self.previous_parameters[7] = gate_gap_param_idx
            end
        end

        -- Handle Octave Shift change (Param 8) - Update immediately
        if prev_params_exist and octave_shift_param_idx ~= nil and
            octave_shift_param_idx ~= self.previous_parameters[8] then
            -- Validate index before using
            if octave_shift_param_idx >= 1 and octave_shift_param_idx <=
                #self.octave_shift_values then
                self.octave_shift_semitones =
                    self.octave_shift_values[octave_shift_param_idx]
                self.previous_parameters[8] = octave_shift_param_idx
                -- Trigger recalculation on octave change? Might be good for smoothness.
                -- If so, need to call the chord calculation/voicing here...
                -- NOTE: For simplicity, we'll let the next clock/trigger handle the actual note update.
            end
        end

        -- --- Timer and Output Logic ---

        -- Decrement gap timer
        if self.gap_timer_remaining > 0 then
            self.gap_timer_remaining = math.max(0.0,
                                                self.gap_timer_remaining - dt)
        end

        -- Check if the *next* clock pulse triggers a chord change and start gap if needed
        if self.gate_gap_duration > 0 and self.internal_clock_count ==
            self.clock_division_steps - 1 then
            -- Only start the timer if it's not already running
            if self.gap_timer_remaining <= 0 then
                self.gap_timer_remaining = self.gate_gap_duration
            end
        end

        -- Determine output gate value based on timer
        local output_gate_value = (self.gap_timer_remaining > 0) and 0.0 or
                                      self.chord_gate_value

        -- Return current voltages and calculated gate state
        return {
            self.output_voltages[1], self.output_voltages[2],
            self.output_voltages[3], self.output_voltages[4], output_gate_value -- Use calculated value
        }
    end,

    draw = function(self)
        -- ... (draw function remains largely the same)
        -- Ensure basic state exists, fallback if needed
        if type(self) ~= "table" or type(self.parameters) ~= "table" or
            type(self.current_root) ~= "number" or not self.scale_names or
            not self.matrix_names then
            drawText(10, 10, "Draw Error: Invalid state!", 15)
            return true
        end

        local root_name = note_names[self.current_root + 1];
        local scale_name = self.current_scale_name or "?? Scale";
        local matrix_name = self.current_matrix_name or "?? Matrix";
        local degree = self.current_scale_degree or 1;
        local y = 20;
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
            local target_root_name = (self.target_root ~= nil) and
                                         note_names[self.target_root + 1] or
                                         "???"
            root_display = root_name .. " (->" .. target_root_name .. ")";
            degree_display = deg_rom .. " (Pending Key)";
        else
            degree_display = deg_rom
        end

        -- Display scale transition state
        local scale_display = scale_name
        if self.scale_change_pending then
            local target_scale_name = (self.target_scale_idx and
                                          self.scale_names[self.target_scale_idx]) or
                                          "?"
            scale_display = scale_name .. " (->" .. target_scale_name .. ")"
        end

        drawText(x, y, "Root: " .. root_display .. " Scale: " .. scale_display);
        y = y + lh;

        -- Clock Div, Transition Type, Inversion Display
        local clock_param_idx = self.parameters[4]
        local trans_param_idx = self.parameters[5]
        local inv_param_idx = self.parameters[6]

        local clk_txt = (clock_param_idx and
                            self.clock_division_options[clock_param_idx]) or
                            "Err"
        local trans_txt = (trans_param_idx and
                              self.transition_options_param[trans_param_idx]) or
                              "Err"
        -- *** Use self.inversion_options ***
        local inv_txt =
            (inv_param_idx and self.inversion_options[inv_param_idx]) or "Err"

        drawText(x, y,
                 "Matrix: " .. matrix_name .. " Div: 1/" .. clk_txt .. " Tr: " ..
                     trans_txt .. " Inv: " .. inv_txt);
        y = y + lh;
        drawText(x, y, "Degree: " .. degree_display);
        y = y + lh + 2;

        drawText(x, y, "Chord:");
        local notes_to_draw = self.current_notes_voiced;
        if notes_to_draw and #notes_to_draw == 4 then
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

    ui = function(self) return true end,

    -- *** CORRECTED: setupUi Function ***
    setupUi = function(self)
        -- Define defaults locally
        local default_matrix_idx = 1
        local default_transition_idx = 5 -- Index for "Random"
        local default_inversion_idx = 1 -- Index for "Root"

        -- Safely access current parameter indices
        local current_matrix_idx = (self and self.parameters and
                                       self.parameters[3]) or default_matrix_idx
        local current_transition_idx = (self and self.parameters and
                                           self.parameters[5]) or
                                           default_transition_idx
        local current_inversion_idx = (self and self.parameters and
                                          self.parameters[6]) or
                                          default_inversion_idx

        -- Safely get counts from self tables, default to 1 if missing or empty
        local matrix_count =
            (self and self.matrix_names and #self.matrix_names > 0 and
                #self.matrix_names) or 1
        local transition_count = (self and self.transition_options_param and
                                     #self.transition_options_param > 0 and
                                     #self.transition_options_param) or 1
        -- *** CORRECTED: Use self.inversion_options ***
        local inversion_count = (self and self.inversion_options and
                                    #self.inversion_options > 0 and
                                    #self.inversion_options) or 1

        -- Return normalized values
        return {
            current_matrix_idx / matrix_count,
            current_transition_idx / transition_count,
            current_inversion_idx / inversion_count
        }
    end,

    pot1Turn = function(self, value)
        local alg = getCurrentAlgorithm()
        -- Map pot1 (Matrix) - corresponds to parameter index 3
        setParameterNormalized(alg, self.parameterOffset + 3, value)
    end,

    pot2Turn = function(self, value)
        local alg = getCurrentAlgorithm()
        -- Map pot2 (Transition) - corresponds to parameter index 5
        setParameterNormalized(alg, self.parameterOffset + 5, value)
    end,

    pot3Turn = function(self, value)
        local alg = getCurrentAlgorithm()
        -- Map pot3 (Inversion) - corresponds to parameter index 6
        setParameterNormalized(alg, self.parameterOffset + 6, value)
    end,

    encoder1Turn = function(self, value)
        local alg = getCurrentAlgorithm()
        -- Map encoder1 (Scale) - corresponds to parameter index 2
        -- Ensure parameter exists before trying to increment
        if self and self.parameters and self.parameters[2] then
            -- Increment parameter directly (let host handle wrapping/clamping)
            setParameter(alg, self.parameterOffset + 2,
                         self.parameters[2] + value)
        end
    end,

    encoder2Turn = function(self, value)
        local alg = getCurrentAlgorithm()
        -- Map encoder2 (Root Note) - corresponds to parameter index 1
        if self and self.parameters and self.parameters[1] ~= nil then
            setParameter(alg, self.parameterOffset + 1,
                         self.parameters[1] + value)
        end
    end,

    serialise = function(self)
        -- Ensure previous_parameters exists before trying to access indices
        local prev_matrix_idx = (self and self.previous_parameters and
                                    self.previous_parameters[3]) or 1
        local prev_clock_div_idx = (self and self.previous_parameters and
                                       self.previous_parameters[4]) or 4
        local prev_transition_idx = (self and self.previous_parameters and
                                        self.previous_parameters[5]) or 5
        local prev_inversion_idx = (self and self.previous_parameters and
                                       self.previous_parameters[6]) or 1
        local prev_gate_gap_idx = (self and self.previous_parameters and
                                      self.previous_parameters[7]) or 4 -- Default to 10ms index (updated)
        local prev_octave_shift_idx = (self and self.previous_parameters and
                                          self.previous_parameters[8]) or 3 -- Default to 0 index

        local state = {
            script_version = self.SCRIPT_VERSION, -- Save current version

            -- Core state (save target values for params 1 & 2)
            current_root = self.current_root, -- Save runtime root
            target_root = self.target_root, -- Save target root (param 1 value)
            scale_index = self.target_scale_idx, -- Save target scale (param 2 value)
            matrix_index = prev_matrix_idx, -- Save last known matrix (param 3)
            current_scale_degree = self.current_scale_degree,

            -- Key/Scale Change State
            key_change_pending = self.key_change_pending,
            scale_change_pending = self.scale_change_pending,
            is_playing_transition_chord = self.is_playing_transition_chord,
            root_after_transition = self.root_after_transition,

            -- Clock Div State (save last known param 4 value)
            clock_division_index = prev_clock_div_idx,
            internal_clock_count = self.internal_clock_count,

            -- Transition Type State (save last known param 5 value)
            transition_index = prev_transition_idx,

            -- Inversion State (save last known param 6 value)
            inversion_index = prev_inversion_idx,

            -- Gate Gap State (save last known param 7 value)
            gate_gap_index = prev_gate_gap_idx,

            -- Octave Shift State (save last known param 8 value)
            octave_shift_index = prev_octave_shift_idx,

            -- Output State
            output_voltages = self.output_voltages,
            current_notes_voiced = self.current_notes_voiced
            -- chord_gate_value / gap_timer_remaining are transient, not saved
        }
        return state
    end
} -- End of main returned table

