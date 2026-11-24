function configure_instruments(inst, cfg, mode)
%CONFIGURE_INSTRUMENTS  Put the 4200A into a known configuration for one kind of step.
%
%   CONFIGURE_INSTRUMENTS(inst, cfg, mode) selects the device path through
%   the RPM and the SMU compliance for the next operations.
%
%   Inputs:
%       inst - InstrumentSession
%       cfg  - configuration struct
%       mode - 'read'  accurate single-point reads   (SMU, cfg.read.compliance)
%              'dc'    DC sweep                      (SMU, cfg.dc.compliance)
%              'pulse' write pulses: PMU path when cfg.pulse.timing_source
%                      is 'pmu', SMU path (cfg.pulse.compliance) when 'pc'
%
%   Outputs: none.
%
%   Instrument side effects: RPM path switching (see KXCI_SELECT_PATH), SMU
%   user mode, optional integration-time command. No bias is applied; when
%   the SMU output is on, its level is first brought to 0 V by the path
%   switch or kept where it is with the new compliance.
%
%   Exceptions:
%       configure_instruments:BadMode         unknown mode string
%       configure_instruments:InstrumentError a command was not acknowledged
%       propagates kxci_write:WriteFailed
%
%   See also CONNECT_INSTRUMENTS, KXCI_SELECT_PATH, SET_COMPLIANCE.

narginchk(3, 3);

switch lower(char(mode))
    case 'read'
        compliance = cfg.read.compliance;
        path       = 'smu';
    case 'dc'
        compliance = cfg.dc.compliance;
        path       = 'smu';
    case 'pulse'
        compliance = cfg.pulse.compliance;   % used by the 'pc' engine only
        if strcmpi(cfg.pulse.timing_source, 'pmu')
            path = 'pulse';
        else
            path = 'smu';
        end
    otherwise
        error('configure_instruments:BadMode', ...
            'Unknown mode "%s". Expected read | dc | pulse.', char(mode));
end

log_message(inst, 'INFO', ...
    'Configuring for mode "%s": path = %s, SMU compliance = %.4g A', ...
    char(mode), path, compliance);

kxci_select_path(inst, cfg, path);
set_compliance(inst, cfg, compliance);

if strcmp(path, 'smu') && ~isempty(cfg.instrument.smu_integration_command)
    kxci_write(inst, '%s', cfg.instrument.smu_integration_command);
end

inst.Mode = lower(char(mode));
inst.ConsecutiveComplianceHits = 0;   % the counter is per-mode, not global

if cfg.instrument.check_errors
    n = kxci_check_errors(inst);
    if n > 0
        error('configure_instruments:InstrumentError', ...
            'Instrument reported %d error(s) while configuring mode "%s": %s', ...
            n, char(mode), inst.LastError);
    end
end
end
