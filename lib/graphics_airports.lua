-- Airports lib/graphics_airports.lua | Version 1.02
-- Screen graphics for Airports
-- 4 pages: TAPE (7), MIXER (8), AMBIENT (9), MASTER (10)
-- Config pages: TRICKS (6) for Jump/Random/Warp

local Graphics = {}

local sin = math.sin
local cos = math.cos
local floor = math.floor
local random = math.random
local pi = math.pi
local clamp = util.clamp
local linlin = util.linlin

local function get_txt(id) return state.str_cache[id] or "..." end

local function draw_header_right(label) screen.level(15); screen.move(128, 8); screen.text_right(label) end

local function draw_left_e1(label, text)
    screen.level(3); screen.move(0, 8); screen.text(label)
    screen.level(15); screen.move(0, 15); screen.text(text)
end

local function draw_vertical_divider() screen.level(1); screen.move(85, 10); screen.line(85, 60); screen.stroke() end

local function draw_right_param_pair(label1, text1, label2, text2)
  local col1_x = 55
  local col2_x = 95
  local label_y = 53
  local value_y = 60
  screen.level(3); screen.move(col1_x, label_y); screen.text(label1)
  screen.level(15); screen.move(col1_x, value_y); screen.text(text1)
  screen.level(3); screen.move(col2_x, label_y); screen.text(label2)
  screen.level(15); screen.move(col2_x, value_y); screen.text(text2)
end

-- Popup display for 16n
local function draw_popup(state)
    if state.popup and state.popup.active then
        if util.time() > state.popup.deadline then
            state.popup.active = false
        else
            screen.level(0)
            screen.rect(2, 11, 124, 11)
            screen.fill()
            screen.level(15)
            screen.rect(2, 11, 124, 11)
            screen.stroke()
            screen.move(64, 19)
            screen.text_center(state.popup.name .. ": " .. state.popup.value)
        end
    end
end

-- Goniameter block (visualization)
local function draw_goniometer(state)
  local cx = 106
  local cy = 29
  local head = state.heads and state.heads.gonio or 1
  local gonio_len = state.GONIO_LEN or 40
  local hist = state.gonio_history
  if not hist then return end
  
  for i=0, gonio_len-1 do
     local idx = (head - 1 - i - 1) % gonio_len + 1
     local frame = hist[idx]
     if frame and frame.s > 0.1 then
        local brightness = math.floor(15 / (i * 0.25 + 1))
        if brightness > 1 then
           screen.level(brightness)
           local s = frame.s
           local w = frame.w
           local points = (i==0) and 10 or 3
           for p=1, points do
               local ang = random() * 6.28
               local rad = random() * s
               local px = cx + (cos(ang) * rad) + ((random()-0.5)*2 * w)
               local py = cy + (sin(ang) * rad * 1.4)
               if px > 86 and px < 127 and py > 12 and py < 50 then
                  screen.pixel(px, py); screen.fill()
               end
           end
        end
     end
  end
end

-- Plasma bar fluid (for meters)
local function draw_plasma_bar(x, y, w, h, val, is_inverted)
   local seg_w = 2; local gap = 1; local total_segs = math.floor(w / (seg_w + gap))
   screen.level(1)
   for i=0, total_segs-1 do screen.rect(x + (i * (seg_w+gap)), y, seg_w, h); screen.fill() end
   local active_float = val * total_segs; local active_int = math.floor(active_float); local active_frac = active_float - active_int
   for i=0, active_int-1 do
      local pos_x = x + (i * (seg_w+gap)); if is_inverted then pos_x = x + w - ((i+1) * (seg_w+gap)) end
      local pct = (i+1) / total_segs; local b = 6; if pct > 0.6 then b = 10 end; if pct > 0.9 then b = 15 end
      screen.level(b); screen.rect(pos_x, y, seg_w, h); screen.fill()
   end
   if active_frac > 0.1 and active_int < total_segs then
      local i = active_int; local pos_x = x + (i * (seg_w+gap)); if is_inverted then pos_x = x + w - ((i+1) * (seg_w+gap)) end
      local pct = (i+1) / total_segs; local base_b = 6; if pct > 0.6 then base_b = 10 end; if pct > 0.9 then base_b = 15 end
      local tip_b = math.floor(base_b * active_frac)
      if tip_b > 0 then screen.level(tip_b); screen.rect(pos_x, y, seg_w, h); screen.fill() end
   end
end

