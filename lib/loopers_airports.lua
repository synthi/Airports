-- Airports lib/loopers_airports.lua | Version 1.01
-- Ambient loopers logic (seamless continuous loopers)
-- Adapted from Avant_lab_V lib/loopers.lua

local Loopers = {}
local util = require 'util'
local MAX_BUFFER_SEC = 120.0

local function f(val) return (val or 0) * 1.0 end

function Loopers.load_file(i, path, state)
    if not path or path == "cancel" or path == "" or path == "-" then return end
    if string.sub(path, -1) == "/" then return end
    
    engine.buffer_read(i, path)
    
    state.tracks[i].state = 5
    state.tracks[i].play_pos = 0
    state.tracks[i].loop_start = 0
    state.tracks[i].loop_end = 1
    
    state.tape_filenames[i] = path:match("^.+/(.+)$")
    
    state.tracks[i].is_dirty = false
    state.tracks[i].file_path = path
    
    Loopers.refresh(i, state)
    print("Looper "..i.." loading: "..state.tape_filenames[i])
end

function Loopers.refresh(t_idx, state)
  local t = state.tracks[t_idx]
  if not t then return end
  
  -- Gate logic for states
  local gate_rec = 0.0; local gate_play = 0.0; local send_dub = 0.0
  
  if t.state == 2 then
      gate_rec = 1.0; gate_play = 0.0; send_dub = 0.0
  elseif t.state == 3 then
      gate_rec = 0.0; gate_play = 1.0; send_dub = t.overdub or 1.0
  elseif t.state == 4 then
      gate_rec = 1.0; gate_play = 1.0; send_dub = t.overdub or 1.0
  elseif t.state == 5 then
      -- Safe Stop: motor runs, audio muted, feedback locked to 1.0
      gate_rec = 0.0; gate_play = 0.0; send_dub = 1.0
  elseif t.state == 1 then
      gate_rec = 0.0; gate_play = 0.0; send_dub = 0.0
  end
  
  local sc_start = util.clamp(t.loop_start or 0, 0, 1)
  local sc_end = util.clamp(t.loop_end or 1, 0, 1)
  if sc_end <= sc_start then sc_end = sc_start + 0.001 end
  
  local length = params:get("l"..t_idx.."_length")
  
   local args = {
       f(gate_rec), f(gate_play), f(t.vol or 0.833), f(t.speed or 1.0),
       f(sc_start), f(sc_end), f(t.src_sel), f(send_dub),
       f(t.wow_macro), f(t.brake_amt or 0), f(t.rec_level or -3.0),
       f(length)
   }

  if t_idx == 1 then engine.l1_config(table.unpack(args))
  elseif t_idx == 2 then engine.l2_config(table.unpack(args))
  elseif t_idx == 3 then engine.l3_config(table.unpack(args))
  elseif t_idx == 4 then engine.l4_config(table.unpack(args))
  end
  
  engine.l_low(t_idx, t.l_low or 0)
  engine.l_high(t_idx, t.l_high or 0)
  engine.l_filter(t_idx, t.l_filter or 0.5)
  engine.l_pan(t_idx, t.l_pan or 0)
  engine.l_width(t_idx, t.l_width or 1)
  engine.l_rec_lvl(t_idx, t.rec_level or -3.0)
  engine.l_brake(t_idx, t.brake_amt or 0)
  engine.l_speed(t_idx, t.speed or 1.0)
end

function Loopers.set_speed_slew(idx, target_speed, slew_time, state, start_val_override)
   local t = state.tracks[idx]
   if slew_time < 0.05 then
      t.speed = target_speed
      Loopers.refresh(idx, state)
      return
   end
   clock.run(function()
      local start_speed = start_val_override or t.speed
      local start_time = util.time()
      while true do
         local now = util.time()
         local elapsed = now - start_time
         local progress = elapsed / slew_time
         if progress >= 1.0 then
            t.speed = target_speed
            Loopers.refresh(idx, state)
            break
         end
         t.speed = start_speed + ((target_speed - start_speed) * progress)
         Loopers.refresh(idx, state)
         clock.sleep(0.02)
      end
   end)
end

function Loopers.seek(idx, rel_pos, state)
   if idx == 1 then engine.l1_seek(rel_pos)
   elseif idx == 2 then engine.l2_seek(rel_pos)
   elseif idx == 3 then engine.l3_seek(rel_pos)
   elseif idx == 4 then engine.l4_seek(rel_pos)
   end
end

