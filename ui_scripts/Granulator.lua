local granulator
local p_delay_mean, p_delay_spread
local p_size_mean, p_size_spread
local p_pitch_mean, p_pitch_spread
local p_lfo_speed, p_lfo_depth
local p_record, p_buffer_size
local p_dry_gain, p_gran_gain
local p_reverse, p_lfo_shape, p_grain_shape
local p_rate_mean, p_rate_spread
local p_grain_limit, p_spawn_mode

-- Modes as booleans: true = mean/speed, false = spread/depth
local delayMode = true   -- true: mean, false: spread
local sizeMode = true    -- true: mean, false: spread
local pitchMode = true   -- true: mean, false: spread
local lfoMode = true     -- true: speed, false: depth

local button1Held = false
local button2Held = false
local button3Held = false
local button4Held = false

-- State variables for button/encoder combos
local button1ComboTriggered = false
local button2ComboTriggered = false
local button3ComboTriggered = false
local button4ComboTriggered = false

local dryGain = 0
local granulatorGain = 0

return {
  name = 'Granulator UI script',
  author = 'Tsurba',
  description = 'UI mapping for Granulator with mean/spread on pots, Buffer/Record on left encoder, LFO Speed/Depth on right encoder, Dry/Gran gain toggle, Reverse and Shape controls on buttons.',
  
  init = function()
    granulator = findAlgorithm("Granulator")
    if granulator == nil then
      return "Could not find 'Granulator'"
    end

    p_delay_mean    = findParameter(granulator, "Delay mean")
    p_delay_spread  = findParameter(granulator, "Delay spread")
    p_size_mean     = findParameter(granulator, "Size mean")
    p_size_spread   = findParameter(granulator, "Size spread")
    p_pitch_mean    = findParameter(granulator, "Pitch mean")
    p_pitch_spread  = findParameter(granulator, "Pitch spread")
    p_lfo_speed     = findParameter(granulator, "LFO speed")
    p_lfo_depth     = findParameter(granulator, "LFO depth")
    p_lfo_shape     = findParameter(granulator, "LFO shape")
    p_record        = findParameter(granulator, "Record")
    p_buffer_size   = findParameter(granulator, "Buffer size")
    p_dry_gain      = findParameter(granulator, "Dry gain")
    p_gran_gain     = findParameter(granulator, "Granulator gain")
    p_reverse       = findParameter(granulator, "Reverse")
    p_grain_shape   = findParameter(granulator, "Shape")
    p_drone1_enable = findParameter(granulator, "Drone 1 enable")
    p_rate_mean     = findParameter(granulator, "Rate mean")
    p_rate_spread   = findParameter(granulator, "Rate spread")
    p_grain_limit   = findParameter(granulator, "Grain limit")
    p_spawn_mode    = findParameter(granulator, "Spawn mode")
    
    if not (p_delay_mean and p_delay_spread and p_size_mean and p_size_spread 
       and p_pitch_mean and p_pitch_spread and p_lfo_speed and p_lfo_depth 
       and p_lfo_shape and p_record and p_buffer_size and p_dry_gain and p_gran_gain
       and p_reverse and p_grain_shape and p_rate_mean and p_rate_spread and p_grain_limit and p_spawn_mode) then
      return "Could not find one or more Granulator parameters"
    end

    return true
  end,

  pot1Turn = function(value)
    if delayMode then
      setParameterNormalized(granulator, p_delay_mean, 1.0 - value)
    else
      setParameterNormalized(granulator, p_delay_spread, value)
    end
  end,
  pot1Push = function()
    delayMode = not delayMode
  end,

  pot2Turn = function(value)
    if button2Held then
      setParameterNormalized(granulator, p_rate_mean, value)
      button2ComboTriggered = true
    else
      if sizeMode then
        -- if value is less than 0.001 set it to 0 to make sure exactly zero is reached
        if value < 0.001 then value = 0 end
        setParameterNormalized(granulator, p_size_mean, value)
      else
        setParameterNormalized(granulator, p_size_spread, value)
      end
    end
  end,
  pot2Push = function()
    sizeMode = not sizeMode
  end,

  pot3Turn = function(value)
    if button2Held then
      setParameterNormalized(granulator, p_rate_spread, value)
      button2ComboTriggered = true
    else
      if pitchMode then
        setParameterNormalized(granulator, p_pitch_mean, value)
      else
        -- if value is less than 0.001 set it to 0 to make sure exactly zero is reached
        if value < 0.001 then value = 0 end
        setParameterNormalized(granulator, p_pitch_spread, value)
      end
    end
  end,
  pot3Push = function()
    pitchMode = not pitchMode
  end,

  encoder1Push = function()
    if getParameter(granulator, p_record) == 0 then
      setParameter(granulator, p_record, 1)
    else
      setParameter(granulator, p_record, 0)
    end
  end,
  encoder1Turn = function(whichWay)
    -- If button 1 or 2 is held, change gain instead of buffer size.
    if button1Held then
      local current = getParameter(granulator, p_dry_gain)
      local newVal = current + whichWay
      setParameter(granulator, p_dry_gain, newVal)
      button1ComboTriggered = true
    elseif button2Held then
      local current = getParameter(granulator, p_gran_gain)
      local newVal = current + whichWay
      setParameter(granulator, p_gran_gain, newVal)
      button2ComboTriggered = true
    else
      local step = 50.0
      local current = getParameter(granulator, p_buffer_size)
      local newVal = current + whichWay * step
      setParameter(granulator, p_buffer_size, newVal)
    end
  end,

  encoder2Push = function()
    lfoMode = not lfoMode
  end,
  encoder2Turn = function(whichWay)
    if button2Held then
      local current = getParameter(granulator, p_grain_limit)
      local newVal = current + whichWay
      setParameter(granulator, p_grain_limit, newVal)
      button2ComboTriggered = true
    else
      local step = 5
      if lfoMode then
        local current = getParameter(granulator, p_lfo_speed)
        local newVal = current + whichWay * step
        setParameter(granulator, p_lfo_speed, newVal)
      else
        local current = getParameter(granulator, p_lfo_depth)
        local newVal = current + whichWay * step
        setParameter(granulator, p_lfo_depth, newVal)
      end
    end
  end,

  button1Push = function()
    button1Held = true
    if button2Held then
      local drone = getParameter(granulator, p_drone1_enable)
      setParameter(granulator, p_drone1_enable, 1 - drone)
      button1ComboTriggered = true
      button2ComboTriggered = true
    end
  end,
  button1Release = function()
    if not button1ComboTriggered then
      local currentDryGain = getParameter(granulator, p_dry_gain)
      if currentDryGain > -40 then
        -- store the current gain to restore it later
        dryGain = currentDryGain
        setParameter(granulator, p_dry_gain, -40)
      else
        -- restore the granulator gain to its stored value
        setParameter(granulator, p_dry_gain, dryGain)
      end
    end
    button1Held = false
    button1ComboTriggered = false
  end,

  button2Push = function()
    button2Held = true
  end,
  button2Release = function()
    if not button2ComboTriggered then
      local currentGranGain = getParameter(granulator, p_gran_gain)
      if currentGranGain > -40 then
        -- store the current gain to restore it later
        granulatorGain = currentGranGain
        setParameter(granulator, p_gran_gain, -40)
      else
        -- restore the granulator gain to its stored value
        setParameter(granulator, p_gran_gain, granulatorGain)
      end
    end
    button2Held = false
    button2ComboTriggered = false
  end,

  button3Push = function()
    button3Held = true
    if button4Held then
      spawnMode = (getParameter(granulator, p_spawn_mode) + 1) % 5
      setParameter(granulator, p_spawn_mode, spawnMode)
      button3ComboTriggered = true
      button4ComboTriggered = true
    end
  end,
  button3Release = function()
    if not button3ComboTriggered then
      local rev = getParameter(granulator, p_reverse)
      local newVal = (rev + 25) % 125
      setParameter(granulator, p_reverse, newVal)
    end
    button3Held = false
    button3ComboTriggered = false
  end,

  button4Push = function()
    button4Held = true
    if button3Held then
      local current = getParameter(granulator, p_grain_shape)
      local newVal = (current + 1) % 6
      setParameter(granulator, p_grain_shape, newVal)
      button3ComboTriggered = true
      button4ComboTriggered = true
    end
  end,
  button4Release = function()
    if not button4ComboTriggered then
      local current = getParameter(granulator, p_lfo_shape)
      local newVal = current + 1
      if newVal >= 3 then newVal = 0 end
      setParameter(granulator, p_lfo_shape, newVal)
    end
    button4Held = false
    button4ComboTriggered = false
  end,

  draw = function()
    drawStandardParameterLine()
    drawAlgorithmUI(granulator)
    
    local delayStr = (delayMode and "Mean  " or "Spread")
    local sizeStr  = (sizeMode  and "Mean  " or "Spread")
    local pitchStr = (pitchMode and "Mean  " or "Spread")
    local lfoStr   = (lfoMode   and "Speed " or "Depth ")
    local modeStr = "Delay:" .. delayStr .. " | Size:" .. sizeStr .. " | Pitch:" .. pitchStr .. " | LFO:" .. lfoStr
    drawTinyText(10, 56, modeStr)
    
    local dM = getParameter(granulator, p_delay_mean)
    local dS = getParameter(granulator, p_delay_spread)
    local sM = getParameter(granulator, p_size_mean)
    local sS = getParameter(granulator, p_size_spread)
    local pM = getParameter(granulator, p_pitch_mean)
    local pS = getParameter(granulator, p_pitch_spread)
    local lSpeed = string.format("%.2f", getParameter(granulator, p_lfo_speed) / 255.00)
    local lDepth = getParameter(granulator, p_lfo_depth)
    local valueStr = "M:" .. dM .. "% S:" .. dS .. "%     M:" .. sM .. "% S:" .. sS .. "%   M:" .. pM .. "st S:" .. pS .. "ct   Spd:" .. lSpeed .. "% D:" .. lDepth .. "%"
    drawTinyText(10, 64, valueStr)
  end,
}