-- ============================================================
-- PAGE 6: TRICKS CONFIG (Jump / Random / Warp)
-- ============================================================
local function draw_tricks_page(state)
   screen.clear()
   
    local sel = state.config_page_track or state.track_sel
    local t = state.tracks[sel]
    local config_type = state.config_page_type
   local cursor = state.config_page_cursor
   
   if config_type == "jump" then
      -- Jump config — header shows specific name + track
      screen.level(4); screen.move(64, 8); screen.text_center("JUMP CONFIG — TRK " .. sel)
      
      local items = {"MODE", "RATE (FREE)", "DIV (SYNC)", "RND LPOS"}
      local values = {
         (t.jump_sync == 0) and "FREE" or "SYNC",
         string.format("%.2f Hz", t.jump_rate),
         "1/" .. tostring(t.jump_div),
         string.format("%.0f%%", t.jump_rnd_lpos * 100)
      }
      
      for i=1, #items do
         local y = 20 + (i * 8)
         if cursor == i then screen.level(15); screen.move(0, y); screen.text(">") else screen.level(3) end
         screen.move(6, y); screen.text(items[i])
         screen.level(15); screen.move(80, y); screen.text_right(values[i])
      end
      
      screen.level(3); screen.move(0, 60); screen.text("K3=EXIT  E2=NAV  E3=VAL")
      
   elseif config_type == "random" then
      -- Random config — per-track page
      screen.level(4); screen.move(64, 8); screen.text_center("RANDOM CONFIG — TRK " .. sel)
      
      local items = {"SPEED", "DEGRADE", "LOOP POS", "EQ/FILTER", "VOLUME"}
      local values = {
         (t.rnd_speed and "ON" or "OFF"),
         (t.rnd_deg and "ON" or "OFF"),
         (t.rnd_loop and "ON" or "OFF"),
         (t.rnd_eq and "ON" or "OFF"),
         (t.rnd_vol and "ON" or "OFF")
      }
      
      for i=1, #items do
         local y = 16 + (i * 8)
         if cursor == i then screen.level(15); screen.move(0, y); screen.text(">") else screen.level(3) end
         screen.move(6, y); screen.text(items[i])
         screen.level(15); screen.move(80, y); screen.text_right(values[i])
      end
      
      screen.level(3); screen.move(0, 60); screen.text("K3=EXIT  E2=NAV  E3=TOG")
      
   elseif config_type == "warp" then
      -- Warp config — specific header, no generic TRICKS CONFIG
      screen.level(4); screen.move(64, 8); screen.text_center("WARP CONFIG")
      
      local mode_txt = (state.warp_mode == 0) and "MULTIPLY" or "DIVIDE"
      local target_txt = (state.warp_target == 0) and "ALL" or "CURRENT"
      
      local items = {"MODE", "AMOUNT", "SMOOTH", "TARGET"}
      local values = {
         mode_txt,
         string.format("%.2fx", state.warp_amount),
         string.format("%.2fs", state.warp_smooth),
         target_txt
      }
      
      for i=1, #items do
         local y = 20 + (i * 8)
         if cursor == i then screen.level(15); screen.move(0, y); screen.text(">") else screen.level(3) end
         screen.move(6, y); screen.text(items[i])
         screen.level(15); screen.move(80, y); screen.text_right(values[i])
      end
      
      -- Preview
      local preview = state.tracks[sel].speed
      screen.level(3); screen.move(0, 60); screen.text("PREVIEW: " .. string.format("%.2f", preview))
   end
   
   draw_popup(state)
   screen.update()
end

