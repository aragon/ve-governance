from dataclasses import dataclass
from typing import List, Dict
import time

@dataclass
class LockedBalance:
    amount: int
    start: int

@dataclass
class GlobalPoint:
    bias: int
    slope: int
    written_ts: int

@dataclass
class TokenPoint:
    coefficients: List[int]  # [bias, slope, 0]
    checkpoint_ts: int
    written_ts: int

# -----------------------
# Simulated On-Chain State
# -----------------------
global_point_history: Dict[int, GlobalPoint] = {}
global_point_latest_index: int = 0
token_point_history: Dict[int, Dict[int, TokenPoint]] = {}
token_point_latest_index: Dict[int, int] = {}
slope_changes: Dict[int, int] = {}
locked_balances: Dict[int, LockedBalance] = {}

# -----------------------
# Curve Parameters
# -----------------------
checkpoint_interval = 3600  # 1 hour
epoch_duration = 7200      # 2 hours
MAX_EPOCHS = 10
MAX_TIME = MAX_EPOCHS * epoch_duration # 20 hours
LINEAR_COEFF = 2
CONSTANT_COEFF = 1
# 3 hours
warmupPeriod = 10800


# function boundElapsedMaxTime(uint256 _elapsed) private view returns (uint256) {
#     uint256 MAX_TIME = maxTime();
#     return _elapsed > MAX_TIME ? MAX_TIME : _elapsed;
# }

def bound_elapsed_max_time(elapsed: int) -> int:
    max_time = MAX_TIME
    return elapsed if elapsed <= max_time else max_time

# ---------------------
# Helper: Binary search for interval
# ---------------------
def get_past_token_point_interval(token_id: int, timestamp: int) -> int:
    token_interval = token_point_latest_index.get(token_id, 0)
    if token_interval == 0:
        return 0

    history = token_point_history.get(token_id, {})

    if history.get(token_interval, TokenPoint([0, 0, 0], 0, 0)).written_ts <= timestamp:
        return token_interval

    if history.get(1, TokenPoint([0, 0, 0], 0, 0)).written_ts > timestamp:
        return 0

    lower = 0
    upper = token_interval
    while upper > lower:
        center = upper - (upper - lower) // 2
        point = history.get(center, TokenPoint([0, 0, 0], 0, 0))
        if point.written_ts == timestamp:
            return center
        elif point.written_ts < timestamp:
            lower = center
        else:
            upper = center - 1

    return lower

def old_get_past_token_point_interval(token_id: int, timestamp: int) -> int:
    token_interval = token_point_latest_index.get(token_id, 0)
    if token_interval == 0:
        return 0

    history = token_point_history.get(token_id, {})

    if history.get(token_interval, TokenPoint([0, 0, 0], 0, 0)).checkpoint_ts <= timestamp:
        return token_interval

    if history.get(1, TokenPoint([0, 0, 0], 0, 0)).checkpoint_ts > timestamp:
        return 0

    lower = 0
    upper = token_interval
    while upper > lower:
        center = upper - (upper - lower) // 2
        point = history.get(center, TokenPoint([0, 0, 0], 0, 0))
        if point.checkpoint_ts == timestamp:
            return center
        elif point.checkpoint_ts < timestamp:
            lower = center
        else:
            upper = center - 1

    return lower

# ---------------------
# Helper: Warmup logic
# ---------------------
# function _isWarm(
#     uint256 _tokenId,
#     uint256 _ts,
#     TokenPoint memory _originalPoint
# ) private view returns (bool) {
#     IVotingEscrow.LockedBalance memory locked = IVotingEscrow(escrow).locked(_tokenId);

#     // This could occur if user withdraw in which case lock is removed.
#     // In such case, `_tokenId` is treated as if it never existed
#     // in which case we anyways return false.
#     if (locked.amount == 0) return false;

#     // Helps to avoid voting powers not being equal after and before upgrade.
#     // This is because before upgrade, checkpoint ts is always greater than writtenTs
#     // whereas in new versions, it's vice versa.
#     if (_originalPoint.checkpointTs > _originalPoint.writtenTs) {
#         return _ts > _originalPoint.writtenTs + warmupPeriod;
#     }

#     return _ts > locked.start + warmupPeriod;
# }
def is_warm(token_id: int, ts: int, original_point: TokenPoint) -> bool:
    locked = locked_balances.get(token_id, LockedBalance(0, 0))

    if locked.amount == 0:
        return False
    # Check if the original point's checkpoint timestamp is greater than its written timestamp
    if original_point.checkpoint_ts > original_point.written_ts:
        return ts > original_point.written_ts + warmupPeriod

    # Otherwise, check against the locked start time
    return ts > locked.start + warmupPeriod

