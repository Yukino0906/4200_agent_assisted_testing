function info = check_contact(inst, cfg)
%CHECK_CONTACT  Low-voltage probe-landing check. Run before ANY high voltage.
%
%   info = CHECK_CONTACT(inst, cfg) applies cfg.safety.contact_check.voltage
%   (0.05 V by default) and classifies what it sees:
%
%       'open'   |I| < contact_check.min_current  -> probe not landed,
%                                                    broken line, or unformed
%       'short'  |I| > contact_check.max_current  -> probes touching each
%                                                    other or destroyed device
%       'ok'     anything in between
%
%   Never apply a high voltage before this passes.
%   The bias used here is far below any switching threshold, so it is safe on
%   a device in any state.
%
%   Inputs:
%       inst - InstrumentSession
%       cfg  - configuration struct
%
%   Outputs:
%       info - struct:
%           .verdict         'ok' | 'open' | 'short' | 'failed'
%           .passed          logical
%           .current_A, .conductance_S, .resistance_Ohm
%           .voltage_V       bias used
%           .message         human-readable explanation
%
%   Instrument side effects: applies the contact-check bias briefly, returns
%   to 0 V.
%
%   Exceptions: none (failures reported through info.verdict).
%
%   See also MEASURE_CONDUCTANCE, RUN_ALL_REQUIRED_TESTS.

narginchk(2, 2);
cc = cfg.safety.contact_check;

info = struct('verdict', 'failed', 'passed', false, ...
              'current_A', NaN, 'conductance_S', NaN, 'resistance_Ohm', NaN, ...
              'voltage_V', cc.voltage, 'message', '');

configure_instruments(inst, cfg, 'read');

[G, r] = measure_conductance(inst, cfg, cc.voltage);
info.current_A      = r.current_A;
info.conductance_S  = G;
info.resistance_Ohm = r.resistance_Ohm;

switch r.status
    case 'dry_run'
        info.verdict = 'failed';
        info.message = 'Dry-run: no contact information available.';
        return;
    case 'aborted'
        info.verdict = 'failed';
        info.message = 'Session aborted during the contact check.';
        return;
end

I = abs(r.current_A);

if ~isfinite(I) || I < cc.min_current
    info.verdict = 'open';
    info.message = sprintf( ...
        ['OPEN CIRCUIT: |I| = %.3g A at %+.3f V is below %.3g A. ' ...
         'Check the probe landing, the cabling and the device. ' ...
         'DO NOT apply a high voltage.'], I, cc.voltage, cc.min_current);
elseif I > cc.max_current
    info.verdict = 'short';
    info.message = sprintf( ...
        ['SHORT: |I| = %.3g A at %+.3f V exceeds %.3g A (R = %.4g Ohm). ' ...
         'Probes may be touching, or the device is destroyed. ' ...
         'DO NOT apply a high voltage.'], I, cc.voltage, cc.max_current, ...
        info.resistance_Ohm);
else
    info.verdict = 'ok';
    info.passed  = true;
    info.message = sprintf( ...
        'Contact OK: I = %.4g A at %+.3f V -> G = %.4g S (R = %.4g Ohm).', ...
        r.current_A, cc.voltage, G, info.resistance_Ohm);
end

if info.passed
    log_message(inst, 'INFO', '%s', info.message);
else
    log_message(inst, 'SAFETY', '%s', info.message);
end
end