-- ============================================================
-- PAGE 7: TAPE (Looper control)
-- ============================================================
local function draw_tape_page(state, shift)
   screen.clear()
   local sel = state.track_sel or 1
   local t = state.tracks[sel]
   local now = util.time()
   
   -- Header: "TAPE X" top right
   screen.level(4); screen.move(128, 8); screen.text_right("TAPE " .. sel)
   
     -- Encoder labels
     if state.grid_track_held then
        -- Track Held mode (tertiary)
        draw_left_e1("REC LVL", string.format("%.1fdB", t.rec_level or -3.0))
        screen.level(3); screen.move(55, 53); screen.text("INPUT SRC")
        local src_names = {"INPUT","PRE REV","POST REV","TRK1","TRK2","TRK3","TRK4"}
        screen.level(15); screen.move(55, 60); screen.text(src_names[(t.src_sel or 0) + 1])
     elseif shift then
        -- Shift mode (K1 held): E1=SPEED, E2=START, E3=END
        local speed = t.speed or 1
        local dir_sym = speed < 0 and "<<" or ">>"
        draw_left_e1("SPEED", string.format("%s %.2f", dir_sym, math.abs(speed)))
        local start_p = floor((t.loop_start or 0) * 100)
        local end_p = floor((t.loop_end or 1) * 100)
        draw_right_param_pair("START", start_p .. "%", "END", end_p .. "%")
     else
        -- Normal mode: E1=LENGTH, E2=DEGRADE, E3=DUB
        draw_left_e1("LENGTH", string.format("%.2fs", params:get("l"..sel.."_length")))
        screen.level(3); screen.move(55, 53); screen.text("DEGRADE")
        screen.level(15); screen.move(55, 60); screen.text(string.format("%.0f%%", (t.wow_macro or 0)*100))
        screen.level(3); screen.move(95, 53); screen.text("DUB")
        screen.level(15); screen.move(95, 60); screen.text(string.format("%.0f%%", (t.overdub or 0.5)*100))
     end
   
   -- E4 label top right, below TAPE X header
   screen.level(3); screen.move(128, 16); screen.text_right("E4:REC LVL")
   
   draw_goniometer(state)
   
   -- Track mini-bars
   local x_base = 0
   for i=1, 4 do
      local trk = state.tracks[i]; local y_off = 20 + (i * 9)
      screen.font_size(8); if i == sel then screen.level(15) else screen.level(2) end
      screen.move(x_base, y_off); screen.text(i)
      local bar_x = x_base + 8; local bar_w = 36
      screen.level(1); screen.rect(bar_x, y_off - 5, bar_w, 6); screen.fill()
      if trk.state == 2 then
         if now % 0.4 > 0.2 then screen.level(15); screen.rect(bar_x, y_off - 5, bar_w, 6); screen.fill() end
         screen.level(0); screen.move(bar_x + 2, y_off); screen.text("REC")
      elseif trk.state == 4 then
           screen.level(8); screen.rect(bar_x, y_off - 5, bar_w, 6); screen.fill()
           screen.level(0); screen.move(bar_x + 2, y_off); screen.text("OVR")
      elseif trk.state == 3 then
           local pos = trk.play_pos or 0; local px = bar_x + (pos * bar_w)
           screen.level(15); screen.pixel(px, y_off - 4); screen.fill(); screen.pixel(px, y_off - 3); screen.fill()
      elseif trk.state == 1 then screen.level(2); screen.pixel(bar_x + (bar_w/2), y_off - 3); screen.fill() end
      screen.level(3)
      local len_txt = string.format("%.1fs", params:get("l"..i.."_length"))
      screen.move(x_base + 12 + bar_w, y_off); screen.text_right(len_txt)
   end
   
   
   draw_popup(state)
   screen.update()
end

