---------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------
local DEBUG_MODE = false
local dbg_enemy_last = {
  level = nil,
  count = nil,
  status = nil,
  key = nil,
}

local function log_info(msg) print("ABL: " ..  msg) end
local function log_debug(msg) if DEBUG_MODE then print("ABL DBG: " .. msg) end end
local function log_error(msg) print("ABL ERROR: " .. msg) end

---------------------------------------------------------------------
-- Variables
---------------------------------------------------------------------
local function script_dir()
    local src = debug.getinfo(1, "S").source
    if src:sub(1,1) == "@" then src = src:sub(2) end
    return (src:gsub("\\", "/"):match("^(.*)/") or ".")
end

local localAppData = os.getenv("LOCALAPPDATA") or os.getenv("USERPROFILE")
if not localAppData then
  print("ABL Lua ERROR: LOCALAPPDATA not available")
  return
end

local dataDir = (os.getenv("LOCALAPPDATA") or "") .. "\\A_Bugs_Life_Archipelago\\"

local statePath      = dataDir .. "abl_state.txt"
local commandPath    = dataDir .. "abl_command.txt"
local berryStatePath = dataDir .. "abl_berries.txt"
local seedStatePath  = dataDir .. "abl_seeds.txt"

local read_u8  = memory.read_u8
local read_u16 = memory.read_u16_le
local write_u8 = memory.write_u8
local write_u16 = memory.write_u16_le

local ram_domain       = "MainRAM"

local berry_addr       = 0x0A6597
local lives_addr       = 0x0A65A0
local grain_addr       = 0x0A65A1
local flik_addr        = 0x0A65A2
local health_addr      = 0x0A6594

local seed_upgrade_list_addr = 0x0B0196

local FLIK_STATUS_READY = 0xFF20
local FLIK_STATUS_BUSY = 0x4669
local MAX_GRAIN = 50
local MAX_HEALTH = 4
local MAX_LIVES = 9
local floor = math.floor
local max = math.max
local min = math.min
local insert = table.insert
local fmt = string.format

local brown_seed_addr  = 0x0A6598
local blue_seed_addr   = 0x0A6599
local green_seed_addr  = 0x0A659A
local purple_seed_addr = 0x0A659B
local yellow_seed_addr = 0x0A659C

local enemy_tens_addr  = 0x0B019A
local enemy_units_addr = 0x0B019B

local level_complete_status_addr = 0x0823A0
local level_index_addr = 0x82504
local level_code_addr  = 0x0A64B0
local flik_status_addr = 0x1FFF18

local unlock_all_levels_addr = 0x082284
local demo_mode_addr = 0x0822F8

local LEVEL_NAME = {
  [17] = "Training",
  [1]  = "Ant Hill",
  [3]  = "Tunnels",
  [2]  = "Council Chamber",
  [6]  = "Cliffside",
  [10] = "Riverbed Canyon",
  [11] = "Bird Nest",
  [4]  = "City Entrance",
  [5]  = "City Square",
  [14] = "Bug Bar",
  [7]  = "Clover Forest",
  [12] = "The Tree",
  [13] = "Battle Arena",
  [9]  = "Ant Hill Part 2",
  [8]  = "Riverbed Flight",
  [15] = "Canyon Showdown",
}

local function level_label(idx)
  return fmt("%s (Level %d)", LEVEL_NAME[idx] or "Unknown", idx)
end

local BERRY_TIER_NAME = {
  [0] = "None",
  [1] = "Green",
  [2] = "Blue",
  [3] = "Purple",
  [4] = "Gold",
}

local function berry_label(tier)
  return BERRY_TIER_NAME[tier] or ("Tier " .. tostring(tier))
end

