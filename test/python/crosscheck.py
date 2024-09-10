# time utils
HOUR = 60 * 60
DAY =  24 * HOUR
WEEK = 7 * DAY

# Variables
AMOUNT = 1000  # example amount to deposit
PERIOD_LENGTH = 2 * WEEK  # example period length in seconds (1 week)
WARMUP_PERIOD = 3 * DAY  # warmup period in days
MAX_PERIODS = 5  # maximum periods

QUADRATIC_COEFFICIENT = 1/7
LINEAR_COEFFICIENT = 2/7
CONSTANT = 1

# Scale amount
amount_scaled = AMOUNT * 1e18

# Function to evaluate y
def evaluate_y(secondsElapsed, PeriodLength, amount_scaled):
    x = secondsElapsed / PeriodLength
    y = amount_scaled * (
        QUADRATIC_COEFFICIENT * (x**2)
        + LINEAR_COEFFICIENT * x
        + CONSTANT         
    )
    return y

# Time points to evaluate, using tuples with optional labels
time_points = [
    ("0", 0),
    ("1 minute", 60),
    ("1 hour", 60 * 60),
    ("1 day", 60 * 60 * 24),
    (f"WARMUP_PERIOD ({WARMUP_PERIOD//DAY} days)", WARMUP_PERIOD),
    (f"WARMUP_PERIOD + 1s", (WARMUP_PERIOD)  + 1),
    ("1 week", 60 * 60 * 24 * 7),
    (f"1 period ({PERIOD_LENGTH // (WEEK)} weeks)", PERIOD_LENGTH),
    (f"2 periods (2 * PERIOD)", 2 * PERIOD_LENGTH),
    (f"3 periods (3 * PERIOD)", 3 * PERIOD_LENGTH),
    (f"4 periods (4 * PERIOD)", 4 * PERIOD_LENGTH),
    (f"PERIOD_END (5 * PERIOD)", MAX_PERIODS * PERIOD_LENGTH)
]

# Evaluate and print results
for label, t in time_points:
    y_value = evaluate_y(t, PERIOD_LENGTH, amount_scaled)
    # Avoid scientific notation by formatting with commas and align values vertically
    print(f"{label:<30} Voting Power: {y_value:>20.0f}")
