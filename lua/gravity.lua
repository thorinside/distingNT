-- N-Body Gravity Simulation Script
--[[
-- Features:
-- * Simulates a randomly generated planetary system (1 Sun, 1-5 Planets) with optional moons.
-- * Uses physics-based gravity calculations (Euler integration) in the `step` function.
-- * Sun is fixed at the center; planets and moons interact gravitationally.
-- * Parameters control: Number of Planets, Randomize trigger, Zoom level, Time Scale, Gravity Strength, External Force Scale, Output Mode.
-- * Inputs control: External Force Direction and Magnitude, Pause/Freeze, Randomize Trigger.
-- * Outputs: Planet position derived voltage (cos(angle) * 5V or inverse distance).
-- * Pots 1-3 control Num Planets, Gravity Strength, Force Magnitude Scale (turn).
-- * Pot 3 Push controls Output Mode (Unipolar/Bipolar).
-- * Encoder 1 controls Zoom (turn).
-- * Encoder 2 controls Time Scale (turn) and Randomize (push).
]] return {
    name = 'Gravity Sim',
    author = 'AI Assistant',

    -- Constants
    screenWidth = 256,
    screenHeight = 64,

    -- Physics/Simulation Constants
    G = 500.0, -- Gravitational constant, adjusted for visual stability and scale.
    ZERO_MAG_THRESHOLD = 0.01, -- Threshold below which force magnitude is considered zero for UI purposes.
    FADE_DURATION = 0.5, -- Seconds for fade in/out animation of the force indicator.

    -- Parameter Indices (1-based)
    PARAM_NUM_PLANETS = 1,
    PARAM_GRAVITY = 2,
    PARAM_FORCE_SCALE = 3,
    PARAM_ZOOM = 4,
    PARAM_TIME_SCALE = 5,
    PARAM_RANDOMIZE = 6,
    PARAM_OUTPUT_MODE = 7, -- New parameter index

    -- Input Indices (1-based)
    INPUT_FREEZE_GATE = 1,
    INPUT_FORCE_DIR_CV = 2,
    INPUT_FORCE_MAG_CV = 3,
    INPUT_RANDOMIZE_TRIG = 4,

    -- Default Parameter Values
    defaultGravityParamVal = 0.0, -- Corresponds to G = 500 (0 = 1x multiplier).
    defaultNumPlanetsVal = 2,
    defaultZoomParamVal = -10.0,
    defaultTimeScaleParamVal = -10.0,
    defaultForceScaleVal = 1.0,
    defaultRandomizeVal = 1, -- "Off"
    defaultOutputModeVal = 2, -- Default to Bipolar (index 2)

    -- Function to setup/reset the planetary system (PHYSICS version - Random Only)
    setupSystem = function(self, numPlanets) -- Removed densityMultiplier arg
        self.bodyStates = {} -- Reset physics states
        local centerX = self.screenWidth / 2
        local centerY = self.screenHeight / 2

        -- Add Sun physics state
        local sunMass = 1000.0 -- Arbitrary large mass for stability, keeps sun relatively fixed.
        local sunRadius = 8 -- Hardcoded Sun properties.
        local sunColor = 15
        local sunState = {
            name = "Sun",
            radius = sunRadius,
            color = sunColor,
            mass = sunMass,
            px = centerX,
            py = centerY,
            vx = 0,
            vy = 0
        }
        table.insert(self.bodyStates, sunState)

        local planetCount = math.max(1, math.min(numPlanets, 5)) -- Clamp to 1-5 planets.

        for i = 1, planetCount do
            local planet = {}
            local orbitalRadius, orbitalSpeed -- Need these for initial velocity calc
            local au = 60 -- Increased AU for a larger initial system scale.

            planet.name = "RandPlanet" .. i
            planet.radius = 2 + math.random(4)
            planet.color = 10 -- Fixed planet color.
            -- Calculate orbital radius based on planet index 'i' plus some randomness.
            orbitalRadius = au * i * (0.8 + math.random() * 0.4) -- e.g., approx i AU +/- 20%
            -- Use orbitalSpeed sign for direction (+1 or -1), magnitude derived later from G.
            orbitalSpeed = (math.random(2) == 1 and 1 or -1)

            -- Random chance for moons
            if math.random() < 0.4 then -- 40% chance
                planet.moons = {}
                local numMoons = math.random(1, 2)
                for j = 1, numMoons do
                    local moon = {}
                    moon.name = planet.name .. "Moon" .. j
                    moon.radius = 1 + math.random(1)
                    moon.color = 3 -- Fixed moon color.
                    moon.orbitalRadius = planet.radius + 2 + math.random(6) -- Orbit radius relative to planet surface.
                    -- Use orbitalSpeed sign for direction (+1 or -1), magnitude derived later from G.
                    moon.orbitalSpeed = (math.random(2) == 1 and 1 or -1)
                    table.insert(planet.moons, moon)
                end
            end

            -- Calculate initial physics state for the planet
            local planetState = {}
            planetState.name = planet.name
            planetState.radius = planet.radius
            planetState.color = planet.color
            planetState.mass = planet.radius * 5.0 -- Mass proportional to radius (constant density).
            planetState.px = centerX + orbitalRadius
            planetState.py = centerY
            -- Calculate velocity for a circular orbit around the sun (ignoring other planets initially).
            local speedMag = math.sqrt(self.G * sunState.mass / orbitalRadius)
            planetState.vx = 0
            planetState.vy = speedMag * (orbitalSpeed >= 0 and 1 or -1) -- Apply direction sign.

            -- Setup moons physics state relative to the planet
            if planet.moons then
                planetState.moons = {}
                for _, moonDef in ipairs(planet.moons) do
                    local moonState = {}
                    moonState.name = moonDef.name
                    moonState.radius = moonDef.radius
                    moonState.color = moonDef.color
                    moonState.mass = moonDef.radius * 1.0 -- Smaller mass factor for moons.
                    -- Initial moon position along planet's local Y+ axis.
                    moonState.px = planetState.px
                    moonState.py = planetState.py + moonDef.orbitalRadius
                    -- Calculate moon velocity relative to planet for circular orbit, then add planet's velocity.
                    local moonSpeedMag = math.sqrt(
                                             self.G * planetState.mass /
                                                 moonDef.orbitalRadius)
                    -- Relative velocity is tangential (local X axis) to the initial Y+ offset.
                    local relVx = moonSpeedMag *
                                      (moonDef.orbitalSpeed >= 0 and -1 or 1) -- Negative sign for orbit direction around center.
                    local relVy = 0
                    -- Combine relative velocity with planet's velocity.
                    moonState.vx = planetState.vx + relVx
                    moonState.vy = planetState.vy + relVy
                    table.insert(planetState.moons, moonState)
                end
            end

            table.insert(self.bodyStates, planetState)
        end
        -- Kinematic data (self.planetarySystem) is no longer used; physics state (self.bodyStates) is authoritative.
        self.planetarySystem = nil
        -- Initialize the forces table to match the new body states structure.
        self:initForcesTable()
    end,

    -- Helper function to initialize/structure the pre-allocated forces table
    initForcesTable = function(self)
        local states = self.bodyStates
        local numBodies = #states
        -- Clear/rebuild the forces table structure to match bodyStates
        self.forcesTable = {}
        for i = 1, numBodies do
            self.forcesTable[i] = {fx = 0, fy = 0}
            -- If the body has moons, create a sub-table for their forces
            if states[i].moons then
                self.forcesTable[i].moonForces = {}
                for j = 1, #states[i].moons do
                    self.forcesTable[i].moonForces[j] = {fx = 0, fy = 0}
                end
            end
        end
    end,

    init = function(self)
        -- Use the new defaults defined at the top level
        local defaultGravityVal = self.defaultGravityParamVal

        -- Initialize physics state storage and parameters
        self.bodyStates = {}
        self.parameters = {} -- Populated by host after return
        self.paused = false -- Simulation starts unpaused
        self.lastForceAngle = 0 -- For drawing force indicator
        self.lastForceMag = 0 -- For drawing force indicator
        self.lastForceNormMag = 0.0 -- Normalized magnitude (CV * Scale) for drawing
        self.forceIndicatorAlpha = 1.0 -- Alpha for force indicator fade effect
        self.outputsTable = {0.0, 0.0, 0.0, 0.0, 0.0} -- Pre-allocate outputs table for efficiency
        self.forcesTable = {} -- Pre-allocate forces table for efficiency

        -- self.state holds data from serialise(), if any (currently none).
        -- self.state = state or {}

        print("Initializing physics simulation.")

        -- Setup the system based on defaults. Parameter/trigger changes will reset later.
        -- Need parameter values for initial setup, use defaults directly here.
        self:setupSystem(self.defaultNumPlanetsVal) -- Use default value constant
        -- NOTE: setupSystem now calls initForcesTable automatically at the end.

        -- Return the script definition, including parameters with correct initial values.
        -- Note: The host stores the returned parameters table in self.parameters.
        return {
            inputs = {kGate, kCV, kCV, kTrigger}, -- Indices match INPUT_* constants
            inputNames = {"Freeze", "Force Dir", "Force Mag", "Rand Trig"},
            -- Define 5 outputs for planet positions (cosine of angle * 5V).
            outputs = {kLinear, kLinear, kLinear, kLinear, kLinear},
            outputNames = {
                "Planet 1 Out", "Planet 2 Out", "Planet 3 Out", "Planet 4 Out",
                "Planet 5 Out"
            },
            parameters = {
                -- Order matches PARAM_* constants
                {"Num Planets", 1, 5, self.defaultNumPlanetsVal}, -- P1 (Pot 1)
                {"Gravity", -10.0, 10.0, self.defaultGravityParamVal}, -- P2 (Pot 2): Gravity Strength (log scale)
                {"Force Scale", 0.0, 2.0, self.defaultForceScaleVal}, -- P3 (Pot 3): Scales CV Force Magnitude
                {"Zoom", -10.0, 10.0, self.defaultZoomParamVal}, -- P4 (Enc 1): Zoom Level (log scale)
                {"Time Scale", -10.0, 10.0, self.defaultTimeScaleParamVal}, -- P5 (Enc 2): Time Scale (log scale)
                {"Randomize", {"Off", "On"}, self.defaultRandomizeVal}, -- P6 (Enc 2 Push): Randomize Trigger
                {
                    "Output Mode", {"Unipolar", "Bipolar"},
                    self.defaultOutputModeVal
                } -- P7 (Pot 3 Push): Output Mode
            }
        }
    end,

    -- Physics update function, called every step (approx 1ms)
    -- Uses simple Euler integration (pos += vel * dt, vel += acc * dt).
    -- Could be improved with Verlet or RK4 for better stability/accuracy if needed.
    updatePhysics = function(self, dt, inputs) -- Added inputs argument
        if not self.bodyStates or #self.bodyStates < 1 then return end -- Exit if no bodies
        if self.paused then return end -- Skip update if paused by Gate input 1

        -- Parameter Indices (Matches definition in init) -- Now using constants below
        -- Default parameter values (used if self.parameters isn't populated yet)
        local gravityParamVal = self.defaultGravityParamVal
        local forceMagScaleParamVal = self.defaultForceScaleVal
        local timeScaleParamVal = self.defaultTimeScaleParamVal

        -- Input Indices (Matches definition in init) -- Now using constants below
        local forceDirCV = 0.0 -- Default force direction CV value
        local forceMagCV = 0.0 -- Default force magnitude CV value

        -- Get current parameter values from self.parameters (set by host)
        -- Check against highest param index used (PARAM_TIME_SCALE) -> Now PARAM_OUTPUT_MODE
        if self.parameters and #self.parameters >= self.PARAM_OUTPUT_MODE then
            gravityParamVal = self.parameters[self.PARAM_GRAVITY]
            forceMagScaleParamVal = self.parameters[self.PARAM_FORCE_SCALE]
            timeScaleParamVal = self.parameters[self.PARAM_TIME_SCALE]
            -- Note: output mode param read in step function where it's used
        end

        -- Get live input CV values
        -- Check against highest CV input index used (INPUT_FORCE_MAG_CV)
        if inputs and #inputs >= self.INPUT_FORCE_MAG_CV then
            forceDirCV = inputs[self.INPUT_FORCE_DIR_CV] -- Input 2 voltage
            forceMagCV = inputs[self.INPUT_FORCE_MAG_CV] -- Input 3 voltage
        end

        -- Calculate G based on parameter (log scale: +/- 10 gives 4x / 0.25x)
        local G = 500.0 * (2 ^ (gravityParamVal / 5.0))

        -- Calculate time scale based on parameter (log scale: +/- 10 gives 4x / 0.25x)
        local timeScale = 2 ^ (timeScaleParamVal / 5.0)
        local effective_dt = dt * timeScale

        -- Calculate External Force Vector from Inputs 2 & 3
        -- Direction from CV 2 (-5V to +5V mapped to 0 to 2*pi radians)
        local forceAngle = (forceDirCV / 5.0 + 1.0) * math.pi
        -- Magnitude from CV 3 (-5V to +5V mapped to -1.0 to 1.0), then scaled by Param 3 (Force Scale)
        local normalizedMagCV = math.max(-1.0, math.min(forceMagCV / 5.0, 1.0))
        local maxBaseForce = 500.0 -- Reduced base force multiplier for gentler drift effect
        local actualForceMag = normalizedMagCV * maxBaseForce *
                                   forceMagScaleParamVal

        -- Store force properties for drawing the indicator
        self.lastForceAngle = forceAngle
        self.lastForceMag = actualForceMag -- Final calculated magnitude
        self.lastForceNormMag = normalizedMagCV * forceMagScaleParamVal -- Combined normalized magnitude for drawing

        -- Update animated alpha for force indicator (smooth fade in/out)
        local targetAlpha = (math.abs(self.lastForceNormMag) <
                                self.ZERO_MAG_THRESHOLD) and 0.0 or 1.0 -- Target 0 if near zero, else 1
        local maxAlphaChange = effective_dt / self.FADE_DURATION -- Max change per step based on dt and fade time
        if self.forceIndicatorAlpha < targetAlpha then
            self.forceIndicatorAlpha = math.min(targetAlpha,
                                                self.forceIndicatorAlpha +
                                                    maxAlphaChange)
        elseif self.forceIndicatorAlpha > targetAlpha then
            self.forceIndicatorAlpha = math.max(targetAlpha,
                                                self.forceIndicatorAlpha -
                                                    maxAlphaChange)
        end

        -- Calculate external force components
        local fx_external = actualForceMag * math.cos(forceAngle)
        local fy_external = actualForceMag * math.sin(forceAngle)

        local states = self.bodyStates
        local numBodies = #states
        -- Softening factor (epsilon^2) added to distance squared prevents extreme forces
        -- at very close distances and avoids division by zero. Increased for stability.
        local epsilon = 1.0

        -- Use the pre-allocated table for storing calculated forces this step
        local forces = self.forcesTable

        -- Reset forces from previous step
        for i = 1, numBodies do
            forces[i].fx = 0
            forces[i].fy = 0
            if forces[i].moonForces then -- Check if moonForces sub-table exists
                for j = 1, #forces[i].moonForces do
                    forces[i].moonForces[j].fx = 0
                    forces[i].moonForces[j].fy = 0
                end
            end
        end

        -- Calculate gravitational forces between all bodies
        local sun = states[1]
        for i = 2, numBodies do -- Iterate through planets (start from 2 to skip sun)
            local body_i = states[i]

            -- 1. Sun -> Planet_i force
            local dx_sp = sun.px - body_i.px
            local dy_sp = sun.py - body_i.py
            local distSq_sp = dx_sp * dx_sp + dy_sp * dy_sp + epsilon * epsilon -- Add softening
            local dist_sp = math.sqrt(distSq_sp)
            if dist_sp > epsilon then -- Avoid self-force / division by zero
                local forceMag_sp = G * sun.mass * body_i.mass / distSq_sp
                local fx_sp = forceMag_sp * dx_sp / dist_sp -- Force components
                local fy_sp = forceMag_sp * dy_sp / dist_sp
                forces[i].fx = forces[i].fx + fx_sp -- Add force to planet i
                forces[i].fy = forces[i].fy + fy_sp
                -- No force applied back to sun (it's fixed)
            end

            -- 2. Planet_j -> Planet_i force (j > i to avoid double counting and self-interaction)
            for j = i + 1, numBodies do
                local body_j = states[j]
                local dx_pp = body_j.px - body_i.px
                local dy_pp = body_j.py - body_i.py
                local distSq_pp = dx_pp * dx_pp + dy_pp * dy_pp + epsilon *
                                      epsilon -- Add softening
                local dist_pp = math.sqrt(distSq_pp)
                if dist_pp > epsilon then
                    local forceMag_pp = G * body_j.mass * body_i.mass /
                                            distSq_pp
                    local fx_pp = forceMag_pp * dx_pp / dist_pp -- Force components
                    local fy_pp = forceMag_pp * dy_pp / dist_pp
                    forces[i].fx = forces[i].fx + fx_pp -- Add force on planet i from planet j
                    forces[i].fy = forces[i].fy + fy_pp
                    forces[j].fx = forces[j].fx - fx_pp -- Add equal opposite force on planet j from planet i
                    forces[j].fy = forces[j].fy - fy_pp
                end
            end

            -- 3. Forces involving moons of Planet_i
            if body_i.moons then
                for k = 1, #body_i.moons do
                    local moon_k = body_i.moons[k]

                    -- 3a. Sun -> Moon_k force
                    local dx_sm = sun.px - moon_k.px
                    local dy_sm = sun.py - moon_k.py
                    local distSq_sm = dx_sm * dx_sm + dy_sm * dy_sm + epsilon *
                                          epsilon -- Add softening
                    local dist_sm = math.sqrt(distSq_sm)
                    if dist_sm > epsilon then
                        local forceMag_sm =
                            G * sun.mass * moon_k.mass / distSq_sm
                        -- Add force to moon k's force accumulator
                        forces[i].moonForces[k].fx =
                            forces[i].moonForces[k].fx + forceMag_sm * dx_sm /
                                dist_sm
                        forces[i].moonForces[k].fy =
                            forces[i].moonForces[k].fy + forceMag_sm * dy_sm /
                                dist_sm
                    end

                    -- 3b. Planet_i -> Moon_k force
                    local dx_pm = body_i.px - moon_k.px
                    local dy_pm = body_i.py - moon_k.py
                    local distSq_pm = dx_pm * dx_pm + dy_pm * dy_pm + epsilon *
                                          epsilon -- Add softening
                    local dist_pm = math.sqrt(distSq_pm)
                    if dist_pm > epsilon then
                        local forceMag_pm =
                            G * body_i.mass * moon_k.mass / distSq_pm
                        local fx_pm = forceMag_pm * dx_pm / dist_pm -- Force components
                        local fy_pm = forceMag_pm * dy_pm / dist_pm
                        -- Add force to moon k
                        forces[i].moonForces[k].fx =
                            forces[i].moonForces[k].fx + fx_pm
                        forces[i].moonForces[k].fy =
                            forces[i].moonForces[k].fy + fy_pm
                        -- Apply opposite force back to Planet_i (Newton's 3rd law)
                        forces[i].fx = forces[i].fx - fx_pm
                        forces[i].fy = forces[i].fy - fy_pm
                    end

                    -- TODO: Optional: Consider Planet_j -> Moon_k forces for j != i?
                    -- TODO: Optional: Consider Moon_l -> Moon_k forces? (Probably negligible effect)
                    -- Keeping it simpler for now: Sun->Moon, ParentPlanet->Moon.

                end
            end
        end

        -- Apply External Force (from CVs) ONLY to Planets (non-sun bodies)
        for i = 2, numBodies do -- Skip sun (index 1)
            forces[i].fx = forces[i].fx + fx_external
            forces[i].fy = forces[i].fy + fy_external
        end

        -- Update velocities and positions using calculated forces (Euler integration)
        -- Update Planets (skip sun at index 1)
        for i = 2, numBodies do
            local body = states[i]
            local force = forces[i]
            local ax = force.fx / body.mass -- Acceleration = Force / Mass
            local ay = force.fy / body.mass
            body.vx = body.vx + ax * effective_dt -- Update velocity using scaled dt
            body.vy = body.vy + ay * effective_dt
            body.px = body.px + body.vx * effective_dt -- Update position using scaled dt
            body.py = body.py + body.vy * effective_dt

            -- Update Moons attached to this planet
            if body.moons then
                for j = 1, #body.moons do
                    local moon = body.moons[j]
                    local moonForce = forces[i].moonForces[j]
                    local moon_ax = moonForce.fx / moon.mass
                    local moon_ay = moonForce.fy / moon.mass
                    moon.vx = moon.vx + moon_ax * effective_dt -- Update velocity using scaled dt
                    moon.vy = moon.vy + moon_ay * effective_dt
                    moon.px = moon.px + moon.vx * effective_dt -- Update position using scaled dt
                    moon.py = moon.py + moon.vy * effective_dt
                end
            end
        end
    end,

    -- Draw function using current physics state (called ~30fps)
    drawPlanetarySystem = function(self)
        -- Parameter Indices (Matches definition in init) -- Now using constants below
        -- Ensure parameters table exists and is populated before accessing
        -- Check against highest param index used (PARAM_RANDOMIZE) -> Now PARAM_OUTPUT_MODE
        if not self.parameters or #self.parameters < self.PARAM_OUTPUT_MODE then
            return -- Skip drawing until parameters are available
        end

        local numPlanetsParam = self.parameters[self.PARAM_NUM_PLANETS] -- Current value of P1
        local randomizeParam = self.parameters[self.PARAM_RANDOMIZE] -- Current value of P6
        local zoomParamVal = self.parameters[self.PARAM_ZOOM] -- Current value of P4

        -- Check for Randomize trigger (Parameter 6 set to 'On' == 2)
        if randomizeParam == 2 then -- If P6 is 'On'
            print("Randomizing system via parameter...")
            self:setupSystem(numPlanetsParam) -- Re-run setup with current P1 value
            -- Reset the parameter back to 'Off' (value 1) immediately
            setParameter(getCurrentAlgorithm(),
                         self.parameterOffset + self.PARAM_RANDOMIZE, 1)
            return -- Exit draw function for this frame after reset
        end

        -- Check if Num Planets parameter (P1) has changed, requiring a system reset
        -- Compare parameter value to actual number of planets in physics state (-1 for sun)
        local currentNumPlanets = #self.bodyStates - 1
        if numPlanetsParam ~= currentNumPlanets then
            print("Resetting system to " .. numPlanetsParam ..
                      " random planets due to parameter change...")
            self:setupSystem(numPlanetsParam) -- Reset physics state (always random)
            return -- Exit draw function for this frame after reset
        end

        -- Proceed with drawing based on current physics state
        local screenWidth = self.screenWidth
        local screenHeight = self.screenHeight
        local centerX = screenWidth / 2
        local centerY = screenHeight / 2
        -- Calculate zoom factor (log scale: +/- 10 gives 4x / 0.25x)
        local zoom = 2 ^ (zoomParamVal / 5.0)

        if not self.bodyStates then return end -- Should not happen if init ran correctly

        -- Draw Sun (always at index 1, assumed fixed at center initially)
        local sun = self.bodyStates[1]
        -- Apply zoom centered on the screen center, not the sun's (potentially drifted) position px, py.
        local sunDrawRadius = math.max(1, sun.radius * zoom) -- Ensure radius is at least 1px
        local sunDrawX = centerX + (sun.px - centerX) * zoom -- Scale position relative to center
        local sunDrawY = centerY + (sun.py - centerY) * zoom
        drawCircle(sunDrawX, sunDrawY, sunDrawRadius, sun.color)

        -- Draw Planets (and their moons) based on their current physics state
        for i = 2, #self.bodyStates do -- Iterate from index 2
            local planet = self.bodyStates[i]
            local planetDrawRadius = math.max(1, planet.radius * zoom) -- Ensure radius is at least 1px
            -- Calculate draw position based on physics position, zoom, and screen center
            local planetDrawX = centerX + (planet.px - centerX) * zoom
            local planetDrawY = centerY + (planet.py - centerY) * zoom
            drawCircle(planetDrawX, planetDrawY, planetDrawRadius, planet.color)

            -- Draw Moons orbiting this Planet
            if planet.moons then
                for j = 1, #planet.moons do
                    local moon = planet.moons[j]
                    local moonDrawRadius = math.max(1, moon.radius * zoom) -- Ensure radius is at least 1px
                    local moonDrawX = centerX + (moon.px - centerX) * zoom
                    local moonDrawY = centerY + (moon.py - centerY) * zoom
                    drawCircle(moonDrawX, moonDrawY, moonDrawRadius, moon.color)
                end
            end
        end
        -- No separate animation logic needed; physics state drives the drawing.
    end,

    -- Main draw function, called ~30fps
    draw = function(self)
        self:drawPlanetarySystem() -- Draw the simulation elements first

        -- Draw Force Indicator arrow in bottom right corner
        -- Fade effect controlled by self.forceIndicatorAlpha (updated in updatePhysics)

        -- Calculate final alpha, ensuring it's clamped between 0.0 and 1.0
        local currentAlpha = math.max(0.0,
                                      math.min(1.0, self.forceIndicatorAlpha))

        if currentAlpha > 0.01 then -- Only draw if alpha is significant enough to be visible
            local indCenterX = 246 -- Indicator center X
            local indCenterY = 54 -- Indicator center Y
            local indRadius = 8 -- Indicator radius

            -- Calculate circle background color brightness based on force magnitude and alpha fade
            local maxCircleBrightness = 8 / 15.0 -- Max brightness (Color 8)
            local minCircleBrightness = 2 / 15.0 -- Min brightness (Color 2)
            local brightnessRange = maxCircleBrightness - minCircleBrightness
            local absNormMag = math.abs(self.lastForceNormMag) -- Absolute normalized magnitude (0.0 to potentially > 1.0)
            -- Target brightness scales with magnitude, clamped if absNormMag > 1.0
            local targetCircleBrightness =
                minCircleBrightness + brightnessRange *
                    math.min(1.0, absNormMag)
            local finalCircleBrightness = targetCircleBrightness * currentAlpha -- Apply alpha fade
            local actualCircleColor = math.floor(
                                          finalCircleBrightness * 15 + 0.5) -- Map brightness back to 0-15 color index
            actualCircleColor = math.max(0, math.min(actualCircleColor, 15)) -- Clamp color index 0-15

            -- Calculate arrow color brightness based only on alpha fade (max brightness is Color 15)
            local targetArrowBrightness = 1.0 -- Color 15 brightness (full)
            local finalArrowBrightness = targetArrowBrightness * currentAlpha -- Apply alpha fade
            local actualArrowColor = math.floor(finalArrowBrightness * 15 + 0.5) -- Map brightness back to 0-15 color index
            actualArrowColor = math.max(0, math.min(actualArrowColor, 15)) -- Clamp color index 0-15

            -- Draw the background circle with calculated color (if color > 0)
            if actualCircleColor > 0 then
                drawCircle(indCenterX, indCenterY, indRadius, actualCircleColor)
            end

            -- Calculate arrow endpoint based on angle and magnitude
            -- Scale arrow length by the ABSOLUTE normalized magnitude (CV * Scale Param), capped by indicator radius
            local arrowLength = math.min(indRadius, indRadius * absNormMag)

            -- Draw arrow only if length and color are significant
            if arrowLength > 0.5 and actualArrowColor > 0 then
                -- Determine the actual angle to draw: base angle for positive force, flipped 180 deg for negative
                local drawAngle = self.lastForceAngle
                if self.lastForceNormMag < 0.0 then
                    drawAngle = drawAngle + math.pi -- Add 180 degrees for negative magnitude
                end

                local arrowEndX = indCenterX + arrowLength * math.cos(drawAngle)
                local arrowEndY = indCenterY + arrowLength * math.sin(drawAngle)

                -- Draw the arrow line
                drawLine(indCenterX, indCenterY, arrowEndX, arrowEndY,
                         actualArrowColor)

                -- Draw a small arrowhead (simple triangle) pointing in the drawAngle direction
                local arrowSize = 2 -- Size of arrowhead lines
                local headAngleOffset = 2.5 -- Angle offset for arrowhead lines (radians)
                local headX1 = arrowEndX + arrowSize *
                                   math.cos(drawAngle - headAngleOffset)
                local headY1 = arrowEndY + arrowSize *
                                   math.sin(drawAngle - headAngleOffset)
                local headX2 = arrowEndX + arrowSize *
                                   math.cos(drawAngle + headAngleOffset)
                local headY2 = arrowEndY + arrowSize *
                                   math.sin(drawAngle + headAngleOffset)
                drawLine(arrowEndX, arrowEndY, headX1, headY1, actualArrowColor)
                drawLine(arrowEndX, arrowEndY, headX2, headY2, actualArrowColor)
            end
        end

        -- Returning true suppresses the default parameter line drawing
        return true
    end,

    -- step function: called every 1ms, responsible for physics updates and output calculation
    step = function(self, dt, inputs)
        self:updatePhysics(dt, inputs) -- Update physics state first

        -- Calculate and return output voltages based on planet positions
        local outputs = self.outputsTable -- Use the pre-allocated table for efficiency
        local maxOutputs = 5 -- Corresponds to number of outputs defined in init
        local centerX = self.screenWidth / 2
        local centerY = self.screenHeight / 2
        local voltageRange = 5.0 -- Target output range +/- 5V
        local epsilon = 0.001 -- Small value to avoid division by zero if planet is exactly at center

        -- Get Output Mode parameter
        local outputMode = self.defaultOutputModeVal -- Default if parameters not ready
        if self.parameters and #self.parameters >= self.PARAM_OUTPUT_MODE then
            outputMode = self.parameters[self.PARAM_OUTPUT_MODE] -- 1 = Unipolar, 2 = Bipolar
        end

        -- Calculate output voltage for each defined output (up to maxOutputs)
        for i = 1, maxOutputs do
            -- Body index is planet index + 1 (since sun is index 1 in bodyStates)
            local bodyIndex = i + 1
            if self.bodyStates and bodyIndex <= #self.bodyStates then
                local planet = self.bodyStates[bodyIndex]
                -- Calculate position relative to the screen center
                local relativeX = planet.px - centerX
                local relativeY = planet.py - centerY

                -- Calculate distance from center (radius)
                local radiusSq = relativeX * relativeX + relativeY * relativeY
                local radius = math.sqrt(radiusSq)

                local voltage = 0.0 -- Default voltage
                local referenceDistance = 30.0 -- Reference distance for Unipolar scaling

                if radius > epsilon then
                    if outputMode == 1 then -- Unipolar Mode
                        -- Voltage inversely proportional to distance, scaled 0 to voltageRange
                        voltage = (referenceDistance / radius) * voltageRange
                        -- Clamp to Unipolar range [0, voltageRange]
                        voltage = math.max(0.0, math.min(voltage, voltageRange))
                    else -- Bipolar Mode (outputMode == 2 or default)
                        -- Calculate cosine of the angle (adjacent/hypotenuse = relativeX / radius)
                        local cosAngle = relativeX / radius
                        -- Calculate base voltage based on angle
                        voltage = cosAngle * voltageRange
                        -- Clamp to Bipolar range [-voltageRange, voltageRange]
                        voltage = math.max(-voltageRange,
                                           math.min(voltage, voltageRange))
                    end
                else
                    -- If planet is at the center (radius <= epsilon)
                    if outputMode == 1 then -- Unipolar
                        voltage = voltageRange -- Max voltage when distance is near zero
                    else -- Bipolar
                        voltage = 0.0 -- Zero voltage when at center (angle undefined)
                    end
                end

                -- Assign the final calculated and clamped voltage
                outputs[i] = voltage
            else
                -- If fewer planets exist than defined outputs, set remaining outputs to 0V
                outputs[i] = 0.0
            end
        end

        return outputs -- Return the table of calculated output voltages
    end,

    -- UI handling: Return true to indicate custom UI handlers are provided
    ui = function(self)
        return true -- Override standard UI parameter display/control
    end,

    -- setupUi: Called once to set initial pot positions based on default parameter values
    setupUi = function(self)
        -- Parameter definitions from init for reference:
        -- P1 (Pot 1): Num Planets (Min=1, Max=5, Default=2)
        -- P2 (Pot 2): Gravity (Min=-10.0, Max=10.0, Default=0.0)
        -- P3 (Pot 3): Force Scale (Min=0.0, Max=2.0, Default=1.0)

        -- Calculate normalized initial pot positions (0.0 to 1.0) using: (default - min) / (max - min)
        return {
            pot1 = (self.defaultNumPlanetsVal - 1) / (5 - 1), -- P1
            pot2 = (self.defaultGravityParamVal - (-10.0)) / (10.0 - (-10.0)), -- P2
            pot3 = (self.defaultForceScaleVal - 0.0) / (2.0 - 0.0) -- P3
        }
    end,

    -- Pot 1 controls Num Planets parameter (Parameter 1)
    pot1Turn = function(self, x) -- x is normalized 0.0 to 1.0
        local paramIndex = self.PARAM_NUM_PLANETS
        local minVal = 1
        local maxVal = 5
        local steps = maxVal - minVal -- Number of steps in the discrete range

        -- Map normalized pot value x [0, 1] to the discrete parameter value [minVal, maxVal]
        -- Multiply by (steps + 1) and floor to distribute values evenly across the pot range.
        local newValue = math.floor(minVal + x * (steps + 1))
        newValue = math.max(minVal, math.min(newValue, maxVal)) -- Clamp to ensure value stays within [minVal, maxVal]

        -- Only update the parameter if the calculated value actually changes
        -- This prevents unnecessary system resets if the pot value jitters slightly within one step's range.
        if newValue ~= self.parameters[paramIndex] then
            setParameter(getCurrentAlgorithm(),
                         self.parameterOffset + paramIndex, newValue)
        end
    end,

    -- Pot 2 controls Gravity Strength parameter (Parameter 2)
    pot2Turn = function(self, x) -- x is normalized 0.0 to 1.0
        local paramIndex = self.PARAM_GRAVITY
        -- For continuous parameters controlled by pots, directly set the normalized value.
        -- The host handles mapping the normalized value [0, 1] to the parameter's defined range [-10.0, 10.0].
        setParameterNormalized(getCurrentAlgorithm(),
                               self.parameterOffset + paramIndex, x)
    end,

    -- Pot 3 controls Force Magnitude Scale parameter (Parameter 3)
    pot3Turn = function(self, x) -- x is normalized 0.0 to 1.0
        local paramIndex = self.PARAM_FORCE_SCALE
        -- Directly set the normalized value [0, 1]. Host maps to the parameter range [0.0, 2.0].
        setParameterNormalized(getCurrentAlgorithm(),
                               self.parameterOffset + paramIndex, x)
    end,

    -- Encoder 1 controls Zoom parameter (Parameter 4)
    encoder1Turn = function(self, dir) -- dir is +1 or -1
        local paramIndex = self.PARAM_ZOOM
        local currentParamVal = self.parameters[paramIndex]
        local step = 1 -- Increment/decrement step size for encoder turns
        local minVal = -10.0
        local maxVal = 10.0

        local newParamVal = currentParamVal + dir * step
        newParamVal = math.max(minVal, math.min(newParamVal, maxVal)) -- Clamp value

        -- Use setParameter for discrete steps controlled by encoders
        setParameter(getCurrentAlgorithm(), self.parameterOffset + paramIndex,
                     newParamVal)
    end,

    -- Encoder 2 controls Time Scale parameter (Parameter 5)
    encoder2Turn = function(self, dir) -- dir is +1 or -1
        local paramIndex = self.PARAM_TIME_SCALE
        local currentParamVal = self.parameters[paramIndex]
        local step = 1 -- Increment/decrement step size
        local minVal = -10.0
        local maxVal = 10.0

        local newParamVal = currentParamVal + dir * step
        newParamVal = math.max(minVal, math.min(newParamVal, maxVal)) -- Clamp value

        setParameter(getCurrentAlgorithm(), self.parameterOffset + paramIndex,
                     newParamVal)
    end,

    -- Encoder 2 Push triggers Randomize (Parameter 6)
    encoder2Push = function(self)
        -- Set the Randomize parameter (Enum: 1="Off", 2="On") to 'On' (value 2).
        -- The draw function checks this parameter and triggers setupSystem if it's 2, then resets it to 1.
        local paramIndex = self.PARAM_RANDOMIZE
        setParameter(getCurrentAlgorithm(), self.parameterOffset + paramIndex, 2) -- Set to 'On'
    end,

    -- Pot 3 Push cycles Output Mode parameter (Parameter 7)
    pot3Push = function(self)
        local paramIndex = self.PARAM_OUTPUT_MODE
        local currentMode = self.parameters[paramIndex]
        local numModes = 2 -- Currently Unipolar (1) and Bipolar (2)

        local nextMode = currentMode + 1
        if nextMode > numModes then
            nextMode = 1 -- Wrap around from Bipolar back to Unipolar
        end

        setParameter(getCurrentAlgorithm(), self.parameterOffset + paramIndex,
                     nextMode)
    end,

    -- Handle Trigger Input 4 for Randomize
    trigger = function(self, input)
        if input == self.INPUT_RANDOMIZE_TRIG then -- Check if it's the correct input index
            print("Triggering randomize via input 4")
            local numPlanetsParamIndex = self.PARAM_NUM_PLANETS
            -- Ensure parameters are available before accessing
            if self.parameters and #self.parameters >= self.PARAM_OUTPUT_MODE then -- Check highest index
                local numPlanetsParam = self.parameters[numPlanetsParamIndex]
                self:setupSystem(numPlanetsParam) -- Call setupSystem directly
            end
        end
    end,

    -- Handle Gate Input 1 for Time Freeze
    gate = function(self, input, rising) -- rising is true for gate high, false for gate low
        if input == self.INPUT_FREEZE_GATE then -- Check if it's the correct input index
            self.paused = rising -- Set pause state based on gate level (high = paused)
        end
        -- Gate callbacks don't typically return outputs.
    end
}
