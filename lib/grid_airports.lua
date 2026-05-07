-- Airports lib/grid_airports.lua | Version 1.02
-- Monome Grid 16x8 interface for Airports

local Grid = {}
local Loopers = include('lib/loopers_airports')
local g -- Grid device reference

local next_frame = {}
for x=1, 16 do next_frame[x] = {}; for y=1, 8 do next_frame[x][y] = 0 end end

local MAX_BRIGHT = 15
local MED_BRIGHT = 8
local DIM_BRIGHT = 3

local VS_VALS = {-2.0, -1.5, -1.0, -0.5, -0.25, 0.0, 0.25, 0.5, 1.0, 1.5, 2.0}

function Grid.init(state, device)
  g = device
  if g then g:all(0); g:refresh() end
  state.grid_keys_held = {}
  for i=1, 4 do state.grid_keys_held[i] = {} end
  state.seek_memory = {}
  state.ribbon_memory = {}
  state.ribbon_press_time = 0
  state.ribbon_start_speed = 1.0
  state.ribbon_target_speed = 1.0
  state.transport_press_time = {0, 0, 0, 0}
  state.preset_press_time = {0, 0, 0, 0}
  for i=1, 4 do state.seq_slots[i] = {data={}, state=0, press_time=0, start_time=0, step=1, duration=0} end
end

local function led_buf(x, y, val)
   if x >=1 and x <=16 and y >=1 and y <=8 then
      next_frame[x][y] = math.floor(val)
   end
end

-- Draw loopers rows (Y=1-4)
local function draw_loopers(state)
  local now = util.time()
  local rec_pulse = math.floor(util.linlin(-1, 1, 0, 5, math.sin(now * 8)))
  local dub_pulse = math.floor(util.linlin(-1, 1, 0, 4, math.sin(now * 4)))
  rec_pulse = util.clamp(rec_pulse, 0, DIM_BRIGHT)
  dub_pulse = util.clamp(dub_pulse, 0, DIM_BRIGHT)

  for t=1, 4 do
    local track = state.tracks[t]
    local bg_bright = 0
    if track.state == 2 then bg_bright = rec_pulse
    elseif track.state == 4 then bg_bright = dub_pulse
    end
    
    local s = math.floor((track.loop_start or 0) * 15) + 1
    local e = math.floor((track.loop_end or 1) * 15) + 1
    
    local has_audio = (track.state == 2 or track.state == 3 or track.state == 4)
    local head_pos = (track.play_pos or 0) * 15 + 1
    local head_max_b = 0
    if has_audio then head_max_b = MAX_BRIGHT
    elseif track.state == 1 then head_pos = 1; head_max_b = DIM_BRIGHT end

    for x=1, 16 do
       local b = bg_bright
       if x == s or x == e then b = math.max(b, 5) end
       
       if head_max_b > 0 then
          local dist = math.abs(x - head_pos)
          if dist > 8 then dist = 16 - dist end
          if dist < 1.5 then
             local intensity = (1.0 - (dist / 1.5)) ^ 2.3
             local pixel_b = math.floor(head_max_b * intensity)
             b = math.max(b, pixel_b)
          end
       end
       led_buf(x, t, b)
    end
  end
end

-- Draw row 5: Track select + Speed ribbon
local function draw_row5(state)
  local now = util.time()
  local sel_pulse = math.floor(util.linlin(-1, 1, 10, MAX_BRIGHT, math.sin(now * 8)))
  
  -- Track select (X=1-4)
  for i=1, 4 do
     local b = 3
     if state.track_sel == i then b = sel_pulse end
     if state.grid_track_held and state.track_sel == i then b = MAX_BRIGHT end
     led_buf(i, 5, b)
  end
  
  -- Separator (X=5)
  led_buf(5, 5, 0)
  
  -- Speed ribbon (X=6-16)
  local t = state.tracks[state.track_sel]
  local s = t.speed or 1
  for i=1, 11 do
     local val = VS_VALS[i]
     local x = i + 5
     local b = DIM_BRIGHT
     if math.abs(s - val) < 0.01 then b = MAX_BRIGHT
     elseif (s > 0 and val > 0 and s >= val) or (s < 0 and val < 0 and s <= val) then b = MED_BRIGHT
     elseif val == 0 and math.abs(s) < 0.01 then b = MAX_BRIGHT end
     led_buf(x, 5, b)
  end
