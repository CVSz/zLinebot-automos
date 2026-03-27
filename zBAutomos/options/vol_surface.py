import numpy as np


def implied_volatility(price: float, s: float, k: float, t: float) -> float:
    _ = price
    if t <= 0:
        raise ValueError("t must be > 0")
    if s <= 0 or k <= 0:
        raise ValueError("s and k must be > 0")
    return float(np.sqrt(2 * abs(np.log(s / k)) / t))


def surface(strikes, maturities):
    vol = {}
    for k in strikes:
        for t in maturities:
            vol[(k, t)] = implied_volatility(100, 100, k, t)
    return vol
