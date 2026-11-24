function safe_output_off(inst)
%SAFE_OUTPUT_OFF  Every PMU output off, SMU to 0 V, then SMU output off.
%
%   SAFE_OUTPUT_OFF(inst) always performs the steps in that order: pulse
%   outputs are disabled first, then the SMU level is set to 0 V and only
%   then is the SMU output disabled, so the device never sees the
%   open-circuit transient of a switch-off at bias.
%
%   The function is safe to call at any time -- when already off, when never
%   connected, in simulation, in dry-run -- and never throws. It is the
%   normal counterpart to SET_VOLTAGE and is also used by EMERGENCY_SHUTDOWN
%   and by the onCleanup handlers of every measurement function.
%
%   Inputs:
%       inst - InstrumentSession (may be [] or invalid)
%
%   Outputs: none.
%
%   Instrument side effects: PMU outputs off, SMU level -> 0 V, SMU output OFF.
%
%   Exceptions: none by design (failures are logged as warnings).
%
%   See also SET_VOLTAGE, KXCI_FORCE_SAFE, EMERGENCY_SHUTDOWN.

if isempty(inst) || ~isvalid(inst)
    return;
end

try
    if inst.Simulate
        inst.LastVoltage  = 0;
        inst.OutputOn     = false;
        inst.PmuOutputsOn = zeros(1, 0);
        log_message(inst, 'INFO', 'SIMULATED: outputs set to 0 V and disabled.');
        return;
    end

    if ~inst.Connected || isempty(inst.Dev)
        inst.LastVoltage = 0;
        inst.OutputOn    = false;
        return;
    end

    kxci_force_safe(inst);
    log_message(inst, 'INFO', 'Outputs set to 0 V and disabled.');

catch err
    try
        warning('safe_output_off:Failed', ...
            ['Could not turn the outputs off cleanly (%s). ' ...
             'CHECK THE 4200A AND TURN THE OUTPUTS OFF MANUALLY.'], err.message);
        log_message(inst, 'ERROR', 'safe_output_off failed: %s', err.message);
    catch
    end
end
end
