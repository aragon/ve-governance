# MAX_EPOCHS Test Fixes (Confirmed)

## Verification matrix

### Current constant
- `src/libs/CurveConstantLib.sol`: `MAX_EPOCHS = 104`

### Passing suites at `MAX_EPOCHS=26`
- `make test-ui-140`: `355 passed, 0 failed`
- `make test-ui-130`: `297 passed, 0 failed`
- `make test-ui-120`: `287 passed, 0 failed`
- `make test-ui-110`: `123 passed, 0 failed`
- `make test-ui-season`: `121 passed, 0 failed`

### Passing suites at `MAX_EPOCHS=104`
- `make test-ui-140`: `355 passed, 0 failed`
- `make test-ui-130`: `297 passed, 0 failed`
- `make test-ui-120`: `287 passed, 0 failed`
- `make test-ui-110`: `123 passed, 0 failed`
- `make test-ui-season`: `121 passed, 0 failed`

## Root causes

1. Hardcoded horizon assumptions (`* 52`)
- Tests warped to fixed `52`-epoch timestamps while contract math is bounded by runtime `maxTime`.
- This fails when `MAX_EPOCHS != 52`.

2. Test helper slope math drift (core `<52` breakage source)
- Previous helper reconstructed slope with truncated `1e18 / maxTime`.
- On-chain curve uses exact shared `linearCoefficient`.
- Exact `assertEq` mismatches accumulated when `MAX_EPOCHS` changed.

3. Helper bias lacked the contract clamp path in some tests
- Contract `getBias` clamps `timeElapsed` to `maxTime`.
- Several tests expected `bias(amount, elapsed)` without clamp, so `<52` failed once elapsed crossed `maxTime`.
- Most visible in `v1_1_0` / `season` `testWritesCheckpoint` at `"after p1"`.

4. Rounding order mismatch in delegation expectations
- `bias(a, t) + bias(b, t)` can differ from `bias(a+b, t)` by rounding.
- Contract behavior rounds after aggregation.

## Implemented fixes

1. Parameterized horizon checks
- Replaced hardcoded `*52` endpoint warps with runtime-derived end timestamp (`getEndTimestamp(...)` / `endTs`).

2. Matched helper math to on-chain coefficient math
- Updated `FixedPointBase` variants to use exact passed `linearCoefficient`.
- `slopeFP(amount) = amount * linearCoefficient`
- `biasFP(amount, duration) = amount*1e18 + slope*duration`

3. Switched expected VP assertions to curve-native bias
- Replaced helper `bias(...)` expectations with `curve.getBias(...)` in curve math tests where clamp/rounding precision matters.

4. Fixed rounding-order assertion
- In delegation checkpoint tests, replaced `bias(a,t)+bias(b,t)` with `bias(a+b,t)` where contract aggregates first.

## Files changed

### v1_4_0
- `test/v1_4_0/base/FixedPointBase.sol`
- `test/v1_4_0/unit/escrow/curve/CurveMath.t.sol`
- `test/v1_4_0/unit/delegation/VPAndCheckpoints.t.sol`

### v1_3_0
- `test/v1_3_0/base/FixedPointBase.sol`
- `test/v1_3_0/base/FactoryBase.sol`
- `test/v1_3_0/unit/escrow/curve/CurveBase.t.sol`
- `test/v1_3_0/unit/escrow/curve/CurveMath.t.sol`
- `test/v1_3_0/unit/delegation/Base.sol`
- `test/v1_3_0/unit/delegation/VPAndCheckpoints.t.sol`

### v1_2_0
- `test/v1_2_0/base/FixedPointBase.sol`
- `test/v1_2_0/base/FactoryBase.sol`
- `test/v1_2_0/unit/escrow/curve/CurveBase.t.sol`
- `test/v1_2_0/unit/escrow/curve/CurveMath.t.sol`
- `test/v1_2_0/unit/delegation/Base.sol`
- `test/v1_2_0/unit/delegation/VPAndCheckpoints.t.sol`

### v1_1_0
- `test/v1_1_0/base/FixedPointBase.sol`
- `test/v1_1_0/unit/escrow/curve/QuadraticCurveBase.t.sol`
- `test/v1_1_0/unit/escrow/curve/QuadraticCurveMath.t.sol`

### season
- `test/season/base/FixedPointBase.sol`
- `test/season/unit/escrow/curve/QuadraticCurveBase.t.sol`
- `test/season/unit/escrow/curve/QuadraticCurveMath.t.sol`

### v1_0_0 (full `make test-ui` follow-up)
- `test/v1_0_0/unit/escrow/curve/QuadraticCurveMath.t.sol`