-- ============================================================
-- PAGE 8: SITRAL MIXER (4-canales vintage)
-- ============================================================
local function draw_mixer_page(state, shift)
   screen.clear()
   local sel = state.track_sel
   local t = state.tracks[sel]
   
   screen.level(4); screen.move(64, 8); screen.text_center("SITRAL MIXER")
   screen.font_size(8)
   
   -- Bottom labels
   if not shift then
      local vol_db = util.linlin(0, 1, -60, 12, t.vol or 0)
      screen.level(3); screen.move(0, 62); screen.text("VOL:")
      screen.level(15); screen.move(18, 62); screen.text(string.format("%.1fdB", vol_db))
      screen.level(3); screen.move(50, 62); screen.text("LOW:")
      screen.level(15); screen.move(68, 62); screen.text(string.format("%.1f", t.l_low or 0))
      screen.level(3); screen.move(95, 62); screen.text("HI:")
      screen.level(15); screen.move(110, 62); screen.text(string.format("%.1f", t.l_high or 0))
   else
      screen.level(3); screen.move(0, 62); screen.text("FLT:")
      screen.level(15); screen.move(18, 62); screen.text(string.format("%.2f", t.l_filter or 0.5))
      screen.level(3); screen.move(50, 62); screen.text("PAN:")
      screen.level(15); screen.move(68, 62); screen.text(string.format("%.2f", t.l_pan or 0))
      screen.level(3); screen.move(95, 62); screen.text("WID:")
      screen.level(15); screen.move(110, 62); screen.text(string.format("%.2f", t.l_width or 1))
   end
   
   -- Rails con faders
   local x_base = 25; local spacing = 26; local y_top = 17; local y_bot = 49; local h_rail = y_bot - y_top
   for i=1, 4 do
      local x = x_base + ((i-1) * spacing)
      local trk = state.tracks[i]
      local is_sel = (i == sel)
      
      -- Selection rectangle
      if is_sel then screen.level(1); screen.rect(x-12, y_top-6, 24, h_rail+11); screen.stroke() end
      
      -- Rail (center line)
      screen.level(2); screen.rect(x-1, y_top, 2, h_rail); screen.fill()
      
      -- Volume fader
      local vol = trk.vol or 0.833
      local y_vol = y_bot - (vol * h_rail)
      screen.level(is_sel and 15 or 8); screen.rect(x - 2, y_vol - 1, 5, 3); screen.fill()
      screen.level(0); screen.pixel(x, y_vol); screen.fill()
      
      -- Low shelf (left line)
      local low = trk.l_low or 0
      local high = trk.l_high or 0
      local y_mid = y_top + (h_rail/2)
      screen.level(3); screen.move(x-6, y_top+5); screen.line(x-6, y_bot-5); screen.stroke()
      local y_low = y_mid - (clamp(low, -18, 18) * 0.33)
      screen.level(is_sel and 15 or 6); screen.pixel(x-6, y_low); screen.fill()
      
      -- High shelf (right line)
      screen.level(3); screen.move(x+6, y_top+5); screen.line(x+6, y_bot-5); screen.stroke()
      local y_high = y_mid - (clamp(high, -18, 18) * 0.33)
      screen.level(is_sel and 15 or 6); screen.pixel(x+6, y_high); screen.fill()
      
      -- DJ Filter (center mark)
      local f = trk.l_filter or 0.5
      if math.abs(f - 0.5) > 0.01 then
         screen.level(15)
         local y_center = y_top + (h_rail/2)
         local dist = math.abs(f - 0.5)
         local h_cut = (dist / 0.5) * (h_rail / 2)
         screen.move(x, y_center)
         if f < 0.5 then screen.line(x, y_center + h_cut) else screen.line(x, y_center - h_cut) end
         screen.stroke()
      end
      
      -- Pan (bottom line)
      local p = trk.l_pan or 0
      local px = x + (p * 8)
      screen.level(4); screen.move(x-8, y_bot+2); screen.line(x+8, y_bot+2); screen.stroke()
      screen.level(is_sel and 15 or 8); screen.pixel(px, y_bot+2); screen.fill()
      
      -- Width (top dots)
      local w = trk.l_width or 1
      local wy = y_top - 4
      if w < 0.1 then screen.level(15); screen.pixel(x, wy); screen.fill()
      else screen.level(8); local spread = w * 2.5; screen.pixel(x-spread, wy); screen.fill(); screen.pixel(x+spread, wy); screen.fill() end
      
      -- Track number
      screen.level(is_sel and 15 or 2); screen.font_size(8); screen.move(x+8, y_top); screen.text(i)
   end
   
   draw_popup(state)
   screen.update()
end

-- ============================================================
-- PAGE 9: AMBIENT (Reverb + Noise + Global Filters)
-- ============================================================
local function draw_ambient_page(state, shift)
   screen.clear()
   screen.level(4); screen.move(64, 8); screen.text_center("AMBIENT ENGINE")
   
   if not shift then
      -- Normal: Rev Mix, Rev Time, Noise Amp, Noise Type
      local rev_mix = params:get("reverb_mix") or 0.25
      local rev_time = params:get("reverb_time") or 4.2
      local noise_amp = params:get("noise_amp") or 0
      local noise_type = params:get("noise_type") or 0
      local noise_names = {"PINK", "WHITE", "CRACKLE", "RAIN", "LORENZ", "GRIT"}
      
      -- Reverb block
      screen.level(3); screen.move(0, 20); screen.text("REVERB")
      screen.level(15); screen.move(30, 20); screen.text(string.format("%.0f%%", rev_mix * 100))
      screen.level(3); screen.move(60, 20); screen.text("TIME")
      screen.level(15); screen.move(85, 20); screen.text(string.format("%.1fs", rev_time))
      
      -- Noise block
      screen.level(3); screen.move(0, 30); screen.text("NOISE")
      screen.level(15); screen.move(30, 30); screen.text(string.format("%.0f%%", noise_amp * 100))
      screen.level(3); screen.move(60, 30); screen.text("TYPE")
      screen.level(15); screen.move(85, 30); screen.text(noise_names[noise_type + 1])
      
      -- NO goniometer on AMBIENT page — keep it clean
      
      screen.level(3); screen.move(0, 53); screen.text("E1:REV MIX")
      screen.level(3); screen.move(50, 53); screen.text("E2:TIME")
      screen.level(3); screen.move(95, 53); screen.text("E3:NOISE")
   else
      -- Shift: Rev Damp, Global LPF, Global HPF
      local rev_damp = params:get("reverb_damp") or 4600
      local global_lpf = params:get("global_lpf") or 20000
      local global_hpf = params:get("global_hpf") or 20
      
      draw_left_e1("DAMP", string.format("%.0fHz", rev_damp))
      screen.level(3); screen.move(55, 53); screen.text("LPF")
      screen.level(15); screen.move(55, 60); screen.text(string.format("%.0fHz", global_lpf))
      screen.level(3); screen.move(95, 53); screen.text("HPF")
      screen.level(15); screen.move(95, 60); screen.text(string.format("%.0fHz", global_hpf))
      
      draw_vertical_divider()
      draw_header_right("FILTERS")
   end
   
   draw_popup(state)
   screen.update()
