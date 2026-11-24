function ok = set_voltage(inst, cfg, v_volts)
%SET_VOLTAGE  Apply a DC level from the SMU to the device, with all safety gates.
%
%   ok = SET_VOLTAGE(inst, cfg, v_volts) checks the requested level against
%   cfg.safety.max_abs_voltage, refuses to act on an aborted session, honours
%   dry-run (logs the intent, drives nothing), routes the RPM to the SMU
%   path if needed, and finally sends the KXCI user-mode command
%
%       DV<smu>, <range code>, <volts>, <compliance A>
%
%   In KXCI user mode the compliance travels with every DV command, so the
%   value set by SET_COMPLIANCE is re-sent here each time.
%
%   This is the ONLY place in the kit that drives the SMU. Anything that
%   applies a bias must go through here or through APPLY_VOLTAGE_PULSE.
%
%   Inputs:
%       inst    - InstrumentSession
%       cfg     - configuration struct
%       v_volts - [V] requested level
%
%   Outputs:
%       ok - logical, true when the level was actually applied
%            (false in dry-run, or when the session is aborted)
%
%   Instrument side effects: switches the RPM to the SMU path when needed,
%   and sets the SMU output level (which turns it on).
%
%   Exceptions:
%       check_voltage_limit:Exceeded  requested level outside the safe envelope
%       set_voltage:Aborted           session already aborted (only when the
%                                     caller requests no output argument)
%       set_voltage:NoCompliance      no compliance has been set yet
%
%   See also SAFE_OUTPUT_OFF, APPLY_VOLTAGE_PULSE, CHECK_VOLTAGE_LIMIT.

narginchk(3, 3);
ok = false;

% Hard voltage gate first: this throws before anything reaches the 4200A.
check_voltage_limit(v_volts, cfg);

if inst.Aborted
    msg = sprintf(['Session is aborted (%s). Refusing to apply %+.4f V. ' ...
                   'Reconnect and confirm before resuming.'], ...
                   inst.LastError, v_volts);
    log_message(inst, 'SAFETY', '%s', msg);
    if nargout == 0
        error('set_voltage:Aborted', '%s', msg);
    end
    return;
end

% Duration guard: a run must not silently exceed its allotted time.
if inst.elapsed() > cfg.safety.max_test_duration
    emergency_shutdown(inst, sprintf( ...
        'Session exceeded cfg.safety.max_test_duration = %g s.', ...
        cfg.safety.max_test_duration));
    return;
end

% Dry-run only suppresses REAL output. In simulation there is no hardware to
% protect, so the virtual device is driven normally and every code path runs.
if inst.DryRun && ~inst.Simulate
    log_message(inst, 'INFO', 'DRY-RUN: would set %s to %+.4f V (output stays off).', ...
        inst.Channel, v_volts);
    inst.LastVoltage = v_volts;    % keep the bookkeeping consistent
    return;
end

if ~isfinite(inst.Compliance) || inst.Compliance <= 0
    error('set_voltage:NoCompliance', ...
        'No compliance set. Call configure_instruments (or set_compliance) first.');
end

kxci_select_path(inst, cfg, 'smu');

kxci_write(inst, 'DV%d, %d, %.6g, %.6g', inst.Smu, ...
    cfg.instrument.smu_range_code, v_volts, inst.Compliance);
if ~inst.OutputOn
    inst.OutputOn = true;
    log_message(inst, 'INFO', 'Output ON (%s).', inst.Channel);
end
inst.LastVoltage = v_volts;
ok = true;
end
