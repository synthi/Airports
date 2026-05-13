-- Airports.lua | Version 1.02
-- Ambient loopers for norns
-- Inspired by Brian Eno's "Music for Airports"
-- 4 seamless continuous loopers with degrade, brake, jump, warp

engine.name = 'Airports'

local Globals = include('lib/globals_airports')
local Loopers = include('lib/loopers_airports')
local Grid = include('lib/grid_airports')
local Graphics = include('lib/graphics_airports')
local Storage = include('lib/storage_airports')

local _16n = include('lib/16n')

g = grid.connect()

local SRC_OPTIONS = {"Input", "Pre Reverb", "Post Reverb", "Track 1", "Track 2", "Track 3", "Track 4"}
local MAX_BUFFER_SEC = 120.0
local DIV_VALUES = {4, 2, 1, 0.5, 0.25, 0.125, 0.0625, 0.03125, 0.015625}
local NOISE_NAMES = {"Pink", "White", "Crackle", "DigiRain", "Lorenz", "Grit"}

state = Globals.new()

-- Helpers
local function update_str(id)
    if params:lookup_param(id) then
        state.str_cache[id] = params:string(id)
    end
end

local function set_p(id, val)
    local eng_cmd = id
    if id == "bus_thresh" then eng_cmd = "comp_thresh"
    elseif id == "bus_ratio" then eng_cmd = "comp_ratio"
    elseif id == "bus_drive" then eng_cmd = "comp_drive"
    end
    
    if engine[eng_cmd] then engine[eng_cmd](val) end
    state.str_cache[id] = params:string(id)
end

local function fmt_db(param) return string.format("%.1fdB", util.linlin(0, 1, -60, 12, param:get())) end
local function fmt_percent(param) return string.format("%.0f%%", param:get() * 100) end
local function fmt_hz(param) return string.format("%.1fHz", param:get()) end
local function fmt_sec(param) return string.format("%.2fs", param:get()) end
local function fmt_ratio(param) return string.format("%.1f:1", param:get()) end
local function fmt_raw_db(param) return string.format("%.1fdB", param:get()) end

-- 16n mapping (for future use)
local fader_map = {
    [1] = "l1_vol", [2] = "l2_vol", [3] = "l3_vol", [4] = "l4_vol",
    [5] = "l1_filter", [6] = "l2_filter", [7] = "l3_filter", [8] = "l4_filter",
    [9] = "reverb_mix", [10] = "reverb_time",
    [11] = "noise_amp", [12] = "global_lpf",
    [13] = "main_mon", [14] = "bus_thresh",
    [15] = "bus_ratio", [16] = "balance"
}

local fader_names = {
    [1] = "TRK 1 VOL", [2] = "TRK 2 VOL", [3] = "TRK 3 VOL", [4] = "TRK 4 VOL",
    [5] = "TRK 1 FLT", [6] = "TRK 2 FLT", [7] = "TRK 3 FLT", [8] = "TRK 4 FLT",
    [9] = "REVERB MIX", [10] = "REVERB TIME",
    [11] = "NOISE LVL", [12] = "GLOBAL LPF",
    [13] = "MAIN MON", [14] = "COMP THRESH",
    [15] = "COMP RATIO", [16] = "BALANCE"
}

-- ============================================================
-- OSC EVENT
-- ============================================================
function osc.event(path, args, from)
  if not state.loaded then return end
  
  if path == "/buffer_info" then
    local idx = math.floor(args[1]); local dur = args[2]
    state.tracks[idx].rec_len = dur
    params:set("l"..idx.."_length", dur)
    Loopers.refresh(idx, state)
    print("Reel " .. idx .. " duration: " .. dur)

  elseif path == "/airports/visuals" then
    if args and #args >= 7 then
        state.amp_l = args[1]; state.amp_r = args[2]; state.comp_gr = args[3]
        
        -- Goniameter
        local h = state.heads.gonio
        local zoom = params:get("scope_zoom") or 4
        state.gonio_history[h].s = util.clamp((args[1]+args[2])*0.5 * zoom * 40, 0, 22)
        state.gonio_history[h].w = util.clamp(math.abs(args[1]-args[2])*0.5 * zoom * 80, 0, 20)
        state.heads.gonio = (h % state.GONIO_LEN) + 1
        
        -- Play positions (pointers[0..3] are args[4..7])
        for i=1, 4 do
            local raw_val = args[3+i]
            if raw_val < 0 then
               -- Recording first pass
               local t_len = math.abs(raw_val)
               state.tracks[i].rec_len = t_len
               state.tracks[i].is_dirty = true
               state.tracks[i].play_pos = 1.0
               state.tracks[i].recording_active = true
            else
               -- Normal playback position
               state.tracks[i].play_pos = util.clamp(raw_val, 0, 1)
               
               if state.tracks[i].recording_active then
                  local final_len = params:get("l"..i.."_length")
                  state.tracks[i].rec_len = final_len
                  state.tracks[i].recording_active = false
               end
            end
        end
    end
  end
