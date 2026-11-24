function r = example_endurance(cfg)
%EXAMPLE_ENDURANCE  SET-train / RESET-train cycling until the window collapses.
%
%   r = EXAMPLE_ENDURANCE()     runs on the simulator (no instrument).
%   r = EXAMPLE_ENDURANCE(cfg)  runs with your device file.
%
%   Every cycle: n x SET pulse -> read G_set -> n x RESET pulse -> read G_reset.
%   Window ratio = G_set / G_reset. The initial window is the median of the
%   first baseline_cycles cycles.
%
%   Fields that matter (cfg.endurance.*):
%       set_amplitude_V, reset_amplitude_V  [V]
%       width_s                             [s]
%       pulses_per_train                         n
%       max_cycles                               hard ceiling on cycles
%       baseline_cycles                          cycles that define the initial window
%       stop_ratio_min                           stop when ratio < this (absolute)
%       stop_frac_min                            ...or < this x the initial ratio
%   Total pulses = 2 x pulses_per_train x cycles; keep it under
%   cfg.safety.max_total_pulses or the run stops at the budget.
%   For long runs, raise max_cycles in steps (100 -> 1000 -> 10000) and look
%   at the data between steps.
%
%   Output in r.run_dir:
%       measurement_data.csv  one row per cycle (cycle_index, G_set_S, G_reset_S,
%                             window_ratio, ratio_vs_initial, stop_reason, ...)
%       endurance.png         G_set and G_reset vs cycle
%
%   See also RUN_ENDURANCE_TEST, LOAD_RUN_CSV.

if nargin < 1 || isempty(cfg)
    cfg = sim_config('endurance');
    cfg.endurance.max_cycles = 40;
end

r = run_endurance_test(cfg);
if r.n_rows < 1
    return;
end

T = load_run_csv(r);
fig = figure('Name', 'Endurance');
semilogy(T.cycle_index, T.G_set_S, 'o-', 'DisplayName', 'after SET train');
hold on;
semilogy(T.cycle_index, T.G_reset_S, 's-', 'DisplayName', 'after RESET train');
xlabel('Cycle');
ylabel(sprintf('G at %+.2f V (S)', cfg.read.voltage));
title(sprintf('%s, stop: %s', cfg.device.device_id, r.summary.stop_reason), ...
    'Interpreter', 'none');
legend('Location', 'best');
save_run_figure(fig, r, 'endurance');
end