def is_warm_valid(token_id: int, ts: int, original_point: TokenPoint) -> bool:
    locked = locked_balances.get(token_id, LockedBalance(0, 0))

    if locked.amount == 0:
        return False
    # Check if the original point's checkpoint timestamp is greater than its written timestamp
    if original_point.checkpoint_ts > original_point.written_ts:
        return ts > original_point.checkpoint_ts + warmupPeriod

    # Otherwise, check against the locked start time
    return ts > locked.start + warmupPeriod


# function _isWarm(TokenPoint memory _point) public view returns (bool) {
#     return block.timestamp > _point.writtenTs + warmupPeriod;
# }
def old_is_warm(point: TokenPoint, ts) -> bool:
    return ts > point.written_ts + warmupPeriod

def old_is_warm_valid(point: TokenPoint, ts) -> bool:
    return ts > point.checkpoint_ts + warmupPeriod

# ---------------------
# Helper: Bias calculation
# ---------------------
def _get_bias(elapsed: int, constant: int, linear: int) -> int:
    bias = constant + linear * elapsed
    return max(bias, 0)

def _get_bias_and_slope(elapsed: int, amount: int):
    slope = amount * LINEAR_COEFF
    bias = _get_bias(
        bound_elapsed_max_time(elapsed),
        amount * CONSTANT_COEFF,
        slope
    )
    return bias, slope

# ---------------------
# Core: votingPowerAt
# ---------------------
def voting_power_at(token_id: int, t: int, is_warm_function = is_warm) -> int:
    interval = get_past_token_point_interval(token_id, t)
    # print(f"Get past token point interval: {interval} for token_id: {token_id} at timestamp: {t}")
    if interval == 0:
        return 0

    history = token_point_history.get(token_id, {})
    original_point = history.get(1)
    if not original_point or not is_warm_function(token_id, t, original_point):
        return 0

    history_point = history.get(interval)

    # Do a copy
    last_point: TokenPoint = TokenPoint(
        coefficients=history_point.coefficients.copy(),
        checkpoint_ts=history_point.checkpoint_ts,
        written_ts=history_point.written_ts
    )
    # history.get(interval)
    bias = last_point.coefficients[0]
    slope = last_point.coefficients[1]

    end = original_point.checkpoint_ts + MAX_TIME

    if last_point.checkpoint_ts > last_point.written_ts:
        last_point.written_ts = last_point.checkpoint_ts

    elapsed = t - last_point.written_ts
    time_till_max = max(end - last_point.written_ts, 0)

    if elapsed >= time_till_max:
        elapsed = time_till_max

    return _get_bias(elapsed, bias, slope)

# function votingPowerAt(uint256 _tokenId, uint256 _t) external view returns (uint256) {
#     uint256 interval = _getPastTokenPointInterval(_tokenId, _t);

#     // epoch 0 is an empty point
#     if (interval == 0) return 0;
#     TokenPoint memory lastPoint = _tokenPointHistory[_tokenId][interval];

#     if (!_isWarm(lastPoint)) return 0;
#     uint256 timeElapsed = _t - lastPoint.checkpointTs;

#     return _getBias(timeElapsed, lastPoint.coefficients);
# }
def old_voting_power_at(token_id: int, t: int, is_warm_function = old_is_warm) -> int:
    interval = old_get_past_token_point_interval(token_id, t)

    if interval == 0:
        return 0
    history = token_point_history.get(token_id, {})
    original_point = history.get(1)

    if not original_point or not is_warm_function(original_point, t):
        return 0

    last_point = history[interval]
    bias = last_point.coefficients[0]
    slope = last_point.coefficients[1]

    elapsed = t - last_point.written_ts
    return _get_bias(elapsed, bias, slope)
# ---------------------



