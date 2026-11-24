function r = example_retention(cfg)
%EXAMPLE_RETENTION  Write a state, then read it periodically until it drifts away.
%
%   r = EXAMPLE_RETENTION()     runs on the simulator (no instrument, short hold).
%   r = EXAMPLE_RETENTION(cfg)  runs with your device file.
%
%   For each entry of cfg.retention.states:
%       1. apply the write train (n_pulses x amplitude_V, width_s)
%       2. read G every interval_s; G0 = first read after the train
%       3. stop at |G - G0| / G0 > drift_limit, or after max_hold_s
%   The device rests at 0 V between reads.
%
%   Fields that matter (cfg.retention.*):
%       states          struct array with .label ('SET'|'RESET'), .amplitude_V,
%                       .width_s, .n_pulses -- one entry per state to hold
%       interval_s      [s] read period (every read is a small disturbance)
%       max_hold_s      [s] hold ceiling per state
%       drift_limit         relative drift that ends the hold early
%       rest_between_s  [s] rest between states
%   Total time is up to numel(states) x max_hold_s: give a background agent
%   job a timeout longer than that.
%
%   Output in r.run_dir:
%       measurement_data.csv  one row per read (state_label, actual_time_s,
%                             conductance_S, G0_S, relative_drift, stop_reason, ...)
%       retention.png         G / G0 vs time, one line per state
%
%   See also RUN_RETENTION_HOLD_TEST, EXAMPLE_RELAXATION, LOAD_RUN_CSV.

if nargin < 1 || isempty(cfg)
    cfg = sim_config('retention');
    cfg.retention.interval_s     = 1;
    cfg.retention.max_hold_s     = 20;
    cfg.retention.rest_between_s = 0;
end

r = run_retention_hold_test(cfg);
if r.n_rows < 1
    return;
end

T = load_run_csv(r);
fig = figure('Name', 'Retention');
for s = unique(T.state_index)'
    k = T.state_index == s;
    lbl = T.state_label(find(k, 1));
    plot(T.actual_time_s(k), T.conductance_S(k) ./ T.G0_S(k), '.-', ...
        'DisplayName', sprintf('%s', lbl{1}));
    hold on;
end
yline(1, 'k:', 'HandleVisibility', 'off');
xlabel('Time after write (s)');
ylabel('G / G_0');
title(sprintf('%s, read at %+.2f V', cfg.device.device_id, cfg.read.voltage), ...
    'Interpreter', 'none');
legend('Location', 'best');
save_run_figure(fig, r, 'retention');
end
