function cfg = sim_config(name)
%SIM_CONFIG  Configuration for running an example on the simulator.
%
%   cfg = SIM_CONFIG(name) returns default_config() set up for the virtual
%   device: no VISA session, no output, no confirmation prompts, and a
%   device_id of 'SIM_<name>'. Use it to rehearse a test before touching a
%   real device. The simulator is a toy whose numbers describe no real cell.
%
%   Inputs:
%       name - char, short label that ends up in the run directory name
%
%   Outputs:
%       cfg - configuration struct
%
%   Instrument side effects: none.
%
%   See also DEFAULT_CONFIG, DEVICE_TEMPLATE.

narginchk(1, 1);
cfg = default_config();
cfg.device.device_id               = ['SIM_' char(name)];
cfg.mode.simulate_instrument       = true;
cfg.mode.dry_run                   = true;
cfg.mode.require_user_confirmation = false;
cfg.mode.verbose                   = false;
end
