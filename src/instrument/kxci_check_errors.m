function [n, messages] = kxci_check_errors(inst)
%KXCI_CHECK_ERRORS  Report and clear the command errors seen since the last check.
%
%   [n, messages] = KXCI_CHECK_ERRORS(inst) returns how many commands were
%   answered with something other than an acknowledge since the previous call
%   (counted by KXCI_WRITE), and resets that count. When
%   cfg.instrument.error_query is set, that query is sent too and a reply
%   that does not match cfg.instrument.no_error_pattern counts as one more
%   error.
%
%   Why it exists: a KXCI command the instrument did not accept leaves the
%   previous setting in force. Without this check a typo in a sequence
%   definition produces a perfectly plausible pulse with the wrong shape.
%
%   cfg.instrument.error_query is empty by default because the command has
%   not been confirmed on this setup; see docs/07_bring_up.md.
%
%   Inputs:
%       inst - InstrumentSession
%
%   Outputs:
%       n        - number of errors found (0 when simulated or unreachable)
%       messages - cellstr describing them
%
%   Instrument side effects: none, or the error query when configured.
%
%   Exceptions: none. Communication problems are logged and reported as n=0
%   with a warning, so this diagnostic can never itself abort a measurement.
%
%   See also KXCI_WRITE, KXCI_QUERY.

n = 0;
messages = {};

if inst.Simulate || ~inst.Connected || isempty(inst.Dev)
    return;
end

if inst.ReplyErrors > 0
    n = inst.ReplyErrors;
    messages{end+1} = sprintf('%d command(s) not acknowledged; last: %s', ...
        inst.ReplyErrors, inst.LastError);
    inst.ReplyErrors = 0;
end

q = inst.Cfg.instrument.error_query;
if ~isempty(q)
    [resp, ok] = kxci_query(inst, q);
    if ~ok
        log_message(inst, 'WARN', 'Error query "%s" got no reply.', q);
    elseif isempty(regexp(resp, inst.Cfg.instrument.no_error_pattern, 'once'))
        n = n + 1;
        messages{end+1} = sprintf('%s -> %s', q, resp);
    end
end

for k = 1:numel(messages)
    log_message(inst, 'ERROR', 'Instrument command error: %s', messages{k});
end
if n > 0
    inst.LastError = strjoin(messages, ' | ');
end
end
