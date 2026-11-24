function r = example_single_pulse_map(cfg)
%EXAMPLE_SINGLE_PULSE_MAP  dG = f(G_before, V_pulse, t_pulse, polarity), one pulse per trial.
%
%   r = EXAMPLE_SINGLE_PULSE_MAP()     runs on the simulator (no instrument).
%   r = EXAMPLE_SINGLE_PULSE_MAP(cfg)  runs with your device file.
%
%   Loop: states x amplitudes (SET and RESET) x widths x repeats. Every trial:
%       1. write-verify back to the start state     (initialize_to_state)
%       2. wait cfg.initial_states.settle_time       (keep >= 1 s on real devices)
%       3. read G_before
%       4. apply exactly ONE test pulse
%       5. wait cfg.read.delay_after_write, read G_after
%       6. append one row to disk
%
%   Fields that matter:
%       cfg.pulse.set_amplitudes / reset_amplitudes  [V]  test amplitudes
%       cfg.pulse.widths                             [s]  test widths
%       cfg.initial_states.normalized                     start states, 0 = HRS .. 1 = LRS
%       cfg.single_pulse.num_states / amplitudes_subset / repeats   matrix size
%       cfg.initial_states.*_amplitude_*             [V]  write-verify drive; keep these
%                                                         OFF the test amplitudes, or the
%                                                         map measures the initialisation
%   Matrix size = states x 2*amplitudes x widths x repeats trials, each costing
%   1 test pulse plus several write-verify pulses. Check the estimate printed
%   at the checkpoint against cfg.safety.max_total_pulses.
%
%   Prerequisite: a conductance window for this device_id.
%
%   Output in r.run_dir:
%       measurement_data.csv  one row per trial (G_before_S, pulse_voltage_V,
%                             pulse_width_s, pulse_width_measured_s, G_after_S,
%                             delta_G_S, normalized_delta_G, initialization_success, ...)
%       pulse_map.png         dG/G_before vs G_before, one marker per amplitude
%   Bin on the MEASURED G_before_S and fit on pulse_width_measured_s, not on
%   the nominal target or the programmed width.
%
%   See also RUN_SINGLE_PULSE_MAP, LOAD_RUN_CSV.

if nargin < 1 || isempty(cfg)
    cfg = sim_config('pulse_map');
    cfg.device.G_hrs_S = cfg.sim.G_hrs;
    cfg.device.G_lrs_S = cfg.sim.G_lrs;
    cfg.pulse.widths   = 10e-6;
    cfg.single_pulse.repeats = 4;
    cfg.initial_states.settle_time = 0.2;
end

r = run_single_pulse_map(cfg);
if r.n_rows < 1
    return;
end

T = load_run_csv(r);
T = T(isfinite(T.G_before_S) & isfinite(T.normalized_delta_G), :);
fig = figure('Name', 'Single-pulse map');
amps = unique(T.pulse_voltage_V)';
for v = amps
    k = T.pulse_voltage_V == v;
    semilogx(T.G_before_S(k), 100 * T.normalized_delta_G(k), 'o', ...
        'DisplayName', sprintf('%+.2f V', v));
    hold on;
end
yline(0, 'k:', 'HandleVisibility', 'off');
xlabel(sprintf('G_{before} at %+.2f V (S)', cfg.read.voltage));
ylabel('\DeltaG / G_{before} (%)');
title(sprintf('%s, one pulse per trial', cfg.device.device_id), 'Interpreter', 'none');
legend('Location', 'best');
save_run_figure(fig, r, 'pulse_map');
end
