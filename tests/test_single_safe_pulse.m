function ok = test_single_safe_pulse(cfg)
%TEST_SINGLE_SAFE_PULSE  Apply ONE modest pulse and verify the pulse machinery.
%
%   ok = TEST_SINGLE_SAFE_PULSE() is the bridge between reading and the full
%   pulse measurements. It:
%
%       1. checks the contact and reads G_before
%       2. applies exactly ONE pulse at the WEAKEST configured SET amplitude
%          and the LONGEST configured width (the gentlest useful combination)
%       3. reads G_after and reports dG and the pulse energy
%       4. VERIFIES THE ACHIEVED PULSE WIDTH against the programmed one
%
%   Step 4 is the reason this test exists. With the PMU engine every
%   configured width is first sent at the READ voltage (non-writing by
%   construction) with a waveform capture, and the delivered FWHM is
%   measured from the PMU's own voltage record (PULSE_FWHM). This checks
%   the segment timing, the rise/fall settings and the RPM path in one go,
%   before any write. With the 'pc' engine the probes run at 0 V and the
%   host timer is checked instead.
%
%   ok = TEST_SINGLE_SAFE_PULSE(cfg) uses a caller-supplied config.
%
%   Inputs:
%       cfg - optional configuration struct
%
%   Outputs:
%       ok - logical, true when the pulse was applied, the width was within
%            10% of the programmed value, and no error was queued
%
%   Instrument side effects: applies ONE real SET pulse. This WILL change the
%   device state.
%
%   Exceptions: none propagate.
%
%   See also APPLY_VOLTAGE_PULSE, TEST_READ_ONLY, RUN_SINGLE_PULSE_MAP.

if nargin < 1 || isempty(cfg)
    cfg = default_config();
    cfg.mode.simulate_instrument = false;
    cfg.mode.dry_run             = false;
    if isempty(cfg.device.device_id)
        cfg.device.device_id = input('Device ID: ', 's');
    end
end

amp   = min(cfg.pulse.set_amplitudes);    % weakest SET amplitude
width = max(cfg.pulse.widths);            % longest width = gentlest ramp

fprintf('\n================================================================\n');
fprintf(' SINGLE SAFE PULSE TEST\n');
fprintf('================================================================\n');

ok   = false;
inst = [];
cleanup = onCleanup(@() local_cleanup(inst));

