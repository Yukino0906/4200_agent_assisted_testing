function ok = confirm_step(cfg, headline, detail)
%CONFIRM_STEP  Ask the operator to authorise a checkpoint before proceeding.
%
%   ok = CONFIRM_STEP(cfg, headline) prints a checkpoint banner and waits for
%   the operator to type "y". It returns false for anything else, so the
%   caller can abort cleanly.
%
%   ok = CONFIRM_STEP(cfg, headline, detail) also prints one or more detail
%   lines (char or cellstr) describing exactly what is about to happen --
%   voltages, compliance, pulse counts. Always pass the numbers the operator
%   needs to sanity-check the step; a checkpoint with no numbers is useless.
%
%   When cfg.mode.require_user_confirmation is false the checkpoint is logged
%   and auto-accepted, which is what unattended batch runs need.
%
%   Use a checkpoint after connection, after the first low-voltage read,
%   before the first DC sweep, before the first high-amplitude pulse, after
%   changing device, and before long batch runs.
%
%   Inputs:
%       cfg      - configuration struct
%       headline - char, short description of the checkpoint
%       detail   - optional char or cellstr of detail lines
%
%   Outputs:
%       ok - logical, true to proceed
%
%   Instrument side effects: none.
%
%   Exceptions: none.
%
%   See also BEGIN_MEASUREMENT.

narginchk(2, 3);
if nargin < 3; detail = {}; end
if ischar(detail) || isstring(detail); detail = cellstr(detail); end

fprintf('\n');
fprintf('+--------------------------------------------------------------+\n');
fprintf('| CHECKPOINT: %-48s |\n', local_trim(headline, 48));
fprintf('+--------------------------------------------------------------+\n');
for i = 1:numel(detail)
    fprintf('  %s\n', detail{i});
end

if ~cfg.mode.require_user_confirmation
    fprintf('  (cfg.mode.require_user_confirmation = false -> auto-accepted)\n\n');
    ok = true;
    return;
end

resp = input('  Proceed? Type "y" to continue, anything else to stop: ', 's');
ok = strcmpi(strtrim(resp), 'y');

if ok
    fprintf('  -> proceeding.\n\n');
else
    fprintf('  -> STOPPED by operator.\n\n');
end
end

% ------------------------------------------------------------------------
function s = local_trim(s, n)
s = char(s);
if numel(s) > n
    s = [s(1:n-3) '...'];
end
end
