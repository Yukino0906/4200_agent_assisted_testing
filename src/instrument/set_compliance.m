function set_compliance(inst, cfg, compliance_A)
%SET_COMPLIANCE  Set the SMU current compliance used by every following DV command.
%
%   SET_COMPLIANCE(inst, cfg, compliance_A) checks the requested value
%   against cfg.safety.max_abs_current and stores it in the session. In KXCI
%   user mode the compliance is an argument of each DV command, so the new
%   value takes effect at the next SET_VOLTAGE; when the SMU output is
%   already on, the present level is re-sent at once with the new limit.
%   Compliance is the primary protection against destroying the device during
%   SET / forming, so an out-of-range request is a hard error, never a clamp.
%
%   This applies to the SMU only. The 4225-PMU has no comparable current
%   limit; see cfg.pmu.max_current_A and docs/05_safety.md.
%
%   Inputs:
%       inst         - InstrumentSession
%       cfg          - configuration struct
%       compliance_A - [A] requested compliance, > 0
%
%   Outputs: none.
%
%   Instrument side effects: when the SMU output is on, re-sends its level
%   with the new compliance.
%
%   Exceptions:
%       set_compliance:BadValue  non-finite or non-positive request
%       set_compliance:Exceeded  request above cfg.safety.max_abs_current
%
%   See also CONFIGURE_INSTRUMENTS, CHECK_CURRENT_LIMIT.

narginchk(3, 3);

if ~isnumeric(compliance_A) || ~isscalar(compliance_A) || ...
        ~isfinite(compliance_A) || compliance_A <= 0
    error('set_compliance:BadValue', ...
        'Compliance must be a finite positive scalar in amperes.');
end

if compliance_A > cfg.safety.max_abs_current
    error('set_compliance:Exceeded', ...
        ['Requested compliance %.6g A exceeds cfg.safety.max_abs_current = %.6g A. ' ...
         'Raise the safety limit deliberately (and re-confirm it) if this is intended.'], ...
        compliance_A, cfg.safety.max_abs_current);
end

changed = ~isequal(inst.Compliance, compliance_A);
inst.Compliance = compliance_A;
if changed && inst.OutputOn && strcmp(inst.Path, 'smu') && ~inst.Aborted && ...
        ~(inst.DryRun && ~inst.Simulate)
    kxci_write(inst, 'DV%d, %d, %.6g, %.6g', inst.Smu, ...
        cfg.instrument.smu_range_code, inst.LastVoltage, compliance_A);
end
log_message(inst, 'INFO', 'Compliance set to %.6g A on %s.', compliance_A, inst.Channel);
end
