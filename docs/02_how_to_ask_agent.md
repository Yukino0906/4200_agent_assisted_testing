# 02 — How to ask an AI agent for a measurement

An agent can write the configuration, run the simulation, drive the instrument, and plot
the result. It cannot see your device, and it must not guess the numbers that protect it.
**Give it numbers, not adjectives.**

## What the agent does with your request

1. Maps your words to a test function.
2. Answers with a **specification table**: device ID, test, mode, voltage ceiling,
   compliance, read bias, amplitudes, widths, counts, stop conditions, estimated pulses and
   duration, outputs.
3. Asks for anything you did not specify.
4. Waits for your explicit "yes".
5. Writes `users/<you>/config/device_<id>.m`, rehearses on the simulator, then runs on the
   instrument (small version first when it is a new device or a new test). Your data go to
   `users/<you>/data/`.
6. Reports status, run directory, key numbers and the plot.

The two safety confirmation flags stay `false` until you approve the limits in chat. You
can also edit them yourself in the device file.

## Request template

Copy, fill in, delete what does not apply.

```text
User:          <your folder under users/>   (e.g. alice)
Device:        <sample>_<R#C#>_<purpose>    (e.g. chipA_R9C9_ltp)
Test:          IV / LTP-LTD / single-pulse map / endurance / retention / read noise / relaxation / other: ...
Mode:          simulation only | real instrument
Max |V|:       ... V   (never exceed)
Compliance:    DC ... A, pulse ... A, read ... A
Read bias:     ... V
Amplitudes:    SET ... V, RESET ... V
Pulse width:   ... ms
Counts:        ... cycles / ... pulses per branch / ... repeats / ... states
Stop when:     ... (e.g. window ratio < 2, |drift| > 30 %, after 30 min)
Output:        CSV + plot of ...; summary of ...
Notes:         what you already know about this device (window, previous runs, probe position)
```

## Examples

### DC I-V

> **Not enough:** "Do an IV on chipA_R9C9."
>
> **Good:** "Real instrument. Device chipA_R9C9_iv. DC I-V, 3 cycles, sweep +1.0 V / −1.0 V,
> step 20 mV, compliance 1 mA, read at −0.1 V. Plot log|I| vs V per cycle and give me
> HRS, LRS and on/off ratio per cycle. If the loop does not open, stop and tell me. Do
> not widen the range on your own."

Follow-up: "The loop opened but did not close. Repeat with ±1.3 V, same everything else."

### LTP / LTD

> **Not enough:** "Measure LTP and LTD."
>
> **Good:** "Real instrument. Device chipA_R9C9_ltp, window from yesterday's IV run on the same
> device ID. LTP/LTD with SET +1.0/+1.2 V and RESET −1.0/−1.2 V, width 10 µs, 50 pulses per
> branch, 3 cycles per amplitude, compliance 1 mA, read −0.1 V. Keep trains whose
> write-verify missed. Plot G vs pulse number. Tell me for each branch what fraction of
> steps go in the expected direction."

### Single-pulse map

> **Good:** "Simulation first, then real. Device chipA_R9C8_map. Single-pulse map: 3 start
> states (0.2, 0.5, 0.8 of the window), amplitudes ±0.9/±1.1/±1.3 V, widths 10 and 100 µs,
> 10 repeats. Write-verify with ±1.0 and ±1.2 V so it stays off the test grid, 1 s settle
> before G_before. Tell me the pulse estimate and the duration before starting. Plot
> ΔG/G vs G_before per amplitude, and count wrong-sign averages."

### Endurance

> **Good:** "Real instrument. Device chipA_R9C8_end. Endurance: 5 × +1.2 V / 5 × −1.2 V, 10 µs,
> up to 1000 cycles, compliance 1 mA. Stop when the window ratio drops below 2 or below 30 %
> of the initial one. Run 100 cycles first and show me the plot before continuing."

### Retention

> **Good:** "Real instrument. Device chipA_R9C8_ret. Retention of one SET state (5 × +1.2 V,
> 10 µs) and one RESET state (5 × −1.2 V, 10 µs). Read every 10 s at −0.1 V, up to
> 30 min per state, stop early at 50 % drift. Run it in the background and tell me when
> it finishes."

### Read noise (choosing a read bias)

> **Good:** "Device chipA_R9C8_noise. Read noise at 3 states (0.1, 0.5, 0.9), 300 reads each.
> Do it at −0.1 V and at −0.3 V. Compare CV and trend, and tell me which bias you would
> use and why."

### Relaxation

> **Good:** "Device chipA_R9C8_relax. Relaxation at 0.2 / 0.5 / 0.8 of the window, reads at 0,
> 0.1, 0.3, 1, 3, 10, 30, 100 s, 3 repeats. Plot drift vs time on a log axis."

### Something the kit does not have

> **Good:** "Write a new test from the custom skeleton: at a fixed +1.1 V, apply widths
> 10, 20, 50, 100, 200 µs, re-initialise to 0.3 of the window before each pulse, read
> after each. Run it in simulation and show me the code and the CSV columns before
> any real run."

## Useful phrases

| You say | Effect |
|---|---|
| "simulation only" | No instrument at all |
| "show me the spec first" | The agent stops at the table |
| "small run first" | A reduced version before the full matrix |
| "do not exceed X V / X A" | Becomes the hard ceiling in the device file |
| "stop and tell me if ..." | An extra stop condition |
| "run in the background and report when done" | Background job with a timeout above the duration |
| "turn everything off" | `test_instrument_connection`: 0 V, outputs off, read back |
| "plot X vs Y from run <folder>" | Analysis on existing data, no instrument |

## Things to avoid

- Vague targets ("good LTP", "make it linear"). Say what you will look at.
- Asking the agent to "find the best voltage" with no ceiling. Give the ladder and the
  ceiling, and ask it to stop at the first sufficient value.
- Pasting another device's numbers as if they applied. Say where they come from.
- Approving limits you have not read. The table exists so you read it.
