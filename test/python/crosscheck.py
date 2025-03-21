# time utils
HOUR = 60 * 60
DAY = 24 * HOUR
WEEK = 7 * DAY

# Variables
AMOUNT = 1_000_000_000  # example amount to deposit
ALTERNATIVE_AMOUNT = 420.69  # alternative amount to deposit
PERIOD_LENGTH = 2 * WEEK  # example period length in seconds (1 week)
WARMUP_PERIOD = 3 * DAY  # warmup period in days
MAX_PERIODS = 6  # maximum periods
MAX_MULTIPLIER = 8  # maximum multiplier

QUADRATIC_COEFFICIENT = 0
LINEAR_COEFFICIENT = MAX_MULTIPLIER / (MAX_PERIODS * PERIOD_LENGTH)
CONSTANT = 1


# Function to evaluate y
def evaluate_y(secondsElapsed):
    x = secondsElapsed
    y = (
        AMOUNT
        * 1e18
        * (QUADRATIC_COEFFICIENT * (x**2) + LINEAR_COEFFICIENT * x + CONSTANT)
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
    (f"2 periods (2 * PERIOD)", 2 * PERIOD_LENGTH),
    (f"3 periods (3 * PERIOD)", 3 * PERIOD_LENGTH),
    (f"4 periods (4 * PERIOD)", 4 * PERIOD_LENGTH),
    (f"PERIOD_END ({MAX_PERIODS} * PERIOD)", MAX_PERIODS * PERIOD_LENGTH),
]

# Evaluate and print results
print()
print(f"==== VP for {AMOUNT} ====")
for label, t in time_points:
    y_value = evaluate_y(t)
    implicit_multiplier = y_value / (AMOUNT * 1e18)
    # Avoid scientific notation by formatting with commas and align values vertically
    print(
        f"{label:<30} Voting Power: {y_value:>20.0f} | {y_value / 1e18:.0f} | {implicit_multiplier:.2f}x"
    )

AMOUNT = ALTERNATIVE_AMOUNT

print()
print(f"==== Changing amount to {AMOUNT} ====")

for label, t in time_points:
    y_value = evaluate_y(t)
    implicit_multiplier = y_value / (AMOUNT * 1e18)
    # Avoid scientific notation by formatting with commas and align values vertically
    print(
        f"{label:<30} Voting Power: {y_value:>20.0f} | {y_value / 1e18:.0f} | {implicit_multiplier:.2f}x"
    )
