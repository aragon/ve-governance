# time utils
HOUR = 60 * 60
DAY = 24 * HOUR
WEEK = 7 * DAY

# Variables
AMOUNT = 1000
SECOND_AMOUNT = 2000
PERIOD_LENGTH = 2 * WEEK  # example period length in seconds (1 week)
WARMUP_PERIOD = 3 * DAY  # warmup period in days
MAX_PERIODS = 52  # maximum periods

QUADRATIC_COEFFICIENT = 0
LINEAR_COEFFICIENT = 1 / 52
CONSTANT = 1

# Scale amount
amount_scaled = AMOUNT * 1e18


# Function to evaluate y
def evaluate_y(secondsElapsed, PeriodLength, amount_scaled):
    x = secondsElapsed / PeriodLength
    y = amount_scaled * (
        QUADRATIC_COEFFICIENT * (x**2) + LINEAR_COEFFICIENT * x + CONSTANT
    )
    return y


def evaluate_y_v2(secondsElapsed, PeriodLength, amount_scaled):
    x = secondsElapsed / PeriodLength
    y = amount_scaled * (
        QUADRATIC_COEFFICIENT * (x * x) + LINEAR_COEFFICIENT * x + CONSTANT
    )
    return y


# Time points to evaluate, using tuples with optional labels
time_points = [
    ("0", 0),
    ("1 minute", 60),
    ("1 hour", 60 * 60),
    ("1 day", 60 * 60 * 24),
    (f"WARMUP_PERIOD ({WARMUP_PERIOD//DAY} days)", WARMUP_PERIOD),
    (f"WARMUP_PERIOD + 1s", (WARMUP_PERIOD) + 1),
    ("1 week", 60 * 60 * 24 * 7),
    (f"1 period ({PERIOD_LENGTH // (WEEK)} weeks)", PERIOD_LENGTH),
    (f"10 periods (10 * PERIOD)", 10 * PERIOD_LENGTH),
    (f"50% periods (26 * PERIOD)", 26 * PERIOD_LENGTH),
    (f"35 periods (35 * PERIOD)", 35 * PERIOD_LENGTH),
    (f"PERIOD_END (26 * PERIOD)", MAX_PERIODS * PERIOD_LENGTH),
]
#
# # Evaluate and print results
# for label, t in time_points:
#     y_value = evaluate_y(t, PERIOD_LENGTH, amount_scaled)
#     # Avoid scientific notation by formatting with commas and align values vertically
#     print(f"{label:<30} Voting Power: {y_value:>20.0f}")
#


# Evaluate 1 week of 1000 + 1 week of an additional 1000
def eval_multiple():
    amount_scaled = AMOUNT * 1e18
    amount_scaled_2 = SECOND_AMOUNT * 1e18
    end_of_week_2 = evaluate_y(1 * WEEK, PERIOD_LENGTH, amount_scaled)
    # then add the second amount
    end_of_week_2_plus_new_deposit = end_of_week_2 + AMOUNT * 1e18
    y_value_2 = evaluate_y(2 * WEEK, PERIOD_LENGTH, end_of_week_2_plus_new_deposit)

    # print all the values above nicely
    print(f"Start of week 2: {amount_scaled}")
    print(f"End of week 2: {end_of_week_2}")
    print(f"start of week 3 + new deposit: {end_of_week_2_plus_new_deposit}")
    print(f"start of week 5 : {y_value_2}")
    print(f"Start of week 5 + deposit: {y_value_2 + amount_scaled}")


eval_multiple()
