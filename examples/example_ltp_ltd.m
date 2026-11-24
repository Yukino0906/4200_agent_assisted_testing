function r = example_ltp_ltd(cfg)
%EXAMPLE_LTP_LTD  Potentiation / depression with trains of identical pulses.
%
%   r = EXAMPLE_LTP_LTD()     runs on the simulator (no instrument).
%   r = EXAMPLE_LTP_LTD(cfg)  runs with your device file, e.g.
%                                 r = example_ltp_ltd(device_chipA_R9C9_ltp());
%
%   For every amplitude pair and cycle:
%       write-verify to near HRS -> N identical SET pulses, read after each   (LTP)
%       write-verify to near LRS -> N identical RESET pulses, read after each (LTD)
%
%   Fields that matter (cfg.ltp_ltd.*):
%       set_amplitudes, reset_amplitudes  [V]  paired weak/medium/strong (> 0 / < 0)
%       width                             [s]  one width for all pulses
%       num_pulses                             pulses per branch
%       num_cycles                             LTP+LTD repetitions per amplitude
%       stop_on_saturation, saturation_tol, saturation_patience
%       require_initialization                 false = run the train even if
%                                              write-verify missed (G_before is
%                                              recorded per pulse anyway)
%   The drive amplitude must clearly exceed the response threshold of that
%   polarity; an under-driven branch measures noise, not the device.
%
%   Prerequisite: a conductance window for this device_id (run example_iv
%   first, or set cfg.device.G_hrs_S / G_lrs_S).
%
%   Output in r.run_dir:
%       measurement_data.csv  one row per pulse (amplitude_index, cycle_id,
%                             branch, pulse_index, pulse_voltage_V,
%                             pulse_width_measured_s, G_before_S, G_after_S, ...)
%       ltp_ltd.png           G vs pulse number, LTP then LTD, per amplitude
%
%   See also RUN_LTP_LTD_TEST, LOAD_RUN_CSV.

if nargin < 1 || isempty(cfg)
    cfg = sim_config('ltp_ltd');
    cfg.device.G_hrs_S = cfg.sim.G_hrs;   % the simulator's window
    cfg.device.G_lrs_S = cfg.sim.G_lrs;
    cfg.ltp_ltd.num_pulses = 30;
    cfg.ltp_ltd.num_cycles = 2;
    cfg.initial_states.settle_time = 0.2;
end

r = run_ltp_ltd_test(cfg);
if r.n_rows < 1
    return;
end

T = load_run_csv(r);
fig = figure('Name', 'LTP / LTD');
amps = unique(T.amplitude_index)';
for a = amps
    for c = unique(T.cycle_id(T.amplitude_index == a))'
        ltp = T.amplitude_index == a & T.cycle_id == c & strcmp(T.branch, 'LTP');
        ltd = T.amplitude_index == a & T.cycle_id == c & strcmp(T.branch, 'LTD');
        nLtp = sum(ltp);
        x = [T.pulse_index(ltp); nLtp + T.pulse_index(ltd)];
        y = [T.G_after_S(ltp); T.G_after_S(ltd)];
        vS = T.pulse_voltage_V(find(ltp, 1));
        vR = T.pulse_voltage_V(find(ltd, 1));
        plot(x, y, '.-', 'DisplayName', ...
            sprintf('%+.2f / %+.2f V, cycle %d', vS, vR, c));
        hold on;
    end
end
xlabel('Pulse number (LTP, then LTD)');
ylabel(sprintf('G at %+.2f V (S)', cfg.read.voltage));
title(sprintf('%s, width %.3g s', cfg.device.device_id, cfg.ltp_ltd.width), ...
    'Interpreter', 'none');
legend('Location', 'best');
save_run_figure(fig, r, 'ltp_ltd');
end
