-- Airports lib/storage_airports.lua | Version 1.00
-- Pset audio save/load, adapted from Avant_lab_V lib/storage.lua

local Storage = {}
local Loopers = include('lib/loopers_airports')

function Storage.save_data(state, pset_id)
   if not pset_id then return end
   if util.file_exists(_path.data .. "Airports") == false then util.make_dir(_path.data .. "Airports") end
   
   -- Save audio snapshots for dirty tracks
   for i=1, 4 do
      local t = state.tracks[i]
      local len = t.rec_len or 0
      if len > 0.002 then
         if t.is_dirty or not t.file_path then
            local timestamp = os.date("%y%m%d%H%M%S")
            local snap_name = _path.audio .. "Airports/snapshots/reel_" .. i .. "_" .. timestamp .. ".wav"
            engine.buffer_write(i, snap_name, len)
            t.file_path = snap_name
            t.is_dirty = false
            print("Airports: snapshot saved: " .. snap_name)
         end
      else
         t.file_path = nil
         t.is_dirty = false
      end
   end
   
   local filename = _path.data .. "Airports/" .. pset_id .. ".data"
   
   local pack = {
      tracks = state.tracks,
      presets_data = state.presets_data,
      presets_status = state.presets_status,
      preset_selected = state.preset_selected,
      seq_slots = state.seq_slots,
      warp_amount = state.warp_amount,
      warp_mode = state.warp_mode,
      warp_smooth = state.warp_smooth,
      warp_target = state.warp_target
   }
   
   tab.save(pack, filename)
   print("Airports: Saved PSET " .. pset_id)
end

