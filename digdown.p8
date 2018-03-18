pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
-- vector metatable
vector = {}
vector.__index = vector
function vector.__add(v1, v2)
    return vector(v1.x + v2.x, v1.y + v2.y)
end
function vector.__sub(v1, v2)
    return vector(v1.x - v2.x, v1.y - v2.y)
end
function vector.__mul(v1, v2)
    if type(v1) == "number" then
        return vector(v1 * v2.x, v1 * v2.y)
    elseif type(v1) == "table" and type(v2) == "table" then
        return vector(v1.x * v2.x, v1.y * v2.y)
    elseif type(v2) == "number" then
        return vector(v1.x * v2, v1.y * v2)
    end
end
function vector.__unm(v)
    return vector(-v.x, -v.y)
end
function vector.__eq(v1, v2)
    return v1.x == v2.x and v1.y == v2.y
end
function vector:tostr()
    return "{ x = " .. self.x .. ", y = " .. self.y .. " }" 
end
function vector.floor(v)
    return vector(flr(v.x), flr(v.y))
end
function vector:linearize()
    return self.y * 128 + self.x
end
function vector:offset(v)
    self.x += v.x
    self.y += v.y
end
function vector.lerp(v1, v2, t)
    return v1 + (v2 - v1) * t
end
function vector:sgn()
    local v = vector(0, 0)
    if self.x == 0 then v.x = 0
    elseif self.x > 0 then v.x = 1
    else v.x = -1 end
    if self.y == 0 then v.y = 0
    elseif self.y > 0 then v.y = 1
    else v.y = -1 end
    return v
end
function vector:dist(other)
    local d = other - self
    return sqrt(d.x * d.x + d.y * d.y)
end
function vector:clone()
    return vector(self.x, self.y)
end
function vector:tileized()
    return vector(flr(self.x / 8) * 8, flr(self.y / 8) * 8)
end
function vector.new(x, y)
    return setmetatable({ x = x, y = y }, vector)
end
setmetatable(vector, { __call = function(_, ...) return vector.new(...) end })
-- util
function rndr(t) -- range
    return rnd(t[2] - t[1]) + t[1]
end
function rndi(from, to) -- integer
    return flr(rnd(to - from) + from)
end
function rndt(from, to) -- tile
    return tileize(rnd(to - from) + from)
