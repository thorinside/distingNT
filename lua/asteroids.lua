-- Asteroids CV Game with Thruster Envelope, Asteroid Splitting, Bullet Collision,
-- Ship-Asteroid Bouncing, Win Envelope Output, and Game Reset
--[[
  This algorithm simulates a simplified Asteroids game using CV signals.

  Inputs:
    - Input 1 (kCV): Rotation CV (-5V to +5V maps to -180° to +180°).
      0V means the ship is oriented straight up.
    - Input 2 (kGate): Thruster gate input. When high, continuous thruster acceleration is applied.
    - Input 3 (kTrigger): (External) (Unused in this version)

  Outputs (6):
    1) Gun trigger pulse (5V when fired).
    2) Thruster envelope (0–5V). When thrusters fire, this is set to 5 and then decays.
    3) Collision envelope (for asteroid collisions, including with the ship).
    4) Explosion envelope (when a bullet hits an asteroid).
    5) Proximity voltage (increases as the ship nears an asteroid).
    6) Win envelope (special envelope triggered when all asteroids are destroyed).

  Controls:
    - Encoder 2 turn: Adjusts the ship’s rotational offset.
    - Encoder 2 press: Fires the gun.
    - Pot 3 push: Fires the thrusters (applying an impulse and setting the envelope).

  Special behavior:
    • When a bullet collides with an asteroid, the explosion envelope is triggered.
      If the asteroid is large (radius > 6), it splits into two smaller asteroids that are given
      random directions and speeds.
    • Asteroids bounce off the ship. When an asteroid collides with the ship (approximated as a circle of radius 8),
      its velocity is reflected and it is repositioned so that it no longer overlaps the ship.
    • When all asteroids are destroyed, a win envelope is set to 5.
      This envelope decays over time, and when it reaches 0, the game automatically resets.

  The draw() function renders the ship (with a thruster flame), asteroids, and bullets.
  Debug text for envelopes has been removed.
  The ui() function returns true so that the module handles UI events.