end

-- Draw row 6: Transport + Jump + Random + Warp
local function draw_row6(state)
  local now = util.time()
  local pulse_rec = math.floor(math.sin(now * 8) * 4 + 7)
  local pulse_dub = math.floor(math.sin(now * 4) * 3 + 6)
  
  -- Transport (X=1-4)
  for i=1, 4 do
     local trk = state.tracks[i]; local b = 1
     if trk.state == 1 then b = 1
     elseif trk.state == 2 then b = pulse_rec
     elseif trk.state == 4 then b = pulse_dub
     elseif trk.state == 3 then b = 8
     elseif trk.state == 5 then b = 4 end
     led_buf(i, 6, b)
  end
  
  -- Separator (X=5)
  led_buf(5, 6, 0)
  
  -- Jump (X=6-9) — un botón por track
  for i=1, 4 do
     local x = i + 5
     local b = DIM_BRIGHT
     if state.tracks[i].jump_held then
        -- Parpadea al rate del jump
        local rate = state.tracks[i].jump_rate or 1.0
        if state.tracks[i].jump_sync == 0 then
           b = math.floor(util.linlin(-1, 1, DIM_BRIGHT, MAX_BRIGHT, math.sin(now * rate * 4)))
        else
           b = math.floor(util.linlin(-1, 1, DIM_BRIGHT, MAX_BRIGHT, math.sin(now * 2)))
        end
     end
     led_buf(x, 6, b)
  end
  
  -- Separator (X=10)
  led_buf(10, 6, 0)
  
  -- Random (X=11-14)
  for i=1, 4 do
     local x = i + 10
     led_buf(x, 6, DIM_BRIGHT)
  end
  
  -- Separator (X=15)
  led_buf(15, 6, 0)
  
  -- Warp (X=16)
  led_buf(16, 6, state.tracks[state.track_sel].warp_active and MAX_BRIGHT or DIM_BRIGHT)
end

-- Draw row 7: Brake (4 niveles × 4 tracks)
local function draw_row7(state)
  for i=1, 16 do
     local track_idx = math.floor((i-1)/4) + 1
     local intensity_idx = (i-1)%4
     local brightness = 2 + (intensity_idx * 3)
     if state.tracks[track_idx].brake_amt and state.tracks[track_idx].brake_amt > 0 then
        local active_intensity = math.floor(state.tracks[track_idx].brake_amt * 4) - 1
        if active_intensity == intensity_idx then brightness = MAX_BRIGHT end
     end
     led_buf(i, 7, brightness)
  end
end

-- Draw row 8: MOM + SHIFT + SEQS + PRESETS + Pages
local function draw_row8(state)
  local now = util.time()
  local pulse_seq = math.floor(math.sin(now * 5) * 4 + 7)
  
  -- MOM (X=1)
  led_buf(1, 8, state.grid_momentary_mode and MAX_BRIGHT or 4)
  
  -- SHIFT (X=2)
  led_buf(2, 8, state.grid_shift_active and MAX_BRIGHT or 0)
  
  -- Sequencers (X=3-6)
  for i=1, 4 do
     local r = state.seq_slots[i]; local b = 1
     if r.state == 1 then b = pulse_seq
     elseif r.state == 2 then b = MAX_BRIGHT
     elseif r.state == 4 then b = math.floor(util.linlin(-1, 1, 2, 6, math.sin(now * 2)))
     elseif r.state == 3 then b = 4 end
     led_buf(i + 2, 8, b)
  end
  
  -- Separator (X=7)
  led_buf(7, 8, 0)
  
  -- Presets (X=8-11)
  for i=1, 4 do
     local x = i + 7
     local st = state.presets_status[i]
     local b = DIM_BRIGHT
     if st == 1 then b = MED_BRIGHT end
     if state.preset_selected == i then b = MAX_BRIGHT end
     if state.preset_morph_active and state.preset_morph_slot == i then b = MAX_BRIGHT end
     led_buf(x, 8, b)
  end
  
  -- Separator (X=12)
  led_buf(12, 8, 0)
  
  -- Page selects (X=13-16)
  for i=1, 4 do
     local page_num = i + 6  -- 7, 8, 9, 10
     local x = i + 12
     local is_sel = (state.current_page == page_num)
     led_buf(x, 8, is_sel and MAX_BRIGHT or DIM_BRIGHT)
  end