try
    cfg = validate_config(cfg);
    run = create_run_directory(cfg, 'single_safe_pulse');
    inst = connect_instruments(cfg, run);

    % ---- 1. contact + baseline ------------------------------------------
    fprintf('[1/4] Contact check and baseline read ...\n');
    contact = check_contact(inst, cfg);
    fprintf('      %s\n', contact.message);
    if ~contact.passed
        fprintf(2, '      STOP: %s\n', contact.verdict);
        finish_measurement(run, cfg, inst, struct('summary', struct()), ...
            'failed', contact.message);
        return;
    end

    configure_instruments(inst, cfg, 'read');
    [Gbefore, bInfo] = measure_conductance(inst, cfg);
    fprintf('      G_before = %.5g S (R = %.5g Ohm)\n', Gbefore, bInfo.resistance_Ohm);

    % ---- 2. timing characterisation, nothing written ---------------------
    usePmu = strcmpi(cfg.pulse.timing_source, 'pmu');
    if usePmu
        vProbe = cfg.read.voltage;
        probeOpts = struct('label', 'timing_probe', 'capture', 'waveform');
        fprintf('\n[2/4] Capturing each width at the read voltage %+.3f V (nothing is written) ...\n', ...
            vProbe);
    else
        vProbe = 0;
        probeOpts = struct('label', 'timing_probe');
        fprintf('\n[2/4] Measuring achieved pulse width at 0 V (nothing is written) ...\n');
    end
    configure_instruments(inst, cfg, 'pulse');
    timing = struct('programmed_s', {}, 'measured_s', {}, 'error_fraction', {});
    for w = cfg.pulse.widths
        pr = apply_voltage_pulse(inst, cfg, vProbe, w, probeOpts);
        e = NaN;
        if isfinite(pr.width_measured_s) && w > 0
            e = (pr.width_measured_s - w) / w;
        end
        timing(end+1) = struct('programmed_s', w, 'measured_s', pr.width_measured_s, ...
                               'error_fraction', e); %#ok<AGROW>
        fprintf('      programmed %8.4g s -> measured %8.4g s  (%+.1f%%)  [%s]\n', ...
            w, pr.width_measured_s, 100*e, pr.status);
        append_measurement_row(run.data_csv, struct( ...
            'device_id', cfg.device.device_id, 'run_id', run.run_id, ...
            'phase', 'timing_probe', 'pulse_voltage_V', vProbe, ...
            'pulse_voltage_measured_V', pr.v_measured_V, 'width_basis', pr.width_basis, ...
            'pulse_width_s', w, 'pulse_width_measured_s', pr.width_measured_s, ...
            'width_error_fraction', e, 'peak_current_A', pr.peak_current_A, ...
            'average_current_A', pr.avg_current_A, ...
            'estimated_pulse_energy_J', pr.energy_J, ...
            'G_before_S', NaN, 'G_after_S', NaN, 'delta_G_S', NaN, ...
            'instrument_status', pr.status, 'error_code', pr.error_code));
    end

    worstErr = max(abs([timing.error_fraction]));
    if isfinite(worstErr) && worstErr > 0.10
        fprintf(2, ['      WARNING: worst width error is %.0f%%. Do NOT use the ' ...
                    'affected widths for the model dataset. Check cfg.pmu.rise_time / ' ...
                    'fall_time and the RPM cabling, or remove those widths.\n'], 100*worstErr);
    end

    % ---- 3. the one real pulse -------------------------------------------
    if ~confirm_step(cfg, 'Apply ONE real write pulse to this device?', { ...
            sprintf('device_id  : %s', cfg.device.device_id), ...
            sprintf('amplitude  : %+.3f V   (weakest configured SET amplitude)', amp), ...
            sprintf('width      : %.4g s    (longest configured width)', width), ...
            local_limit_line(cfg), ...
            sprintf('G_before   : %.5g S', Gbefore), ...
            'THIS WILL CHANGE THE DEVICE STATE.'})
        finish_measurement(run, cfg, inst, struct('summary', struct()), ...
            'stopped_by_user', 'operator declined the pulse');
        return;
    end

    fprintf('\n[3/4] Applying the pulse ...\n');
    configure_instruments(inst, cfg, 'pulse');
    pr = apply_voltage_pulse(inst, cfg, amp, width, struct('label', 'safe_pulse'));
    fprintf(['      status = %s, V measured = %+.4g V, width = %.5g s (%s), ' ...
             'I_peak = %.4g A, E = %.4g J (%s)\n'], ...
        pr.status, pr.v_measured_V, pr.width_measured_s, pr.width_basis, ...
        pr.peak_current_A, pr.energy_J, pr.energy_method);

    if cfg.read.delay_after_write > 0
        pause(cfg.read.delay_after_write);
    end

    % ---- 4. verify --------------------------------------------------------
    fprintf('\n[4/4] Reading back ...\n');
    configure_instruments(inst, cfg, 'read');
    [Gafter, aInfo] = measure_conductance(inst, cfg);
    dG = Gafter - Gbefore;
    fprintf('      G_after  = %.5g S (R = %.5g Ohm)\n', Gafter, aInfo.resistance_Ohm);
    fprintf('      dG       = %+.5g S  (%+.2f%%)\n', dG, 100*dG/Gbefore);

    append_measurement_row(run.data_csv, struct( ...
        'device_id', cfg.device.device_id, 'run_id', run.run_id, ...
        'phase', 'write_pulse', 'pulse_voltage_V', amp, ...
        'pulse_voltage_measured_V', pr.v_measured_V, 'width_basis', pr.width_basis, ...
        'pulse_width_s', width, 'pulse_width_measured_s', pr.width_measured_s, ...
        'width_error_fraction', (pr.width_measured_s - width)/width, ...
        'peak_current_A', pr.peak_current_A, 'average_current_A', pr.avg_current_A, ...
        'estimated_pulse_energy_J', pr.energy_J, ...
        'G_before_S', Gbefore, 'G_after_S', Gafter, 'delta_G_S', dG, ...
        'instrument_status', pr.status, 'error_code', pr.error_code));

    % PASS criterion: every probe width delivered within 10%, the write pulse
    % applied, and no abort. A probe record without both edges gives NaN and
    % fails the check -- an unverified width is not a verified one.
    machineryOk = all(isfinite([timing.error_fraction])) && worstErr <= 0.10;
    loadedErr   = abs(pr.width_measured_s - width) / width;
    ok = strcmp(pr.status, 'ok') && machineryOk && ...
         isfinite(pr.width_measured_s) && ~inst.Aborted;

    fprintf('\n      Width check at the probe level: worst error %.1f%%\n', 100*worstErr);
    fprintf('      Write pulse at %+.2f V        : %.5g s (%s) vs %.5g s programmed (%+.1f%%)\n', ...
        amp, pr.width_measured_s, pr.width_basis, width, 100*loadedErr);
    if usePmu && isfinite(pr.v_measured_V)
        fprintf(['      Measured top voltage %+.4g V vs %+.4g V programmed: the PMU drives\n' ...
                 '      through 50 Ohm, so the device sees less on low resistance. Record\n' ...
                 '      pulse_voltage_measured_V with every result.\n'], pr.v_measured_V, amp);
    end

    summary = struct('amplitude_V', amp, 'width_s', width, ...
        'width_measured_s', pr.width_measured_s, 'worst_width_error', worstErr, ...
        'G_before_S', Gbefore, 'G_after_S', Gafter, 'delta_G_S', dG, ...
        'energy_J', pr.energy_J, 'energy_method', pr.energy_method, ...
        'pulse_status', pr.status);
    finish_measurement(run, cfg, inst, struct('summary', summary), ...
        local_status(ok), pr.error_code);

catch err
    fprintf(2, '\nSINGLE PULSE TEST FAILED\n  %s: %s\n', err.identifier, err.message);
    if ~isempty(inst) && isvalid(inst)
        emergency_shutdown(inst, 'single safe pulse test failed');
    end
end

fprintf('\n----------------------------------------------------------------\n');
if ok
    fprintf(' RESULT: PASS. The pulse path and its timing are verified.\n');
    fprintf(' Next: a small DC I-V run (examples/example_iv.m).\n');
else
    fprintf(2, ' RESULT: FAIL or suspicious. Do not start a long pulse run.\n');
end
fprintf('----------------------------------------------------------------\n\n');

if nargout == 0
    clear ok;
end
end

% ------------------------------------------------------------------------
function s = local_status(ok)
if ok; s = 'completed'; else; s = 'failed'; end
end

function local_cleanup(inst)
try
    if ~isempty(inst) && isvalid(inst) && inst.Connected
        safe_output_off(inst);
        disconnect_instruments(inst);
    end
catch
end
end

function s = local_limit_line(cfg)
if strcmpi(cfg.pulse.timing_source, 'pmu')
    s = sprintf(['current    : NO hardware compliance (PMU); run stops above %.4g A, ' ...
                 'series R = %g Ohm'], cfg.pmu.max_current_A, cfg.pmu.series_resistance_Ohm);
else
    s = sprintf('compliance : %.4g A (SMU)', cfg.pulse.compliance);
end
end