local enemy_thresholds = {
  [17] = { [25] = -1, [50] =  2, [75] = -1, [100] =  4 }, -- Training
  [1]  = { [25] =  5, [50] = 10, [75] = 15, [100] = 21 }, -- Ant Hill
  [3]  = { [25] = 12, [50] = 25, [75] = 37, [100] = 50 }, -- Tunnels
  [2]  = { [25] = -1, [50] =  2, [75] = -1, [100] =  3 }, -- Council Chamber
  [6]  = { [25] =  3, [50] =  6, [75] =  9, [100] = 12 }, -- Cliffside
  [10] = { [25] = 13, [50] = 25, [75] = 38, [100] = 51 }, -- Riverbed Canyon
  [11] = { [25] =  2, [50] =  5, [75] =  7, [100] =  9 }, -- Bird Nest
  [4]  = { [25] =  6, [50] = 13, [75] = 20, [100] = 26 }, -- City Entrance
  [5]  = { [25] =  6, [50] = 12, [75] = 18, [100] = 23 }, -- City Square
  [14] = { [25] = -1, [50] = -1, [75] = -1, [100] =  1 }, -- Bug Bar
  [7]  = { [25] =  6, [50] = 12, [75] = 18, [100] = 24 }, -- Clover Forest
  [12] = { [25] =  8, [50] = 16, [75] = 24, [100] = 32 }, -- The Tree
  [13] = { [25] = -1, [50] =  2, [75] = -1, [100] =  4 }, -- Battle Arena
  [9]  = { [25] =  4, [50] =  8, [75] = 12, [100] = 15 }, -- Ant Hill, Part 2
  [8]  = { [25] = 14, [50] = 28, [75] = 42, [100] = 56 }, -- Riverbed Flight
  [15] = { [25] =  4, [50] =  8, [75] = 12, [100] = 16 }, -- Canyon Showdown
}

local function enemy_need(level_index, pct)
  local t = enemy_thresholds[level_index]
  if not t then return nil end
  local v = t[pct]
  if not v or v < 1 then return nil end
  return v
end

local level_init_done = false
local grainsanity_enabled = false
local grainsanity_step = 10
local grain_all = false

local enemysanity_25 = false
local enemysanity_50 = false
local enemysanity_75 = false
local enemysanity_100 = false
local enemy_observed_max = {}

local flik_individual = false
local flik_all = false

local last_notready_printed_code = nil

local completed_grain_sanity = {}
local completed_enemy_pct = { [25]={}, [50]={}, [75]={}, [100]={} }
local configPath = dataDir .. "abl_config.txt"

---------------------------------------------------------------------
-- Utility
---------------------------------------------------------------------

local function load_config()
    grainsanity_enabled = false
    grainsanity_step = 10
    grain_all = false
    flik_individual = false
    flik_all = false
    enemysanity_25 = false
    enemysanity_50 = false
    enemysanity_75 = false
    enemysanity_100 = false

    local handlers = {
        enable_grain_all = function(v) grain_all = (v == "1") end,
        enable_grainsanity = function(v) grainsanity_enabled = (v == "1") end,
        grainsanity_step = function(v) grainsanity_step = tonumber(v) or 10 end,
        enable_enemy_25 = function(v) enemysanity_25 = (v == "1") end,
        enable_enemy_50 = function(v) enemysanity_50 = (v == "1") end,
        enable_enemy_75 = function(v) enemysanity_75 = (v == "1") end,
        enable_enemy_100 = function(v) enemysanity_100 = (v == "1") end,
        enable_flik_individual = function(v) flik_individual = (v == "1") end,
        enable_flik_all = function(v) flik_all = (v == "1") end,
    }

    local f = io.open(configPath, "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^(%S+)%s*=%s*(%S+)")
        if k and v then
            local h = handlers[k]
            if h then h(v) end
        end
    end
    f:close()
end

local function assertPath(name, p)
  if not p or p == "" then
    error("ABL Lua Error: " .. name .. " is nil/empty")
  end
end

local function append_state(line)
    local f = io.open(statePath, "a")
    if not f then return end
    f:write(line, "\n")
    f:close()
end

local function read_enemy_kills()
    local tens_raw  = read_u8(enemy_tens_addr,  ram_domain)
    local units_raw = read_u8(enemy_units_addr, ram_domain)

    local tens  = tens_raw  & 0x0F
    local units = units_raw & 0x0F

    return tens * 10 + units
