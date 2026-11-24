function r = example_relaxation(cfg)
%EXAMPLE_RELAXATION  Short-term drift after a write: G(t) / G(0) on a log time axis.
%
%   r = EXAMPLE_RELAXATION()     runs on the simulator (no instrument).
%   r = EXAMPLE_RELAXATION(cfg)  runs with your device file.
%
%   For each state and repeat: write-verify to the state, then read at the
%   scheduled times cfg.relaxation.sample_times (0 = as early as possible).
%   The actual elapsed time of every read is recorded; use it, not the
%   schedule.
%
%   Fields that matter (cfg.relaxation.*):
%       sample_times        [s] sorted, log-spaced; max(sample_times) sets the
%                               length of every trace
%       states_normalized       states, 0 = HRS .. 1 = LRS
%       repeats                 traces per state
%   Total time ~ max(sample_times) x states x repeats.
%
%   Relaxation is the seconds-to-minutes drift right after a write. It is
%   what decides whether a write-then-verify result is still true a moment
%   later. Use EXAMPLE_RETENTION for the long hold.
%
%   Prerequisite: a conductance window for this device_id.
%
%   Output in r.run_dir:
%       measurement_data.csv  one row per read (state_index, repeat_id,
%                             actual_time_s, conductance_S, G_zero_S,
%                             relative_drift, within_tolerance, ...)
%       relaxation.png        relative drift vs time, one line per trace
%
%   See also RUN_RELAXATION_TEST, EXAMPLE_RETENTION, LOAD_RUN_CSV.

if nargin < 1 || isempty(cfg)
    cfg = sim_config('relaxation');
    cfg.device.G_hrs_S = cfg.sim.G_hrs;
    cfg.device.G_lrs_S = cfg.sim.G_lrs;
    cfg.relaxation.sample_times = [0 0.1 0.3 1 3 10];
    cfg.relaxation.repeats      = 1;
end

r = run_relaxation_test(cfg);
if r.n_rows < 1
    return;
end

T = load_run_csv(r);
fig = figure('Name', 'Relaxation');
for s = unique(T.state_index)'
    for k = unique(T.repeat_id(T.state_index == s))'
        m = T.state_index == s & T.repeat_id == k & T.actual_time_s > 0;
        semilogx(T.actual_time_s(m), 100 * T.relative_drift(m), 'o-', ...
            'DisplayName', sprintf('state %d, repeat %d', s, k));
        hold on;
    end
end
yline(0, 'k:', 'HandleVisibility', 'off');
xlabel('Time after verify read (s)');
ylabel('(G - G_0) / G_0 (%)');
title(sprintf('%s, read at %+.2f V', cfg.device.device_id, cfg.read.voltage), ...
    'Interpreter', 'none');
legend('Location', 'best');
save_run_figure(fig, r, 'relaxation');
end