function Loopers.clear(idx, state)
   local t = state.tracks[idx]
   -- Cancel any running fade
   if t.fade_clock then
      clock.cancel(t.fade_clock)
      t.fade_clock = nil
   end
   t.state = 1; t.rec_len = 0; t.play_pos = 0
   t.loop_start = 0; t.loop_end = 1; t.speed = 1.0; t.overdub = 1.0
   t.wow_macro = 0; t.brake_amt = 0
   t.fade_vca = 1.0
   state.tape_filenames[idx] = nil
   t.is_dirty = false
   t.file_path = nil
   
   -- Reset length to full 120s
   params:set("l"..idx.."_length", MAX_BUFFER_SEC)
   
   if engine.clear then engine.clear(idx) end
   
   Loopers.refresh(idx, state)
   print("Track " .. idx .. " CLEARED")
end

function Loopers.delta_param(param_name, d, state)
   local idx = state.track_sel
   local t = state.tracks[idx]
   if not t then return end
   
   if param_name == "vol" then t.vol = util.clamp((t.vol or 0.833) + d*0.01, 0, 1)
   
   elseif param_name == "speed" then
     local old_s = t.speed or 1
     local s = old_s + (d * 0.01)
     local snap_dist = 0.03
     if math.abs(s) < snap_dist and math.abs(old_s) > 0.001 then s = 0 end
     if math.abs(s - 1.0) < snap_dist and math.abs(old_s - 1.0) > 0.001 then s = 1.0 end
     if math.abs(s + 1.0) < snap_dist and math.abs(old_s + 1.0) > 0.001 then s = -1.0 end
     t.speed = util.clamp(s, -2.0, 2.0)
     
   elseif param_name == "overdub" then
      t.overdub = util.clamp((t.overdub or 1.0) + d*0.01, 0, 1.11)
      params:set("l"..idx.."_dub", t.overdub)
   
   elseif param_name == "degrade" then
      t.wow_macro = util.clamp((t.wow_macro or 0) + d*0.01, 0, 1)
      params:set("l"..idx.."_deg", t.wow_macro)
   
   elseif param_name == "start" then
      local e = t.loop_end or 1
      t.loop_start = util.clamp((t.loop_start or 0) + d*0.005, 0, e - 0.01)
   
   elseif param_name == "end" then
      local s = t.loop_start or 0
      t.loop_end = util.clamp((t.loop_end or 1) + d*0.005, s + 0.01, 1.0)
   
   elseif param_name == "rec_level" then
      t.rec_level = util.clamp((t.rec_level or -3.0) + d*0.5, -60, 12)
   
   elseif param_name == "aux" then
      t.aux_send = util.clamp((t.aux_send or 0) + d*0.01, 0, 1)
   
   elseif param_name == "src_sel" then
       t.src_sel = util.clamp((t.src_sel or 0) + d, 0, 6)
   
   elseif param_name == "jump_rate" then
      t.jump_rate = util.clamp((t.jump_rate or 1.0) + d*0.1, 0.1, 10.0)
   
   elseif param_name == "jump_div" then
      t.jump_div = util.clamp((t.jump_div or 4) + d, 1, 256)
   
   elseif param_name == "jump_sync" then
      t.jump_sync = (t.jump_sync + d) % 2
   
   elseif param_name == "jump_rnd_lpos" then
      t.jump_rnd_lpos = util.clamp((t.jump_rnd_lpos or 0) + d*0.01, 0, 1)
   
   elseif param_name == "brake" then
      t.brake_amt = util.clamp((t.brake_amt or 0) + d*0.01, 0, 1)
   
   elseif param_name == "filter" then
      t.l_filter = util.clamp((t.l_filter or 0.5) + d*0.01, 0, 1)
   
   elseif param_name == "low" then
      t.l_low = util.clamp((t.l_low or 0) + d*0.1, -18, 18)
   
   elseif param_name == "high" then
      t.l_high = util.clamp((t.l_high or 0) + d*0.1, -18, 18)
   
   elseif param_name == "pan" then
      t.l_pan = util.clamp((t.l_pan or 0) + d*0.05, -1, 1)
   
   elseif param_name == "width" then
      t.l_width = util.clamp((t.l_width or 1) + d*0.05, 0, 2)
   end
   Loopers.refresh(idx, state)
end

