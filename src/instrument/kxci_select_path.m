function kxci_select_path(inst, cfg, path)
%KXCI_SELECT_PATH  Route the device to the SMU or to the PMU through the RPM.
%
%   KXCI_SELECT_PATH(inst, cfg, 'smu') connects the device to the SMU for
%   reads and DC sweeps. KXCI_SELECT_PATH(inst, cfg, 'pulse') connects it to
%   the PMU for write pulses. Nothing is sent when the requested path is
%   already active.
%
%   The 4225-RPM sits between the instrument and the probe. Its output goes
%   either to the PMU channel or to the SMU wired into the RPM's SMU input,
%   never to both. A read taken while the RPM is still on the pulse path sees
%   an open circuit; a pulse executed while it is on the SMU path never
%   reaches the device. SET_VOLTAGE and APPLY_VOLTAGE_PULSE therefore call
%   this function themselves, so a test that forgets CONFIGURE_INSTRUMENTS
%   still measures through the right path.
%
%   Switching order (never switch a path that carries a bias):
%       to 'pulse': SMU to 0 V -> PMU init (once) -> RPM to pulse ->
%                   PMU current range
%       to 'smu'  : PMU outputs off (except a sense channel that is the
%                   current return) -> RPM to SMU -> SMU user mode (US)
%   followed by cfg.instrument.rpm_settle_s for the relays.
%
%   The RPM path codes come from cfg.pmu.rpm_code_pulse (0, from Keithley's
%   KXCI examples) and cfg.pmu.rpm_code_smu (UNVERIFIED default 3). Confirm
%   the SMU code with test_read_only on a resistor (docs/07_bring_up.md).
%
%   Inputs:
%       inst - InstrumentSession
%       cfg  - configuration struct
%       path - 'smu' | 'pulse'
%
%   Outputs: none.
%
%   Instrument side effects: RPM relay switching, PMU initialisation, SMU
%   level to 0 V before leaving the SMU path, PMU outputs off before leaving
%   the pulse path.
%
%   Exceptions:
%       kxci_select_path:BadPath  unknown path
%
%   See also CONFIGURE_INSTRUMENTS, SET_VOLTAGE, APPLY_VOLTAGE_PULSE.

narginchk(3, 3);
path = lower(char(path));
if ~any(strcmp(path, {'smu', 'pulse'}))
    error('kxci_select_path:BadPath', 'Unknown path "%s" (smu | pulse).', path);
end
usePmu = cfg.pmu.enabled;
if ~usePmu
    path = 'smu';   % no PMU: SMU pulses stay on the SMU path
end
if strcmp(inst.Path, path)
    return;
end

rpmCode = struct('pulse', cfg.pmu.rpm_code_pulse, 'smu', cfg.pmu.rpm_code_smu);

switch path
    case 'pulse'
        % The SMU is about to be disconnected: bring it to 0 V first.
        if inst.OutputOn && inst.LastVoltage ~= 0
            kxci_write(inst, 'DV%d, %d, 0, %.6g', inst.Smu, ...
                cfg.instrument.smu_range_code, local_comp(inst, cfg));
            inst.LastVoltage = 0;
        end
        if ~inst.PmuInitialised
            kxci_write(inst, ':PMU:INIT 1');          % segment-ARB mode
            inst.PmuInitialised = true;
        end
        kxci_write(inst, ':PMU:RPM:CONFIGURE %s, %d', ...
            local_rpm(inst, inst.PmuForce), rpmCode.pulse);
        chans = inst.PmuForce;
        if inst.PmuSense > 0
            kxci_write(inst, ':PMU:RPM:CONFIGURE %s, %d', ...
                local_rpm(inst, inst.PmuSense), rpmCode.pulse);
            chans(end+1) = inst.PmuSense;
        end
        for ch = chans
            kxci_write(inst, ':PMU:MEASURE:RANGE %d, %d, %.6g', ch, ...
                cfg.pmu.measure_range_type, cfg.pmu.current_range_A);
        end
        inst.UserMode = false;   % PMU commands may leave SMU user mode

    case 'smu'
        if usePmu
            keep = [];
            if strcmpi(cfg.instrument.return_path, 'pmu_sense') && inst.PmuSense > 0
                keep = inst.PmuSense;   % that channel IS the current return
            end
            % Row vectors only: setdiff of two empties is 0x1, and a for loop
            % over a 0x1 array runs ONCE with an empty value, which would send
            % ":PMU:OUTPUT:STATE , 0".
            for ch = local_row(setdiff(inst.PmuOutputsOn, keep))
                kxci_write(inst, ':PMU:OUTPUT:STATE %d, 0', ch);
            end
            inst.PmuOutputsOn = local_row(intersect(inst.PmuOutputsOn, keep));
            if ~isempty(keep) && ~ismember(keep, inst.PmuOutputsOn)
                kxci_write(inst, ':PMU:OUTPUT:STATE %d, 1', keep);
                inst.PmuOutputsOn(end+1) = keep;
            end
            kxci_write(inst, ':PMU:RPM:CONFIGURE %s, %d', ...
                local_rpm(inst, inst.PmuForce), rpmCode.smu);
        end
        local_enter_user_mode(inst);
end

if inst.isLive() && cfg.instrument.rpm_settle_s > 0 && usePmu
    pause(cfg.instrument.rpm_settle_s);
end
inst.Path = path;
log_message(inst, 'INFO', 'Device path: %s.', path);
end

% ========================================================================
function local_enter_user_mode(inst)
% Re-sent on every switch: whether PMU commands leave SMU user mode is not
% documented, and US is harmless when already in it.
kxci_write(inst, 'US');
inst.UserMode = true;
end

function r = local_row(v)
r = reshape(v, 1, []);
end

function s = local_rpm(inst, ch)
s = sprintf('PMU%d-%d', inst.PmuCard, ch);
end

function c = local_comp(inst, cfg)
c = inst.Compliance;
if ~isfinite(c) || c <= 0
    c = cfg.read.compliance;
end
end