end

local function unlock_all_levels()
    local v = read_u8(unlock_all_levels_addr, ram_domain)
    if v == 1 then
        write_u8(unlock_all_levels_addr, 15, ram_domain)
        log_debug("forced unlock all levels (1 -> 15)")
    end
end

---------------------------------------------------------------------
-- Init
---------------------------------------------------------------------
local function init_after_first_frame()
    assertPath("statePath", statePath)
    assertPath("commandPath", commandPath)
    assertPath("berryStatePath", berryStatePath)
    assertPath("seedStatePath", seedStatePath)
    os.execute('mkdir "' .. dataDir .. '" >nul 2>nul')
    load_config()
    log_debug(fmt(
      "config: grainsanity=%s step=%d grain_all=%s enemy25=%s enemy50=%s enemy75=%s enemy100=%s flik_individual=%s flik_all=%s",
      tostring(grainsanity_enabled),
      grainsanity_step,
      tostring(grain_all),
      tostring(enemysanity_25),
      tostring(enemysanity_50),
      tostring(enemysanity_75),
      tostring(enemysanity_100),
      tostring(flik_individual),
      tostring(flik_all)
    ))
    log_info("load successful")
end

log_info("loading script...")
emu.frameadvance()
init_after_first_frame()

---------------------------------------------------------------------
-- Commands from C#
---------------------------------------------------------------------

local function process_commands()
    local f = io.open(commandPath, "r")
    if not f then return end

    local lines = {}
    for line in f:lines() do
        if line ~= "" then
            insert(lines, line)
        end
    end
    f:close()

    if #lines == 0 then return end

    local wf = io.open(commandPath, "w")
    if wf then wf:write(""); wf:close() end

    for _, line in ipairs(lines) do
        local cmd, a = line:match("^(%S+)%s*(%S*)")

        if cmd == "LIFE" and a == "+1" then
            local lives = read_u8(lives_addr, ram_domain)
            if lives < MAX_LIVES then
                local new = lives + 1
                if new > MAX_LIVES then new = MAX_LIVES end
                write_u8(lives_addr, new, ram_domain)
                log_info("gave extra life -> " .. new)
            end

        elseif cmd == "HEALTH" and a == "+1" then
            local status = read_u16(flik_status_addr, ram_domain)
            if status == FLIK_STATUS_READY then
                local hp = read_u8(health_addr, ram_domain)
                if hp > 0 and hp < MAX_HEALTH then
                    local new_hp = hp + 1
                    if new_hp > MAX_HEALTH then new_hp = MAX_HEALTH end
                    write_u8(health_addr, new_hp, ram_domain)
                    log_info("increased health -> " .. new_hp)
                end
            end
        end
    end
end

---------------------------------------------------------------------
-- Berry tiers (absolute per level)
---------------------------------------------------------------------

local berry_tiers = {}

local function load_berry_state()
    berry_tiers = {}
    local f = io.open(berryStatePath, "r")
    if not f then return end

    for line in f:lines() do
        local idx, tier = line:match("^LEVEL%s+(%d+)%s+(%d+)")
        if idx and tier then
            idx  = tonumber(idx)
            tier = tonumber(tier)
            if idx and tier then
                if tier < 0 then tier = 0 end
                if tier > 4 then tier = 4 end
                berry_tiers[idx] = tier
            end
        end
    end

    f:close()
end

---------------------------------------------------------------------
-- Seed extra tiers (per level)
---------------------------------------------------------------------

local seed_tiers = {}

