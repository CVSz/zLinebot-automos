import torch.nn as nn


class OrderBookLSTM(nn.Module):
    def __init__(self, feature_size: int = 20, hidden_size: int = 64, classes: int = 3):
        super().__init__()
        self.lstm = nn.LSTM(feature_size, hidden_size, batch_first=True)
        self.fc = nn.Linear(hidden_size, classes)

    def forward(self, x):
        out, _ = self.lstm(x)
        return self.fc(out[:, -1])
