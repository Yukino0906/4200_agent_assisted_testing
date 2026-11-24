function r = example_iv(cfg)
%EXAMPLE_IV  Bipolar DC I-V cycling: hysteresis loop and HRS/LRS window.
%
%   r = EXAMPLE_IV()     runs on the simulator (no instrument).
%   r = EXAMPLE_IV(cfg)  runs with your device file, e.g.
%                            r = example_iv(device_chipA_R9C9_iv());
%
%   Each cycle sweeps  0 -> +v_positive_max -> 0 -> v_negative_max -> 0
%   and reads HRS/LRS at cfg.read.voltage after each half.
%
%   Fields that matter (cfg.dc.*):
%       v_positive_max, v_negative_max  [V]  sweep ends; start small, widen step by step
%       v_step [V], delay [s]                point spacing and dwell per point
%       compliance [A]                       the main protection; start at 1e-3 or lower
%       num_cycles                           start with 3-5
%
%   Output in r.run_dir:
%       measurement_data.csv  one row per point (cycle_id, segment,
%                             applied_voltage_V, measured_current_A, ...)
%       cycle_summary.csv     one row per cycle (G_hrs_S, G_lrs_S, on_off_ratio,
%                             V_set_complete_V, V_reset_complete_V, ...)
%       iv.png                |I| vs V on a log axis, one line per cycle
%
%   The window (G_hrs_S, G_lrs_S) is stored in the run metadata. Later pulse
%   tests with the same device_id pick it up automatically.
%
%   V_set / V_reset here are hysteresis-CLOSURE voltages (transition
%   complete), not jump-onset thresholds. Quote the definition with them.
%
%   See also RUN_DC_CYCLE_TEST, LOAD_RUN_CSV.

if nargin < 1 || isempty(cfg)
    cfg = sim_config('iv');
    cfg.dc.num_cycles = 3;
end

r = run_dc_cycle_test(cfg);
if r.n_rows < 1
    return;
end

T = load_run_csv(r);
fig = figure('Name', 'DC I-V');
cycles = unique(T.cycle_id)';
for c = cycles
    k = T.cycle_id == c & T.applied_voltage_V ~= 0;   % |I| at 0 V is just the noise floor
    semilogy(T.applied_voltage_V(k), abs(T.measured_current_A(k)), '.-', ...
        'DisplayName', sprintf('cycle %d', c));
    hold on;
end
xlabel('Voltage (V)');
ylabel('|Current| (A)');
title(sprintf('%s, compliance %.3g A', cfg.device.device_id, cfg.dc.compliance), ...
    'Interpreter', 'none');
legend('Location', 'southeast');
save_run_figure(fig, r, 'iv');

S = load_run_csv(r, 'cycle_summary.csv');
fprintf('\n  cycle   G_HRS (S)    G_LRS (S)    on/off   V_set_closure (V)   V_reset_closure (V)\n');
for i = 1:height(S)
    fprintf('  %5d   %10.4g   %10.4g   %6.1f   %17.3f   %19.3f\n', S.cycle_id(i), ...
        S.G_hrs_S(i), S.G_lrs_S(i), S.on_off_ratio(i), ...
        S.V_set_complete_V(i), S.V_reset_complete_V(i));
end
fprintf('  (G read at %+.3f V)\n', cfg.read.voltage);
end
