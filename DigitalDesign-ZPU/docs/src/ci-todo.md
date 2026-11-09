# CI TODO

Open items that block CI coverage but need another team (or an admin) to act. CI picks each one up once it's done.

## GPIO team

- [ ] Move `rtl/zpu_gpio.sv` to `rtl/gpio/zpu_gpio.sv` and add `rtl/gpio/gpio.f` (same format as `rtl/uart/uart.f`). CI then adds `gpio` to `LINT_BLOCKS` in the top-level `Makefile`.
- [ ] Confirm which branch is canonical for GPIO: `gpio` (has `rtl/zpu_gpio.sv` and `tb/tb_gpio.sv`) or `sajjat-gpio1` (has `zpu_gpio.sv` at the repo root).

## Core team

- [ ] `rtl/core/tb/tb_stack_datapath.sv` doesn't connect the `clk` and `rst` ports that `rtl/core/src/stack_datapath.sv` now has.
- [ ] Confirm `operand_a <= 32'b0` in `stack_datapath.sv` is intended; it never uses `stack_top`.
- [ ] Once the testbench drives the clock and reset, the stack datapath test on `ci/rtl-prototype` (`scripts/test_stack_datapath.sh`) runs against the real core files.

## Wishbone team

- [ ] `wishbone-bus` tracks FuseSoC output under `build/`. Run `git rm -r --cached build/` on that branch before it merges; `main` already ignores `/build/`.

## GHES admin

- [ ] Artifact uploads used to fail with HTTP 504. CI no longer ignores upload failures, so if this comes back the build job goes red.

## Deferred on purpose

- Branch protection on `main`: off until the CI pipeline has a verified track record.
- `lint-test/**` branches: kept for testing; don't delete them yet.
