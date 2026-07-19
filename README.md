# Booth Radix-4 Multiplier: signed 8x8, SystemVerilog

A full modified Booth radix-4 signed 8x8 multiplier, exhaustively verified over all 65,536 signed input pairs.

This design also serves as the controlled baseline for my [b4g3-multiplier](https://github.com/kiankhooban/b4g3-multiplier) repo, which implements the B4G3 encoding from IEEE ARITH 2024. Both share an identical back end (one's-complement partial products, sign vector, 3:2 compression tree, final CPA), so the only differences between the two designs are in the encoding path. Any cost or delay comparison between them isolates the encoder.

## How it works

Standard modified Booth radix-4: the multiplier operand B is scanned in overlapping 3-bit windows `{b_next, b_curr, b_prev}`, each window selecting one partial product from the full digit menu `{0, +A, +2A, -A, -2A}`. Four windows cover 8 bits, so there are 4 partial products instead of 8.

Two implementation choices worth noting:

- **One's-complement partial products.** Negative digits invert the magnitude instead of negating it. The matching "+1" corrections are collected into a single sign vector row `K` and summed once in the compression tree, instead of paying a carry-propagate negation per partial product.
- **No carry network, no special top unit.** All four Booth units are identical. The top window naturally holds `B[7]`, so the operand sign is handled for free. (The B4G3 variant needs a prefix network and a dedicated top-dibit encoder to get the same behavior; that is the cost it pays for a cheaper digit set.)

### Encoding table

| `{b_next, b_curr, b_prev}` | Digit |
|---|---|
| 000 | 0 |
| 001 | +A |
| 010 | +A |
| 011 | +2A |
| 100 | -2A |
| 101 | -A |
| 110 | -A |
| 111 | 0 |

## Modules

| Module | Role |
|---|---|
| `encoder` | 3-bit overlapping-window Booth encoder |
| `mux` | Partial product select `{0, A, 2A}` plus one's-complement inversion |
| `booth_unit` | Encoder + mux pair, emits the PP and its sign-correction bit |
| `csa16` | 3:2 carry-save compressor node |
| `booth_multiplier` | Top level: 4 Booth units, sign vector, compression tree, final CPA |

Dataflow in the top level: 4 partial products sign-extended to 16 bits and placed at weights 4^i, plus the sign vector `K`, reduced from 5 rows to 2 by three `csa16` stages, then one carry-propagate add.

## Verification

`tb_booth.sv` is self-checking. It first runs 15 named corner cases (the ones that have actually broken designs like this: `-128 * -128`, `A = -128` forcing `-2A`, `B = -128` exercising the top window sign) and then exhaustively sweeps all 65,536 signed pairs against golden `A * B`.

Status: **PASS**, 65,551 checks, 0 mismatches (Icarus Verilog 12).

## Running

```sh
# Icarus Verilog
iverilog -g2012 -o sim booth_radix_4.sv tb_booth.sv && vvp sim

# Verilator
verilator --binary --top-module tb_booth booth_radix_4.sv tb_booth.sv && obj_dir/Vtb_booth

# Vivado xsim: add both files, set tb_booth as top, Run All
```

Icarus prints `sorry: constant selects in always_* processes` notes. Those are sensitivity-list warnings, not errors; the exhaustive sweep confirms the logic is correct.

The testbench targets any design whose top module is `booth_multiplier(A, B, product)`, so the same file verifies both this repo and the B4G3 repo. Run it against one design at a time.

## Related

- [b4g3-multiplier](https://github.com/kiankhooban/b4g3-multiplier): the ARITH 2024 carry-based encoding, same back end, direct comparison target
- [booth-encoder-radix2](https://github.com/kiankhooban/booth-encoder-radix2): my earlier radix-2 Booth encoder
- [multiplier-4x4-partial-products](https://github.com/kiankhooban/multiplier-4x4-partial-products): shift-and-add baseline where this line of work started
