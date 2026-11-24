function [response, ok] = kxci_query(inst, cmd, varargin)
%KXCI_QUERY  Send a KXCI command that returns data, and read the reply.
%
%   [response, ok] = KXCI_QUERY(inst, cmd) writes `cmd` and returns the
%   instrument's reply as a trimmed char row vector, e.g.
%   kxci_query(inst, 'TI1') or kxci_query(inst, ':PMU:TEST:STATUS?').
%
%   KXCI_QUERY(inst, fmt, a, b, ...) formats the command first.
%
%   In simulation mode no transmission happens and ('', false) is returned;
%   callers that need simulated values (measure_current) branch before
%   reaching this function.
%
%   Inputs:
%       inst - InstrumentSession
%       cmd  - char/string command that produces a reply
%
%   Outputs:
%       response - char, trimmed reply ('' on failure or in simulation)
%       ok       - logical, true when a reply was actually received
%
%   Instrument side effects: executes `cmd` on the 4200A.
%
%   Exceptions:
%       kxci_query:NotConnected  no live session and not simulated
%       kxci_query:QueryFailed   only when the caller requests no `ok` output;
%                                with two outputs, failures are reported via ok
%
%   See also KXCI_WRITE, KXCI_CHECK_ERRORS, KXCI_PARSE_READING.

narginchk(2, inf);
if ~isempty(varargin)
    cmd = sprintf(char(cmd), varargin{:});
end
cmd = char(cmd);

response = '';
ok = false;

inst.noteCommand(cmd);
log_message(inst, 'CMD', '?? %s', cmd);

if inst.Simulate
    return;
end

if ~inst.Connected || isempty(inst.Dev)
    if nargout >= 2
        return;
    end
    error('kxci_query:NotConnected', ...
        'Cannot query "%s": no live instrument session.', cmd);
end

try
    response = kxci_transact(inst.Dev, cmd, true);
    ok = true;
    log_message(inst, 'CMD', '<< %s', local_clip(response));
catch err
    inst.LastError = err.message;
    if nargout >= 2
        log_message(inst, 'WARN', 'Query "%s" failed: %s', cmd, err.message);
        return;
    end
    error('kxci_query:QueryFailed', ...
        'KXCI query failed for "%s": %s', cmd, err.message);
end
end

% ------------------------------------------------------------------------
function s = local_clip(s)
% PMU data replies can be thousands of points; keep the log readable.
if numel(s) > 300
    s = sprintf('%s ... (%d characters)', s(1:300), numel(s));
end
end