def checkpoint(token_id: int, from_locked: LockedBalance, new_locked: LockedBalance, now: int):
    global global_point_latest_index

    if token_id == 0:
        raise Exception("InvalidTokenId")
    if new_locked.start < from_locked.start:
        raise Exception("InvalidCheckpoint")

    global_index = global_point_latest_index

    # new_bias, new_slope = get_bias_and_slope(bound_elapsed_max_time(now - new_locked.start), new_locked.amount)
    new_bias, new_slope = _get_bias_and_slope(now - new_locked.start, new_locked.amount)

    if global_index > 0:
        last_point = GlobalPoint(
            bias=global_point_history[global_index].bias,
            slope=global_point_history[global_index].slope,
            written_ts=global_point_history[global_index].written_ts
        )
    else:
        last_point = GlobalPoint(bias=0, slope=0, written_ts=now)

    if now % checkpoint_interval == 0:
        raise Exception("CheckpointOnDepositIntervalNotAllowed")

    last_checkpoint = last_point.written_ts
    t_i = (last_checkpoint // checkpoint_interval) * checkpoint_interval

    for _ in range(255):
        t_i += checkpoint_interval
        if t_i > now:
            t_i = now
        d_slope = slope_changes.get(t_i, 0)

        last_point.bias += last_point.slope * (t_i - last_checkpoint)
        last_point.slope -= d_slope
        last_point.bias = max(last_point.bias, 0)
        last_point.slope = max(last_point.slope, 0)

        last_checkpoint = t_i
        last_point.written_ts = t_i
        global_index += 1

        if t_i == now:
            break
        else:
            global_point_history[global_index] = GlobalPoint(
                bias=last_point.bias,
                slope=last_point.slope,
                written_ts=t_i
            )

    max_time = MAX_TIME
    new_locked_end = new_locked.start + max_time
    from_locked_end = from_locked.start + max_time

    if (from_locked.start != 0 and new_locked.start != 0 and from_locked.start != new_locked.start and
        (new_locked_end >= now or from_locked_end >= now)):
        raise Exception("InvalidLocks")

    if new_locked_end <= now:
        new_slope = 0

    old_bias, old_slope = 0, 0
    if from_locked.amount > 0:
        old_bias, old_slope = _get_bias_and_slope(now - from_locked.start, from_locked.amount)
        if from_locked_end <= now:
            old_slope = 0

    last_point.bias += (new_bias - old_bias)
    last_point.slope += (new_slope - old_slope)
    last_point.bias = max(last_point.bias, 0)
    last_point.slope = max(last_point.slope, 0)

    token_idx = token_point_latest_index.get(token_id, 0)

    if token_idx > 0 and from_locked_end > now:
        slope_changes[from_locked_end] = slope_changes.get(from_locked_end, 0) - old_slope

    slope_changes[new_locked_end] = slope_changes.get(new_locked_end, 0) + new_slope

    if global_index > 1 and global_point_history[global_index - 1].written_ts == now:
        global_point_history[global_index - 1] = last_point
    else:
        print(last_point)
        global_point_latest_index = global_index
        global_point_history[global_index] = last_point

    # written_ts_max = bound_elapsed_max_time(now - new_locked.start) + new_locked.start
    # token_point = TokenPoint(
    #     coefficients=[new_bias, new_slope, 0],
    #     checkpoint_ts=new_locked.start,
    #     written_ts=written_ts_max
    # )

    token_point = TokenPoint(
        coefficients=[new_bias, new_slope, 0],
        checkpoint_ts=new_locked.start,
        written_ts=now
    )

    if token_id not in token_point_history:
        token_point_history[token_id] = {}

    if token_idx > 0 and token_point_history[token_id][token_idx].written_ts == now:
        token_point_history[token_id][token_idx] = token_point
    else:
        token_idx += 1
        token_point_latest_index[token_id] = token_idx
        token_point_history[token_id][token_idx] = token_point


def print_state():
    print("")
    for index,point in global_point_history.items():
        print(f"Global Point - Index: {index}, Bias: {point.bias}, Slope: {point.slope}, Timestamp: {point.written_ts}")
    for token_id, points in token_point_history.items():
        print(f"Token ID: {token_id}")
        for index,point in points.items():
            print(f"  Token Point - Index: {index}, Coefficients: {point.coefficients}, Checkpoint Timestamp: {point.checkpoint_ts}, Written Timestamp: {point.written_ts}")
    for timestamp, slope in slope_changes.items():
        print(f"Slope Change - Timestamp: {timestamp}, Slope: {slope}")


def _increase_test():
    now = 100000
    # 1 day ago
    start = now - 86400
    checkpoint(
        token_id=1,
        from_locked=LockedBalance(amount=0, start=start),
        new_locked=LockedBalance(amount=10, start=start),
        now=now
    )
    print_state()

    now += 3600
    checkpoint(
        token_id=1,
        from_locked=LockedBalance(amount=15, start=start),
        new_locked=LockedBalance(amount=20, start=start),
        now=now
    )
    print_state()

def _decrease_test():
    now = 100000
    # 1 day ago
    start = now - 86400
    checkpoint(
        token_id=1,
        from_locked=LockedBalance(amount=0, start=start),
        new_locked=LockedBalance(amount=10, start=start),
        now=now
    )
    print_state()

    now += 3600
    checkpoint(
        token_id=1,
        from_locked=LockedBalance(amount=10, start=start),
        new_locked=LockedBalance(amount=2, start=start),
        now=now
    )
    print_state()


def _multiple_tokens():
    now = 100000
    # 1 day ago
    start = now - 86400
    checkpoint(
        token_id=1,
        from_locked=LockedBalance(amount=0, start=start),
        new_locked=LockedBalance(amount=10, start=start),
        now=now
    )
    print_state()

    now += 3600
    checkpoint(
        token_id=2,
        from_locked=LockedBalance(amount=0, start=start),
        new_locked=LockedBalance(amount=10, start=start),
        now=now
    )
    print_state()

def _multiple_tokens_decrease():
    now = 100000
    # 1 day ago
    start = now - 86400
    checkpoint(
        token_id=1,
        from_locked=LockedBalance(amount=0, start=start),
        new_locked=LockedBalance(amount=10, start=start),
        now=now
    )
    print_state()

    now += 3600
    checkpoint(
        token_id=2,
        from_locked=LockedBalance(amount=0, start=start),
        new_locked=LockedBalance(amount=10, start=start),
        now=now
    )
    print_state()

    now += 3600
    checkpoint(
        token_id=1,
        from_locked=LockedBalance(amount=10, start=start),
        new_locked=LockedBalance(amount=2, start=start),
        now=now
    )
    print_state()
    now += 3600
    checkpoint(
        token_id=2,
        from_locked=LockedBalance(amount=10, start=start),
        new_locked=LockedBalance(amount=2, start=start),
        now=now
    )

def _different_start_time():
    now = 100000
    # 1 day ago
    start = now - 10000
    checkpoint(
        token_id=1,
        from_locked=LockedBalance(amount=0, start=0),
        new_locked=LockedBalance(amount=10, start=start),
        now=now
    )
    print_state()

    now += 3600
    checkpoint(
        token_id=1,
        from_locked=LockedBalance(amount=10, start=0),
        new_locked=LockedBalance(amount=10, start=start),
        now=now
    )

    print_state()


def _escrow_test():
    now = 100000
    # start should be at previous checkpoint interval
    start = (now // checkpoint_interval) * checkpoint_interval

    checkpoint(
        token_id=1,
        from_locked=LockedBalance(amount=0, start=start),
        new_locked=LockedBalance(amount=10, start=start),
        now=now
    )
    print_state()

    # now += 3600
    # checkpoint(
    #     token_id=1,
    #     from_locked=LockedBalance(amount=10, start=start),
    #     new_locked=LockedBalance(amount=10, start=start),
    #     now=now
    # )
    # print_state()

def _voting_power_no_first_epoch():
    now = 100000
    first = 100000
    # start should be at previous checkpoint interval
    start = (now // checkpoint_interval) * checkpoint_interval

    checkpoint(
        token_id=1,
        from_locked=LockedBalance(amount=0, start=start),
        new_locked=LockedBalance(amount=10, start=start),
        now=now
    )
    print_state()

    # max time later
    # Have now aligned to checkpoint interval + max_time * 2
    # + 1 to avoid checkpoint on interval exactly
    now = (now // checkpoint_interval) * checkpoint_interval + MAX_TIME * 2 + 1

    checkpoint(
        token_id=1,
        from_locked=LockedBalance(amount=10, start=start),
        new_locked=LockedBalance(amount=10, start=start),
        now=now
    )
    print()
    print(f"Max Timestamp: {start + MAX_TIME}")
    print_state()

    # No first epoch by 1 second
    # This is first checkpoint (100000) - 1 second
    at = first - 1
    print(f"Voting Power at {at}: {voting_power_at(1, at)}")


def _voting_power_at_last_minus():
    now = 100000
    first = 100000
    # start should be at previous checkpoint interval
    start = (now // checkpoint_interval) * checkpoint_interval

    checkpoint(
        token_id=1,
        from_locked=LockedBalance(amount=0, start=start),
        new_locked=LockedBalance(amount=10, start=start),
        now=now
    )
    print_state()

    # max time later
    # Have now aligned to checkpoint interval + max_time * 2
    # + 1 to avoid checkpoint on interval exactly
    now = (now // checkpoint_interval) * checkpoint_interval + MAX_TIME * 2 + 1

    checkpoint(
        token_id=1,
        from_locked=LockedBalance(amount=10, start=start),
        new_locked=LockedBalance(amount=10, start=start),
        now=now
    )
    print()
    print(f"Max Timestamp: {start + MAX_TIME}")
    print_state()

    # At max time * 2
    at = start + MAX_TIME - 1
    print(f"Voting Power at {at}: {voting_power_at(1, at)}")


def _test_warmup():
    now = 100000
    first = 100000
    # start should be at previous checkpoint interval
    start = (now // checkpoint_interval) * checkpoint_interval

    _token_id = 1
    _from_locked = LockedBalance(amount=0, start=start)
    _new_locked = LockedBalance(amount=10, start=start)

    checkpoint(
        token_id=_token_id,
        from_locked=_from_locked,
        new_locked=_new_locked,
        now=now
    )
    locked_balances[_token_id] = _new_locked

    print_state()

    at = start + warmupPeriod + 1
    print(f"Voting Power at {at}: {voting_power_at(1, at)}")
    print(f"Voting Power at {at} (old): {old_voting_power_at(1, at)}")

def _test_warmup_old():
    now = 100000
    # start should be at previous checkpoint interval
    prev_checkpoint = (now // checkpoint_interval) * checkpoint_interval
    next_checkpoint = prev_checkpoint + checkpoint_interval

    _token_id = 1
    # _from_locked = LockedBalance(amount=0, start=next_checkpoint)
    _new_locked = LockedBalance(amount=10, start=next_checkpoint)

    token_point_history[_token_id] = {
        1: TokenPoint(coefficients=[100, 100, 0], checkpoint_ts=next_checkpoint, written_ts=now)
    }
    token_point_latest_index[_token_id] = 1
    locked_balances[_token_id] = _new_locked

    at = next_checkpoint + warmupPeriod - 500

    # That case should return 0 as we are on an old timestamp that haven't
    # yet passed warmup period

    print()
    print("AT NEXT CHECKPOINT - WARMUP PERIOD - 500")
    print(f"Voting Power at {at}: {voting_power_at(_token_id, at, is_warm)}") # THIS DOES NOT RETURN 0 uses writtenTs + warmupPeriod
    print(f"Voting Power at {at}: {voting_power_at(_token_id, at, is_warm_valid)}") # uses checkpointTs + warmupPeriod

    at = next_checkpoint + warmupPeriod

    print()
    print("AT NEXT CHECKPOINT + WARMUP PERIOD")
    print(f"Voting Power at {at}: {voting_power_at(_token_id, at, is_warm)}") # THIS DOES NOT RETURN 0
    print(f"Voting Power at {at}: {voting_power_at(_token_id, at, is_warm_valid)}")

    at = next_checkpoint + warmupPeriod + 1

    # In this case both values are equal
    print()
    print("AT NEXT CHECKPOINT + WARMUP PERIOD + 1")
    print(f"Voting Power at {at}: {voting_power_at(_token_id, at, is_warm)}")
    print(f"Voting Power at {at}: {voting_power_at(_token_id, at, is_warm_valid)}")

    ###########################################

    # Lets now create an hypotetic "new" point using the new logic of "previous checkpoint"

    _token_id = 1
    # _from_locked = LockedBalance(amount=0, start=next_checkpoint)
    _new_locked = LockedBalance(amount=10, start=prev_checkpoint)

    token_point_history[_token_id] = {
        1: TokenPoint(coefficients=[100, 100, 0], checkpoint_ts=prev_checkpoint, written_ts=now)
    }
    token_point_latest_index[_token_id] = 1
    locked_balances[_token_id] = _new_locked

    # In this case both values are equal ALWAYS
    at = prev_checkpoint + warmupPeriod - 1

    print()
    print('====================================')
    print("AT PREVIOUS CHECKPOINT + WARMUP PERIOD - 1")
    print(f"Voting Power at {at}: {voting_power_at(_token_id, at, is_warm)}")
    print(f"Voting Power at {at}: {voting_power_at(_token_id, at, is_warm_valid)}")

    at = prev_checkpoint + warmupPeriod + 1
    print()
    print("AT PREVIOUS CHECKPOINT + WARMUP PERIOD + 1")
    print(f"Voting Power at {at}: {voting_power_at(_token_id, at, is_warm)}")
    print(f"Voting Power at {at}: {voting_power_at(_token_id, at, is_warm_valid)}")


if __name__ == "__main__":
    # _increase_test()
    # _decrease_test()
    # _multiple_tokens()
    # _multiple_tokens_decrease()
    # _different_start_time()
    # _escrow_test()
    # _voting_power_no_first_epoch()
    # _voting_power_at_last_minus()
    # _test_warmup()
    _test_warmup_old()