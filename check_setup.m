function report = check_setup(host)
%CHECK_SETUP  Check this PC before the first 4200A connection. Sends nothing to any instrument.
%
%   report = CHECK_SETUP() checks, on the PC that will run the kit:
%       1. MATLAB version and install folder
%       2. Instrument Control Toolbox (visadev) and MATLAB's own tcpclient
%       3. NI-VISA: which instrument resources it can see
%       4. network adapters and their IPv4 addresses (ipconfig)
%       5. the kit's regression suite, test_dry_run (simulator + KXCI mock)
%
%   report = CHECK_SETUP(host) also pings host, e.g. check_setup('192.168.0.2').
%
%   Nothing here opens a connection to the 4200A or applies any voltage:
%   visadevlist only lists resources, ping only tests the network.
%
%   Inputs:
%       host - optional char, IP address of the 4200A
%
%   Outputs:
%       report - struct with every finding; also printed as a summary
%
%   Instrument side effects: none.
%
%   Exceptions: none; each failed check is reported in the summary.
%
%   See also SETUP_PATHS, TEST_DRY_RUN, TEST_INSTRUMENT_CONNECTION.

if nargin < 1; host = ''; end
root = setup_paths();

report = struct();
report.kit_root       = root;
report.matlab_version = version;
report.matlab_root    = matlabroot;
report.ict_installed  = ~isempty(ver('instrument'));
report.has_visadev    = exist('visadev', 'file') == 2;
report.has_tcpclient  = exist('tcpclient', 'file') == 2;

% ---- NI-VISA ----------------------------------------------------------
% With nothing attached, visadevlist times out after ~10 s; that only means
% NI-VISA sees no instrument yet.
report.visa_resources = '';
if report.has_visadev
    try
        report.visa_resources = evalc('disp(visadevlist)');
    catch err
        report.visa_resources = ['none found (' err.message ')'];
    end
end

% ---- network ----------------------------------------------------------
[~, report.ipconfig] = system('ipconfig');
report.ping_ok = NaN;
if ~isempty(host)
    [st, report.ping] = system(['ping -n 2 ' host]);
    report.ping_ok = (st == 0);
end

% ---- regression -------------------------------------------------------
try
    report.dry_run_ok = test_dry_run();
catch err
    report.dry_run_ok = false;
    report.dry_run_error = err.message;
end

% ---- summary ----------------------------------------------------------
fprintf('\n================================================================\n');
fprintf(' 4200A KIT SETUP CHECK\n');
fprintf('================================================================\n');
fprintf('  Kit folder                 : %s\n', root);
fprintf('  MATLAB                     : %s\n', report.matlab_version);
fprintf('  MATLAB folder              : %s\n', report.matlab_root);
fprintf('  Instrument Control Toolbox : %s\n', local_yes(report.ict_installed && report.has_visadev));
fprintf('  tcpclient (no VISA needed) : %s\n', local_yes(report.has_tcpclient));
if report.has_visadev
    fprintf('  NI-VISA resources          :\n%s\n', local_indent(report.visa_resources));
end
fprintf('  Network adapters           :\n%s\n', local_indent(local_adapters(report.ipconfig)));
if ~isempty(host)
    fprintf('  ping %-21s : %s\n', host, local_yes(report.ping_ok));
end
fprintf('  test_dry_run               : %s\n', local_yes(report.dry_run_ok));
fprintf('----------------------------------------------------------------\n');
if ~report.has_visadev && ~report.has_tcpclient
    fprintf(2, '  No transport available: install the Instrument Control Toolbox or use MATLAB R2020b+.\n');
elseif ~report.has_visadev
    fprintf('  No visadev: use cfg.instrument.transport = ''tcpclient''.\n');
end
fprintf(['  Next: README.md, Quick start step 3: find the adapter cabled to the 4200A\n' ...
         '  (a 169.254.x.x address means automatic addressing on both ends).\n\n']);

if nargout == 0
    clear report;
end
end

% ========================================================================
function s = local_yes(tf)
if isequal(tf, true); s = 'yes'; else; s = 'NO'; end
end

function s = local_adapters(txt)
% Adapter headings, their IPv4 lines (including "Autoconfiguration IPv4", the
% 169.254.x.x address Windows picks when nothing assigns one) and "Media
% disconnected" lines. Written for English ipconfig output; anything else is
% printed whole.
lines = splitlines(string(txt));
keep = contains(lines, "IPv4") | contains(lines, "Media disconnected") | ...
       (strlength(lines) > 0 & ~startsWith(lines, " ") & endsWith(strtrim(lines), ":"));
s = char(strjoin(lines(keep), newline));
if isempty(strtrim(s)); s = char(txt); end
end

function s = local_indent(txt)
s = char(strjoin("      " + splitlines(string(txt)), newline));
end
