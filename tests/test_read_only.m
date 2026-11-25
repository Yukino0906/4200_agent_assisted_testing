function ok = test_read_only(cfg)
%TEST_READ_ONLY  Contact check and repeated low-bias reads. No writes at all.
%
%   ok = TEST_READ_ONLY() connects, verifies the probe contact at
%   cfg.safety.contact_check.voltage, then reads the conductance 10 times at
%   cfg.read.voltage and reports the spread. It never applies a switching
%   voltage, so it is the correct second step after a probe landing.
%
%   Run it every time you move to a new device: it catches a lifted probe, a
%   broken line, a short, and an unformed device before any energy is put
%   into the stack.
%
%   ok = TEST_READ_ONLY(cfg) uses a caller-supplied config. The default runs
%   against the REAL instrument with dry_run disabled -- reading at 0.1 V is
%   the whole point and is harmless -- but writes are impossible because this
%   function never calls apply_voltage_pulse.
%
%   Inputs:
%       cfg - optional configuration struct
%
%   Outputs:
%       ok - logical, true when the contact check passed and the reads were
%            consistent
%
%   Instrument side effects: applies the contact-check bias and the read
%   bias. Returns to 0 V with the output off.
%
%   Exceptions: none propagate.
%
%   See also TEST_INSTRUMENT_CONNECTION, CHECK_CONTACT, MEASURE_CONDUCTANCE.

if nargin < 1 || isempty(cfg)
    cfg = default_config();
    cfg.mode.simulate_instrument = false;
    cfg.mode.dry_run             = false;   % reading requires the output on
    if isempty(cfg.device.device_id)
        cfg.device.device_id = input('Device ID: ', 's');
    end
end

fprintf('\n================================================================\n');
fprintf(' READ-ONLY CONTACT AND CONDUCTANCE CHECK\n');
fprintf('================================================================\n');
fprintf('  device_id        : %s\n', cfg.device.device_id);
fprintf('  contact bias     : %+.3f V\n', cfg.safety.contact_check.voltage);
fprintf('  read bias        : %+.3f V\n', cfg.read.voltage);
fprintf('  read compliance  : %.4g A\n', cfg.read.compliance);
fprintf('  NO write pulses are applied by this test.\n\n');

ok   = false;
inst = [];

try
    cfg = validate_config(cfg);
    run = create_run_directory(cfg, 'read_only_check');
    inst = connect_instruments(cfg, run);
    % Output-off guard for every exit, Ctrl+C included. Built only now: an
    % anonymous function captures the value `inst` has when it is created,
    % so a guard made while inst was [] could never turn anything off.
    % InstrumentSession is a handle, so this guard sees the live session.
    cleanup = onCleanup(@() local_cleanup(inst));

    % ---- contact check --------------------------------------------------
    fprintf('[1/3] Contact check ...\n');
    contact = check_contact(inst, cfg);
    fprintf('      %s\n', contact.message);
    if ~contact.passed
        fprintf(2, '\n  STOP: contact check failed (%s). Do not proceed.\n', contact.verdict);
        result = struct('summary', struct('contact_verdict', contact.verdict, ...
            'contact_current_A', contact.current_A));
        finish_measurement(run, cfg, inst, result, 'failed', contact.message);
        return;
    end

    if ~confirm_step(cfg, 'Contact confirmed -- proceed to repeated reads?', { ...
            sprintf('measured : %.4g A -> G = %.4g S (R = %.4g Ohm)', ...
                    contact.current_A, contact.conductance_S, contact.resistance_Ohm), ...
            sprintf('next     : 10 reads at %+.3f V (no writes)', cfg.read.voltage)})
        result = struct('summary', struct());
        finish_measurement(run, cfg, inst, result, 'stopped_by_user', 'operator stopped');
        return;
    end

    % ---- repeated reads -------------------------------------------------
    fprintf('\n[2/3] Ten conductance reads at %+.3f V ...\n', cfg.read.voltage);
    configure_instruments(inst, cfg, 'read');
    n = 10;
    G = nan(1, n);
    t0 = tic;
    for k = 1:n
        [G(k), info] = measure_conductance(inst, cfg);
        fprintf('      %2d: I = %+.5g A, G = %.5g S, R = %.5g Ohm  [%s]\n', ...
            k, info.current_A, G(k), info.resistance_Ohm, info.status);
        row = struct('device_id', cfg.device.device_id, 'run_id', run.run_id, ...
            'read_index', k, 'timestamp_s', toc(t0), ...
            'read_voltage_V', info.read_voltage_V, ...
            'measured_current_A', info.current_A, 'conductance_S', G(k), ...
            'resistance_Ohm', info.resistance_Ohm, 'instrument_status', info.status);
        append_measurement_row(run.data_csv, row);
    end

    % ---- verdict --------------------------------------------------------
    fprintf('\n[3/3] Assessment ...\n');
    g = G(isfinite(G));
    summary = struct('contact_verdict', contact.verdict, ...
                     'n_reads', numel(g), 'mean_G_S', NaN, 'std_G_S', NaN, 'cv', NaN);
    if numel(g) < 2
        fprintf(2, '      Too few valid reads (%d).\n', numel(g));
    else
        summary.mean_G_S = mean(g);
        summary.std_G_S  = std(g);
        summary.cv       = summary.std_G_S / abs(summary.mean_G_S);
        fprintf('      G = %.5g S  +/- %.3g S  (CV = %.4f, R = %.5g Ohm)\n', ...
            summary.mean_G_S, summary.std_G_S, summary.cv, 1/summary.mean_G_S);
        if summary.cv > 0.05
            fprintf(2, ['      WARNING: %.1f%% scatter between reads. Check the probe ' ...
                        'landing and the cabling before trusting any dG measurement.\n'], ...
                100*summary.cv);
        else
            fprintf('      Read repeatability looks healthy.\n');
            ok = true;
        end
    end

    result = struct('summary', summary);
    finish_measurement(run, cfg, inst, result, 'completed', '');

catch err
    fprintf(2, '\nREAD-ONLY TEST FAILED\n  %s: %s\n', err.identifier, err.message);
    if ~isempty(inst) && isvalid(inst)
        emergency_shutdown(inst, 'read-only test failed');
    end
end

fprintf('\n----------------------------------------------------------------\n');
if ok
    fprintf(' RESULT: PASS. Next: tests\\test_single_safe_pulse.m\n');
else
    fprintf(2, ' RESULT: not clean. Investigate before applying any pulse.\n');
end
fprintf('----------------------------------------------------------------\n\n');

if nargout == 0
    clear ok;
end
end

% ------------------------------------------------------------------------
function local_cleanup(inst)
try
    if ~isempty(inst) && isvalid(inst) && inst.Connected
        safe_output_off(inst);
        disconnect_instruments(inst);
    end
catch
end
end