function Loopers.transport_rec(state, idx, action_type)
   if action_type == "press" then
      local t = state.tracks[idx]
      if t.state == 5 or t.state == 0 or t.state == 1 then
         if t.state == 1 and engine.clear then
             engine.clear(idx); engine["l"..idx.."_seek"](0)
         end
         t.state = 4  -- Overdub (creates loop)
      elseif t.state == 3 then t.state = 4  -- Play -> Dub
      elseif t.state == 4 then t.state = 3  -- Dub -> Play
      elseif t.state == 2 then t.state = 3 end  -- Rec -> Play
      Loopers.refresh(idx, state)
   end
end

function Loopers.randomize_track(idx, state)
   local t = state.tracks[idx]
   if not t then return end
   
   if t.rnd_speed then
      t.speed = math.random() * 4 - 2  -- -2 a 2
   end
   if t.rnd_deg then
      t.wow_macro = math.random()
   end
   if t.rnd_loop then
      local s = math.random() * 0.8
      local e = s + (math.random() * (1 - s))
      t.loop_start = s
      t.loop_end = e
   end
   if t.rnd_eq then
      t.l_low = (math.random() * 36) - 18
      t.l_high = (math.random() * 36) - 18
      t.l_filter = math.random()
      t.l_pan = (math.random() * 2) - 1
      t.l_width = math.random() * 2
   end
   if t.rnd_vol then
      t.vol = math.random() * 0.5 + 0.3
   end
   
   Loopers.refresh(idx, state)
end

function Loopers.stop_with_fade(idx, state)
   local t = state.tracks[idx]
   if not t then return end
   local fade_time = params:get("l"..idx.."_fade_time") or 0
   
   -- Cancel any existing fade
   if t.fade_clock then
      clock.cancel(t.fade_clock)
      t.fade_clock = nil
   end
   
   -- Change state to stop, refresh (volume untouched!)
   t.state = 5
   Loopers.refresh(idx, state)
   
   if fade_time < 0.05 then
      -- Instant: set VCA to 0
      t.fade_vca = 0.0
      engine.l_fade_vca(idx, 0.0)
   else
      -- Gradual fade out: ramp VCA from current value to 0
      -- Proportional time: if VCA=0.625, ramp_time = fade_time * 0.625
      local start_vca = t.fade_vca or 1.0
      local ramp_time = fade_time * start_vca
      local start_time = util.time()
      t.fade_clock = clock.run(function()
         while true do
            local elapsed = util.time() - start_time
            local progress = elapsed / ramp_time
            if progress >= 1.0 then
               t.fade_vca = 0.0
               engine.l_fade_vca(idx, 0.0)
               t.fade_clock = nil
               break
            end
            local vca = start_vca * (1.0 - progress)
            t.fade_vca = vca
            engine.l_fade_vca(idx, vca)
            clock.sleep(0.02)
         end
      end)
   end
end

function Loopers.play_with_fade(idx, state)
   local t = state.tracks[idx]
   if not t then return end
   local fade_time = params:get("l"..idx.."_fade_time") or 0
   
   -- Cancel any existing fade
   if t.fade_clock then
      clock.cancel(t.fade_clock)
      t.fade_clock = nil
   end
   
   -- Change state to play, refresh (volume untouched!)
   t.state = 3
   Loopers.refresh(idx, state)
   
   -- Current VCA position (may be mid-fade from a previous stop)
   local current_vca = t.fade_vca or 0.0
   
   -- Calculate proportional ramp time based on how far we need to go
   local ramp_time = fade_time * (1.0 - current_vca)
   if ramp_time < 0.05 then
      -- Instant: set VCA to 1
      t.fade_vca = 1.0
      engine.l_fade_vca(idx, 1.0)
   else
      -- Gradual fade in: ramp VCA from current to 1.0
      local start_time = util.time()
      t.fade_clock = clock.run(function()
         while true do
            local elapsed = util.time() - start_time
            local progress = elapsed / ramp_time
            if progress >= 1.0 then
               t.fade_vca = 1.0
               engine.l_fade_vca(idx, 1.0)
               t.fade_clock = nil
               break
            end
            local vca = current_vca + ((1.0 - current_vca) * progress)
            t.fade_vca = vca
            engine.l_fade_vca(idx, vca)
            clock.sleep(0.02)
         end
      end)
   end
end

function Loopers.jump(idx, state)
   local t = state.tracks[idx]
   if not t then return end
   
   -- Randomize loop position based on jump_rnd_lpos
   local rnd_offset = (math.random() * 2 - 1) * t.jump_rnd_lpos * 0.1
   local range = t.loop_end - t.loop_start
   local pos = t.loop_start + (math.random() * range)
   pos = util.clamp(pos + rnd_offset, 0, 1)
   
   Loopers.seek(idx, pos, state)
end

return Loopers