function Storage.load_data(state, pset_id)
   if not pset_id then return end
   local filename = _path.data .. "Airports/" .. pset_id .. ".data"
   
   if util.file_exists(filename) then
      local pack = tab.load(filename)
      if pack then
         -- Sanitize presets data
         if pack.presets_data then
            for i=1, 4 do
               if pack.presets_status and pack.presets_status[i] == 0 then
                  pack.presets_data[i] = {}
               end
               if pack.presets_data[i] and not pack.presets_data[i].tracks then
                  pack.presets_data[i] = {}
                  if pack.presets_status then pack.presets_status[i] = 0 end
               end
            end
         end
         
         -- Restore presets
         state.presets_data = pack.presets_data or state.presets_data
         state.presets_status = pack.presets_status or state.presets_status
         state.preset_selected = pack.preset_selected or 0
         
         -- Restore warp config
         if pack.warp_amount then state.warp_amount = pack.warp_amount end
         if pack.warp_mode then state.warp_mode = pack.warp_mode end
         if pack.warp_smooth then state.warp_smooth = pack.warp_smooth end
         if pack.warp_target then state.warp_target = pack.warp_target end
         
         -- Restore sequencers (stopped state)
         if pack.seq_slots then
            for i=1, 4 do
               if pack.seq_slots[i] then
                  local s = pack.seq_slots[i]
                  if s.data and #s.data > 0 and s.duration and s.duration > 0 then
                     state.seq_slots[i] = {
                        data = s.data,
                        state = 3,  -- Stopped (ready to play)
                        press_time = 0,
                        start_time = 0,
                        step = 1,
                        duration = s.duration
                     }
                  else
                     state.seq_slots[i] = {data={}, state=0, press_time=0, start_time=0, step=1, duration=0}
                  end
               end
            end
         end
         
         -- Restore track state
         local load_behavior_audio = params:get("load_behavior_audio") or 1  -- 1=Stop, 2=Play
         local load_behavior = params:get("load_behavior") or 1
         
         if pack.tracks then
            for i=1, 4 do
               local loaded_t = pack.tracks[i]
               if loaded_t then
                  -- Restore track parameters
                  state.tracks[i].vol = loaded_t.vol or 0.833
                  state.tracks[i].speed = loaded_t.speed or 1.0
                  state.tracks[i].rec_len = loaded_t.rec_len or 0
                  state.tracks[i].loop_start = loaded_t.loop_start or 0
                  state.tracks[i].loop_end = loaded_t.loop_end or 1
                  state.tracks[i].overdub = loaded_t.overdub or 1.0
                  state.tracks[i].wow_macro = loaded_t.wow_macro or 0.0
                  state.tracks[i].src_sel = loaded_t.src_sel or 0
                  state.tracks[i].rec_level = loaded_t.rec_level or -3.0
                  state.tracks[i].brake_amt = loaded_t.brake_amt or 0
                  
                  state.tracks[i].l_low = loaded_t.l_low or 0
                  state.tracks[i].l_high = loaded_t.l_high or 0
                  state.tracks[i].l_filter = loaded_t.l_filter or 0.5
                  state.tracks[i].l_pan = loaded_t.l_pan or 0
                  state.tracks[i].l_width = loaded_t.l_width or 1
                  
                  state.tracks[i].jump_rate = loaded_t.jump_rate or 1.0
                  state.tracks[i].jump_div = loaded_t.jump_div or 4
                  state.tracks[i].jump_sync = loaded_t.jump_sync or 0
                  state.tracks[i].jump_rnd_lpos = loaded_t.jump_rnd_lpos or 0
                  
                  state.tracks[i].rnd_speed = loaded_t.rnd_speed ~= nil and loaded_t.rnd_speed or true
                  state.tracks[i].rnd_deg = loaded_t.rnd_deg ~= nil and loaded_t.rnd_deg or true
                  state.tracks[i].rnd_loop = loaded_t.rnd_loop ~= nil and loaded_t.rnd_loop or false
                  state.tracks[i].rnd_eq = loaded_t.rnd_eq ~= nil and loaded_t.rnd_eq or false
                  state.tracks[i].rnd_vol = loaded_t.rnd_vol ~= nil and loaded_t.rnd_vol or false
                  
                  state.tracks[i].fade_out = loaded_t.fade_out or 0
                  
                  -- Update Params to match State
                  params:set("l"..i.."_vol", state.tracks[i].vol)
                  params:set("l"..i.."_speed", state.tracks[i].speed)
                  params:set("l"..i.."_dub", state.tracks[i].overdub)
                  params:set("l"..i.."_deg", state.tracks[i].wow_macro)
                  params:set("l"..i.."_src", state.tracks[i].src_sel + 1)
                  params:set("l"..i.."_rec_lvl", state.tracks[i].rec_level)
                  params:set("l"..i.."_low", state.tracks[i].l_low)
                  params:set("l"..i.."_high", state.tracks[i].l_high)
                  params:set("l"..i.."_filter", state.tracks[i].l_filter)
                  params:set("l"..i.."_pan", state.tracks[i].l_pan)
                  params:set("l"..i.."_width", state.tracks[i].l_width)
                  
                  -- Load audio if file exists
                  if loaded_t.file_path and util.file_exists(loaded_t.file_path) then
                     engine.buffer_read(i, loaded_t.file_path)
                     state.tracks[i].file_path = loaded_t.file_path
                     state.tracks[i].is_dirty = false
                     state.tape_filenames[i] = loaded_t.file_path:match("^.+/(.+)$")
                     
                if load_behavior_audio == 2 then
                       -- Play on load
                       if loaded_t.state == 2 or loaded_t.state == 3 or loaded_t.state == 4 then
                          state.tracks[i].state = 3  -- Play
                       else
                          state.tracks[i].state = 5  -- Stop
                       end
                    else
                       state.tracks[i].state = 5  -- Stop
                    end
                  else
                     state.tracks[i].state = 1  -- Empty
                     state.tracks[i].file_path = nil
                     state.tape_filenames[i] = nil
                  end
                  
                  Loopers.refresh(i, state)
               end
            end
         end
         
         print("Airports: Loaded PSET " .. pset_id)
      else
         print("Airports: No data file found.")
      end
   end
end

return Storage