end

function Grid.redraw(state)
  if not g or not g.device then return end
  for x=1, 16 do for y=1, 8 do next_frame[x][y] = 0 end end
  
  if not state.loaded then return end
  
  -- Draw all rows
  draw_loopers(state)
  draw_row5(state)
  draw_row6(state)
  draw_row7(state)
  draw_row8(state)
  
  -- Send to grid (only changed LEDs)
  for x=1, 16 do
     for y=1, 8 do
        local new_val = next_frame[x][y]
        if state.grid_cache[x][y] ~= new_val then
           g:led(x, y, new_val)
           state.grid_cache[x][y] = new_val
        end
     end
  end
  g:refresh()
end

-- Record events for sequencers
local function record_event(state, x, y, z)
  for i=1, 4 do
    local r = state.seq_slots[i]
    if r.state == 2 then  -- Recording
       local now = util.time()
       local dt = now - r.start_time
       table.insert(r.data, {dt=dt, x=x, y=y, z=z, tid=state.track_sel})
       table.sort(r.data, function(a,b) return a.dt < b.dt end)
    end
  end
end

-- Handle micro-loops on track rows (Y=1-4)
local function handle_looper_touch(state, x, y, z)
  local trk = y
  if z == 1 then
     state.grid_keys_held[trk][x] = true
     state.grid_track_held = true
     state.track_sel = trk
     
     -- Reset 16n latches for layer switch
     for i=1, 4 do state.fader_latched[i] = false end
     
     clock.run(function()
        clock.sleep(0.06)
        local count = 0; local min_x = 17; local max_x = 0
        for k, v in pairs(state.grid_keys_held[trk]) do if v then count = count + 1; if k < min_x then min_x = k end; if k > max_x then max_x = k end end end
        
        if count == 1 then
           if state.grid_keys_held[trk][x] then
              local pos = (x-1)/15
              local t = state.tracks[trk]
              state.seek_memory[trk] = {start_p = t.loop_start or 0, end_p = t.loop_end or 1}
              local buf_len = params:get("l"..trk.."_length") or 10.0
              local rand_ms = math.random(80, 180) / 1000.0
              local frac = rand_ms / buf_len
              t.loop_start = pos; t.loop_end = math.min(pos + frac, 1.0)
              Loopers.refresh(trk, state); engine["l"..trk.."_seek"](pos)
           end
        elseif count >= 2 then
           state.tracks[trk].loop_start = (min_x - 1) / 15
           state.tracks[trk].loop_end = (max_x - 1) / 15
           Loopers.refresh(trk, state)
        end
     end)
  elseif z == 0 then
     state.grid_keys_held[trk][x] = nil
     local any_held = false
     for k,v in pairs(state.grid_keys_held[trk]) do if v then any_held = true end end
     if not any_held then
         state.grid_track_held = false
         for i=1, 4 do state.fader_latched[i] = false end
     end
     
     local count = 0; for k,v in pairs(state.grid_keys_held[trk]) do if v then count=count+1 end end
     if count == 0 and state.seek_memory[trk] then
         local t = state.tracks[trk]; local mem = state.seek_memory[trk]
         t.loop_start = mem.start_p; t.loop_end = mem.end_p
         Loopers.refresh(trk, state); state.seek_memory[trk] = nil
     end
  end
end

