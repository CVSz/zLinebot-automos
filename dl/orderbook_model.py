from __future__ import annotations

import torch
import torch.nn as nn


class OrderBookNet(nn.Module):
    """Simple order book microstructure model for BUY/SELL/HOLD logits."""

    def __init__(self, input_size: int = 20, hidden_size: int = 64, num_classes: int = 3):
        super().__init__()
        self.lstm = nn.LSTM(input_size=input_size, hidden_size=hidden_size, batch_first=True)
        self.fc = nn.Linear(hidden_size, num_classes)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        out, _ = self.lstm(x)
        out = out[:, -1, :]
        return self.fc(out)


def build_feature_vector(top_bids: list[list[float]], top_asks: list[list[float]]) -> torch.Tensor:
    """
    Build a 20-feature vector from top-10 bid/ask levels:
    [bid_prices(10), ask_prices(10)] and append engineered factors in sequence data upstream.
    """
    bid_prices = [level[0] for level in top_bids[:10]]
    ask_prices = [level[0] for level in top_asks[:10]]
    features = bid_prices + ask_prices
    if len(features) < 20:
        features += [0.0] * (20 - len(features))
    return torch.tensor(features, dtype=torch.float32)


def softmax_probs(logits: torch.Tensor) -> dict[str, float]:
    probs = torch.softmax(logits, dim=-1).detach().cpu().tolist()
    return {
        "BUY": probs[0],
        "SELL": probs[1],
        "HOLD": probs[2],
    }