end
function rnde(t) -- element in indexed table
    return t[rndi(1, #t + 1)]
end
function tileize(p)
    return flr(p / 8) * 8
end
function addif(t, v, f)
    if f(v) then add(t, v) end
end
function anyin(v, t)
    return 
end
-- constants
sprites = 
{
    player = 
    { 
        walk = { 1, 2, 3, 4 },
        death = { 5, 6 },
        dig = { 7, 8, 9, 10 }
    },
    dirt =
    {
        base = 16,
        muddy = { 17, 18 },
        decorations = { 20, 21, 23, 36, 37 },
    },
    rock = { 19, 62 },
    worm = 
    {
        head = { 48, 49 },
        body = 50,
        tail = 51
    },
    beetle = { 52, 53 },
    water = 60,
    seed = 22,
    tunnel = 
    {
        vertical = 32,
        horizontal = 34,
        corner = 33,
        junction = 11
    }
}
dt = 1.0 / 60
-- decoration settings
decorations = true
rock_count = { 1, 5 }
-- plant settings
seed_count = { 0, 0 } -- { 1, 4 }
seed_min_depth = 64
-- worm settings
worm_spawn_delay = { 3, 6 }
worm_mouth_speed = 0.2
worm_length = { 2, 10 }
worm_speed = { 30, 60 }
worm_spawn_height = { 24, 128 }
-- beetle settings
beetle_spawn_delay = { 3, 6 }
beetle_speed = { 10, 15 }
beetle_spawn_height = { 16, 128 }
beetle_anim_speed = 0.25
beetle_max_count = 10

function _init()
    -- registries
    holes = {}
    worms = {}
    beetles = {} 
    seeds = {}
    player = 
    {
        pos = vector(0, 8),
        origin = vector(0, 8),
        dest = vector(0, 8),
        move_progress = 0,
        sprite = sprites.player.walk[1],
        flip_x = false,
        anim_frame = 0
    }
    water_particles = {}
    skull = {}
    rocks = {}
    -- support
    water_buffer = {}
    water_draw_buffer = {}
    draw_counter = 0
    until_worm_spawn = 0
    until_beetle_spawn = 0
    -- transparency colors
    palt(0, false)
    palt(10, true)
    -- look for water tiles
    for i = 0, 16 do
    for j = 16, 0, -1 do
        if mget(i, j) == sprites.dirt.base and rnd() < 0.3 then
            mset(i, j, rnde(sprites.dirt.muddy))
        elseif mget(i, j) == sprites.water then
            for ti = 0, 8 do
            for tj = 8, 0, -1 do
                local particle = 
                { 
                    cell = vector(i * 8 + ti, j * 8 + tj):linearize(),
                    dir = 0
                }
                add(water_particles, particle)
                water_buffer[particle.cell] = true
            end
            end
            -- clear them
            mset(i, j, 0)
        end
    end
    end
    -- init timers
    until_worm_spawn = rndr(worm_spawn_delay)
    until_beetle_spawn = rndr(beetle_spawn_delay)
    -- seeds
    for i = 1, rndr(seed_count) do
        local seed = 
        {
            pos = vector(rndt(0, 128), rndt(seed_min_depth, 128))
        }
        seeds[seed.pos:linearize()] = seed
    end
    -- decorations
    if decorations then
        for d in all(sprites.dirt.decorations) do
            local tile = vector(rndi(0, 16), rndi(4, 16))
            mset(tile.x, tile.y, d)
        end
    end
    -- rocks
    for i = 1, rndr(rock_count) do
        local rock = 
        {
            sprite = rnde(sprites.rock),
            pos = vector(rndt(0, 128), rndt(seed_min_depth, 128)),
            flip_x = rnd(1) < 0.5,
            flip_y = rnd(1) < 0.5
        }
        rocks[rock.pos:linearize()] = rock
    end
    -- play song
    music(1)
end

function _update60()
    update_player()
    -- water
    if draw_counter > 0 then
        update_water()
    end
    -- enemies
    update_worms()
    update_beetles()
end

function update_player()
    if player.dead then
        -- todo: screenshake
        player.anim_frame += dt * 10
        player.sprite = sprites.player.death[flr(player.anim_frame % 2) + 1]
        player.pos += player.vel
        player.vel += vector(0, dt * 3)
        if player.pos.y > 512 then
            -- todo: palette fade? like with a coroutine?
            reload()
            _init()
        end
    else
        -- inputs
        local dig_pos = nil
        local direction = nil
        if btnp(⬅️) then
            dig_pos = player.origin - vector(8, 0)
            direction = vector(-1, 0)
        elseif btnp(➡️) then
            dig_pos = player.origin + vector(8, 0)
            direction = vector(1, 0)
        elseif btnp(⬆️) and not is_surface(player.origin) then
            dig_pos = player.origin - vector(0, 8)
            direction = vector(0, -1)
        elseif btnp(⬇️) then
            dig_pos = player.origin + vector(0, 8)
            direction = vector(0, 1)
        end
        -- obstacles
        if dig_pos != nil then
            if rocks[dig_pos:linearize()] != nil then dig_pos = nil end
        end
        -- digging & player locomotion
        if dig_pos != nil and player.move_progress == 0 then
            player.digging = dig(dig_pos, direction)
            if not player.digging then
                sfx(3)
            end
            player.dest = player.origin + direction * 8
            player.flip_x = direction.x == -1
        end
        -- animation
        if player.dest != player.pos then
            player.pos = vector.lerp(player.origin, player.dest, player.move_progress)
            local animation = player.digging and sprites.player.dig or sprites.player.walk 
            player.sprite = animation[flr(player.move_progress * 4) + 1]
            local speed = player.digging and 0.4 or 0.7
            player.move_progress = min(player.move_progress + speed / 8, 1)
            if player.move_progress == 1 then
                player.pos = player.dest
                player.origin = player.pos
                player.sprite = sprites.player.walk[1]
                player.move_progress = 0
            end
        end
    end
end

function kill_player()
    if player.dead then return end
    player.dead = true  
    player.vel = vector(0, -1.25)
    music(-1)
    sfx(-1)
    sfx(4)
    sfx(14)
end

function update_worms()
    -- spawning
    until_worm_spawn -= dt
    if until_worm_spawn <= 0 then
        until_worm_spawn = rndr(worm_spawn_delay)
        local dir = rnd() < 0.5 and 1 or -1
        local screenedge = dir == 1 and -8 or 128
        local worm = 
        {
            pos = vector(screenedge, rndt(worm_spawn_height[1], worm_spawn_height[2])),
            dir = dir,
            speed = rndr(worm_speed),
            length = rndi(worm_length[1], worm_length[2]),
            mouth_anim = 0,
            type = rndi(0, 2) -- type 1 undigs!
        }
        add(worms, worm)
        sfx(10)
    end
    -- logic
    local player_tile = player.pos:tileized()
    for worm in all(worms) do
        worm.pos.x += worm.speed * worm.dir * dt
        if (worm.dir == 1 and worm.pos.x - worm.dir * 8 * worm.length > 128) or
           (worm.dir == -1 and worm.pos.x - worm.dir * 8 * worm.length < 0) then
            del(worms, worm)
        else
            local dig_pos = worm.pos:tileized()
            if worm.dir == -1 then dig_pos.x += 8 end
            if rocks[dig_pos:linearize()] == nil then
                if worm.type == 0 then
                    dig(dig_pos, vector(worm.dir, 0))
                else 
                    undig(dig_pos)
                end
            end
            worm.mouth_anim = (worm.mouth_anim + dt * worm_mouth_speed * worm.speed) % 2
        end
        -- player hurt
        local worm_tile = worm.pos:tileized()
        if worm_tile == player_tile or
           worm_tile + vector(8, 0) == player_tile then
            kill_player()
        end
    end
end

function update_beetles()
    -- spawning
    until_beetle_spawn -= dt
    if until_beetle_spawn <= 0 and #beetles < beetle_max_count then
        until_beetle_spawn = rndr(beetle_spawn_delay)
        -- try to find an edge tunnel
        local edge_tiles = {}
        for i = 8, 128, 8 do
            local hole = hole_at(vector(0, i))
            if hole != nil and hole.dir.x != 0 then add(edge_tiles, hole) end
            hole = hole_at(vector(120, i))
            if hole != nil and hole.dir.x != 0 then add(edge_tiles, hole) end
        end
        -- pick a random one
        if #edge_tiles > 0 then
            local hole = edge_tiles[rndi(1, #edge_tiles + 1)]
            local dir = vector(hole.pos.x == 0 and 1 or -1, 0)
            local beetle = 
            {
                pos = hole.pos - dir * 8,
                dir = dir,
                origin = hole.pos - dir * 8,
                dest = hole.pos,
                speed = rndr(beetle_speed),
                anim_frame = 0,
                move_progress = 0
            }
            add(beetles, beetle)
            sfx(1)
        end
    end
    -- logic
    local player_tile = player.pos:tileized()
    for beetle in all(beetles) do
        if beetle.dest != beetle.pos then
            -- advance towards dest 
            beetle.pos = vector.lerp(beetle.origin, beetle.dest, beetle.move_progress)
            beetle.move_progress = min(beetle.move_progress + beetle.speed / 8 * dt, 1) 
            beetle.anim_frame = (beetle.anim_frame + dt * beetle_anim_speed * beetle.speed) % 2
            if beetle.move_progress == 1 then
                beetle.pos = beetle.dest
                beetle.origin = beetle.pos
                beetle.move_progress = 0
            end   
        else
            -- find a new dest
            local lookahead_tile = beetle.pos + beetle.dir * 8
            local last_origin = beetle.pos - beetle.dir * 8
            if lookahead_tile.x >= 0 and lookahead_tile.x < 128 and
               hole_at(lookahead_tile) == nil then
                -- look for nearby holes
                local neighbors = {}
                local neighbor_tiles = 
                {
                    vector(0, 8), vector(0, -8),
                    vector(8, 0), vector(-8, 0)
                }
                for nt in all(neighbor_tiles) do
                    addif(neighbors, hole_at(beetle.pos + nt), 
                          function(h) return (h != nil and h.pos != last_origin) end)
                end
                -- pick a random one
                if #neighbors > 0 then
                    local neighbor = neighbors[rndi(1, #neighbors + 1)]
                    beetle.dir = (neighbor.pos - beetle.pos):sgn()
                else
                    -- turn around
                    beetle.dir = -beetle.dir
                end
            end
            beetle.dest = beetle.pos + beetle.dir * 8
        end
        -- screen overflow
        if (beetle.dir.x == 1 and beetle.pos.x > 128) or 
           (beetle.dir.x == -1 and beetle.pos.x < -8) then
            del(beetles, beetle)
        end
        -- player hurt
        local beetle_tile = beetle.pos:tileized()
        if beetle_tile == player_tile or
           beetle_tile + vector(8, 0) == player_tile then
            kill_player()
        end
    end
end

function update_water()
    for i = 1, #water_particles do
        -- update particle
        local particle = water_particles[i]
        if is_watersafe(particle.cell + 128) then
            offset_water_particle(particle, 128)
        else
            if particle.dir != 0 then
                if is_watersafe(particle.cell + particle.dir) then
                    offset_water_particle(particle, particle.dir)
                else
                    particle.dir = -particle.dir
                end
            else
                particle.dir = flr(rnd(3)) - 1
            end
        end
        -- commit to draw buffer
        local buffer_entry =  { particle.cell % 128, particle.cell / 128 }
        water_draw_buffer[i] = buffer_entry
    end
end

function offset_water_particle(p, o)
    water_buffer[p.cell] = false
    p.cell += o
    water_buffer[p.cell] = true
end

function is_watersafe(cell)
    if water_buffer[cell] == true then return false end
    local color = pget(cell % 128, cell / 128) -- todo: peek?
    return color == 0 or color == 12
end

function dig(pos, dir)
    if is_surface(pos) then return false end
    local has_dug = false
    local hole = hole_at(pos)
    if hole == nil then 
        hole = 
        {
            pos = pos,
            dir = dir,
            type = dir.x == 0 and "v" or "h",
            sprite = dir.x == 0 and 
                sprites.tunnel.vertical or
                sprites.tunnel.horizontal 
        }
        holes[pos:linearize()] = hole
        has_dug = true 
        sfx(12)
    end
    -- junction detection
    detect_junctions(hole)
    detect_junctions(hole_at(hole.pos + vector(0, 8)))
    detect_junctions(hole_at(hole.pos + vector(0, -8)))
    detect_junctions(hole_at(hole.pos + vector(8, 0)))
    detect_junctions(hole_at(hole.pos + vector(-8, 0)))
    -- corner detection
    local corner_hole, ct = corner_type(hole)
    if corner_hole != nil then
        corner_hole.type = "c"
        corner_hole.sprite = sprites.tunnel.corner
        corner_hole.flip_x = ct == "ne" or ct == "se"
        corner_hole.flip_y = ct == "sw" or ct == "se"
    end
    return has_dug
end

function undig(pos)
    local hole = hole_at(pos)
    if hole != nil then
        holes[pos:linearize()] = nil
    end
    if mget(pos.x / 8, pos.y / 8) == sprites.dirt.base then
        mset(pos.x / 8, pos.y / 8, rnde(sprites.dirt.muddy))
    end
end

function detect_junctions(hole)
    if hole == nil then return end
    if hole.type == "j" then return end
    local junctions = 0
    if hole_at(hole.pos + vector(0, 8)) then junctions += 1 end
    if hole_at(hole.pos + vector(0, -8)) then junctions += 1 end
    if hole_at(hole.pos + vector(8, 0)) then junctions += 1 end
    if junctions < 3 and hole_at(hole.pos + vector(-8, 0)) then junctions += 1 end
    if junctions >= 3 then
        hole.type = "j"
        hole.sprite = sprites.tunnel.junction
    end
end

function is_surface(pos)
    return pos.y <= 8
end

function hole_at(pos)
    return holes[pos:linearize()]
end

function corner_type(cur_hole)
    local last_hole = hole_at(cur_hole.pos - cur_hole.dir * 8)
    if last_hole == nil then return nil end
    if last_hole.type == "j" then return nil end

    if (last_hole.dir.x > 0) and (cur_hole.dir.y > 0) then
        return last_hole, "ne"
    elseif (last_hole.dir.x > 0) and (cur_hole.dir.y < 0) then
        return last_hole, "se"
    elseif (last_hole.dir.x < 0) and (cur_hole.dir.y > 0) then
        return last_hole, "nw"
    elseif (last_hole.dir.x < 0) and (cur_hole.dir.y < 0) then
        return last_hole, "sw"

    elseif (last_hole.dir.y > 0) and (cur_hole.dir.x < 0) then
        return last_hole, "se"
    elseif (last_hole.dir.y > 0) and (cur_hole.dir.x > 0) then
        return last_hole, "sw"
    elseif (last_hole.dir.y < 0) and (cur_hole.dir.x < 0) then
        return last_hole, "ne"
    elseif (last_hole.dir.y < 0) and (cur_hole.dir.x > 0) then
        return last_hole, "nw"

    else return nil end
end

function _draw()
    cls()
    -- background
    map(0, 0, 0, 0, 16, 16)
    -- logo
    sspr(0, 32, 54, 40, 128 - 54, 0)
    -- tunnels
    draw_tunnels()
    -- water
    for p in all(water_draw_buffer) do
        pset(p[1], p[2], 12) -- todo: poke?
    end
    -- entities
    spr(player.sprite, player.pos.x, player.pos.y, 1, 1, player.flip_x)
    draw_worms()
    draw_beetles()
    draw_rocks()
    --sspr(sprites.snake * 8, 0, 16, 8, 0, 0, 16, 8, false, false)
    draw_counter += 1
end

function draw_tunnels()
    for _, h in pairs(holes) do
        spr(h.sprite, h.pos.x, h.pos.y, 1, 1, h.flip_x, h.flip_y)
        if h.pos.y <= 8 and (h.type == "v" or (h.type == "c" and h.flip_y)) then 
            rectfill(h.pos.x + 1, 0, h.pos.x + 6, 7, 0) 
        end
    end
end

function draw_rocks()
    for _, rock in pairs(rocks) do
        spr(rock.sprite, rock.pos.x, rock.pos.y, 1, 1, rock.flip_x, rock.flip_y)
    end
end

function draw_worms()
    for worm in all(worms) do
        if worm.type == 1 then
            pal(14, 3)
            pal(8, 1)
        end
        -- head
        local sprite = sprites.worm.head[flr(worm.mouth_anim) + 1]
        spr(sprite, worm.pos.x, worm.pos.y, 1, 1, worm.dir == 1, false)
        -- body
        for i = 1, worm.length - 1 do
            spr(sprites.worm.body, worm.pos.x - worm.dir * 8 * i, worm.pos.y)
        end
        -- tail
        spr(sprites.worm.tail, worm.pos.x - worm.dir * 8 * worm.length,
            worm.pos.y, 1, 1, worm.dir == 1, false)
        if worm.type == 1 then
            pal(14, 14)
            pal(8, 8)
        end
    end
end

function draw_beetles()
    for beetle in all(beetles) do
        local sprite = sprites.beetle[flr(beetle.anim_frame) + 1]
        -- todo: sprite rotation
        spr(sprite, beetle.pos.x, beetle.pos.y, 1, 1, beetle.dir.x == 1, false)
    end
end

__gfx__
aaaaaaaaaaa997aaaaa977aaaaa997aaaaa999aaaa9999aaaa9779aaaaaaaaaaaaa997aaaaa997aaaaa997aa00000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaa4444aaaa4444aaaa4444aaaa4444aaa999999aaa4774aaaaa977aaaa4444aaaa4444aaaa4444aa00000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aa7aa7aaa999999aa999999aa999999aa999999aaffeeffaf999999faa4444aaa999999aa999999aa999999a00000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaa77aaaaaf4ffeaaa4ffeeaaaf4ffeaaaff4feaacfeefcacafeefaca999999aaaf4ffeaaaf4ffeaaaf4ffea00000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaa77aaaaaccffaaaacfffaaaaccffaaaacccfaaadc00cdaadcffcdaaa4ffeeaaaccffaaaaccffaaaaccffaa00000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aa7aa7aaaadcc7aaaadc77aaaadcc7aaaacdccaaaac77caaaac77caaaacfffaaaadcd7aaaadcc74daacdcf4d00000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaadcdcaaaacdccaaaadcdcaaaacdcdaaaccddccaaacddcaaacdcccaaaacdcdaaaacd4f4daa444caa00000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaa44f44da44f44daaa44f44daaa44f44dadaaaadaaadaadaa4f44ddaaa4444f44aad4444daaddddaa00000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
444444444444444444454444a6d666da4444444444977944a444444a44454454aaa33aa3aaa33aaaaaaaaaaaa9a99a9aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
4444444444554444444444546d6666dd44544444499999944455554445544444aaa3ba3aaaab3aaaaaaffaaaaa9449aaaaa87aaaaaaaaaaaaaaaaaaaaaaaaaaa
4444444444554444554444446d66666d44444f44440ff0444503305440f54f54aaaa3b3aaab33aaaaafeefaaa944449aaa7888aaaaaaaaaaaaaaaaaaaaaaaaaa
444444444444444455444444dd66666d44444ff4f4ffff4f4533b3545ffffff5aaaa33aa3333abb3aafeefaaa944449aaa8878aaaaaaaaaaaaaaaaaaaaaaaaaa
444444444444445444445444d6d66ddd4444f4444ff44ff4453333540f0ff0f5aaaa33aa3b333333a3affa3aa394493aa3affa3aaaaaaaaaaaaaaaaaaaaaaaaa
444444444444444444444444ddddd66d44ff4455444ff4444503305400ffff05aaaa3baaaab33baaaa333baaa9399b9aaa333baaaaaaaaaaaaaaaaaaaaaaaaaa
444444444544444445444554dd66d66d544f445544f44f444455554445445554aaa3baaaaaa3baaaaaa3baaaaaa3baaaaaa3baaaaaaaaaaaaaaaaaaaaaaaaaaa
444444444444444444444554adddddda4444444444f44f44a444444a44454444aaa33aaaaaa33aaaaaa33aaaaaa33aaaaaa33aaaaaaaaaaaaaaaaaaaaaaaaaaa
0000000444004400440044004400440044444444444444444444444445555444aaa33aaaaaaaaaaaa822228aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
0000000044000000000000000000000054599954444444544554455ffffff954aaab3aaaaaaaaaaaaa8882aaaaa99aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
40000000400000000000000000000000459400955445544445545fffff9fff94aab3aaaaaaa3aaaaaa8228aaaa9ff9aaaaa7a7aa777aa77aa77aa77aaaaaaaaa
4000000440000000000000000000000009404454455005444444ff99fffffff9aa33aaaa333aabb3aa2888aaaa9ff9aaaaa777aa77a7aaaa77aaa77aaaaaaaaa
000000040000000000000000000000000499900550988054444ff9009ff99f99aa33aa3a3b333333a3a88a3aa3a99a3aaaa777aa77a7a77a77a7aaaaaaaaaaaa
000000000000000000000000000000004044999559888054444ff9009f955999aa3ba3aaaab33baaaa333baaaa333baaaaaa7aaa777aa77aa77aa77aaaaaaaaa
400000004000000000000000000000004550445450888054445fff99ff5ff554aa33b3aaaaa3baaaaaa3baaaaaa3baaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
40000004400000000000000005000550544555444555554445ff999f94f9f994aaa33aaaaaa33aaaaaa33aaaaaa33aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa4ffff9f5f4ff9994aaa33aaaaaaaaaaaaaaa3aaaaaaaaaaaccccccccbb33bb33addd66da55555555
ee77e8eeae77e8eee8eee8eee8eee8eaa335bb3aaa55bb3a4fffff944ff99944aaab3aaaaaaaaaaaaaa3baaaaaaccaaacccccccc33bb33bbdd66d66d55555555
e7007e77e7007e777e777e777e777eee30335553a3355553ff99f5f4fff99444aaaab3aaaaa3aaaaaa33b3aaaac77caacccccccc55335533d666d66d44444444
e7007e77e7007e777e777e777e777eee30335bb530335bb5ff49f44fff994444aaaa33aaaaa3abb3aa3b33aaaac77caacccccccc55555555d666d6dd44444444
7e77eeeeee77eeeeeeeeeeeeeeeeeeee33335333303353339fff5f9ff9554544aaaa33aaaaaa3333a3a33a3aa3acca3acccccccc44444444d6666d6d44444444
aaaee8eeeeeee8eee8eee8eee8eee8ee7a75333333353333599954ff44444444aaaa3baaaaa33baaaa333baaaa333baacccccccc44444444dd66d66d44444444
a7eee8eeaeeee8eee8eee8eee8eee8eaaa5353537a7353534455444444444444aaa3baaaaaa3baaaaaa3baaaaaa3baaacccccccc44444444ddddd6dd44444444
aeeaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa5a5a5aaa5a5a54455444445444444aaa33aaaaaa33aaaaaa33aaaaaa33aaacccccccc44444444adddddda44444444
a77777aaa77aa7777aaaaa77777aaaa777aaaa77aaaa73a77a777aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
a37c737a777a777777aaaa77777caa77777ea777a7a337a7779737aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
37773333aaaa777a77aeaa777333a777a373377737a777a3333377aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
3773a7ea377a77aaa333aa773a373777a337a777733c7737377733aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
a77aa77a7c7a77a777aa3377aa77a7773777a777977377a77e77e73aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
a777777a7773773377a3aa777777377779773377777777a777a7773aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
a7777733777a777797aaaa777773aa77777aa7337a777aa7773777aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
a7777aaa777aa7777aaaaa7777aaaaa777aaaa77aa77aaaa77a77aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
__map__
0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3c0b3c0b3c0b3c0b3c0b3c0b3c0b3c0b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1010101010101010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1010101010101010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1010101010101010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1010101010101010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1010101010101010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1010101010101010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1010101010101010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1010101010101010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1010101010101010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1010101010101010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1010101010101010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1010101010101010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1010101010101010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1010101010101010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
010101010004022040220502a060030501a0500005000050000500005000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010200001a5501b5501c5501d5501e5501f550095500a5500c5500b5501a55019550185501555012550115500f0500c0500a5501d550205502555028550295500000000000000000000000000000000000000000
010200002455022550205401e5301c5301a5301853016530145402254022540195501e55023560185601e560235601d5602156014560185501c5400b5300f530145200f5300e5300755018550185502055032550
000300000f0500e050150501205017500185001750017500175001750017500165001650012500125001650013500195001b500135001e5001350013500145001750014500135001350013500135001550016500
0002000000000260502605027050280502a0502c0502c0502b0502705024050000001f05000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01100000350523105232052330523d0520000233052330523005230052340523505200002310020000200002350523105232052330523d0520000233052330523005230052340523505200002000020000200002
01100000000022105222052230521f0521f0521e0521c05219052000021c052190521c0521f052180021800217002150021300214002170021900200002000020000200002000020000200002000020000200002
001000002505025050250502505025050000002a0502a0502b0502505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000200001f0501f0502105022050280502a0500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0105000029056290562b0562d0562e05630056340563b0563a006330063b006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006
00100000150531405313053110530e0530e0530b0530a053080530000308003080030b0030c003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300003
0105000029050290502b0502d0502e05030050340503b050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000100002705023050220501b0501a050130500e050080500705005050050500e0500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101000022600161501615010150141502015015150171501715017150181500d150171501a150121501b150131501a1501a1501d1501e150111501d1501c1501c1501a150151501315014150141500000000000
01100000291522a1522c1520000230152000022915229152291522815229152291522a1022a1021110229102291022b1022c1022b102311022910229102291022810229102291021110211102111021110211102
010300001b1511c1511c1511d15120151000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000100001b1501a1501a15019150191501a1502b1502f150311500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00100000170500100017050000001705001000170501700017050170001e050000001e050000001e0500200014050140001405014000140501300014050140001c050130001b0501700019050000001705000000
001000000050000500273202742001500005002732027420005000050027320274200050000500273202742000500273002a3202a420005002a3002a3202a42000500233001c3201c42000500073001c3201c420
001000001b7501b7501b7501e7501e7501e7501e7501e75020750207501e7501e7501e750197501775017750197501975014750147501475014750147501475014750147501c7501c7501c7501c7501c7501c750
001000002353019500225300050020530005001e5300050020530005001e530005001b530005001e530005002353000500225300050020530005001e530005001c5301d5001e530005001c530005001b53000500
00100000170501705027700237001705017050237002370017050170502a7002c70017050170502c7002c70012050120502870028700120501205028700277001005010050257002570010050100502570025700
001000000f0500000012050000001705000000000000000000000000001005011000120500300019050000000f0500f0001205017000170500000000000000000000003000100500000012050000001905000000
0010000027320000000000000000233200130002300000002832020300000000000023320000000000000000273201d3000000000000233200000000000000002a32000000000000000027320000000000000000
__music__
01 11404040
00 11404040
00 11124040
00 11125340
00 11521340
00 11451340
00 14154040
00 14154040
00 16574040
00 16174040
02 16174040
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 40404040
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 40404040
00 40404040
00 40404040
00 40404040
00 40404040
00 40404040
00 40404040
00 41404040
00 40404040
