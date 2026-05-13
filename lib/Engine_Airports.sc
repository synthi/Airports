// lib/Engine_Airports.sc | Version 1.03
// AIRPORTS — 4 Ambient Loopers for norns
// FIXED v1.02: Input sources: INPUT, PRE REVERB, POST REVERB, TRACK 1-4

Engine_Airports : CroneEngine {
    var <synth_proc, <synth_loopers, <synth_rev;
    var <buf1, <buf2, <buf3, <buf4;
    var <dummy_buf;

    var <amp_bus_l, <amp_bus_r, <pos_bus, <gr_bus;
    var <track_out_buses;
    var <b_analysis;

    // Signal flow buses
    var <b_input_proc;      // Processor output -> Loopers
    var <b_reverb_send;     // Loopers -> Reverb
    var <b_reverb_return;   // Reverb -> Loopers

    var <osc_bridge;

    alloc {
        var buffers;

        buf1 = Buffer.alloc(context.server, context.server.sampleRate * 120.0, 2);
        buf2 = Buffer.alloc(context.server, context.server.sampleRate * 120.0, 2);
        buf3 = Buffer.alloc(context.server, context.server.sampleRate * 120.0, 2);
        buf4 = Buffer.alloc(context.server, context.server.sampleRate * 120.0, 2);
        dummy_buf = Buffer.alloc(context.server, 44100, 2);

        buffers = [buf1, buf2, buf3, buf4];

        amp_bus_l = Bus.control(context.server);
        amp_bus_r = Bus.control(context.server);
        pos_bus = Bus.control(context.server, 4);
        gr_bus = Bus.control(context.server);

        track_out_buses = { Bus.audio(context.server, 2) } ! 4;

        b_input_proc = Bus.audio(context.server, 2);
        b_reverb_send = Bus.audio(context.server, 2);
        b_reverb_return = Bus.audio(context.server, 2);
        b_analysis = Bus.control(context.server, 4);

        context.server.sync;

        osc_bridge = OSCFunc({ |msg|
            NetAddr("127.0.0.1", 10111).sendMsg("/airports/visuals", *msg.drop(3));
        }, '/airports/visuals', context.server.addr).fix;

        // -----------------------------------------------------------
        // PROCESSOR: Input + noise + global LPF/HPF
        // Writes to b_input_proc only (NOT to reverb send)
        // -----------------------------------------------------------
        SynthDef(\Airports_Processor, {
            |in_bus=0, bus_proc_out=0,
             noise_amp=0, noise_type=0,
             global_lpf=20000, global_hpf=20|

            var input, noise, noise_L, noise_R;
            var proc_sig;

            noise_L = Select.ar(noise_type, [
                PinkNoise.ar, WhiteNoise.ar * 0.5, Crackle.ar(1.9),
                Latch.ar(WhiteNoise.ar, Dust.ar(LFNoise1.kr(0.3).exprange(5, 50))) * 0.4,
                LFNoise1.ar(500) * 0.7,
                Dust2.ar(LFNoise1.kr(0.3).exprange(300, 2000)) * 0.9
            ]);
            noise_R = Select.ar(noise_type, [
                PinkNoise.ar, WhiteNoise.ar * 0.5, Crackle.ar(1.9),
                Latch.ar(WhiteNoise.ar, Dust.ar(LFNoise1.kr(0.3).exprange(5, 50))) * 0.4,
                LFNoise1.ar(500) * 0.7,
                Dust2.ar(LFNoise1.kr(0.3).exprange(300, 2000)) * 0.9
            ]);
            noise = [noise_L, noise_R] * noise_amp * 0.6;
            noise = LeakDC.ar(noise).tanh;

            input = In.ar(in_bus, 2);
            input = HPF.ar(input, 35);
            input = LPF.ar(input, 18000);

            proc_sig = input + noise;
            proc_sig = LPF.ar(proc_sig, global_lpf);
            proc_sig = HPF.ar(proc_sig, global_hpf);
            proc_sig = LeakDC.ar(proc_sig);

            // Output ONLY to the processor bus -> loopers input
            Out.ar(bus_proc_out, proc_sig);
        }).add;

        // -----------------------------------------------------------
        // REVERB: Reads from send bus, writes to return bus
        // -----------------------------------------------------------
        SynthDef(\Airports_Reverb, {
            |in_bus=0, out_bus=0,
             reverb_mix=0.25, reverb_time=4.2, reverb_damp=4600|

            var input, wet, sig;

            input = In.ar(in_bus, 2);

            wet = input.collect({ |chan|
                var p = DelayN.ar(chan, 0.1, 0.03);
                var combs = 6.collect({
                    CombL.ar(p, 0.2, Rand(0.03, 0.07) + LFNoise2.kr(Rand(0.1, 0.3)).range(0, 0.0025), reverb_time)
                }).sum;
                2.do({ combs = AllpassN.ar(combs, 0.050, Rand(0.01, 0.05), 1); });
                combs * 0.2;
            });
            wet = LPF.ar(Decimator.ar(wet, 32000, 12), reverb_damp);

            sig = (input * (1 - reverb_mix)) + (HPF.ar(wet, 10) * reverb_mix);
            Out.ar(out_bus, sig);
        }).add;

        // -----------------------------------------------------------
        // LOOPERS: 4 seamless ambient loopers + master + reverb send
        // Input sources: 1=INPUT, 2=PRE REVERB, 3=POST REVERB, 4-7=TRACK1-4
        // -----------------------------------------------------------
        SynthDef(\Airports_Loopers, {
            |out_bus=0,
             bus_proc_in=0, bus_reverb_send=0, bus_reverb_return=0,
             buf1=0, buf2=0, buf3=0, buf4=0,
             t1_bus=0, t2_bus=0, t3_bus=0, t4_bus=0,
              main_mon=0.833,
              monitor_amp=0,
              comp_thresh=0.5, comp_ratio=2.0, comp_drive=0.0,
              bass_focus_mode=0, limiter_ceil=0.0, balance=0.0,
             l1_rec=0, l1_play=0, l1_vol=0, l1_speed=1, l1_start=0, l1_end=1, l1_src=0, l1_dub=0.5, l1_deg=0, l1_brake=0, l1_rec_lvl=0, l1_length=60, l1_seek_pos=0, t_l1_seek_trig=0,
             l2_rec=0, l2_play=0, l2_vol=0, l2_speed=1, l2_start=0, l2_end=1, l2_src=0, l2_dub=0.5, l2_deg=0, l2_brake=0, l2_rec_lvl=0, l2_length=60, l2_seek_pos=0, t_l2_seek_trig=0,
             l3_rec=0, l3_play=0, l3_vol=0, l3_speed=1, l3_start=0, l3_end=1, l3_src=0, l3_dub=0.5, l3_deg=0, l3_brake=0, l3_rec_lvl=0, l3_length=60, l3_seek_pos=0, t_l3_seek_trig=0,
             l4_rec=0, l4_play=0, l4_vol=0, l4_speed=1, l4_start=0, l4_end=1, l4_src=0, l4_dub=0.5, l4_deg=0, l4_brake=0, l4_rec_lvl=0, l4_length=60, l4_seek_pos=0, t_l4_seek_trig=0,
             l1_low=0, l1_high=0, l1_filter=0.5, l1_pan=0, l1_width=1,
             l2_low=0, l2_high=0, l2_filter=0.5, l2_pan=0, l2_width=1,
             l3_low=0, l3_high=0, l3_filter=0.5, l3_pan=0, l3_width=1,
             l4_low=0, l4_high=0, l4_filter=0.5, l4_pan=0, l4_width=1|

            var proc_in, rev_out;
            var loop_outputs_sum;
            var synth_buffers, track_buses;
            var l_rec_arr, l_play_arr, l_vol_arr, l_speed_arr, l_start_arr, l_end_arr, l_src_arr, l_dub_arr, l_deg_arr, l_brake_arr, l_rec_lvl_arr, l_length_arr, l_seek_p_arr, l_seek_t_arr;
            var l_low_arr, l_high_arr, l_filter_arr, l_pan_arr, l_width_arr;
            var pointers = Array.fill(4, { DC.kr(0) });
            var master_out, main_mon_amp;
            var bf_freq, bf_mono, bf_highs;
            var driven_sig, master_glue, gr_sig;
            var trig_visuals;
            var trk1_in, trk2_in, trk3_in, trk4_in;
            var pre_rev_sig;

            // Inputs
            proc_in = In.ar(bus_proc_in, 2);
            rev_out = In.ar(bus_reverb_return, 2);

            loop_outputs_sum = Silent.ar(2);

            synth_buffers = [buf1, buf2, buf3, buf4];
            track_buses = [t1_bus, t2_bus, t3_bus, t4_bus];

            trk1_in = InFeedback.ar(t1_bus, 2);
            trk2_in = InFeedback.ar(t2_bus, 2);
            trk3_in = InFeedback.ar(t3_bus, 2);
            trk4_in = InFeedback.ar(t4_bus, 2);

            l_rec_arr = [l1_rec, l2_rec, l3_rec, l4_rec];
            l_play_arr = [l1_play, l2_play, l3_play, l4_play];
            l_vol_arr = [l1_vol, l2_vol, l3_vol, l4_vol];
            l_speed_arr = [l1_speed, l2_speed, l3_speed, l4_speed];
            l_start_arr = [l1_start, l2_start, l3_start, l4_start];
            l_end_arr = [l1_end, l2_end, l3_end, l4_end];
            l_src_arr = [l1_src, l2_src, l3_src, l4_src];
            l_dub_arr = [l1_dub, l2_dub, l3_dub, l4_dub];
            l_deg_arr = [l1_deg, l2_deg, l3_deg, l4_deg];
            l_brake_arr = [l1_brake, l2_brake, l3_brake, l4_brake];
            l_rec_lvl_arr = [l1_rec_lvl, l2_rec_lvl, l3_rec_lvl, l4_rec_lvl];
            l_length_arr = [l1_length, l2_length, l3_length, l4_length];
            l_seek_p_arr = [l1_seek_pos, l2_seek_pos, l3_seek_pos, l4_seek_pos];
            l_seek_t_arr = [t_l1_seek_trig, t_l2_seek_trig, t_l3_seek_trig, t_l4_seek_trig];
            l_low_arr = [l1_low, l2_low, l3_low, l4_low];
            l_high_arr = [l1_high, l2_high, l3_high, l4_high];
            l_filter_arr = [l1_filter, l2_filter, l3_filter, l4_filter];
            l_pan_arr = [l1_pan, l2_pan, l3_pan, l4_pan];
            l_width_arr = [l1_width, l2_width, l3_width, l4_width];

            4.do({ |i|
                var b_idx, bus_idx;
                var gate_rec, gate_play;
                var rate_slew, brake_idx, brake_mod, lfo_mod, lfo_lag_time;
                var deg_curve, flutter_mod, final_rate;
                var organic_brake_hpf, flux_gain;
                var loop_len_samps, start_pos, end_pos, ptr;
                var play_sig, deg_lpf, deg_hpf, corrosion_am, loop_ero, loop_dust_trig, loop_dropout_env, loop_gain_loss;
                var sat_drive;
                var dynamic_cutoff, sig_out, in_sig;
                var deg_idx, fb_comp_curve, amp_det, dyn_stab, safe_fb, write_sig;
                var tape_physics_cutoff, output_sig, sat_low, slew_val, c_lpf, c_hpf;
                var mid, side;
                var gate_ar, rec_timer, is_first_pass, ptr_norm, neg_time;
                var gate_play_ar;
                var input_sources;

                b_idx = synth_buffers[i];
                bus_idx = track_buses[i];

                gate_rec = Lag.kr(l_rec_arr[i], 0.1);
                gate_play = Lag.kr(l_play_arr[i], 0.1);

                // BRAKE
                brake_idx = (l_brake_arr[i] * 4).round;
                brake_mod = Select.kr(brake_idx, [1.0, 1.0, 1.0, 0.5, 0.0]);
                brake_mod = Lag3.kr(brake_mod, 0.3);
                lfo_mod = Select.kr(brake_idx, [1.0, LFNoise2.kr(2).range(0.97, 1.03), LFNoise2.kr(8).range(0.91, 1.09), LFNoise2.kr(4).range(0.95, 1.05), 1.0]);
                lfo_lag_time = Select.kr(brake_idx, [0.1, 0.25, 0.1, 0.05, 0.05]);
                lfo_mod = Lag.kr(lfo_mod, lfo_lag_time);
                rate_slew = Lag.kr(l_speed_arr[i], 0.07) * brake_mod * lfo_mod;

                // DEGRADE flutter
                deg_curve = l_deg_arr[i].pow(4.0);
                flutter_mod = Select.kr(l_deg_arr[i] > 0.4, [
                    LinLin.kr(l_deg_arr[i], 0.0, 0.4, 0.0, 0.002),
                    Select.kr(l_deg_arr[i] > 0.6, [LinLin.kr(l_deg_arr[i], 0.4, 0.6, 0.002, 0.02), Select.kr(l_deg_arr[i] > 0.8, [LinLin.kr(l_deg_arr[i], 0.6, 0.8, 0.02, 0.04), LinLin.kr(l_deg_arr[i], 0.8, 1.0, 0.04, 0.08)])])
                ]);
                flutter_mod = Lag.kr(flutter_mod, 0.1);
                final_rate = rate_slew * (1.0 + OnePole.ar(LFNoise2.ar(4+(i*1.5)) * (flutter_mod * 0.5), 0.5));

                organic_brake_hpf = LinExp.kr(rate_slew.abs + 0.001, 0.001, 1.0, 250, 10);
                organic_brake_hpf = Lag.kr(organic_brake_hpf, 0.1);
                flux_gain = (rate_slew.abs * 5.0).clip(0, 1).pow(3);

                loop_len_samps = l_length_arr[i].max(0.001) * SampleRate.ir;
                start_pos = Lag.kr(l_start_arr[i], 0.1) * loop_len_samps;
                end_pos = (Lag.kr(l_end_arr[i], 0.1) * loop_len_samps).max(start_pos + 10);

                ptr = Phasor.ar(l_seek_t_arr[i], final_rate * BufRateScale.kr(b_idx), start_pos, end_pos, l_seek_p_arr[i] * loop_len_samps);

                // Negative pointer
                gate_ar = K2A.ar(l_rec_arr[i]);
                gate_play_ar = K2A.ar(l_play_arr[i]);
                rec_timer = Sweep.ar(gate_ar, gate_ar);
                is_first_pass = (gate_ar > 0.5) * (gate_play_ar < 0.5);
                ptr_norm = A2K.kr(ptr / loop_len_samps);
                neg_time = A2K.kr(rec_timer.neg);
                pointers[i] = Select.kr(A2K.kr(is_first_pass), [ptr_norm, neg_time]);

                play_sig = BufRd.ar(2, b_idx, ptr, 1, 2);

                // DEGRADE processing
                deg_lpf = Lag.kr(Select.kr(l_deg_arr[i] > 0.5, [LinExp.kr(l_deg_arr[i], 0.0, 0.5, 17000, 12000), Select.kr(l_deg_arr[i] > 0.8, [LinExp.kr(l_deg_arr[i], 0.5, 0.8, 12000, 4000), LinExp.kr(l_deg_arr[i], 0.8, 1.0, 4000, 2800)])]), 0.1);
                play_sig = LPF.ar(LPF.ar(play_sig, deg_lpf), deg_lpf);
                corrosion_am = Lag.kr(1.0 - (LFNoise2.kr(8 + (i*2)).unipolar * Select.kr(l_deg_arr[i] > 0.8, [LinLin.kr(l_deg_arr[i], 0.0, 0.8, 0.0, 0.6), LinLin.kr(l_deg_arr[i], 0.8, 1.0, 0.6, 0.75)])), 0.1);
                play_sig = play_sig * corrosion_am;
                loop_ero = LinLin.kr(l_deg_arr[i], 0.4, 1.0, 0.0, 0.5).max(0);
                loop_dust_trig = Dust.kr(loop_ero * 15);
                loop_dropout_env = Decay.kr(loop_dust_trig, 0.1);
                loop_gain_loss = (loop_dropout_env * loop_ero).clip(0, 0.9);
                play_sig = play_sig * (1.0 - loop_gain_loss);
                sat_drive = Select.kr(l_deg_arr[i] > 0.2, [DC.kr(1.0), Select.kr(l_deg_arr[i] > 0.5, [LinLin.kr(l_deg_arr[i], 0.2, 0.5, 1.0, 1.5), Select.kr(l_deg_arr[i] > 0.8, [LinLin.kr(l_deg_arr[i], 0.5, 0.8, 1.5, 3.0), LinLin.kr(l_deg_arr[i], 0.8, 1.0, 3.0, 4.5)])])]);
                play_sig = Select.ar(l_deg_arr[i] >= 0.2, [(play_sig * sat_drive).tanh, play_sig]);
                dynamic_cutoff = (rate_slew.abs * 20000).clip(50, 20000);
                play_sig = LPF.ar(play_sig, dynamic_cutoff);
                sig_out = play_sig;

                // INPUT SOURCES:
                // 1: proc_in (INPUT + noise + filters)
                // 2: loop_outputs_sum (PRE REVERB - dry mix of all loopers)
                // 3: rev_out (POST REVERB - reverbed mix)
                // 4-7: trk1_in..trk4_in (cross-feed from track outputs)
                // IMPORTANT: pre_rev_sig = loop_outputs_sum at audio rate
                input_sources = [proc_in, loop_outputs_sum, rev_out, trk1_in, trk2_in, trk3_in, trk4_in];
                in_sig = Select.ar(l_src_arr[i], input_sources);

                // Apply degrade to input
                in_sig = LPF.ar(LPF.ar(in_sig, deg_lpf), deg_lpf);
                in_sig = in_sig * corrosion_am;

                // Gain compensation
                deg_idx = (l_deg_arr[i] * 20).round;
                fb_comp_curve = Select.kr(deg_idx, [1.00, 1.00, 1.00, 1.05, 1.05, 0.99, 0.97, 0.95, 0.93, 0.93, 0.94, 0.88, 0.85, 0.83, 0.80, 0.74, 0.64, 0.59, 0.48, 0.39, 0.33]);

                amp_det = Amplitude.kr(play_sig, 0.0005, 0.3);
                dyn_stab = 1.0 - (amp_det.max(0.8) - 0.8 * 0.7).clip(0, 0.6);
                safe_fb = Select.kr(gate_play < 0.5, [fb_comp_curve * dyn_stab, DC.kr(1.0)]);

                write_sig = (play_sig * l_dub_arr[i] * safe_fb) + (in_sig * l_rec_lvl_arr[i].dbamp * gate_rec);
                BufWr.ar(write_sig, b_idx, ptr);

                output_sig = sig_out * gate_play;

                // PHYSICS
                tape_physics_cutoff = LinExp.ar(final_rate.abs.max(0.01), 0.25, 1.0, 6000, 17000).clip(1000, 20000);
                output_sig = LPF.ar(output_sig, tape_physics_cutoff);
                deg_hpf = Select.kr(l_deg_arr[i] > 0.5, [LinExp.kr(l_deg_arr[i], 0.0, 0.5, 10, 60), Select.kr(l_deg_arr[i] > 0.8, [LinExp.kr(l_deg_arr[i], 0.5, 0.8, 60, 100), LinExp.kr(l_deg_arr[i], 0.8, 1.0, 100, 160)])]);
                output_sig = HPF.ar(output_sig, deg_hpf);
                output_sig = HPF.ar(output_sig, organic_brake_hpf);
                output_sig = output_sig * flux_gain;

                // Klangfilm EQ
                sat_low = output_sig.squared * 0.2 * l_low_arr[i].max(0);
                output_sig = (output_sig + sat_low).distort;
                output_sig = BLowShelf.ar(output_sig, 60, 0.6, l_low_arr[i]);
                output_sig = BHiShelf.ar(output_sig, 10000, 0.6, l_high_arr[i]);
                slew_val = LinExp.kr(l_high_arr[i].max(0), 0, 12, 20000, 2000);
                output_sig = Slew.ar(output_sig, slew_val, slew_val).sin;

                // DJ Filter
                c_lpf = l_filter_arr[i].min(0.5) * 2;
                c_hpf = (l_filter_arr[i] - 0.5).max(0) * 2;
                output_sig = LPF.ar(output_sig, LinExp.kr(c_lpf, 0, 1, 20, 20000));
                output_sig = HPF.ar(output_sig, LinExp.kr(c_hpf, 0, 1, 20, 20000));
                output_sig = (output_sig * (1.0 + (l_low_arr[i].abs.max(l_high_arr[i].abs) / 18.0).squared)).tanh;

                mid = (output_sig[0] + output_sig[1]) * 0.5;
                side = (output_sig[0] - output_sig[1]) * 0.5;
                output_sig = Balance2.ar(mid + (side * l_width_arr[i]), mid - (side * l_width_arr[i]), l_pan_arr[i]);

                Out.ar(bus_idx, output_sig);
                loop_outputs_sum = loop_outputs_sum + (output_sig * LinLin.kr(l_vol_arr[i], 0, 1, -60, 12).dbamp * (l_vol_arr[i] > 0.001));
            });

            // Master
            master_out = loop_outputs_sum + (proc_in * monitor_amp.dbamp);
            main_mon_amp = LinLin.kr(main_mon, 0, 1, -60, 12).dbamp * (main_mon > 0.001);

            // Send to reverb (before master processing)
            Out.ar(bus_reverb_send, loop_outputs_sum);

            // Bass Focus
            bf_freq = Select.kr(bass_focus_mode.clip(1, 3), [50, 100, 200]);
            bf_mono = LPF.ar(LPF.ar((master_out[0] + master_out[1]) * 0.5, bf_freq), bf_freq);
            bf_highs = [HPF.ar(HPF.ar(master_out[0], bf_freq), bf_freq), HPF.ar(HPF.ar(master_out[1], bf_freq), bf_freq)];
            master_out = Select.ar(bass_focus_mode > 0, [master_out, bf_highs + (bf_mono ! 2)]);

            driven_sig = master_out * comp_drive.dbamp;
            master_glue = Compander.ar(driven_sig, driven_sig, comp_thresh.dbamp, 1.0, 1.0/comp_ratio, 0.01, 0.1);
            gr_sig = (Peak.kr(driven_sig, Impulse.kr(20)) - Peak.kr(master_glue, Impulse.kr(20))).max(0);

            master_out = Limiter.ar(Balance2.ar(master_glue[0], master_glue[1], balance).tanh, limiter_ceil.dbamp) * main_mon_amp;
            Out.ar(out_bus, master_out);

            // Visuals
            trig_visuals = Impulse.kr(60);
            SendReply.kr(trig_visuals, '/airports/visuals', [
                Mix(LagUD.kr(Peak.kr(master_out[0], Impulse.kr(30)), 0, 0.1)),
                Mix(LagUD.kr(Peak.kr(master_out[1], Impulse.kr(30)), 0, 0.1)),
                Mix(LagUD.kr(gr_sig.sum, 0, 0.1)),
                pointers[0], pointers[1], pointers[2], pointers[3]
            ].flat);
        }).add;

        context.server.sync;

        // INSTANTIATE
        synth_proc = Synth.new(\Airports_Processor, [\in_bus, context.in_b, \bus_proc_out, b_input_proc.index], context.xg, \addToHead);

        synth_loopers = Synth.new(\Airports_Loopers, [
            \out_bus, context.out_b,
            \bus_proc_in, b_input_proc.index,
            \bus_reverb_send, b_reverb_send.index,
            \bus_reverb_return, b_reverb_return.index,
            \buf1, buf1, \buf2, buf2, \buf3, buf3, \buf4, buf4,
            \t1_bus, track_out_buses[0].index, \t2_bus, track_out_buses[1].index,
            \t3_bus, track_out_buses[2].index, \t4_bus, track_out_buses[3].index
        ], context.xg, \addToTail);

        synth_rev = Synth.new(\Airports_Reverb, [\in_bus, b_reverb_send.index, \out_bus, b_reverb_return.index], context.xg, \addToTail);

        // COMMANDS
        this.addCommand("noise_amp", "f", { |msg| synth_proc.set(\noise_amp, msg[1]); });
        this.addCommand("noise_type", "f", { |msg| synth_proc.set(\noise_type, msg[1]); });
        this.addCommand("global_lpf", "f", { |msg| synth_proc.set(\global_lpf, msg[1]); });
        this.addCommand("global_hpf", "f", { |msg| synth_proc.set(\global_hpf, msg[1]); });

        this.addCommand("reverb_mix", "f", { |msg| synth_rev.set(\reverb_mix, msg[1]); });
        this.addCommand("reverb_time", "f", { |msg| synth_rev.set(\reverb_time, msg[1]); });
        this.addCommand("reverb_damp", "f", { |msg| synth_rev.set(\reverb_damp, msg[1]); });

        this.addCommand("l1_config", "ffffffffffff", { |msg| synth_loopers.set(\l1_rec, msg[1], \l1_play, msg[2], \l1_vol, msg[3], \l1_speed, msg[4], \l1_start, msg[5], \l1_end, msg[6], \l1_src, msg[7], \l1_dub, msg[8], \l1_deg, msg[9], \l1_brake, msg[10], \l1_rec_lvl, msg[11], \l1_length, msg[12]); });
        this.addCommand("l2_config", "ffffffffffff", { |msg| synth_loopers.set(\l2_rec, msg[1], \l2_play, msg[2], \l2_vol, msg[3], \l2_speed, msg[4], \l2_start, msg[5], \l2_end, msg[6], \l2_src, msg[7], \l2_dub, msg[8], \l2_deg, msg[9], \l2_brake, msg[10], \l2_rec_lvl, msg[11], \l2_length, msg[12]); });
        this.addCommand("l3_config", "ffffffffffff", { |msg| synth_loopers.set(\l3_rec, msg[1], \l3_play, msg[2], \l3_vol, msg[3], \l3_speed, msg[4], \l3_start, msg[5], \l3_end, msg[6], \l3_src, msg[7], \l3_dub, msg[8], \l3_deg, msg[9], \l3_brake, msg[10], \l3_rec_lvl, msg[11], \l3_length, msg[12]); });
        this.addCommand("l4_config", "ffffffffffff", { |msg| synth_loopers.set(\l4_rec, msg[1], \l4_play, msg[2], \l4_vol, msg[3], \l4_speed, msg[4], \l4_start, msg[5], \l4_end, msg[6], \l4_src, msg[7], \l4_dub, msg[8], \l4_deg, msg[9], \l4_brake, msg[10], \l4_rec_lvl, msg[11], \l4_length, msg[12]); });

        this.addCommand("l1_seek", "f", { |msg| synth_loopers.set(\l1_seek_pos, msg[1], \t_l1_seek_trig, 1); });
        this.addCommand("l2_seek", "f", { |msg| synth_loopers.set(\l2_seek_pos, msg[1], \t_l2_seek_trig, 1); });
        this.addCommand("l3_seek", "f", { |msg| synth_loopers.set(\l3_seek_pos, msg[1], \t_l3_seek_trig, 1); });
        this.addCommand("l4_seek", "f", { |msg| synth_loopers.set(\l4_seek_pos, msg[1], \t_l4_seek_trig, 1); });

        this.addCommand("l_vol", "if", { |msg| synth_loopers.set(("l" ++ msg[1] ++ "_vol").asSymbol, msg[2]); });
        this.addCommand("l_low", "if", { |msg| synth_loopers.set(("l" ++ msg[1] ++ "_low").asSymbol, msg[2]); });
        this.addCommand("l_high", "if", { |msg| synth_loopers.set(("l" ++ msg[1] ++ "_high").asSymbol, msg[2]); });
        this.addCommand("l_filter", "if", { |msg| synth_loopers.set(("l" ++ msg[1] ++ "_filter").asSymbol, msg[2]); });
        this.addCommand("l_pan", "if", { |msg| synth_loopers.set(("l" ++ msg[1] ++ "_pan").asSymbol, msg[2]); });
        this.addCommand("l_width", "if", { |msg| synth_loopers.set(("l" ++ msg[1] ++ "_width").asSymbol, msg[2]); });
        this.addCommand("l_rec_lvl", "if", { |msg| synth_loopers.set(("l" ++ msg[1] ++ "_rec_lvl").asSymbol, msg[2]); });
        this.addCommand("l_brake", "if", { |msg| synth_loopers.set(("l" ++ msg[1] ++ "_brake").asSymbol, msg[2]); });
        this.addCommand("l_speed", "if", { |msg| synth_loopers.set(("l" ++ msg[1] ++ "_speed").asSymbol, msg[2]); });

        this.addCommand("main_mon", "f", { |msg| synth_loopers.set(\main_mon, msg[1]); });
        this.addCommand("monitor_amp", "f", { |msg| synth_loopers.set(\monitor_amp, msg[1]); });
        this.addCommand("comp_thresh", "f", { |msg| synth_loopers.set(\comp_thresh, msg[1]); });
        this.addCommand("comp_ratio", "f", { |msg| synth_loopers.set(\comp_ratio, msg[1]); });
        this.addCommand("comp_drive", "f", { |msg| synth_loopers.set(\comp_drive, msg[1]); });
        this.addCommand("bass_focus", "i", { |msg| synth_loopers.set(\bass_focus_mode, msg[1]); });
        this.addCommand("limiter_ceil", "f", { |msg| synth_loopers.set(\limiter_ceil, msg[1]); });
        this.addCommand("balance", "f", { |msg| synth_loopers.set(\balance, msg[1]); });

        this.addCommand("buffer_read", "is", { |msg|
            var remote = NetAddr("127.0.0.1", 10111);
            var bufnum = buffers[msg[1]-1];
            if(File.exists(msg[2]), {
                bufnum.zero;
                Buffer.readChannel(context.server, msg[2], 0, bufnum.numFrames, [0, 1], action: { |b|
                    var dur = b.numFrames / context.server.sampleRate;
                    b.copyData(bufnum); b.free;
                    remote.sendMsg("/buffer_info", msg[1], dur);
                });
            });
        });
        this.addCommand("buffer_write", "isf", { |msg|
            var bufnum = buffers[msg[1]-1];
            var duration = msg[3];
            var numFrames = (duration * context.server.sampleRate).asInteger;
            if(numFrames > 0, { bufnum.write(msg[2], "wav", "int24", numFrames); }, { bufnum.write(msg[2], "wav", "int24"); });
        });
        this.addCommand("clear", "i", { |msg| buffers[msg[1]-1].zero; });
    }

    free {
        osc_bridge.free;
        synth_proc.free; synth_loopers.free; synth_rev.free;
        amp_bus_l.free; amp_bus_r.free;
        gr_bus.free;
        track_out_buses.do(_.free);
        buf1.free; buf2.free; buf3.free; buf4.free; dummy_buf.free;
        b_input_proc.free; b_reverb_send.free; b_reverb_return.free; b_analysis.free;
    }
}