end

-- ============================================================
-- ENCODER
-- ============================================================
function enc(n, d)
  local page = state.current_page
  
  -- Config pages
  if state.config_page_active then
     local config_type = state.config_page_type
     local cursor = state.config_page_cursor
     local sel = state.config_page_track or state.track_sel
     local t = state.tracks[sel]
     
     if n == 2 then
        -- E2: Navigate cursor
        if config_type == "jump" then
           state.config_page_cursor = util.clamp(cursor + d, 1, 4)
        elseif config_type == "random" then
           state.config_page_cursor = util.clamp(cursor + d, 1, 5)
        elseif config_type == "warp" then
           state.config_page_cursor = util.clamp(cursor + d, 1, 4)
        end
     elseif n == 3 then
        -- E3: Change value
        if config_type == "jump" then
           if cursor == 1 then
              t.jump_sync = (t.jump_sync + math.abs(d)) % 2
           elseif cursor == 2 then
              t.jump_rate = util.clamp(t.jump_rate + d * 0.1, 0.1, 10.0)
           elseif cursor == 3 then
              t.jump_div = util.clamp(t.jump_div + d * d, 1, 256)
              if t.jump_div < 1 then t.jump_div = 1 end
           elseif cursor == 4 then
              t.jump_rnd_lpos = util.clamp(t.jump_rnd_lpos + d * 0.01, 0, 1)
           end
        elseif config_type == "random" then
           if cursor == 1 then t.rnd_speed = not t.rnd_speed
           elseif cursor == 2 then t.rnd_deg = not t.rnd_deg
           elseif cursor == 3 then t.rnd_loop = not t.rnd_loop
           elseif cursor == 4 then t.rnd_eq = not t.rnd_eq
           elseif cursor == 5 then t.rnd_vol = not t.rnd_vol end
        elseif config_type == "warp" then
           if cursor == 1 then
              state.warp_mode = (state.warp_mode + math.abs(d)) % 2
           elseif cursor == 2 then
              local amounts = {0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0}
              local idx = 3  -- default 1.0
              for i, v in ipairs(amounts) do
                 if math.abs(v - state.warp_amount) < 0.01 then idx = i; break end
              end
              idx = util.clamp(idx + d, 1, #amounts)
              state.warp_amount = amounts[idx]
           elseif cursor == 3 then
              state.warp_smooth = util.clamp(state.warp_smooth + d * 0.01, 0.01, 1.0)
           elseif cursor == 4 then
              state.warp_target = (state.warp_target + 1) % 2
           end
        end
     end
     return
  end
  
  -- Normal pages
  local shift = state.k1_held or state.grid_shift_active
  
  -- Tertiary mode (Track Held) — works on ALL pages
  if state.grid_track_held then
     if n == 1 then Loopers.delta_param("rec_level", d, state)
     elseif n == 2 then Loopers.delta_param("src_sel", d, state) end
     return
  end
  
  -- TAPE LIBRARY page (6)
  if page == 6 and not state.config_page_active then
     if n == 2 then
        state.tape_library_sel = util.clamp((state.tape_library_sel or 1) + d, 1, 4)
     end
     return
  end
  
  if page == 7 then
     -- TAPE page
     -- E4 = REC LEVEL (always, in all modes)
     if n == 4 then Loopers.delta_param("rec_level", d, state)
     
     -- Shift mode (K1 held / grid_shift)
     elseif shift then
         if n == 1 then Loopers.delta_param("speed", d, state)
         elseif n == 2 then Loopers.delta_param("start", d, state)
         elseif n == 3 then Loopers.delta_param("end", d, state) end
     
     -- Normal mode: E1=LENGTH, E2=DEGRADE, E3=DUB
     else
         if n == 1 then
            local resolution = (math.abs(d) > 1) and 1.0 or 0.01
            local id = "l"..state.track_sel.."_length"
            params:delta(id, d * resolution)
         elseif n == 2 then Loopers.delta_param("degrade", d, state)
         elseif n == 3 then Loopers.delta_param("overdub", d, state) end
     end
     
  elseif page == 8 then
     -- MIXER page (Sitral Mixer)
     if shift then
        if n == 1 then Loopers.delta_param("filter", d, state)
        elseif n == 2 then Loopers.delta_param("pan", d, state)
        elseif n == 3 then Loopers.delta_param("width", d, state) end
     else
        if n == 1 then Loopers.delta_param("vol", d, state)
        elseif n == 2 then Loopers.delta_param("low", d, state)
        elseif n == 3 then Loopers.delta_param("high", d, state) end
     end
     
  elseif page == 9 then
     -- AMBIENT page
     if shift then
        if n == 1 then params:delta("reverb_damp", d)
        elseif n == 2 then params:delta("global_lpf", d)
        elseif n == 3 then params:delta("global_hpf", d) end
     else
        if n == 1 then params:delta("reverb_mix", d)
        elseif n == 2 then params:delta("reverb_time", d)
        elseif n == 3 then params:delta("noise_amp", d) end
     end
     if n == 4 then params:delta("noise_type", d) end
     
  elseif page == 10 then
     -- MASTER page
     if shift then
        -- Shift: Main Mon (Master Output), Balance, Comp Drive
        if n == 1 then params:delta("main_mon", d)
        elseif n == 2 then params:delta("balance", d)
        elseif n == 3 then params:delta("bus_drive", d) end
     else
        -- No-shift: Monitor, Thresh, Ratio
        if n == 1 then params:delta("monitor_amp", d)
        elseif n == 2 then params:delta("bus_thresh", d)
        elseif n == 3 then params:delta("bus_ratio", d) end
     end
     if n == 4 then params:delta("balance", d) end
  end
end

-- ============================================================
-- KEY
-- ============================================================
function key(n, z)
  if n == 1 then
     state.k1_held = (z == 1)
     return
  end
  
  -- K3 in config pages = exit
  if state.config_page_active and n == 3 and z == 1 then
     state.config_page_active = false
     state.current_page = state.config_previous_page
     state.config_page_type = ""
     return
  end
  
  -- Page navigation with K1+Key2/Key3
  if state.k1_held and z == 1 then
     if n == 2 then
        state.current_page = state.current_page - 1
        if state.current_page < 7 then state.current_page = 10 end
     elseif n == 3 then
        state.current_page = state.current_page + 1
        if state.current_page > 10 then state.current_page = 7 end
     end
     return
  end
  
  -- Normal key functions per page
  
  -- TAPE LIBRARY page (6)
  if state.current_page == 6 and not state.config_page_active then
     local fileselect = require 'fileselect'
     if n == 2 and z == 1 then
        -- K2: Load tape
        state.file_selector_active = true
        fileselect.enter("/home/we/dust/audio/", function(file)
           state.file_selector_active = false
           if file ~= "cancel" then Loopers.load_file(state.tape_library_sel, file, state) end
        end)
     elseif n == 3 and z == 1 then
        -- K3: Save tape
        local sel = state.tape_library_sel
        local len = state.tracks[sel].rec_len or 0
        if len > 0 then
           local name = _path.audio .. "Airports/reel_" .. sel .. "_" .. os.date("%y%m%d%H%M") .. ".wav"
           engine.buffer_write(sel, name, len)
           state.tape_filenames[sel] = name:match("^.+/(.+)$")
           state.tape_msg_timers[sel] = util.time() + 2.0
           state.tracks[sel].file_path = name
           print("Tape " .. sel .. " saved: " .. name)
        end
     end
     return
  end
  
  if state.current_page == 9 then
     -- AMBIENT page: K2/K3 cycle noise type
     if n == 2 and z == 1 then
        local cur = params:get("noise_type")
        params:set("noise_type", ((cur - 2) % 6) + 1)
     elseif n == 3 and z == 1 then
        local cur = params:get("noise_type")
        params:set("noise_type", (cur % 6) + 1)
     end
  
  elseif state.current_page == 7 then
     if n == 2 then
        -- K2: toggle degrade parameter selection (or rec in shift)
        if state.grid_track_held then
           -- toggle input source
           local t = state.tracks[state.track_sel]
            t.src_sel = (t.src_sel + 1) % 7
           Loopers.refresh(state.track_sel, state)
        else
           Loopers.transport_rec(state, state.track_sel, z == 1 and "press" or "release")
        end
     elseif n == 3 and z == 1 then
        -- K3: reverse speed
        if state.grid_track_held then
           local t = state.tracks[state.track_sel]
           -- fine tune length up
           local id = "l"..state.track_sel.."_length"
           params:delta(id, 0.01)
        else
           local t = state.tracks[state.track_sel]
           t.speed = (t.speed or 1) * -1
           Loopers.refresh(state.track_sel, state)
        end
     end
  end
end

-- ============================================================
-- GRID CALLBACK
-- ============================================================
g.key = function(x, y, z)
  Grid.key(x, y, z, state, engine, nil, nil)
end

-- ============================================================
-- SEQUENCER PLAYBACK
-- ============================================================
function rec_play_tick_tape(slot)
    while true do
      local r = state.seq_slots[slot]
      if r.state ~= 4 then clock.sleep(0.1)
      else
         local event = r.data[r.step]
         if event then
            local rate = 1.0
            local next_time = 0
            if r.step < #r.data then
               next_time = (r.data[r.step+1].dt - event.dt) / rate
            elseif r.state == 4 then
               next_time = (r.duration - event.dt) / rate
            end
            if next_time < 0 then next_time = 0 end
            if event.x and event.y and event.z then
               Grid.key(event.x, event.y, event.z, state, engine, true, event.tid)
            end
            if next_time > 0 then clock.sleep(next_time) end
            r.step = r.step + 1
            if r.step > #r.data then r.step = 1 end
         else clock.sleep(0.1) end
      end
    end
end

-- ============================================================
-- 16n HANDLER (for future use)
-- ============================================================
local function normalize_16n(midi_val)
    if midi_val < 1 then return 0.0 end
    if midi_val > 126 then return 1.0 end
    if midi_val <= 80 then return util.linlin(1, 80, 0.0, 0.5, midi_val)
    else return util.linlin(80, 126, 0.5, 1.0, midi_val) end
end

local function apply_glue(val, id)
    if id >= 5 and id <= 8 then
        if math.abs(val - 0.5) < 0.03 then return 0.5 end
    end
    if id >= 1 and id <= 4 then
        if math.abs(val - 0.833) < 0.03 then return 0.833 end
    end
    return val
end

local function handle_16n(msg)
    -- Handle 16n physical shift button
    if msg.type == 'shift_press' then
       state.sixteen_n_shift = true
       -- Reset fader latches so layer switch is smooth
       for i=1, 8 do state.fader_latched[i] = false end
       return
    elseif msg.type == 'shift_release' then
       state.sixteen_n_shift = false
       for i=1, 8 do state.fader_latched[i] = false end
       return
    end
    
    local id = _16n.cc_2_slider_id(msg.cc)
    if not id then return end
    
    local p_name = fader_map[id]
    local display_name = fader_names[id]
    
    -- Layer shift: Track Held OR 16n switch → faders 1-4 = degrade, 5-8 = brake continuo
    if state.grid_track_held or state.sixteen_n_shift or state.k1_held or state.grid_shift_active then
        if id >= 1 and id <= 4 then
            p_name = "l"..id.."_deg"
            display_name = "TRK "..id.." DEGRADE"
        elseif id >= 5 and id <= 8 then
            local trk = id - 4
            p_name = "l"..trk.."_brake16"
            display_name = "TRK "..trk.." BRAKE"
        end
    elseif not fader_map[id] then
        return
    end
    
    local p_obj = params:lookup_param(p_name)
    if not p_obj then return end
    
    local norm_val = normalize_16n(msg.val)
    norm_val = apply_glue(norm_val, id)
    state.hw_positions[id] = norm_val
    
    local real_val = p_obj.controlspec:map(norm_val)
    local current_real = params:get(p_name)
    local current_norm = p_obj.controlspec:unmap(current_real)
    
    if not state.fader_latched[id] then
        local diff = norm_val - current_norm
        if math.abs(diff) < 0.05 then
            state.fader_latched[id] = true
        else
            state.popup.name = display_name or p_obj.name
            local dir = (diff < 0) and " ( >> )" or " ( << )"
            
            local ghost_txt = string.format("%.2f", real_val)
            if p_name:find("vol") or p_name:find("amp") or p_name:find("drive") or p_name:find("rec_lvl") or p_name:find("brake") then
                ghost_txt = string.format("%.1fdB", util.linlin(0,1,-60,12,norm_val))
            end
            if p_name:find("freq") then ghost_txt = string.format("%.0fHz", real_val) end
            if p_name:find("mix") or p_name:find("fb") or p_name:find("deg") then ghost_txt = string.format("%.0f%%", real_val*100) end
            
            state.popup.value = ghost_txt .. " -> " .. p_obj:string() .. dir
            state.popup.active = true
            state.popup.deadline = util.time() + 1.5
            return
        end
    end
    
    if state.fader_latched[id] then
        params:set(p_name, real_val)
        
        -- Refresh looper if track-related param changed
        if (id >= 1 and id <= 8) then
            local trk = (id > 4) and (id - 4) or id
            Loopers.refresh(trk, state)
        end
        
        state.popup.name = display_name or p_obj.name
        state.popup.value = p_obj:string()
        state.popup.active = true
        state.popup.deadline = util.time() + 1.5
    end
end

-- ============================================================
-- UPDATE MORPHING
-- ============================================================
function update_morph()
  if state.preset_morph_active and state.preset_morph_slot then
     local slot = state.preset_morph_slot
     local target = state.presets_data[slot]
     if not target or not target.tracks then state.preset_morph_active = false; return end
     
     local morph_time = params:get("preset_morph") or 2.0
     if state.morph_fast_mode then morph_time = 0.1 end
     
     if morph_time < 0.05 then
        for i=1, 4 do
           local td = target.tracks[i]
           if td then
              state.tracks[i].speed = td.speed
              state.tracks[i].vol = td.vol
              state.tracks[i].loop_start = td.loop_start
              state.tracks[i].loop_end = td.loop_end
              state.tracks[i].overdub = td.overdub
              state.tracks[i].wow_macro = td.wow_macro
              state.tracks[i].l_low = td.l_low or 0
              state.tracks[i].l_high = td.l_high or 0
              state.tracks[i].l_filter = td.l_filter or 0.5
              state.tracks[i].l_pan = td.l_pan or 0
              state.tracks[i].l_width = td.l_width or 1
              Loopers.refresh(i, state)
           end
        end
        state.preset_morph_active = false
     else
        local now = util.time()
        local elapsed = now - state.preset_morph_start_time
        local progress = elapsed / morph_time
        if progress >= 1.0 then
           for i=1, 4 do
              local td = target.tracks[i]
              if td then
                 state.tracks[i].speed = td.speed
                 state.tracks[i].vol = td.vol
                 state.tracks[i].loop_start = td.loop_start
                 state.tracks[i].loop_end = td.loop_end
                 state.tracks[i].overdub = td.overdub
                 state.tracks[i].wow_macro = td.wow_macro
                 if td.l_low then state.tracks[i].l_low = td.l_low end
                 if td.l_high then state.tracks[i].l_high = td.l_high end
                 if td.l_filter then state.tracks[i].l_filter = td.l_filter end
                 if td.l_pan then state.tracks[i].l_pan = td.l_pan end
                 if td.l_width then state.tracks[i].l_width = td.l_width end
                 Loopers.refresh(i, state)
              end
           end
           state.preset_morph_active = false
        else
           for i=1, 4 do
              local td = target.tracks[i]; local ts = state.preset_morph_src[i]
              if td and ts then
                 state.tracks[i].speed = (ts.speed or 1.0) + ((td.speed or 1.0) - (ts.speed or 1.0)) * progress
                 state.tracks[i].vol = (ts.vol or 0.833) + ((td.vol or 0.833) - (ts.vol or 0.833)) * progress
                 state.tracks[i].loop_start = (ts.loop_start or 0) + ((td.loop_start or 0) - (ts.loop_start or 0)) * progress
                 state.tracks[i].loop_end = (ts.loop_end or 1) + ((td.loop_end or 1) - (ts.loop_end or 1)) * progress
                 state.tracks[i].overdub = (ts.overdub or 1.0) + ((td.overdub or 1.0) - (ts.overdub or 1.0)) * progress
                 state.tracks[i].wow_macro = (ts.wow_macro or 0) + ((td.wow_macro or 0) - (ts.wow_macro or 0)) * progress
                 state.tracks[i].l_low = (ts.l_low or 0) + ((td.l_low or 0) - (ts.l_low or 0)) * progress
                 state.tracks[i].l_high = (ts.l_high or 0) + ((td.l_high or 0) - (ts.l_high or 0)) * progress
                 state.tracks[i].l_filter = (ts.l_filter or 0.5) + ((td.l_filter or 0.5) - (ts.l_filter or 0.5)) * progress
                 state.tracks[i].l_pan = (ts.l_pan or 0) + ((td.l_pan or 0) - (ts.l_pan or 0)) * progress
                 state.tracks[i].l_width = (ts.l_width or 1) + ((td.l_width or 1) - (ts.l_width or 1)) * progress
                 Loopers.refresh(i, state)
              end
           end
        end
     end
  end
end

-- ============================================================
-- JUMP HOLD (continuous jump while held)
-- ============================================================
function jump_hold_tick()
  while true do
    for i=1, 4 do
      if state.tracks[i].jump_held then
        local now = util.time()
        local elapsed = now - state.tracks[i].jump_hold_start
        if elapsed > 0.2 then  -- Initial delay before continuous jump
          local rate = state.tracks[i].jump_rate or 1.0
          local period = 1.0 / rate
          if now % period < 0.05 then  -- Tick at rate
            Loopers.jump(i, state)
          end
        end
      end
    end
    clock.sleep(0.02)
  end
end

-- ============================================================
-- INIT
-- ============================================================
function init()
  audio.level_adc_cut(1)
  
  -- Create directories
  if util.file_exists(_path.data .. "Airports") == false then util.make_dir(_path.data .. "Airports") end
  if util.file_exists(_path.audio .. "Airports") == false then util.make_dir(_path.audio .. "Airports") end
  if util.file_exists(_path.audio .. "Airports/snapshots") == false then util.make_dir(_path.audio .. "Airports/snapshots") end
  
  -- ========================
  -- PARAMETERS
  -- ========================
  params:add_separator("AIRPORTS")
  
  params:add_group("GLOBAL", 6)
  params:add{type = "control", id = "main_mon", name = "Main Monitor", controlspec = controlspec.new(0, 1, 'lin', 0.001, 0.833), formatter = fmt_db, action = function(x) set_p("main_mon", x) end}
  params:add{type = "control", id = "fader_slew", name = "Fader Slew", controlspec = controlspec.new(0.01, 10.0, 'exp', 0.01, 0.05, "s"), formatter = fmt_sec, action = function(x) set_p("fader_slew", x) end}
  params:add{type = "control", id = "preset_morph", name = "Preset Morph", controlspec = controlspec.new(0.01, 30.0, 'exp', 0.01, 2.0, "s"), formatter = fmt_sec}
  params:add{type = "option", id = "load_behavior", name = "Load Behavior", options = {"Stop", "Play"}, default = 1}
  params:add{type = "option", id = "load_behavior_audio", name = "Load: Audio", options = {"Stop", "Play"}, default = 1}
  params:add{type = "control", id = "scope_zoom", name = "Scope Zoom", controlspec = controlspec.new(1, 10, 'lin', 0.1, 4)}
  
  params:add_group("INPUT", 3)
  params:add{type = "control", id = "input_amp", name = "Input Level", controlspec = controlspec.new(0, 2, 'lin', 0.001, 1.0), formatter = fmt_percent, action = function(x) set_p("input_amp", x) end}
  params:add{type = "control", id = "noise_amp", name = "Noise Level", controlspec = controlspec.new(0, 2, 'lin', 0.001, 0.0), formatter = fmt_percent, action = function(x) engine.noise_amp(x) end}
  params:add{type = "option", id = "noise_type", name = "Noise Type", options = NOISE_NAMES, default = 1, action = function(x) engine.noise_type(x-1) end}
  
  params:add_group("GLOBAL FILTERS", 2)
  params:add{type = "control", id = "global_lpf", name = "Global LPF", controlspec = controlspec.new(150, 20000, 'exp', 0, 20000, "Hz"), formatter = fmt_hz, action = function(x) engine.global_lpf(x) end}
  params:add{type = "control", id = "global_hpf", name = "Global HPF", controlspec = controlspec.new(20, 2000, 'exp', 0, 20, "Hz"), formatter = fmt_hz, action = function(x) engine.global_hpf(x) end}
  
  params:add_group("REVERB", 3)
  params:add{type = "control", id = "reverb_mix", name = "Reverb Mix", controlspec = controlspec.new(0, 1, 'lin', 0.001, 0.25), formatter = fmt_percent, action = function(x) engine.reverb_mix(x) end}
  params:add{type = "control", id = "reverb_time", name = "Reverb Time", controlspec = controlspec.new(0.1, 30.0, 'exp', 0.1, 4.2, "s"), formatter = fmt_sec, action = function(x) engine.reverb_time(x) end}
  params:add{type = "control", id = "reverb_damp", name = "Reverb Damp", controlspec = controlspec.new(100, 20000, 'exp', 10, 4600, "Hz"), formatter = fmt_hz, action = function(x) engine.reverb_damp(x) end}
  
  params:add_group("MONITOR", 1)
  params:add{type = "control", id = "monitor_amp", name = "Monitor Level", controlspec = controlspec.new(-60, 6, 'lin', 0.1, 0, "dB"), formatter = fmt_raw_db, action = function(x) engine.monitor_amp(x) end}
  
  params:add_group("MASTER", 6)
  params:add{type = "control", id = "bus_thresh", name = "Comp Thresh", controlspec = controlspec.new(-60.0, 0.0, 'lin', 0.1, -12.0, "dB"), formatter = fmt_raw_db, action = function(x) set_p("bus_thresh", x) end}
  params:add{type = "control", id = "bus_ratio", name = "Comp Ratio", controlspec = controlspec.new(1.0, 20.0, 'lin', 0.1, 2.2), formatter = fmt_ratio, action = function(x) set_p("bus_ratio", x) end}
  params:add{type = "control", id = "bus_drive", name = "Comp Drive", controlspec = controlspec.new(0.0, 24.0, 'lin', 0.1, 1.0, "dB"), formatter = fmt_raw_db, action = function(x) set_p("bus_drive", x) end}
  params:add{type = "option", id = "bass_focus", name = "Bass Focus", options = {"OFF", "50Hz", "100Hz", "200Hz"}, default = 1, action = function(x) engine.bass_focus(x-1) end}
  params:add{type = "control", id = "limiter_ceil", name = "Limiter Ceil", controlspec = controlspec.new(-6.0, 0.0, 'lin', 0.1, -0.1, "dB"), formatter = fmt_raw_db, action = function(x) set_p("limiter_ceil", x) end}
  params:add{type = "control", id = "balance", name = "Balance", controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 0.0), formatter = function(p) return string.format("%.2f", p:get()) end, action = function(x) set_p("balance", x) end}
  
  -- Randomize setup
  params:add_group("RANDOMIZE SETUP", 20)
  for i=1, 4 do
    params:add{type = "trigger", id = "rnd_trk"..i.."_speed", name = "Trk"..i.." Speed", action = function() state.tracks[i].rnd_speed = not state.tracks[i].rnd_speed; update_str("rnd_trk"..i.."_speed") end}
    params:add{type = "trigger", id = "rnd_trk"..i.."_deg", name = "Trk"..i.." Degrade", action = function() state.tracks[i].rnd_deg = not state.tracks[i].rnd_deg; update_str("rnd_trk"..i.."_deg") end}
    params:add{type = "trigger", id = "rnd_trk"..i.."_loop", name = "Trk"..i.." Loop", action = function() state.tracks[i].rnd_loop = not state.tracks[i].rnd_loop; update_str("rnd_trk"..i.."_loop") end}
    params:add{type = "trigger", id = "rnd_trk"..i.."_eq", name = "Trk"..i.." EQ/Filter", action = function() state.tracks[i].rnd_eq = not state.tracks[i].rnd_eq; update_str("rnd_trk"..i.."_eq") end}
    params:add{type = "trigger", id = "rnd_trk"..i.."_vol", name = "Trk"..i.." Volume", action = function() state.tracks[i].rnd_vol = not state.tracks[i].rnd_vol; update_str("rnd_trk"..i.."_vol") end}
  end
  
  -- Track parameters (4 tracks)
  for i=1, 4 do
    params:add_group("TRACK " .. i, 16)
    params:add{type = "control", id = "l"..i.."_speed", name = "Speed", controlspec = controlspec.new(-2.0, 2.0, 'lin', 0.002, 1.0), formatter = function(p) return string.format("x%.2f", p:get()) end, action = function(x) state.tracks[i].speed = x; Loopers.refresh(i, state) end}
    params:add{type = "control", id = "l"..i.."_vol", name = "Volume", controlspec = controlspec.new(0, 1.0, 'lin', 0.001, 0.833), formatter = fmt_db, action = function(x) state.tracks[i].vol = x; Loopers.refresh(i, state) end}
    params:add{type = "control", id = "l"..i.."_dub", name = "Overdub", controlspec = controlspec.new(0, 1.11, 'lin', 0.001, 1.0), formatter = fmt_percent, action = function(x) state.tracks[i].overdub = x; Loopers.refresh(i, state) end}
    params:add{type = "control", id = "l"..i.."_length", name = "Length", controlspec = controlspec.new(0.001, 120.0, 'exp', 0.01, 120.0, "s"), action = function(x)
        Loopers.refresh(i, state)
        if state.loaded and state.tracks[i].state ~= 1 then
            state.tracks[i].rec_len = x
            state.tracks[i].ignore_neg_pointer = true
            clock.run(function() clock.sleep(0.2); state.tracks[i].ignore_neg_pointer = false end)
        end
    end}
    params:add{type = "control", id = "l"..i.."_deg", name = "Degrade", controlspec = controlspec.new(0, 1.0, 'lin', 0.001, 0.0), formatter = fmt_percent, action = function(x) state.tracks[i].wow_macro = x; Loopers.refresh(i, state) end}
    params:add{type = "control", id = "l"..i.."_start", name = "Loop Start", controlspec = controlspec.new(0, 1.0, 'lin', 0.001, 0.0), formatter = fmt_percent, action = function(x) state.tracks[i].loop_start = x; Loopers.refresh(i, state) end}
    params:add{type = "control", id = "l"..i.."_end", name = "Loop End", controlspec = controlspec.new(0, 1.0, 'lin', 0.001, 1.0), formatter = fmt_percent, action = function(x) state.tracks[i].loop_end = x; Loopers.refresh(i, state) end}
    params:add{type = "option", id = "l"..i.."_src", name = "Input Source", options = SRC_OPTIONS, default = 1, action = function(x) state.tracks[i].src_sel = x - 1; Loopers.refresh(i, state) end}
    params:add{type = "control", id = "l"..i.."_rec_lvl", name = "Rec Level", controlspec = controlspec.new(-60, 12, 'lin', 0.1, 0, "dB"), formatter = fmt_raw_db, action = function(x) state.tracks[i].rec_level = x; Loopers.refresh(i, state) end}
    params:add{type = "control", id = "l"..i.."_low", name = "Low Shelf", controlspec = controlspec.new(-18, 18, 'lin', 0.1, 0.0, "dB"), formatter = fmt_raw_db, action = function(x) state.tracks[i].l_low = x; Loopers.refresh(i, state) end}
    params:add{type = "control", id = "l"..i.."_high", name = "High Shelf", controlspec = controlspec.new(-18, 18, 'lin', 0.1, 0.0, "dB"), formatter = fmt_raw_db, action = function(x) state.tracks[i].l_high = x; Loopers.refresh(i, state) end}
    params:add{type = "control", id = "l"..i.."_filter", name = "DJ Filter", controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.5), formatter = fmt_percent, action = function(x) state.tracks[i].l_filter = x; Loopers.refresh(i, state) end}
    params:add{type = "control", id = "l"..i.."_pan", name = "Pan", controlspec = controlspec.new(-1, 1, 'lin', 0.01, 0), formatter = function(p) return string.format("%.2f", p:get()) end, action = function(x) state.tracks[i].l_pan = x; Loopers.refresh(i, state) end}
    params:add{type = "control", id = "l"..i.."_width", name = "Width", controlspec = controlspec.new(0, 2, 'lin', 0.01, 1), formatter = fmt_percent, action = function(x) state.tracks[i].l_width = x; Loopers.refresh(i, state) end}
    -- Hidden params for 16n layer shift (brake continuo, mapped from 16n faders 5-8)
    params:add{type = "control", id = "l"..i.."_brake16", name = "Brake 16n", controlspec = controlspec.new(0, 1, 'lin', 0.01, 0), formatter = fmt_percent, action = function(x) state.tracks[i].brake_amt = x; Loopers.refresh(i, state) end}
    -- Fade out time per track
    params:add{type = "control", id = "l"..i.."_fade_time", name = "Fade Time", controlspec = controlspec.new(0, 30.0, 'lin', 0.1, 0.0, "s"), formatter = fmt_sec}
  end

  -- TAPE LIBRARY
  params:add_group("TAPE LIBRARY", 5)
  params:add{type = "trigger", id = "save_all_tapes", name = "Save All Tapes", action = function()
     for i=1, 4 do
        local len = state.tracks[i].rec_len or 0
        if len > 0.1 then
            local name = _path.audio .. "Airports/snapshots/tape_" .. i .. "_" .. os.date("%y%m%d%H%M") .. ".wav"
            engine.buffer_write(i, name, len)
            state.tape_filenames[i] = name:match("^.+/(.+)$")
            state.tape_msg_timers[i] = util.time() + 2.0
            state.tracks[i].is_dirty = false
            state.tracks[i].file_path = name
            print("Tape " .. i .. " saved: " .. name)
        end
     end
  end}
  params:add{type = "file", id = "load_reel_1", name = "Load Tape 1", path = _path.audio, action = function(f) Loopers.load_file(1, f, state) end}
  params:add{type = "file", id = "load_reel_2", name = "Load Tape 2", path = _path.audio, action = function(f) Loopers.load_file(2, f, state) end}
  params:add{type = "file", id = "load_reel_3", name = "Load Tape 3", path = _path.audio, action = function(f) Loopers.load_file(3, f, state) end}
  params:add{type = "file", id = "load_reel_4", name = "Load Tape 4", path = _path.audio, action = function(f) Loopers.load_file(4, f, state) end}
  
  Grid.init(state, g)
  
  -- Pset save/load hooks
  params.action_write = function(filename, name, number) Storage.save_data(state, number) end
  params.action_read = function(filename, silent, number) Storage.load_data(state, number) end
  
  -- Metros
  local screen_timer = metro.init()
  screen_timer.time = 1/60
  screen_timer.event = function() redraw() end
  screen_timer:start()
  
  local grid_timer = metro.init()
  grid_timer.time = 1/30
  grid_timer.event = function() Grid.redraw(state) end
  grid_timer:start()
  
  local update_timer = metro.init()
  update_timer.time = 0.05
  update_timer.event = function()
    update_morph()
  end
  update_timer:start()
  
  -- Jump hold clock
  clock.run(jump_hold_tick)
  
  -- Sequencer playbacks
  for i=1, 4 do
    clock.run(function() rec_play_tick_tape(i) end)
  end
  
  params:bang()
  
  -- 16n init
  clock.run(function()
     clock.sleep(2.0)
     _16n.init(handle_16n)
     print("16n initialized.")
  end)
  
  -- Load
  clock.run(function()
     clock.sleep(0.5)
     state.loaded = true
      print("Airports loaded (v1.02). 7 input sources, 4 ambient loopers ready.")
  end)
end

-- ============================================================
-- REDRAW
-- ============================================================
function redraw()
  if state.file_selector_active then return end
  if not state.loaded then return end
  screen.clear()
  Graphics.draw(state)
  screen.update()
end