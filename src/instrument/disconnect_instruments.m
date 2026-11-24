function disconnect_instruments(inst)
%DISCONNECT_INSTRUMENTS  Bring the 4200A to a safe state and release the connection.
%
%   DISCONNECT_INSTRUMENTS(inst) turns every output off at 0 V, reports any
%   unacknowledged commands into the log, and then explicitly deletes the
%   transport object. A plain `clear dev` can leave the socket open so that
%   the next connection is refused; deleting explicitly avoids that.
%
%   The function never throws, so it is safe inside onCleanup and catch
%   blocks.
%
%   Inputs:
%       inst - InstrumentSession (may be [] or invalid)
%
%   Outputs: none.
%
%   Instrument side effects: outputs OFF at 0 V, connection closed. The RPM
%   path is left as it is.
%
%   Exceptions: none by design.
%
%   See also SAFE_OUTPUT_OFF, CONNECT_INSTRUMENTS, EMERGENCY_SHUTDOWN.

if isempty(inst) || ~isvalid(inst)
    return;
end

try
    safe_output_off(inst);
catch
end

try
    if inst.Connected && ~inst.Simulate && inst.Cfg.instrument.check_errors
        kxci_check_errors(inst);
    end
catch
end

try
    log_message(inst, 'INFO', ...
        'Disconnecting. Commands sent: %d, pulses applied: %d, compliance hits: %d, elapsed: %.1f s.', ...
        inst.CommandCount, inst.PulseCount, inst.ComplianceHits, inst.elapsed());
catch
end

try
    if ~isempty(inst.Dev) && ~isa(inst.Dev, 'KxciMock')
        delete(inst.Dev);
    end
catch err
    try
        warning('disconnect_instruments:DeleteFailed', ...
            'Could not delete the transport object: %s', err.message);
    catch
    end
end

try
    inst.Dev       = [];
    inst.Connected = false;
    inst.OutputOn  = false;
catch
end

try
    log_message('flush');
catch
end
end
