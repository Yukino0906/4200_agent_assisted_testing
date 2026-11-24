function r = example_read_noise(cfg)
%EXAMPLE_READ_NOISE  Repeated reads of fixed states: read noise and read disturb.
%
%   r = EXAMPLE_READ_NOISE()     runs on the simulator (no instrument).
%   r = EXAMPLE_READ_NOISE(cfg)  runs with your device file.
%
%   The device is written to each state once, then read num_reads times at
%   cfg.read.voltage with no write in between. A spread with no trend is read
%   noise; a monotonic trend is read disturb or relaxation, and the test
%   flags it.
%
%   Fields that matter:
%       cfg.read_noise.states_normalized   states, 0 = HRS .. 1 = LRS
%       cfg.read_noise.num_reads           reads per state (300-1000)
%       cfg.read.voltage                   [V] the read bias under test
%       cfg.read.num_average_reads         samples averaged per read
%   Run it once per candidate read bias to choose one: a good read bias has
%   low CV and no trend.
%
%   Prerequisite: a conductance window for this device_id.
%
%   Output in r.run_dir:
%       measurement_data.csv  one row per read (state_index, read_index,
%                             timestamp_s, read_voltage_V, conductance_S, ...)
%       read_noise.png        G vs read index per state, CV in the legend
%
%   See also RUN_READ_NOISE_TEST, LOAD_RUN_CSV.

if nargin < 1 || isempty(cfg)
    cfg = sim_config('read_noise');
    cfg.device.G_hrs_S = cfg.sim.G_hrs;
    cfg.device.G_lrs_S = cfg.sim.G_lrs;
    cfg.read_noise.num_reads = 100;
end

r = run_read_noise_test(cfg);
if r.n_rows < 1
    return;
end

T = load_run_csv(r);
fig = figure('Name', 'Read noise');
for s = unique(T.state_index)'
    k = T.state_index == s & isfinite(T.conductance_S);
    g = T.conductance_S(k);
    semilogy(T.read_index(k), g, '.', 'DisplayName', ...
        sprintf('state %d: CV %.2f %%', s, 100 * std(g) / mean(g)));
    hold on;
end
xlabel('Read index');
ylabel(sprintf('G at %+.2f V (S)', cfg.read.voltage));
title(sprintf('%s, %d reads per state', cfg.device.device_id, cfg.read_noise.num_reads), ...
    'Interpreter', 'none');
legend('Location', 'best');
save_run_figure(fig, r, 'read_noise');
end
