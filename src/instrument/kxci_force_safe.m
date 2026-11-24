function kxci_force_safe(inst)
%KXCI_FORCE_SAFE  Best-effort: PMU outputs off, SMU to 0 V and off. Never throws.
%
%   KXCI_FORCE_SAFE(inst) is the last line of defence used by
%   SAFE_OUTPUT_OFF and EMERGENCY_SHUTDOWN. Unlike KXCI_WRITE it does not
%   stop at the first failure and does not call EMERGENCY_SHUTDOWN, so it
%   can run while the session is already failing.
%
%   Order: discard any unread replies -> every PMU channel output off ->
%   SMU user mode -> SMU level 0 V -> SMU output off. The RPM path is left
%   where it is: switching relays is not a safety action.
%
%   Every command still consumes its acknowledge in ack mode, so the
%   connection stays in step for whatever runs next.
%
%   Inputs:
%       inst - InstrumentSession (connected, not simulated)
%
%   Outputs: none.
%
%   Instrument side effects: outputs off.
%
%   Exceptions: none by design (failures are logged).
%
%   See also SAFE_OUTPUT_OFF, EMERGENCY_SHUTDOWN.

if isempty(inst) || ~isvalid(inst) || inst.Simulate || ...
        ~inst.Connected || isempty(inst.Dev)
    return;
end

cfg = inst.Cfg;
try
    flush(inst.Dev);       % a timed-out exchange may have left a reply behind
catch
end

cmds = {};
if cfg.pmu.enabled
    for ch = reshape(unique([inst.PmuForce, inst.PmuSense(inst.PmuSense > 0), ...
                             reshape(inst.PmuOutputsOn, 1, [])]), 1, [])
        cmds{end+1} = sprintf(':PMU:OUTPUT:STATE %d, 0', ch); %#ok<AGROW>
    end
end
comp = inst.Compliance;
if ~isfinite(comp) || comp <= 0; comp = cfg.read.compliance; end
cmds{end+1} = 'US';
cmds{end+1} = sprintf('DV%d, %d, 0, %.6g', inst.Smu, cfg.instrument.smu_range_code, comp);
cmds{end+1} = sprintf('DV%d', inst.Smu);   % no arguments = output off

failures = 0;
for k = 1:numel(cmds)
    try
        inst.noteCommand(cmds{k});
        reply = kxci_transact(inst.Dev, cmds{k}, inst.AckMode);
        log_message(inst, 'CMD', '>> %s  << %s', cmds{k}, reply);
    catch err
        failures = failures + 1;
        try
            log_message(inst, 'ERROR', 'Safe-off command "%s" failed: %s', cmds{k}, err.message);
        catch
        end
    end
end

inst.PmuOutputsOn = zeros(1, 0);
inst.OutputOn     = false;
inst.LastVoltage  = 0;
inst.UserMode     = true;

if failures > 0
    try
        warning('kxci_force_safe:Failed', ...
            ['%d safe-off command(s) failed. CHECK THE 4200A: in Clarius/KXCI ' ...
             'confirm every SMU and PMU output is off.'], failures);
    catch
    end
end
end
