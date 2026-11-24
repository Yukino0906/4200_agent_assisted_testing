function tf = local_require_init(cfg, test_name)
%LOCAL_REQUIRE_INIT  Must a test skip a condition when write-verify misses?
%
%   tf = LOCAL_REQUIRE_INIT(cfg, test_name) reads
%   cfg.<test_name>.require_initialization, defaulting to TRUE when the field
%   is absent so existing behaviour is unchanged.
%
%   WHY THIS IS A CHOICE AND NOT A CONSTANT
%       Write-verify lands inside its tolerance window only some of the time
%       on a device with strong post-write relaxation. Skipping every miss
%       throws away most of the run: it can cut a multi-state measurement
%       down to a single state and remove whole LTP/LTD branches.
%
%       For measurements whose quantity of interest is referenced to the
%       state the device is ACTUALLY in -- read noise, relaxation, dG versus
%       G_before -- the target only has to be close, because the real state
%       is measured and recorded alongside the data. Those tests can set
%       require_initialization = false and bin on the measured conductance.
%
%       For measurements that genuinely need a specific starting state, leave
%       it true. Either way initialization_success is recorded, so a miss is
%       always visible and never silently becomes a "device failure".
%
%   Inputs:
%       cfg       - configuration struct
%       test_name - char, the cfg sub-struct to look in (e.g. 'read_noise')
%
%   Outputs:
%       tf - logical
%
%   Instrument side effects: none.
%   Exceptions: none.
%
%   See also INITIALIZE_TO_STATE, RUN_READ_NOISE_TEST, RUN_RELAXATION_TEST.

tf = true;
if isfield(cfg, test_name)
    s = cfg.(test_name);
    if isstruct(s) && isfield(s, 'require_initialization')
        tf = logical(s.require_initialization);
    end
end
end
