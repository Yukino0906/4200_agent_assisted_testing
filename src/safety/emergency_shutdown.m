function emergency_shutdown(inst, reason)
%EMERGENCY_SHUTDOWN  Force the device to a safe state. Never throws.
%
%   EMERGENCY_SHUTDOWN(inst, reason) turns every PMU output off, drives the
%   SMU to 0 V and turns it off, marks the session as aborted, and logs the
%   reason. It is designed to be called from onCleanup handlers, catch
%   blocks, destructors, and safety checks -- i.e. from contexts where
%   throwing would mask the original fault. It therefore swallows every
%   error it encounters and reports problems as warnings only.
%
%   Once a session is Aborted, no further bias may be applied: SET_VOLTAGE
%   and APPLY_VOLTAGE_PULSE refuse to run. Recovery requires an explicit
%   reconnect plus user confirmation -- there is no
%   automatic resumption of write voltages.
%
%   Inputs:
%       inst   - InstrumentSession (may be [] or an already-dead handle)
%       reason - char/string describing why the shutdown was triggered
%
%   Outputs: none.
%
%   Instrument side effects: sets 0 V and turns outputs OFF.
%
%   Exceptions: none, by design.
%
%   See also SAFE_OUTPUT_OFF, CHECK_CURRENT_LIMIT, DISCONNECT_INSTRUMENTS.

if nargin < 2 || isempty(reason)
    reason = 'unspecified';
end
reason = char(reason);

try
    fprintf(2, '\n*** EMERGENCY SHUTDOWN *** %s\n', reason);
catch
end

if isempty(inst) || ~isvalid(inst)
    return;
end

try
    inst.Aborted   = true;
    inst.LastError = reason;
catch
end

try
    log_message(inst, 'SAFETY', 'EMERGENCY SHUTDOWN: %s', reason);
catch
end

% ---- PMU outputs off, SMU to 0 V, SMU off -------------------------------
try
    if inst.Connected && ~inst.Simulate && ~isempty(inst.Dev)
        kxci_force_safe(inst);
    end
catch shutErr
    try
        warning('emergency_shutdown:WriteFailed', ...
            ['Could not command the instrument during emergency shutdown (%s). ' ...
             'CHECK THE 4200A AND TURN EVERY SMU/PMU OUTPUT OFF MANUALLY.'], ...
            shutErr.message);
    catch
    end
end

try
    inst.OutputOn    = false;
    inst.LastVoltage = 0;
catch
end

try
    if inst.Simulate && ~isempty(inst.Sim) && isvalid(inst.Sim)
        % Nothing physical to do; state is preserved for post-mortem.
    end
catch
end

% Get every buffered log line onto disk: after a shutdown the log is the
% only record of what led up to it.
try
    log_message('flush');
catch
end
end