--]] return {
    name = "Asteroids CV Game",
    author = "Thorinside / ChatGPT o3-mini-high",

    init = function(self)
        -- Ship starts centered with zero velocity.
        self.ship = {
            x = 128,
            y = 32,
            vx = 0,
            vy = 0,
            base_angle = 0, -- Derived from CV input.
            encoder_offset = 0, -- Adjusted via Encoder 1.
            angle = 0 -- Final computed angle.
        }
        self.asteroids = {}
        local numAsteroids = 5
        for i = 1, numAsteroids do
            table.insert(self.asteroids, {
                x = math.random(256),
                y = math.random(64),
                vx = (math.random() - 0.5) * 20,
                vy = (math.random() - 0.5) * 20,
                radius = math.random(5, 10)
            })
        end

        -- Bullet list.
        self.bullets = {}

        -- Initialize timers, envelopes, and thruster effect.
        self.gunTriggerTimer = 0 -- 50 ms pulse for gun output.
        self.thrusterEnvelope = 0 -- Thruster envelope (0–5V).
        self.thrusterEffectTimer = 0 -- For drawing the thruster flame.
        self.collisionEnv = 0 -- Collision envelope.
        self.explosionEnv = 0 -- Explosion envelope.
        self.winEnv = 0 -- Special win envelope.
        self.simTime = 0 -- Accumulated simulation time.
        -- Flag for continuous thruster activation.
        self.thrusterActive = false

        return {
            inputs = {kCV, kGate, kTrigger},
            outputs = 6,
            inputNames = {"Rotation CV", "Thruster Gate", "Unused"},
            outputNames = {
                "Gun Out", "Thruster Env", "Collision Env", "Explosion Env",
                "Proximity", "Win Env"
            },
            parameters = {{"Asteroid Count", 1, 10, numAsteroids, kInt}}
        }
    end,

    resetGame = function(self)
        self.ship.x = 128
        self.ship.y = 32
        self.ship.vx = 0
        self.ship.vy = 0
        self.ship.encoder_offset = 0
        self.ship.base_angle = 0
        self.ship.angle = 0
        self.asteroids = {}
        local numAsteroids = self.parameters[1]
        for i = 1, numAsteroids do
            table.insert(self.asteroids, {
                x = math.random(256),
                y = math.random(64),
                vx = (math.random() - 0.5) * 20,
                vy = (math.random() - 0.5) * 20,
                radius = math.random(5, 10)
            })
        end
        self.bullets = {}
        self.winEnv = 0
        self.collisionEnv = 0
        self.explosionEnv = 0
        self.thrusterEnvelope = 0
        self.simTime = 0
    end,

    step = function(self, dt, inputs)
        if dt > 0.05 then dt = 0.05 end
        self.simTime = self.simTime + dt

        -- Update ship angle from CV.
        local cv = inputs[1] or 0
        self.ship.base_angle = (cv / 5) * 180
        self.ship.angle = self.ship.base_angle + self.ship.encoder_offset

        -- Thruster gate input is handled in gate().

        -- Update gun trigger timer.
        if self.gunTriggerTimer > 0 then
            self.gunTriggerTimer = self.gunTriggerTimer - dt
            if self.gunTriggerTimer < 0 then self.gunTriggerTimer = 0 end
        end

        -- Update thruster envelope.
        if self.thrusterActive then
            self.thrusterEnvelope = 5
            self.thrusterEffectTimer = 0.1 -- Maintain flame effect.
            local angleRad = math.rad(self.ship.angle - 90)
            local thrustAcceleration = 50 -- pixels/s^2.
            self.ship.vx = self.ship.vx + math.cos(angleRad) *
                               thrustAcceleration * dt
            self.ship.vy = self.ship.vy + math.sin(angleRad) *
                               thrustAcceleration * dt
        else
            local envelopeDecay = 10 -- V/s decay.
            self.thrusterEnvelope = math.max(0, self.thrusterEnvelope -
                                                 envelopeDecay * dt)
            if self.thrusterEffectTimer > 0 then
                self.thrusterEffectTimer = self.thrusterEffectTimer - dt
                if self.thrusterEffectTimer < 0 then
                    self.thrusterEffectTimer = 0
                end
            end
        end

        -- Decay collision and explosion envelopes.
        local decayRate = 10
        self.collisionEnv = math.max(0, self.collisionEnv - decayRate * dt)
        self.explosionEnv = math.max(0, self.explosionEnv - decayRate * dt)

        -- Update ship position with wrapping.
        self.ship.x = self.ship.x + self.ship.vx * dt
        self.ship.y = self.ship.y + self.ship.vy * dt
        if self.ship.x < 0 then self.ship.x = self.ship.x + 256 end
        if self.ship.x > 256 then self.ship.x = self.ship.x - 256 end
        if self.ship.y < 0 then self.ship.y = self.ship.y + 64 end
        if self.ship.y > 64 then self.ship.y = self.ship.y - 64 end

        -- Update asteroids.
        for _, ast in ipairs(self.asteroids) do
            ast.x = ast.x + ast.vx * dt
            ast.y = ast.y + ast.vy * dt
            if ast.x < 0 then ast.x = ast.x + 256 end
            if ast.x > 256 then ast.x = ast.x - 256 end
            if ast.y < 0 then ast.y = ast.y + 64 end
            if ast.y > 64 then ast.y = ast.y - 64 end
        end

        -- Update bullets.
        for i = #self.bullets, 1, -1 do
            local bullet = self.bullets[i]
            bullet.x = bullet.x + bullet.vx * dt
            bullet.y = bullet.y + bullet.vy * dt
            bullet.lifetime = bullet.lifetime - dt
            if bullet.lifetime <= 0 or bullet.x < 0 or bullet.x > 256 or
                bullet.y < 0 or bullet.y > 64 then
                table.remove(self.bullets, i)
            end
        end

        -- Check bullet-to-asteroid collisions.
        for i = #self.bullets, 1, -1 do
            local bullet = self.bullets[i]
            for j = #self.asteroids, 1, -1 do
                local ast = self.asteroids[j]
                local dx = bullet.x - ast.x
                local dy = bullet.y - ast.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < ast.radius then
                    self.explosionEnv = 5
                    table.remove(self.bullets, i)
                    local hitAst = table.remove(self.asteroids, j)
                    if hitAst.radius > 6 then
                        local newRadius = hitAst.radius * 0.6
                        for k = 1, 2 do
                            local randomAngle = math.random() * 2 * math.pi
                            local randomSpeed = 20 + math.random() * 30
                            table.insert(self.asteroids, {
                                x = hitAst.x,
                                y = hitAst.y,
                                vx = randomSpeed * math.cos(randomAngle),
                                vy = randomSpeed * math.sin(randomAngle),
                                radius = newRadius
                            })
                        end
                    end
                    break
                end
            end
        end

        -- Check asteroid-to-asteroid collisions.
        for i = 1, #self.asteroids - 1 do
            for j = i + 1, #self.asteroids do
                local a = self.asteroids[i]
                local b = self.asteroids[j]
                local dx = a.x - b.x
                local dy = a.y - b.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < (a.radius + b.radius) then
                    self.collisionEnv = 5
                    a.vx, b.vx = b.vx, a.vx
                    a.vy, b.vy = b.vy, a.vy
                end
            end
        end

        -- Check ship-to-asteroid collisions (bounce asteroids off the ship).
        local shipCollisionRadius = 8
        for i = 1, #self.asteroids do
            local ast = self.asteroids[i]
            local dx = ast.x - self.ship.x
            local dy = ast.y - self.ship.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < (shipCollisionRadius + ast.radius) then
                self.collisionEnv = 5
                local nx = dx / d
                local ny = dy / d
                local dot = ast.vx * nx + ast.vy * ny
                ast.vx = ast.vx - 2 * dot * nx
                ast.vy = ast.vy - 2 * dot * ny
                local overlap = (shipCollisionRadius + ast.radius) - d
                ast.x = ast.x + nx * overlap
                ast.y = ast.y + ny * overlap
            end
        end

        -- Check if all asteroids have been destroyed.
        if #self.asteroids == 0 and self.winEnv == 0 then self.winEnv = 5 end
        if self.winEnv > 0 then
            local winDecay = 10
            self.winEnv = math.max(0, self.winEnv - winDecay * dt)
            if self.winEnv == 0 then self:resetGame() end
        end

        -- Compute proximity voltage (ship to nearest asteroid).
        local minDist = 1e6
        for _, ast in ipairs(self.asteroids) do
            local dx = ast.x - self.ship.x
            local dy = ast.y - self.ship.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < minDist then minDist = d end
        end
        local threshold = 50
        local proximity = 0
        if minDist < threshold then
            proximity = (1 - (minDist / threshold)) * 5
        end

        local gunOut = (self.gunTriggerTimer > 0) and 5 or 0
        local thrusterOut = self.thrusterEnvelope
        return {
            gunOut, thrusterOut, self.collisionEnv, self.explosionEnv,
            proximity, self.winEnv
        }
    end,

    -- Use the gate() function to handle the kGate input for thruster control.
    gate = function(self, input, rising)
        if input == 2 then self.thrusterActive = rising end
        return {}
    end,

    fireGun = function(self)
        self.gunTriggerTimer = 0.05 -- 50 ms pulse.
        local angleRad = math.rad(self.ship.angle - 90)
        local bulletSpeed = 100 -- pixels/s.
        local bullet = {
            x = self.ship.x,
            y = self.ship.y,
            vx = math.cos(angleRad) * bulletSpeed,
            vy = math.sin(angleRad) * bulletSpeed,
            lifetime = 1.0
        }
        table.insert(self.bullets, bullet)
    end,

    fireThruster = function(self)
        local angleRad = math.rad(self.ship.angle - 90)
        local impulse = 50
        self.ship.vx = self.ship.vx + math.cos(angleRad) * impulse
        self.ship.vy = self.ship.vy + math.sin(angleRad) * impulse
        self.thrusterEffectTimer = 0.1
        self.thrusterEnvelope = 5
    end,

    -- Use encoder1Push to fire the thruster impulse.
    encoder2Push = function(self) self:fireGun() end,

    encoder2Turn = function(self, value)
        self.ship.encoder_offset = self.ship.encoder_offset + (value * 10 - 5)
    end,

    pot3Push = function(self) self:fireThruster() end,

    -- Helper: Draw the ship (with wrapping) and thruster flame.
    drawShip = function(self, sx, sy)
        local shipSize = 8
        local angleRad = math.rad(self.ship.angle - 90)
        local function getCoords(offsetX, offsetY)
            local cx = sx + offsetX
            local cy = sy + offsetY
            local x1 = cx + math.cos(angleRad) * shipSize
            local y1 = cy + math.sin(angleRad) * shipSize
            local x2 = cx + math.cos(angleRad + 2.5) * shipSize
            local y2 = cy + math.sin(angleRad + 2.5) * shipSize
            local x3 = cx + math.cos(angleRad - 2.5) * shipSize
            local y3 = cy + math.sin(angleRad - 2.5) * shipSize
            return x1, y1, x2, y2, x3, y3
        end
        local offsets = {{0, 0}}
        if sx < shipSize then table.insert(offsets, {256, 0}) end
        if sx > 256 - shipSize then table.insert(offsets, {-256, 0}) end
        if sy < shipSize then table.insert(offsets, {0, 64}) end
        if sy > 64 - shipSize then table.insert(offsets, {0, -64}) end
        if sx < shipSize and sy < shipSize then
            table.insert(offsets, {256, 64})
        end
        if sx < shipSize and sy > 64 - shipSize then
            table.insert(offsets, {256, -64})
        end
        if sx > 256 - shipSize and sy < shipSize then
            table.insert(offsets, {-256, 64})
        end
        if sx > 256 - shipSize and sy > 64 - shipSize then
            table.insert(offsets, {-256, -64})
        end

        for _, off in ipairs(offsets) do
            local ox, oy = off[1], off[2]
            local x1, y1, x2, y2, x3, y3 = getCoords(ox, oy)
            drawLine(x1, y1, x2, y2, 15)
            drawLine(x2, y2, x3, y3, 15)
            drawLine(x3, y3, x1, y1, 15)
            if self.thrusterEffectTimer and self.thrusterEffectTimer > 0 then
                local midX = (x2 + x3) / 2
                local midY = (y2 + y3) / 2
                local flameAngle = math.rad(self.ship.angle + 90)
                local maxFlameLength = 6
                local flameLength = maxFlameLength *
                                        (self.thrusterEffectTimer / 0.1)
                local endX = midX + math.cos(flameAngle) * flameLength
                local endY = midY + math.sin(flameAngle) * flameLength
                drawLine(midX, midY, endX, endY, 15)
            end
        end
    end,

    -- Helper: Draw a bullet as a small circle.
    drawBullet = function(self, x, y)
        local r = 2
        local steps = 8
        local angleStep = (2 * math.pi) / steps
        local prevX = x + math.cos(0) * r
        local prevY = y + math.sin(0) * r
        for i = 1, steps do
            local a = i * angleStep
            local newX = x + math.cos(a) * r
            local newY = y + math.sin(a) * r
            drawLine(prevX, prevY, newX, newY, 15)
            prevX = newX
            prevY = newY
        end
    end,

    draw = function(self)
        self:drawShip(self.ship.x, self.ship.y)
        for _, ast in ipairs(self.asteroids) do
            local steps = 8
            local angleStep = (2 * math.pi) / steps
            local prevX = ast.x + math.cos(0) * ast.radius
            local prevY = ast.y + math.sin(0) * ast.radius
            for i = 1, steps do
                local a = i * angleStep
                local x = ast.x + math.cos(a) * ast.radius
                local y = ast.y + math.sin(a) * ast.radius
                drawLine(prevX, prevY, x, y, 10)
                prevX, prevY = x, y
            end
            local x = ast.x + math.cos(0) * ast.radius
            local y = ast.y + math.sin(0) * ast.radius
            drawLine(prevX, prevY, x, y, 10)
        end
        for _, bullet in ipairs(self.bullets) do
            self:drawBullet(bullet.x, bullet.y)
        end
        return true
    end,

    ui = function(self) return true end
}
