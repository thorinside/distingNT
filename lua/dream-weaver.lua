-- L-System Dream Weaver
-- Generates evolving melodies with chaotic beauty.
--[[
MIT License

Copyright (c) 2025 Dream Weaver Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

-- V/Oct: Utility Function - Convert MIDI note to V/Oct with adjustments
local function v_oct(n)
    -- Map to a more reasonable/audible range (keep in audible range)
    n = (n % 36) + 48 -- Keep notes between C3 (48) and C6 (84)
    return (n - 60) / 12
end

return {
    name = "Dream Weaver",
    author = "L-System Explorer",
    description = "Evolving melody generator with L-systems.",

    init = function(self)
        -- Internal state
        self.t = 0
        self.axiom = "A"
        self.rules = {
            A = {"AB", "AC"}, -- Rule options
            B = {"BD"},
            C = {"A+D", "A-D"},
            D = {"[A]1", "0"} -- "0" for rests
        }
        self.notes = {A = 60, B = 62, C = 64, D = 65}
        self.octave = 0
        self.seq = {}
        self.step = 0
        
        -- Gate state tracking
        self.triggerActive = false
        self.triggerTime = 0

        -- Parameters
        self.iter = 4
        self.mistake = 0
        self.swing = 1
        self.offset = 0

        -- Generate initial sequence
        self.seq = self:sequence(self:lsys(self.axiom, self.iter, self.mistake),
                                 self.swing)

        -- Output initialization
        self.out = {0.0, 0.0}

        return {
            inputs = {kGate},
            outputs = {kLinear, kStepped},
            inputNames = {"Clock Input"},
            outputNames = {"V/Oct Output", "Gate Output"},
            parameters = {
                {"Iterations", 1, 8, 4, kNone}, {"Mistakes", 0, 1, 0, kPercent},
                {"Swing", 1, 4, 1, kNone}, {"Offset", -12, 12, 0, kSemitones}
            }
        }
    end,

    -- L-System: Recursive and Rule-Based
    lsys = function(self, str, n, mistake, depth)
        depth = depth or 1
        if n <= 0 then return str end
        local out = ""
        for i = 1, #str do
            local char = str:sub(i, i)
            local opts = self.rules[char]
            if opts and math.random() > mistake then
                local rule = opts[math.random(#opts)] or char
                out = out ..
                          (string.find(rule, char) and
                              self:lsys(rule, n - 1, mistake, depth + 1) or rule)
            else
                out = out .. char
            end
        end
        return out
    end,

    -- Sequence: Compact Conversion
    sequence = function(self, str, swing)
        local time = 0
        local iterations = 1
        local s = {}
        local octave = 0 -- Local octave to avoid using global

        for i = 1, #str do
            local char = str:sub(i, i)
            local note = self.notes[char]
            if note then
                iterations = math.random(1, swing)
                for j = 1, iterations do
                    s[#s + 1] = {
                        note = note + octave * 12,
                        start = time,
                        dur = 1
                    }
                end
                time = time + 1
            elseif char == "+" then
                octave = octave + 1
            elseif char == "-" then
                octave = octave - 1
            elseif char == "1" then
                time = time + 1
            end
        end
        return s
    end,

    gate = function(self, input, rising)
        if input == 1 and rising then
            -- Gate rising edge triggers next note
            self.triggerActive = true
            self.triggerTime = 0
            
            -- Get current note
            local note = self.seq[self.step]
            if note then
                self.out[1] = v_oct(note.note + self.offset) -- V/Oct + offset
                self.out[2] = 5 -- Gate high
            else
                self.out[2] = 0 -- Gate low
            end
            
            -- Advance to next step
            self.step = self.step + 1
            if self.step > #self.seq then self.step = 1 end
        elseif input == 1 and not rising then
            -- Gate falling edge
            self.triggerActive = false
            self.out[2] = 0 -- Gate low
        end
    end,

    step = function(self, dt, inputs)
        -- Check if parameters have changed
        local iter = math.floor(self.parameters[1])
        local mistake = self.parameters[2]
        local swing = math.floor(self.parameters[3])
        local offset = self.parameters[4]

        -- Regenerate sequence if needed
        if iter ~= self.iter or mistake ~= self.mistake or swing ~= self.swing then
            self.iter = iter
            self.mistake = mistake
            self.swing = swing
            self.seq = self:sequence(self:lsys(self.axiom, self.iter, self.mistake), self.swing)
            self.step = 1
        end

        -- Update offset
        self.offset = offset
        
        -- Automatic gate release if using internal clock
        if self.triggerActive then
            self.triggerTime = (self.triggerTime or 0) + dt
            -- Release gate after 0.1 seconds (100ms)
            if self.triggerTime > 0.1 then
                self.triggerActive = false
                self.out[2] = 0 -- Gate low
            end
        end

        return self.out
    end,

    draw = function(self)
        local width = 256
        local height = 64
        local headerHeight = 15
        local spacing = 10
        local left = 10

        -- Header
        drawText(left, headerHeight, "Dream Weaver")

        -- Current parameters
        drawText(left, headerHeight + spacing * 1, "Iter: " .. self.iter)
        drawText(left, headerHeight + spacing * 2,
                 "Mistakes: " .. string.format("%.2f", self.mistake))
        drawText(left, headerHeight + spacing * 3, "Swing: " .. self.swing)
        drawText(left, headerHeight + spacing * 4,
                 "Step: " .. self.step .. "/" .. #self.seq)

        -- Draw sequence visualization
        local seqLength = #self.seq
        if seqLength > 0 then
            local seqHeight = height - 15
            local seqWidth = width - 60
            local barWidth = math.min(5, seqWidth / seqLength)

            -- Draw sequence bars
            for i = 1, seqLength do
                local note = self.seq[i]
                if note then
                    local x = 50 + (i - 1) * barWidth
                    local noteHeight = math.min(35, (note.note % 12) * 3)
                    local y = seqHeight - noteHeight
                    local color = (i == self.step) and 15 or 7

                    -- Draw note bar
                    drawLine(x, seqHeight, x, y, color)
                    if i == self.step then
                        drawRectangle(x - 1, y - 1, x + 1, y + 1, color)
                    end
                end
            end
        end

        return true
    end,

    ui = function(self) return true end,

    pot1Turn = function(self, v)
        self.iter = math.floor(v * 7) + 1
        self.seq = self:sequence(self:lsys(self.axiom, self.iter, self.mistake), self.swing)
        self.step = 1
    end,

    pot2Turn = function(self, v)
        self.mistake = v
        self.seq = self:sequence(self:lsys(self.axiom, self.iter, self.mistake), self.swing)
        self.step = 1
    end,

    pot3Turn = function(self, v)
        self.swing = math.floor(v * 3) + 1
        self.seq = self:sequence(self:lsys(self.axiom, self.iter, self.mistake), self.swing)
        self.step = 1
    end,

    encoder1Turn = function(self, inc)
        self.offset = math.max(-12, math.min(self.offset + inc, 12))
    end
}
