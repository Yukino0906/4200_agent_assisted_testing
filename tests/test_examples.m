function ok = test_examples()
%TEST_EXAMPLES  Run every example on the simulator and check its outputs.
%
%   ok = TEST_EXAMPLES() calls each examples/example_*.m with no arguments
%   (simulator mode), and checks that the run completed, wrote data and
%   saved its figure. Takes several minutes; needs no instrument.
%
%   Run it after changing an example or anything the examples depend on.
%
%   Outputs:
%       ok - logical, true when every example passed
%
%   Instrument side effects: none (every example defaults to the simulator).
%
%   See also TEST_DRY_RUN.

cases = { ...
    'example_iv',                @example_iv,                'iv.png'; ...
    'example_ltp_ltd',           @example_ltp_ltd,           'ltp_ltd.png'; ...
    'example_single_pulse_map',  @example_single_pulse_map,  'pulse_map.png'; ...
    'example_endurance',         @example_endurance,         'endurance.png'; ...
    'example_retention',         @example_retention,         'retention.png'; ...
    'example_read_noise',        @example_read_noise,        'read_noise.png'; ...
    'example_relaxation',        @example_relaxation,        'relaxation.png'};

passed = 0;
failed = 0;
for i = 1:size(cases, 1)
    name = cases{i, 1};
    fprintf('\n=== %s ===\n', name);
    try
        r = cases{i, 2}();
        close all;
        good = strcmp(r.status, 'completed') && r.n_rows > 0 && ...
               exist(fullfile(r.run_dir, cases{i, 3}), 'file') == 2;
        detail = sprintf('status=%s rows=%g png=%d', r.status, r.n_rows, ...
            exist(fullfile(r.run_dir, cases{i, 3}), 'file') == 2);
    catch e
        good = false;
        detail = sprintf('%s: %s', e.identifier, e.message);
    end
    if good
        passed = passed + 1;
        fprintf('  [ PASS ] %s\n', name);
    else
        failed = failed + 1;
        fprintf(2, '  [ FAIL ] %s -- %s\n', name, detail);
    end
end

fprintf('\n EXAMPLES: %d passed, %d failed\n\n', passed, failed);
ok = (failed == 0);
if nargout == 0
    clear ok;
end
end