-- Check if event should be recorded by sequencers
local function is_recordable(x, y, is_page_nav)
  -- Don't record: page buttons (Y=8, X=13-16)
  if y == 8 and x >= 13 then return false end
  -- Don't record: SHIFT (Y=8, X=2)
  if y == 8 and x == 2 then return false end
  -- Don't record: MOMENTARY (Y=8, X=1)
  if y == 8 and x == 1 then return false end
  -- Don't record: SEQUENCER buttons (Y=8, X=3-6) — CRITICAL: prevents self-re-triggering
  if y == 8 and x >= 3 and x <= 6 then return false end
  -- Don't record: Track Select (Y=5, X=1-4)
  if y == 5 and x >= 1 and x <= 4 then return false end
  -- YES record presets (Y=8, X=8-11), transport, speed, brake, jump, random, warp, looper touch
  return true
end

function Grid.key(x, y, z, state, engine, simulated_page, target_track)
   local now = util.time()
   local is_physical = (simulated_page == nil)
   
   -- Debounce (only for physical events)
   if is_physical then
      if z == 1 then
         local last = state.grid_debounce[x][y] or 0
         if (now - last) < 0.05 then return end
         state.grid_debounce[x][y] = now
         state.button_state[x][y] = true
      elseif z == 0 then
         if not state.button_state[x][y] then return end
         state.button_state[x][y] = false
      end
   end
   
   -- Record event for sequencers (only physical events)
   if is_physical then
      local is_page_nav = (y == 8 and x >= 13)
      if is_recordable(x, y, is_page_nav) then
         record_event(state, x, y, z)
      end
   end
  
  -- =====================
  -- ROW 8: MOM, SHIFT, SEQS, PRESETS, PAGES
  -- =====================
  if y == 8 then
     -- SHIFT (X=2)
     if x == 2 then
        state.grid_shift_active = (z == 1)
        if z == 0 then
           -- Close config page if leaving shift
           if state.config_page_active then
              state.config_page_active = false
              state.current_page = state.config_previous_page
              state.config_page_type = ""
           end
        end
        return
     end
     
     -- MOMENTARY (X=1)
     if x == 1 and z == 1 then
        state.grid_momentary_mode = not state.grid_momentary_mode
        return
     end
     
     -- SEQUENCERS (X=3-6)
     if x >= 3 and x <= 6 then
        local slot = x - 2
        if z == 1 then
           if state.seq_slots[slot].state == 0 then
              state.seq_slots[slot].state = 1  -- Arm
           elseif state.seq_slots[slot].state == 1 then
              state.seq_slots[slot].state = 2  -- Record
              state.seq_slots[slot].start_time = now
              state.seq_slots[slot].data = {}
              state.seq_slots[slot].step = 1
              state.seq_slots[slot].duration = 0
           elseif state.seq_slots[slot].state == 2 then
              state.seq_slots[slot].state = 4  -- Play
              state.seq_slots[slot].duration = now - state.seq_slots[slot].start_time
              if state.seq_slots[slot].duration < 0.001 then state.seq_slots[slot].duration = 1 end
           elseif state.seq_slots[slot].state == 4 then
              state.seq_slots[slot].state = 2  -- Re-record
              state.seq_slots[slot].start_time = now
              state.seq_slots[slot].data = {}
              state.seq_slots[slot].step = 1
           end
        elseif z == 0 then
           -- Hold > 1s clears seq
           local hold_time = now - state.grid_debounce[x][y]
           if hold_time > 1.0 and state.seq_slots[slot].state ~= 0 then
              state.seq_slots[slot].state = 0
              state.seq_slots[slot].data = {}
              state.seq_slots[slot].duration = 0
           end
        end
        -- Update sequencer_active flag
        local any_active = false
        for i=1, 4 do if state.seq_slots[i].state == 4 then any_active = true end end
        state.sequencer_active = any_active
        return
     end
     
     -- PRESETS (X=8-11)
     if x >= 8 and x <= 11 then
        local slot = x - 7
        if z == 1 then
           state.preset_press_time[slot] = now
           
           if state.presets_status[slot] == 0 then
              -- Save new preset
              local saved = {}
              local t = state.tracks[1]
              saved[1] = {speed=t.speed, vol=t.vol, loop_start=t.loop_start, loop_end=t.loop_end, state=t.state, overdub=t.overdub, wow_macro=t.wow_macro, l_low=t.l_low, l_high=t.l_high, l_filter=t.l_filter, l_pan=t.l_pan, l_width=t.l_width, jump_rate=t.jump_rate, jump_div=t.jump_div, jump_sync=t.jump_sync, jump_rnd_lpos=t.jump_rnd_lpos}
              t = state.tracks[2]
              saved[2] = {speed=t.speed, vol=t.vol, loop_start=t.loop_start, loop_end=t.loop_end, state=t.state, overdub=t.overdub, wow_macro=t.wow_macro, l_low=t.l_low, l_high=t.l_high, l_filter=t.l_filter, l_pan=t.l_pan, l_width=t.l_width, jump_rate=t.jump_rate, jump_div=t.jump_div, jump_sync=t.jump_sync, jump_rnd_lpos=t.jump_rnd_lpos}
              t = state.tracks[3]
              saved[3] = {speed=t.speed, vol=t.vol, loop_start=t.loop_start, loop_end=t.loop_end, state=t.state, overdub=t.overdub, wow_macro=t.wow_macro, l_low=t.l_low, l_high=t.l_high, l_filter=t.l_filter, l_pan=t.l_pan, l_width=t.l_width, jump_rate=t.jump_rate, jump_div=t.jump_div, jump_sync=t.jump_sync, jump_rnd_lpos=t.jump_rnd_lpos}
              t = state.tracks[4]
              saved[4] = {speed=t.speed, vol=t.vol, loop_start=t.loop_start, loop_end=t.loop_end, state=t.state, overdub=t.overdub, wow_macro=t.wow_macro, l_low=t.l_low, l_high=t.l_high, l_filter=t.l_filter, l_pan=t.l_pan, l_width=t.l_width, jump_rate=t.jump_rate, jump_div=t.jump_div, jump_sync=t.jump_sync, jump_rnd_lpos=t.jump_rnd_lpos}
              state.presets_data[slot] = {tracks = saved}
              state.presets_status[slot] = 1
              state.preset_selected = slot
              
           elseif state.preset_selected == slot and not state.sequencer_active then
              -- Resave (only if seq not active)
              local saved = {}
              local t = state.tracks[1]
              saved[1] = {speed=t.speed, vol=t.vol, loop_start=t.loop_start, loop_end=t.loop_end, state=t.state, overdub=t.overdub, wow_macro=t.wow_macro, l_low=t.l_low, l_high=t.l_high, l_filter=t.l_filter, l_pan=t.l_pan, l_width=t.l_width, jump_rate=t.jump_rate, jump_div=t.jump_div, jump_sync=t.jump_sync, jump_rnd_lpos=t.jump_rnd_lpos}
              t = state.tracks[2]
              saved[2] = {speed=t.speed, vol=t.vol, loop_start=t.loop_start, loop_end=t.loop_end, state=t.state, overdub=t.overdub, wow_macro=t.wow_macro, l_low=t.l_low, l_high=t.l_high, l_filter=t.l_filter, l_pan=t.l_pan, l_width=t.l_width, jump_rate=t.jump_rate, jump_div=t.jump_div, jump_sync=t.jump_sync, jump_rnd_lpos=t.jump_rnd_lpos}
              t = state.tracks[3]
              saved[3] = {speed=t.speed, vol=t.vol, loop_start=t.loop_start, loop_end=t.loop_end, state=t.state, overdub=t.overdub, wow_macro=t.wow_macro, l_low=t.l_low, l_high=t.l_high, l_filter=t.l_filter, l_pan=t.l_pan, l_width=t.l_width, jump_rate=t.jump_rate, jump_div=t.jump_div, jump_sync=t.jump_sync, jump_rnd_lpos=t.jump_rnd_lpos}
              t = state.tracks[4]
              saved[4] = {speed=t.speed, vol=t.vol, loop_start=t.loop_start, loop_end=t.loop_end, state=t.state, overdub=t.overdub, wow_macro=t.wow_macro, l_low=t.l_low, l_high=t.l_high, l_filter=t.l_filter, l_pan=t.l_pan, l_width=t.l_width, jump_rate=t.jump_rate, jump_div=t.jump_div, jump_sync=t.jump_sync, jump_rnd_lpos=t.jump_rnd_lpos}
              state.presets_data[slot] = {tracks = saved}
              
           elseif not (state.sequencer_active and state.preset_selected == slot) then
              -- Load preset (allow load even if seq active, but not if currently selected and seq active)
              local target = state.presets_data[slot]
              if target and target.tracks then
                 -- Save current state for morph
                 state.preset_morph_src = {}
                 for i=1, 4 do
                    state.preset_morph_src[i] = {speed=state.tracks[i].speed, vol=state.tracks[i].vol, loop_start=state.tracks[i].loop_start, loop_end=state.tracks[i].loop_end, state=state.tracks[i].state, overdub=state.tracks[i].overdub, wow_macro=state.tracks[i].wow_macro, l_low=state.tracks[i].l_low, l_high=state.tracks[i].l_high, l_filter=state.tracks[i].l_filter, l_pan=state.tracks[i].l_pan, l_width=state.tracks[i].l_width}
                 end
                 state.preset_morph_active = true
                 state.preset_morph_slot = slot
                 state.preset_morph_start_time = now
                 state.preset_selected = slot
                 
                 -- Immediate apply (morph will transition over time)
                 for i=1, 4 do
                    local td = target.tracks[i]
                    if td then
                       state.tracks[i].speed = td.speed
                       state.tracks[i].vol = td.vol
                       state.tracks[i].loop_start = td.loop_start
                       state.tracks[i].loop_end = td.loop_end
                       state.tracks[i].overdub = td.overdub
                       state.tracks[i].wow_macro = td.wow_macro
                       if td.state then state.tracks[i].state = td.state end
                       if td.l_low then state.tracks[i].l_low = td.l_low end
                       if td.l_high then state.tracks[i].l_high = td.l_high end
                       if td.l_filter then state.tracks[i].l_filter = td.l_filter end
                       if td.l_pan then state.tracks[i].l_pan = td.l_pan end
                       if td.l_width then state.tracks[i].l_width = td.l_width end
                       if td.jump_rate then state.tracks[i].jump_rate = td.jump_rate end
                       if td.jump_div then state.tracks[i].jump_div = td.jump_div end
                       if td.jump_sync then state.tracks[i].jump_sync = td.jump_sync end
                       if td.jump_rnd_lpos then state.tracks[i].jump_rnd_lpos = td.jump_rnd_lpos end
                       Loopers.refresh(i, state)
                    end
                 end
              end
           end
        elseif z == 0 then
           local hold_time = now - state.preset_press_time[slot]
           if state.presets_status[slot] == 1 and hold_time > 1.0 and not state.sequencer_active then
              state.presets_status[slot] = 0
              state.presets_data[slot] = {}
              if state.preset_selected == slot then state.preset_selected = 0 end
           end
        end
        return
     end
     
      -- PAGE SELECTS (X=13-16) — Held = Shift mode (like Avant_lab_V)
      if x >= 13 and x <= 16 then
         if z == 1 then
            state.grid_shift_active = true
            state.current_page = x - 6  -- Maps 13→7, 14→8, 15→9, 16→10
         elseif z == 0 then
            state.grid_shift_active = false
         end
         return
      end
     
     return
  end
  
  -- =====================
  -- ROW 7: BRAKE
  -- =====================
  if y == 7 then
     local trk_idx = math.floor((x-1)/4) + 1
     local intensity = (x-1)%4 + 1
     local amt = intensity * 0.25
     if z == 1 then
        state.tracks[trk_idx].brake_amt = math.max(state.tracks[trk_idx].brake_amt or 0, amt)
     elseif z == 0 then
        state.tracks[trk_idx].brake_amt = 0
     end
     Loopers.refresh(trk_idx, state)
     return
  end
  
  -- =====================
  -- ROW 6: TRANSPORT, JUMP, RANDOM, WARP
  -- =====================
  if y == 6 then
     -- TRANSPORT (X=1-4)
     if x >= 1 and x <= 4 then
        local trk = x
        if z == 1 then
           state.transport_press_time[trk] = now
           
           -- Shift + Transport = toggle Play/Stop
           if state.grid_shift_active or state.grid_track_held then
              local current = state.tracks[trk].state
              local next_st = 5
              if current == 5 then next_st = 3 end
              state.tracks[trk].state = next_st
              Loopers.refresh(trk, state)
              return
           end
        elseif z == 0 then
           local hold_time = now - state.transport_press_time[trk]
           if state.grid_shift_active or state.grid_track_held then return end
           
           if hold_time > 1.0 then
              Loopers.clear(trk, state)
           else
              local st = state.tracks[trk].state
              local next_st = 3
              
              -- Auto-loop timeout logic
              if state.tracks[trk].first_pass then
                  local rec_dur = now - (state.tracks[trk].rec_start_time or now)
                  local max_len = params:get("l"..trk.."_length")
                  if rec_dur > max_len then state.tracks[trk].first_pass = false end
              end
              
              -- State machine
              if st == 0 or st == 1 then
                 if st == 1 and engine.clear then
                     engine.clear(trk); engine["l"..trk.."_seek"](0)
                 end
                 state.tracks[trk].first_pass = true
                 state.tracks[trk].rec_start_time = now
                 next_st = 4
              elseif st == 5 then
                 state.tracks[trk].first_pass = false
                 next_st = 3
              elseif st == 4 and state.tracks[trk].first_pass then
                 local dur = now - (state.tracks[trk].rec_start_time or now)
                 params:set("l"..trk.."_length", dur + 0.15)
                 state.tracks[trk].first_pass = false
                 next_st = 4
              elseif st == 3 then
                 next_st = 4
              elseif st == 4 then
                 next_st = 3
              elseif st == 2 then
                 next_st = 3
              end
              
              state.tracks[trk].state = next_st
              Loopers.refresh(trk, state)
           end
        end
        return
     end
     
     -- JUMP (X=6-9)
     if x >= 6 and x <= 9 then
        local trk = x - 5
        if z == 1 then
           if state.grid_shift_active then
              -- Shift+Jump: Open jump config page
              state.config_previous_page = state.current_page
              state.current_page = 6  -- TRICKS page
              state.config_page_active = true
              state.config_page_type = "jump"
              state.config_page_cursor = 1
           else
              -- Momentary jump
              state.tracks[trk].jump_held = true
              state.tracks[trk].jump_hold_start = now
              Loopers.jump(trk, state)
           end
        elseif z == 0 then
           state.tracks[trk].jump_held = false
        end
        return
     end
     
     -- RANDOM (X=11-14)
     if x >= 11 and x <= 14 then
        local trk = x - 10
        if z == 1 then
           if state.grid_shift_active then
              -- Shift+Random: Open random config page
              state.config_previous_page = state.current_page
              state.current_page = 6
              state.config_page_active = true
              state.config_page_type = "random"
              state.config_page_cursor = 1
           else
              Loopers.randomize_track(trk, state)
           end
        end
        return
     end
     
     -- WARP (X=16)
     if x == 16 then
        if z == 1 then
           if state.grid_shift_active then
              -- Shift+Warp: Open warp config page
              state.config_previous_page = state.current_page
              state.current_page = 6
              state.config_page_active = true
              state.config_page_type = "warp"
              state.config_page_cursor = 1
           else
              -- Apply warp to all tracks
              for i=1, 4 do
                 local t = state.tracks[i]
                 state.tracks[i].warp_original_speeds[i] = t.speed
                 if state.warp_mode == 0 then
                    t.speed = util.clamp(t.speed * state.warp_amount, -2, 2)
                 else
                    t.speed = util.clamp(t.speed / state.warp_amount, -2, 2)
                 end
                 state.tracks[i].warp_active = true
                 Loopers.refresh(i, state)
              end
           end
        elseif z == 0 then
           -- Restore original speeds
           for i=1, 4 do
              if state.tracks[i].warp_active then
                 local orig = state.tracks[i].warp_original_speeds[i] or 1.0
                 if state.warp_smooth < 0.1 then
                    state.tracks[i].speed = orig
                 else
                    Loopers.set_speed_slew(i, orig, state.warp_smooth, state, state.tracks[i].speed)
                 end
                 state.tracks[i].warp_active = false
                 Loopers.refresh(i, state)
              end
           end
        end
        return
     end
     return
  end
  
  -- =====================
  -- ROW 5: TRACK SELECT + SPEED RIBBON
  -- =====================
  if y == 5 then
     -- Track Select (X=1-4)
     if x >= 1 and x <= 4 then
        if z == 1 then
           state.track_sel = x
           state.grid_track_held = true
           for i=1, 4 do state.fader_latched[i] = false end
        elseif z == 0 then
           state.grid_track_held = false
           for i=1, 4 do state.fader_latched[i] = false end
        end
        return
     end
     
     -- Speed Ribbon (X=6-16)
     if x >= 6 then
        local idx = x - 5
        local tgt_speed = VS_VALS[idx] or 1.0
        local target = state.track_sel
        if z == 1 then
           state.ribbon_press_time = now
           state.ribbon_start_speed = state.tracks[target].speed or 1.0
           if state.grid_momentary_mode and not state.ribbon_memory[target] then
              state.ribbon_memory[target] = state.tracks[target].speed
           end
           state.ribbon_target_speed = tgt_speed
           if state.grid_momentary_mode then
              Loopers.set_speed_slew(target, state.ribbon_target_speed, 0.07, state, state.ribbon_start_speed)
           end
        elseif z == 0 then
           if state.grid_momentary_mode and state.ribbon_memory[target] then
              Loopers.set_speed_slew(target, state.ribbon_memory[target], 0.1, state, state.tracks[target].speed)
              state.ribbon_memory[target] = nil
           else
              if not state.grid_momentary_mode then
                 local dur = now - state.ribbon_press_time
                  local slew = 0
                  if dur < 0.15 then slew = 0.1
                 elseif dur < 2.0 then slew = util.linlin(0.15, 2.0, 0.5, 2.0, dur)
                 elseif dur < 3.0 then slew = 5.0
                 else slew = 8.0 end
                 Loopers.set_speed_slew(target, state.ribbon_target_speed, slew, state, state.ribbon_start_speed)
              end
           end
        end
        return
     end
     return
  end
  
  -- =====================
  -- ROW 1-4: LOOPER TOUCH (Micro-loops)
  -- =====================
  if y >= 1 and y <= 4 then
     handle_looper_touch(state, x, y, z)
     return
  end
end

-- Seq playback function
function Grid.seq_tick(slot, state)
   clock.run(function()
      while true do
         local r = state.seq_slots[slot]
         if r.state ~= 2 and r.state ~= 4 then
            clock.sleep(0.1)
         else
            local event = r.data[r.step]
            if event then
            local rate = 1.0
               local next_time = 0
               if r.step < #r.data then
                  next_time = (r.data[r.step+1].dt - event.dt) / rate
               else
                  if r.state == 4 then
                     next_time = (r.duration - event.dt) / rate
                  else
                     -- Recording: will get more events
                     clock.sleep(0.05)
                  end
               end
               if next_time > 0 and next_time < 60 then
                  if event.x and event.y and event.z then
                     Grid.key(event.x, event.y, event.z, state, engine, true, event.tid)
                  end
                  clock.sleep(next_time)
               end
               r.step = r.step + 1
               if r.step > #r.data then r.step = 1 end
            else
               clock.sleep(0.1)
            end
         end
      end
   end)
end

return Grid