end

-- ============================================================
-- PAGE 10: MASTER (Compressor + Output)
-- ============================================================
local function draw_master_page(state, shift)
   screen.clear()
   screen.level(4); screen.move(64, 8); screen.text_center("MASTER OUTPUT")
   
   if not shift then
      local mon = params:get("main_mon") or 0.833
      local thresh = params:get("bus_thresh") or -12.0
      local ratio = params:get("bus_ratio") or 2.2
      local bal = params:get("balance") or 0
      
      draw_left_e1("MONITOR", string.format("%.1fdB", util.linlin(0, 1, -60, 12, mon)))
      
      screen.level(3); screen.move(55, 53); screen.text("THRESH")
      screen.level(15); screen.move(55, 60); screen.text(string.format("%.1fdB", thresh))
      screen.level(3); screen.move(95, 53); screen.text("RATIO")
      screen.level(15); screen.move(95, 60); screen.text(string.format("%.1f:1", ratio))
      
      -- GR Meter + L/R Meters
      local gr = state.comp_gr or 0
      local gr_norm = clamp(gr * 4, 0, 1)
      screen.level(3); screen.move(0, 25); screen.text("GR")
      draw_plasma_bar(18, 23, 50, 2, gr_norm, true)
      
      local amp_l_db = 20 * math.log10(state.amp_l > 0.0001 and state.amp_l or 0.0001)
      local amp_r_db = 20 * math.log10(state.amp_r > 0.0001 and state.amp_r or 0.0001)
      local l_norm = clamp(linlin(-60, 0, 0, 1, amp_l_db), 0, 1)
      local r_norm = clamp(linlin(-60, 0, 0, 1, amp_r_db), 0, 1)
      
      screen.level(3); screen.move(0, 30); screen.text("L")
      draw_plasma_bar(18, 28, 50, 3, l_norm, false)
      screen.level(3); screen.move(0, 37); screen.text("R")
      draw_plasma_bar(18, 35, 50, 3, r_norm, false)
      
      draw_vertical_divider()
      draw_header_right("MASTER")
      draw_goniometer(state)
      
   else
      -- Shift: Limiter Ceil, Bass Focus, Comp Drive
      local ceil = params:get("limiter_ceil") or -0.1
      local bf = params:get("bass_focus") or 0
      local drive = params:get("bus_drive") or 1.0
      local bf_names = {"OFF", "50Hz", "100Hz", "200Hz"}
      
      draw_left_e1("CEIL", string.format("%.1fdB", ceil))
      
      screen.level(3); screen.move(55, 53); screen.text("BASS")
      screen.level(15); screen.move(55, 60); screen.text(bf_names[bf + 1])
      screen.level(3); screen.move(95, 53); screen.text("DRIVE")
      screen.level(15); screen.move(95, 60); screen.text(string.format("%.1fdB", drive))
      
      draw_vertical_divider()
      draw_header_right("MASTER")
      draw_goniometer(state)
   end
   
   draw_popup(state)
   screen.update()
end

-- ============================================================
-- MAIN DRAW FUNCTION
-- ============================================================
function Graphics.draw(state)
  local page = state.current_page
  local shift = state.k1_held or state.grid_shift_active or state.grid_track_held
  
  -- Config pages (Shift+button)
  if state.config_page_active then
     draw_tricks_page(state)
     return
  end
  
  -- Normal pages
  if page == 10 then draw_master_page(state, shift); return end
  if page == 9 then draw_ambient_page(state, shift); return end
  if page == 8 then draw_mixer_page(state, shift); return end
  if page == 7 then draw_tape_page(state, shift); return end
  
  -- Fallback
  draw_tape_page(state, shift)
end

return Graphics