local function load_seed_state()
    seed_tiers = {}
    local f = io.open(seedStatePath, "r")
    if not f then return end

    for line in f:lines() do
        local idx, b, g, bl, p, y =
            line:match("^LEVEL%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
        if idx and b and g and bl and p and y then
            idx = tonumber(idx)
            b   = tonumber(b)
            g   = tonumber(g)
            bl  = tonumber(bl)
            p   = tonumber(p)
            y   = tonumber(y)
            if idx then
                seed_tiers[idx] = { b, g, bl, p, y }
            end
        end
    end

    f:close()
end

---------------------------------------------------------------------
-- Check tracking
---------------------------------------------------------------------

local completed_flik_all    = {}
local completed_flik_letter = { F = {}, L = {}, I = {}, K = {} }
local completed_grain       = {}
local completed_enemies     = {}
local completed_level_complete = {}

local wait_level_complete_zero = false

local level_complete_armed = false
local prev_level_complete_status = 0
local flik_bits = {
    F = 0x01,
    L = 0x02,
    I = 0x04,
    K = 0x08
}

local current_level_index = nil
local current_level_code  = nil

local prev_flik_mask      = 0
local prev_grain          = 0
local prev_enemies        = 0

local WARMUP_FRAMES = 60
local warmupFramesRemaining = 0

---------------------------------------------------------------------
-- Seed upgrade logic
---------------------------------------------------------------------

local base_seed_tiers      = nil
local applied_seed_extras  = nil

local desired_berry_tier   = nil

local SEED = { BROWN = 0, GREEN = 1, BLUE = 2, PURPLE = 3, YELLOW = 4 }

local seed_addr_by_index = {
    [SEED.BROWN]  = brown_seed_addr,
    [SEED.GREEN]  = green_seed_addr,
    [SEED.BLUE]   = blue_seed_addr,
    [SEED.PURPLE] = purple_seed_addr,
    [SEED.YELLOW] = yellow_seed_addr,
}

local seed_hud_base_by_index = {
    [SEED.BROWN]  = 0x081F4E,
    [SEED.BLUE]   = 0x081F62,
    [SEED.GREEN]  = 0x081F8A,
    [SEED.PURPLE] = 0x081F76,
    [SEED.YELLOW] = 0x081F9E,
}

local seed_hud_row2_base_byte = {
    [SEED.BROWN]  = 0x70,
    [SEED.PURPLE] = 0x78,
    [SEED.GREEN]  = 0x7C,
    [SEED.BLUE]   = 0xF4,
    [SEED.YELLOW] = 0xF8,
}

local upgrade_nibble_code_by_index = {
    [SEED.BLUE]   = 0x1,
    [SEED.GREEN]  = 0x2,
    [SEED.PURPLE] = 0x3,
    [SEED.YELLOW] = 0x4,
}

local function clamp_tier(t)
    if not t or t < 0 then return 0 end
    if t > 4 then return 4 end
    return t
end

local function read_seed_tier(addr)
    local raw = read_u8(addr, ram_domain)
    return clamp_tier(floor(raw / 0x11))
end

local function read_seed_raw(addr)
    return read_u8(addr, ram_domain)
end

local function write_seed_tier(addr, tier)
    tier = clamp_tier(tier)
    write_u8(addr, tier * 0x11, ram_domain)
end

local function write_seed_hud_block(seed_index, tier)
    local base_addr = seed_hud_base_by_index[seed_index]
    local row2_base = seed_hud_row2_base_byte[seed_index]
    if not base_addr or not row2_base then return end

    tier = clamp_tier(tier)
    local tier_group = max(tier - 1, 0)

    write_u8(base_addr, row2_base + tier_group, ram_domain)

    local v0 = 0x00 + 0x40 * tier_group
    local v1 = 0x15 + 0x40 * tier_group
    local v2 = 0x2A + 0x40 * tier_group

    write_u8(base_addr + 0x02, v0, ram_domain)
    write_u8(base_addr + 0x04, v1, ram_domain)
    write_u8(base_addr + 0x06, v2, ram_domain)

    write_u8(base_addr + 0x08, v0, ram_domain)
    write_u8(base_addr + 0x0A, v1, ram_domain)
    write_u8(base_addr + 0x0C, v2, ram_domain)
end

local function compute_packed_upgrade_list_from_tiers(tiers_by_index)
    local order = { SEED.BLUE, SEED.GREEN, SEED.PURPLE, SEED.YELLOW }
    local packed = 0
    local nib = 0

    for _, idx in ipairs(order) do
        local tier = tiers_by_index[idx] or 0
        if tier > 0 then
            local code = upgrade_nibble_code_by_index[idx]
            if code and nib < 4 then
                packed = packed + (code << (nib * 4))
                nib = nib + 1
            end
        end
    end

    return packed
end

local function write_seed_upgrade_list_from_tiers(tiers_by_index)
    local packed = compute_packed_upgrade_list_from_tiers(tiers_by_index)
    write_u16(seed_upgrade_list_addr, packed, ram_domain)
end

local function apply_seed_upgrades_for_level(level_index)
    local extras = seed_tiers[level_index] or { 0, 0, 0, 0, 0 }

    base_seed_tiers = {
        read_seed_tier(brown_seed_addr),
        read_seed_tier(green_seed_addr),
        read_seed_tier(blue_seed_addr),
        read_seed_tier(purple_seed_addr),
        read_seed_tier(yellow_seed_addr),
    }

    applied_seed_extras = { 0, 0, 0, 0, 0 }

    local tiers_after = {}

    for seed_index = 0, 4 do
        local base_tier = base_seed_tiers[seed_index + 1] or 0
        local extra = extras[seed_index + 1] or 0
        extra = clamp_tier(extra)

        local desired = clamp_tier(base_tier + extra)
        local addr = seed_addr_by_index[seed_index]
        if addr then
            write_seed_tier(addr, desired)
            write_seed_hud_block(seed_index, desired)
            tiers_after[seed_index] = desired
        end

        applied_seed_extras[seed_index + 1] = extra
    end

    write_seed_upgrade_list_from_tiers(tiers_after)
end

local function sync_seed_upgrades_during_level()
    if not current_level_index or not base_seed_tiers or not applied_seed_extras then return end

    local extras = seed_tiers[current_level_index]
    if not extras then return end

    local tiers_after = {}
    local changed = false

    for seed_index = 0, 4 do
        local desired_extra = extras[seed_index + 1] or 0
        desired_extra = clamp_tier(desired_extra)

        local prev_extra = applied_seed_extras[seed_index + 1] or 0
        if desired_extra ~= prev_extra then
            changed = true
            applied_seed_extras[seed_index + 1] = desired_extra
        end

        local base_tier = base_seed_tiers[seed_index + 1] or 0
        local desired_tier = clamp_tier(base_tier + desired_extra)
        local addr = seed_addr_by_index[seed_index]
        if addr and changed then
            write_seed_tier(addr, desired_tier)
            write_seed_hud_block(seed_index, desired_tier)
        end
        tiers_after[seed_index] = desired_tier
    end

    if changed then
        write_seed_upgrade_list_from_tiers(tiers_after)
        log_info("applied updated AP seed extras for level " .. tostring(current_level_index))
    end
end

local function enforce_ap_seed_truth()
    if not current_level_index or not base_seed_tiers or not applied_seed_extras then return end

    local desired_tiers = {}
    local any_fixed = false

    for seed_index = 0, 4 do
        local base_tier = base_seed_tiers[seed_index + 1] or 0
        local extra = applied_seed_extras[seed_index + 1] or 0
        local max_unlocked = clamp_tier(base_tier + extra)
        desired_tiers[seed_index] = max_unlocked

        local addr = seed_addr_by_index[seed_index]
        if addr then
            local current_tier = read_seed_tier(addr)
            if current_tier > max_unlocked then
                write_seed_tier(addr, max_unlocked)
                write_seed_hud_block(seed_index, max_unlocked)
                any_fixed = true
            end
        end
    end

    local desired_packed = compute_packed_upgrade_list_from_tiers(desired_tiers)
    local current_packed = read_u16(seed_upgrade_list_addr, ram_domain)
    if current_packed ~= desired_packed then
        write_u16(seed_upgrade_list_addr, desired_packed, ram_domain)
        any_fixed = true
    end

    return any_fixed
end

---------------------------------------------------------------------
-- Berry sync + watchdog
---------------------------------------------------------------------

local BERRY_TIER_TO_RAW = { [0]=0, [1]=1, [2]=2, [3]=4, [4]=3 }
local RAW_TO_BERRY_TIER = { [0]=0, [1]=1, [2]=2, [4]=3, [3]=4 }

local function berry_raw_from_tier(tier)
    tier = clamp_tier(tier)
    return BERRY_TIER_TO_RAW[tier] or 0
end

local function berry_tier_from_raw(raw)
    return RAW_TO_BERRY_TIER[raw] or 0
end

local function apply_berry_tier_for_level(level_index)
    local tier = berry_tiers[level_index] or 0
    tier = clamp_tier(tier)
    desired_berry_tier = tier
    write_u8(berry_addr, berry_raw_from_tier(tier), ram_domain)
end

local function sync_berry_tier_during_level()
    if not current_level_index then return end
    local tier = berry_tiers[current_level_index]
    if tier == nil then return end
    tier = clamp_tier(tier)

    if desired_berry_tier == nil or tier ~= desired_berry_tier then
        desired_berry_tier = tier
        write_u8(berry_addr, berry_raw_from_tier(tier), ram_domain)
        log_info("applied updated AP berry tier -> " .. berry_label(tier))
    end
end

local function enforce_ap_berry_truth()
    if desired_berry_tier == nil then return false end

    local minTier = desired_berry_tier

    local purpleMax = 0
    if base_seed_tiers and applied_seed_extras then
        local base = base_seed_tiers[SEED.PURPLE + 1] or 0
        local extra = applied_seed_extras[SEED.PURPLE + 1] or 0
        purpleMax = clamp_tier(base + extra)
    end

    local maxTier = minTier
    if purpleMax > maxTier then maxTier = purpleMax end

    local currentRaw = read_u8(berry_addr, ram_domain)
    local currentTier = berry_tier_from_raw(currentRaw)

    if currentTier < minTier then
        write_u8(berry_addr, berry_raw_from_tier(minTier), ram_domain)
        return true
    end
    if currentTier > maxTier then
        write_u8(berry_addr, berry_raw_from_tier(maxTier), ram_domain)
        return true
    end

    return false
end

---------------------------------------------------------------------
-- Level state
---------------------------------------------------------------------

local function update_level_state()
    local idx    = read_u8(level_index_addr, ram_domain)
    local code   = read_u16(level_code_addr, ram_domain)
    local status = read_u16(flik_status_addr, ram_domain)

    if code ~= current_level_code then
        current_level_code = code
        level_init_done = false
        warmupFramesRemaining = 0
        wait_level_complete_zero = false
    end

    if not enemy_thresholds[idx] then
        current_level_index = nil
        base_seed_tiers = nil
        applied_seed_extras = nil
        desired_berry_tier = nil
        level_init_done = false
        return
    end

    current_level_index = idx

    if status ~= FLIK_STATUS_READY then
        if status == FLIK_STATUS_BUSY then
            return
        end

        if current_level_index and level_init_done and last_notready_printed_code ~= current_level_code then
            last_notready_printed_code = current_level_code
            log_debug(fmt(
                "level %s enemy counter peak=%d",
                level_label(current_level_index),
                enemy_observed_max[current_level_index] or 0
            ))
        end
        return
    end

    if not level_init_done then
        load_berry_state()
        load_seed_state()

        prev_flik_mask = read_u8(flik_addr, ram_domain)
        prev_grain     = read_u8(grain_addr, ram_domain)
        prev_enemies   = read_enemy_kills()

        enemy_observed_max[current_level_index] = 0

        wait_level_complete_zero = (read_u8(level_complete_status_addr, ram_domain) ~= 0)

        apply_berry_tier_for_level(current_level_index)
        apply_seed_upgrades_for_level(current_level_index)

        warmupFramesRemaining = WARMUP_FRAMES
        level_init_done = true

        log_debug(fmt(
            "entered level %s (code 0x%04X), berry tier %s",
            level_label(current_level_index), current_level_code, berry_label(desired_berry_tier or 0)
        ))
        log_debug(fmt(
          "level %s enemy counter peak=%d",
          level_label(idx),
          enemy_observed_max[idx] or 0
        ))
    end
end

local function track_enemy_max()
  if not current_level_index then return end
  local c = read_enemy_kills()
  local prev = enemy_observed_max[current_level_index] or 0
  if c > prev then
    enemy_observed_max[current_level_index] = c
  end
end

---------------------------------------------------------------------
-- Checks (edge-triggered)
---------------------------------------------------------------------

local function get_level_index_for_checks()
    if current_level_index ~= nil then
        return current_level_index
    end
    return read_u8(level_index_addr, ram_domain)
end

local function check_flik()
    local level_index = get_level_index_for_checks()
    local mask = read_u8(flik_addr, ram_domain)

    if flik_individual then
        for letter, bitmask in pairs(flik_bits) do
            local had_before = prev_flik_mask & bitmask ~= 0
            local has_now    = mask & bitmask ~= 0

            if has_now and not had_before and not completed_flik_letter[letter][level_index] then
                completed_flik_letter[letter][level_index] = true
                append_state(fmt("CHECK FLIK_%s %d", letter, level_index))
                log_info("queued FLIK " .. letter .. " check for level " .. level_label(level_index))
            end
        end
    end

    if flik_all then
        local all_before = prev_flik_mask & 0x0F == 0x0F
        local all_now    = mask & 0x0F == 0x0F

        if all_now and not all_before and not completed_flik_all[level_index] then
            completed_flik_all[level_index] = true
            append_state("CHECK FLIK_ALL " .. level_index)
            log_info("queued FLIK ALL check for level " .. level_label(level_index))
        end
    end

    prev_flik_mask = mask
end

local function check_grain()
    local level_index = get_level_index_for_checks()
    local grain = read_u8(grain_addr, ram_domain)

    if not completed_grain[level_index] and grain == MAX_GRAIN and prev_grain < MAX_GRAIN then
        completed_grain[level_index] = true
        append_state("CHECK GRAIN " .. level_index)
        log_info("queued GRAIN check for level " .. level_label(level_index))
    end

    prev_grain = grain
end

local function check_grain_sanity()
  if not grainsanity_enabled then return end
  local level_index = get_level_index_for_checks()
  local grain = read_u8(grain_addr, ram_domain)

  if not completed_grain_sanity[level_index] then completed_grain_sanity[level_index] = {} end

  local step = max(1, min(MAX_GRAIN, grainsanity_step))

  local t = step
  while t <= MAX_GRAIN do
    if grain >= t and prev_grain < t and not completed_grain_sanity[level_index][t] then
      completed_grain_sanity[level_index][t] = true
      append_state(fmt("CHECK GRAIN%d %d", t, level_index))
      log_info("queued GRAIN " .. t .. " check for level " .. level_label(level_index))
    end
    t = t + step
  end
end

local function round_nearest(x)
  return floor(x + 0.5)
end

function check_enemy_sanity()
    local status = read_u16(flik_status_addr, ram_domain)
    if status ~= FLIK_STATUS_READY then
        return
    end

    local level_index = get_level_index_for_checks()
    if not level_index then return end

    local count = read_enemy_kills()

    if DEBUG_MODE then
        local t = enemy_thresholds[level_index] or {}
        local need25, need50, need75, need100 = t[25], t[50], t[75], t[100]

        local function hit(need) return (need and need > 0 and count >= need) and 1 or 0 end

        local peak = enemy_observed_max[level_index] or 0

        local key = table.concat({
            level_index,
            hit(need25), hit(need50), hit(need75), hit(need100),
            enemysanity_25 and 1 or 0, enemysanity_50 and 1 or 0, enemysanity_75 and 1 or 0, enemysanity_100 and 1 or 0,
            (completed_enemy_pct[25][level_index] and 1 or 0),
            (completed_enemy_pct[50][level_index] and 1 or 0),
            (completed_enemy_pct[75][level_index] and 1 or 0),
            (completed_enemy_pct[100][level_index] and 1 or 0),
            peak,
        }, "|")

        if dbg_enemy_last.key ~= key then
            dbg_enemy_last.key = key
            log_debug(fmt(
                "lvl=%d count=%d peak=%d need(25/50/75/100)=(%s/%s/%s/%s) hit=(%d/%d/%d/%d) enabled=(%s/%s/%s/%s) done=(%s/%s/%s/%s)",
                level_index, count, peak,
                tostring(need25), tostring(need50), tostring(need75), tostring(need100),
                hit(need25), hit(need50), hit(need75), hit(need100),
                tostring(enemysanity_25), tostring(enemysanity_50), tostring(enemysanity_75), tostring(enemysanity_100),
                tostring(completed_enemy_pct[25][level_index]),
                tostring(completed_enemy_pct[50][level_index]),
                tostring(completed_enemy_pct[75][level_index]),
                tostring(completed_enemy_pct[100][level_index])
            ))
        end
    end

    local function fire(pct)
        if completed_enemy_pct[pct][level_index] then return end
        completed_enemy_pct[pct][level_index] = true
        append_state("CHECK ENEMIES" .. pct .. " " .. level_index)
        log_info("queued ENEMIES " .. pct .. "% check for level " .. level_label(level_index))
    end

    local function try_pct(pct, enabled)
        if not enabled then return end

        local t = enemy_thresholds[level_index]
        local v = t and t[pct] or nil
        if not v or v < 1 then return end

        if count >= v and prev_enemies < v then
            fire(pct)
        end
    end

    try_pct(25, enemysanity_25)
    try_pct(50, enemysanity_50)
    try_pct(75, enemysanity_75)
    try_pct(100, enemysanity_100)

    prev_enemies = count
end

local function check_level_complete()
    if not current_level_index then return end
    if not level_init_done then return end
    if warmupFramesRemaining and warmupFramesRemaining > 0 then return end

    local status = read_u16(flik_status_addr, ram_domain)
    if status ~= FLIK_STATUS_READY then return end

    local level_index = get_level_index_for_checks()
    if not level_index then return end
    if completed_level_complete[level_index] then return end

    local s = read_u8(level_complete_status_addr, ram_domain)

    if not level_complete_armed then
        if s == 0 then
            level_complete_armed = true
            prev_level_complete_status = 0
        else
            prev_level_complete_status = s
        end
        return
    end

    if prev_level_complete_status == 0 and s == 1 then
        completed_level_complete[level_index] = true
        append_state("CHECK LEVEL_COMPLETE " .. level_index)
        log_info("queued LEVEL_COMPLETE check for level " .. level_label(level_index))
    end

    prev_level_complete_status = s
end

---------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------

local frameCounter = 0
local reloadEveryFrames = 300

local function step()
    unlock_all_levels()
    update_level_state()
    if not current_level_index then return end
    process_commands()
    local status = read_u16(flik_status_addr, ram_domain)
    frameCounter = frameCounter + 1
    if current_level_index and (frameCounter % reloadEveryFrames == 0) and status == FLIK_STATUS_READY and level_init_done then
        load_config()
        load_seed_state()
        load_berry_state()
        sync_seed_upgrades_during_level()
        sync_berry_tier_during_level()
    end

    enforce_ap_seed_truth()
    enforce_ap_berry_truth()

    if warmupFramesRemaining > 0 then
        warmupFramesRemaining = warmupFramesRemaining - 1
        prev_flik_mask = read_u8(flik_addr, ram_domain)
        prev_grain     = read_u8(grain_addr, ram_domain)
        prev_enemies   = read_enemy_kills()
        return
    end

    track_enemy_max()
    check_flik()
    check_grain_sanity()
    check_grain()
    check_enemy_sanity()
    check_level_complete()
end

while true do
    local ok, err = pcall(step)
    if not ok then
        log_error(tostring(err))
    end
    emu.frameadvance()
end