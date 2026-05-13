-- Airports lib/globals_airports.lua | Version 1.00
-- Estado global del script Airports

local Globals = {}

function Globals.new()
  local s = {}
  
  s.loaded = false
  s.amp_l = 0.0; s.amp_r = 0.0; s.comp_gr = 0.0
  
  -- Grid cache y estado
  s.grid_cache = {}
  s.grid_debounce = {}
  s.button_state = {}
  for i=1, 16 do
     s.grid_cache[i] = {}
     s.grid_debounce[i] = {}
     s.button_state[i] = {}
     for y=1, 8 do
        s.grid_cache[i][y] = -1
        s.grid_debounce[i][y] = 0
        s.button_state[i][y] = false
     end
  end
  
  -- Estado de tracks
  s.track_sel = 1
  s.tracks = {}
  for i=1, 4 do
    s.tracks[i] = {
      state = 1, rec_len = 0.0, play_pos = 0.0,
      loop_start = 0.0, loop_end = 1.0, speed = 1.0,
      vol = 0.833, rec_level = -3.0, overdub = 1.0,
      wow_macro = 0.0, aux_send = 0.0, src_sel = 0,
      brake_amt = 0.0,
      is_dirty = false, file_path = nil,
      l_low = 0.0, l_high = 0.0, l_filter = 0.5, l_pan = 0.0, l_width = 1.0,
      recording_active = false,
      ignore_neg_pointer = false,
      -- Jump params
      jump_rate = 1.0,
      jump_div = 4,
      jump_sync = 0,  -- 0=FREE, 1=SYNC
      jump_rnd_lpos = 0.0,
      -- Jump active state
      jump_held = false,
      jump_hold_start = 0,
      -- Warp state
      warp_active = false,
      warp_original_speeds = {},
      -- Random config
      rnd_speed = true,
      rnd_deg = true,
      rnd_loop = false,
      rnd_eq = false,
      rnd_vol = false,
      rnd_speed_mode = 1,  -- 1=Free, 2=Octaves, 3=Oct+5th, 4=Semitones, 5=Diatonic
      fade_out = 0.0,
      fade_vca = 1.0,
      fade_clock = nil
    }
  end
  
  -- Presets (4 slots)
  s.presets_data = {{}, {}, {}, {}}
  s.presets_status = {0, 0, 0, 0}
  s.preset_selected = 0
  s.preset_press_time = {0, 0, 0, 0}
  s.preset_morph_active = false
  s.preset_morph_slot = nil
  s.preset_morph_src = {}
  s.preset_morph_start_time = 0
  
  -- Sequencers (4 slots)
  s.seq_slots = {}
  for i=1, 4 do
    s.seq_slots[i] = {data={}, state=0, press_time=0, start_time=0, step=1, duration=0}
  end
  s.sequencer_active = false
  
  -- Grid state
  s.grid_shift_active = false
  s.grid_track_held = false
  s.grid_momentary_mode = true  -- true=momentary (default, grid OFF), false=latched (grid ON)
  s.grid_keys_held = {}
  for i=1, 4 do s.grid_keys_held[i] = {} end
  s.seek_memory = {}
  s.ribbon_memory = {}
  s.ribbon_press_time = 0
  s.ribbon_start_speed = 1.0
  s.ribbon_target_speed = 1.0
  
  -- Transport state
  s.transport_press_time = {0, 0, 0, 0}
  
  -- Pages
  s.current_page = 7  -- Default: TAPE page
  
  -- Key held state
  s.k1_held = false
  s.k2_held = false
  s.k3_held = false
  
  -- Config page state (Shift+botón)
  s.config_page_active = false
  s.config_page_type = ""  -- "jump", "random", "warp"
  s.config_page_cursor = 1
  s.config_previous_page = 7
  
  -- Warp config
  s.warp_amount = 2.0
  s.warp_mode = 0  -- 0=MULTIPLY, 1=DIVIDE
  s.warp_smooth = 0.05
  s.warp_target = 0  -- 0=ALL, 1=CURRENT
  
  -- Random config
  s.rnd_speed_range = 2.0
  s.rnd_deg_range = 1.0
  s.rnd_apply_to = 0  -- 0=ALL, 1=CURRENT
  
  -- Fx memory
  s.fx_memory = {}
  
  -- 16n
  s.fader_latched = {}
  s.hw_positions = {}
  for i=1, 16 do
    s.fader_latched[i] = false
    s.hw_positions[i] = -1
  end
  s.grid_mixer_held = false
  s.sixteen_n_shift = false
  
  -- Popup
  s.popup = {
    active = false,
    name = "",
    value = "",
    deadline = 0
  }
  
  -- Tape library
  s.tape_filenames = {nil, nil, nil, nil}
  s.tape_msg_timers = {0, 0, 0, 0}
  s.tape_library_sel = 1
  s.file_selector_active = false
  
  -- Visualization data
  s.GONIO_LEN = 40
  s.gonio_history = {}
  for i=1, s.GONIO_LEN do s.gonio_history[i] = {s=0, w=0} end
  s.heads = {gonio=1}
  
  -- Misc
  s.str_cache = {}
  s.morph_fast_mode = false
  s.saved_morph_time = 2.0
  s.first_pass = false
  s.rec_start_time = 0
  
  return s
end

return Globals