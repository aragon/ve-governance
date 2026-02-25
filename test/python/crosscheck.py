#!/usr/bin/env python3
"""Curve sanity checker for pre-deployment review.

Reads curve constants from Solidity, prints:
- Core curve stats
- A 24-row equally spaced value grid
"""

from __future__ import annotations

import ast
import re
from pathlib import Path

WAD = 10**18

SECOND = 1
MINUTE = 60 * SECOND
HOUR = 60 * MINUTE
DAY = 24 * HOUR
WEEK = 7 * DAY
YEAR = 365 * DAY

UNIT_ENV = {
    "SECOND": SECOND,
    "SECONDS": SECOND,
    "MINUTE": MINUTE,
    "MINUTES": MINUTE,
    "HOUR": HOUR,
    "HOURS": HOUR,
    "DAY": DAY,
    "DAYS": DAY,
    "WEEK": WEEK,
    "WEEKS": WEEK,
}


def div_trunc(a: int, b: int) -> int:
    if b == 0:
        raise ZeroDivisionError("division by zero")
    sign = -1 if (a < 0) ^ (b < 0) else 1
    return sign * (abs(a) // abs(b))


class SafeIntEval(ast.NodeVisitor):
    def __init__(self, env: dict[str, int]) -> None:
        self.env = env

    def visit_Expression(self, node: ast.Expression) -> int:
        return self.visit(node.body)

    def visit_Constant(self, node: ast.Constant) -> int:
        if isinstance(node.value, int):
            return node.value
        raise ValueError(f"unsupported literal: {node.value!r}")

    def visit_Name(self, node: ast.Name) -> int:
        if node.id not in self.env:
            raise NameError(node.id)
        return self.env[node.id]

    def visit_BinOp(self, node: ast.BinOp) -> int:
        left = self.visit(node.left)
        right = self.visit(node.right)

        if isinstance(node.op, ast.Add):
            return left + right
        if isinstance(node.op, ast.Sub):
            return left - right
        if isinstance(node.op, ast.Mult):
            return left * right
        if isinstance(node.op, ast.Div):
            return div_trunc(left, right)
        if isinstance(node.op, ast.FloorDiv):
            return div_trunc(left, right)
        if isinstance(node.op, ast.Pow):
            return left**right

        raise ValueError(f"unsupported operator: {type(node.op).__name__}")

    def visit_UnaryOp(self, node: ast.UnaryOp) -> int:
        operand = self.visit(node.operand)
        if isinstance(node.op, ast.UAdd):
            return operand
        if isinstance(node.op, ast.USub):
            return -operand
        raise ValueError(f"unsupported unary operator: {type(node.op).__name__}")

    def generic_visit(self, node: ast.AST) -> int:
        raise ValueError(f"unsupported expression node: {type(node).__name__}")


def preprocess_expr(expr: str) -> str:
    cleaned = expr
    cleaned = re.sub(r"//.*", "", cleaned)
    cleaned = cleaned.strip()

    # Remove numeric separators while preserving identifier underscores.
    cleaned = re.sub(r"\b\d[\d_]*\b", lambda m: m.group(0).replace("_", ""), cleaned)

    cast_pattern = re.compile(r"\b(?:u?int\d+|int|uint)\s*\(\s*([^()]+?)\s*\)")
    while True:
        updated = cast_pattern.sub(r"(\1)", cleaned)
        if updated == cleaned:
            break
        cleaned = updated

    cleaned = re.sub(r"\b(\d+)[eE](\d+)\b", r"(\1*10**\2)", cleaned)

    unit_map = [
        ("weeks", "WEEKS"),
        ("week", "WEEKS"),
        ("days", "DAYS"),
        ("day", "DAYS"),
        ("hours", "HOURS"),
        ("hour", "HOURS"),
        ("minutes", "MINUTES"),
        ("minute", "MINUTES"),
        ("seconds", "SECONDS"),
        ("second", "SECONDS"),
    ]
    for unit_word, unit_name in unit_map:
        cleaned = re.sub(
            rf"\b(\d+)\s*{unit_word}\b",
            rf"(\1*{unit_name})",
            cleaned,
        )

    return cleaned


def eval_int_expr(expr: str, env: dict[str, int]) -> int:
    tree = ast.parse(expr, mode="eval")
    evaluator = SafeIntEval(env)
    return evaluator.visit(tree)


def parse_constants_from_solidity(path: Path) -> dict[str, int]:
    text = path.read_text()
    pattern = re.compile(
        r"\b(?:u?int\d+|int\d+)\s+(?:[A-Za-z_]\w*\s+)*constant\s+([A-Za-z_]\w*)\s*=\s*(.*?);",
        re.S,
    )
    matches = pattern.findall(text)

    if not matches:
        raise RuntimeError(f"No constants found in {path}")

    pending = {name: preprocess_expr(expr) for name, expr in matches}
    resolved: dict[str, int] = dict(UNIT_ENV)

    while pending:
        progressed = False
        for name, expr in list(pending.items()):
            try:
                value = eval_int_expr(expr, resolved)
            except NameError:
                continue
            resolved[name] = value
            del pending[name]
            progressed = True

        if not progressed:
            unresolved = "\n".join(f"  {k} = {v}" for k, v in pending.items())
            raise RuntimeError(f"Could not resolve constants in {path}:\n{unresolved}")

    return resolved


def parse_epoch_duration(clock_path: Path) -> int:
    text = clock_path.read_text()
    match = re.search(
        r"function\s+epochDuration\s*\(\)\s*external\s+pure\s+returns\s*\(uint256\)\s*\{\s*return\s+(.*?);",
        text,
        re.S,
    )
    if not match:
        # sane fallback for this repo
        return 2 * WEEK
    expr = preprocess_expr(match.group(1))
    env = dict(UNIT_ENV)
    env.update(parse_constants_from_solidity(clock_path))
    return eval_int_expr(expr, env)


def format_duration(seconds: int) -> str:
    if seconds < 0:
        return f"-{format_duration(-seconds)}"
    weeks, rem = divmod(seconds, WEEK)
    days, rem = divmod(rem, DAY)
    hours, rem = divmod(rem, HOUR)
    minutes, secs = divmod(rem, MINUTE)
    return f"{weeks}w {days}d {hours}h {minutes}m {secs}s"


def format_totals(seconds: int) -> str:
    weeks = ratio_to_str(seconds, WEEK, decimals=1)
    months = ratio_to_str(seconds, 30 * DAY, decimals=1)
    days = ratio_to_str(seconds, DAY, decimals=1)
    return f"{weeks}w, {months} months, {days} days"


def fp_to_str(fp_value: int, decimals: int = 9) -> str:
    sign = "-" if fp_value < 0 else ""
    x = abs(fp_value)
    whole, frac = divmod(x, WAD)
    frac_scaled = (frac * (10**decimals)) // WAD
    return f"{sign}{whole}.{frac_scaled:0{decimals}d}"


def ratio_to_str(num: int, den: int, decimals: int = 6) -> str:
    if den == 0:
        return "n/a"
    sign = "-" if (num < 0) ^ (den < 0) else ""
    n = abs(num)
    d = abs(den)
    whole = n // d
    frac = ((n % d) * (10**decimals)) // d
    return f"{sign}{whole}.{frac:0{decimals}d}"


def get_multiplier_fp(
    elapsed_seconds: int,
    max_time: int,
    constant_fp: int,
    linear_fp: int,
    quadratic_fp: int,
) -> int:
    t = min(max(elapsed_seconds, 0), max_time)
    return constant_fp + linear_fp * t + quadratic_fp * t * t


def get_bias(
    amount: int,
    elapsed_seconds: int,
    max_time: int,
    constant_fp: int,
    linear_fp: int,
    quadratic_fp: int,
) -> int:
    mfp = get_multiplier_fp(elapsed_seconds, max_time, constant_fp, linear_fp, quadratic_fp)
    if mfp <= 0:
        return 0
    return div_trunc(amount * mfp, WAD)


def print_stats(
    max_epochs: int,
    epoch_duration: int,
    max_time: int,
    constant_fp: int,
    linear_fp: int,
    quadratic_fp: int,
) -> None:
    start_mult_fp = get_multiplier_fp(0, max_time, constant_fp, linear_fp, quadratic_fp)
    end_mult_fp = get_multiplier_fp(max_time, max_time, constant_fp, linear_fp, quadratic_fp)

    linear_contrib_fp = linear_fp * max_time
    quad_contrib_fp = quadratic_fp * max_time * max_time

    print("=== Curve Stats ===")
    print(f"maxEpochs           : {max_epochs}")
    print(f"epochDuration       : {epoch_duration} sec ({format_duration(epoch_duration)})")
    print(f"maxTime             : {max_time} sec ({format_totals(max_time)})")
    print()
    print("shared coefficients (fixed-point, 1e18 scale):")
    print(f"  constant          : {constant_fp}")
    print(f"  linear            : {linear_fp}")
    print(f"  quadratic         : {quadratic_fp}")
    print()
    print("derived multipliers:")
    print(f"  start             : {fp_to_str(start_mult_fp)}x")
    print(f"  end               : {fp_to_str(end_mult_fp)}x")
    print(f"  delta             : {fp_to_str(end_mult_fp - start_mult_fp)}x")
    print(f"  linear@max        : {fp_to_str(linear_contrib_fp)}x")
    print(f"  quadratic@max     : {fp_to_str(quad_contrib_fp)}x")
    print()


def build_time_grid(max_time: int, rows: int = 24) -> list[tuple[str, int]]:
    if rows < 2:
        base = [0]
    else:
        base = [div_trunc(i * max_time, rows - 1) for i in range(rows)]

    points: list[tuple[str, int]] = [("", t) for t in base]
    points.append(("maxTime", max_time))
    points.append(("maxTime+1s", max_time + 1))
    points.append(("maxTime+1y", max_time + YEAR))
    return points


def wad_to_token_str(value_wad: int, decimals: int = 6) -> str:
    sign = "-" if value_wad < 0 else ""
    x = abs(value_wad)
    whole, frac = divmod(x, WAD)
    frac_scaled = (frac * (10**decimals)) // WAD
    return f"{sign}{whole:,}.{frac_scaled:0{decimals}d}"


def print_value_grid(
    amounts: list[int],
    time_grid: list[tuple[str, int]],
    max_time: int,
    constant_fp: int,
    linear_fp: int,
    quadratic_fp: int,
) -> None:
    print("=== Value Grid ===")
    print("inputs: 1e18 and 300e18")
    print()

    header = (
        f"{'row':>3} | {'note':>10} | {'seconds':>10} | {'days':>10} | {'weeks':>10}"
        f" | {'months(30d)':>12} | {'vp(1e18 in)':>16} | {'vp(300e18 in)':>16}"
    )
    print(header)
    print("-" * len(header))

    amount_a, amount_b = amounts
    for idx, (note, t) in enumerate(time_grid):
        vp_a = get_bias(amount_a, t, max_time, constant_fp, linear_fp, quadratic_fp)
        vp_b = get_bias(amount_b, t, max_time, constant_fp, linear_fp, quadratic_fp)

        days = ratio_to_str(t, DAY, decimals=4)
        weeks = ratio_to_str(t, WEEK, decimals=4)
        months = ratio_to_str(t, 30 * DAY, decimals=4)

        print(
            f"{idx:>3} | {note:>10} | {t:>10} | {days:>10} | {weeks:>10} | {months:>12}"
            f" | {wad_to_token_str(vp_a):>16} | {wad_to_token_str(vp_b):>16}"
        )
    print()


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    constants_path = repo_root / "src" / "libs" / "CurveConstantLib.sol"
    clock_path = repo_root / "src" / "clock" / "Clock.sol"

    constants = parse_constants_from_solidity(constants_path)
    epoch_duration = parse_epoch_duration(clock_path)

    required = [
        "MAX_EPOCHS",
        "SHARED_CONSTANT_COEFFICIENT",
        "SHARED_LINEAR_COEFFICIENT",
        "SHARED_QUADRATIC_COEFFICIENT",
    ]
    missing = [name for name in required if name not in constants]
    if missing:
        missing_str = ", ".join(missing)
        raise RuntimeError(f"Missing required constants in {constants_path}: {missing_str}")

    max_epochs = constants["MAX_EPOCHS"]
    constant_fp = constants["SHARED_CONSTANT_COEFFICIENT"]
    linear_fp = constants["SHARED_LINEAR_COEFFICIENT"]
    quadratic_fp = constants["SHARED_QUADRATIC_COEFFICIENT"]
    max_time = max_epochs * epoch_duration

    amounts = [10**18, 300 * 10**18]
    time_grid = build_time_grid(max_time, rows=24)

    print_stats(max_epochs, epoch_duration, max_time, constant_fp, linear_fp, quadratic_fp)
    print_value_grid(amounts, time_grid, max_time, constant_fp, linear_fp, quadratic_fp)

    print("Recommendation: run `make check-curve` before deployment.")


if __name__ == "__main__":
    main()
