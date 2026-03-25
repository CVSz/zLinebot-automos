import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

from cnn_ob import OrderBookCNN


def train(epochs: int = 5, lr: float = 1e-3):
    # Placeholder training tensor: replace with order book tensors
    x = torch.randn(2048, 3, 40, 16)
    y = torch.randint(0, 3, (2048,))

    loader = DataLoader(TensorDataset(x, y), batch_size=64, shuffle=True)
    model = OrderBookCNN()
    optim = torch.optim.Adam(model.parameters(), lr=lr)
    criterion = nn.CrossEntropyLoss()

    model.train()
    for epoch in range(epochs):
        total_loss = 0.0
        for xb, yb in loader:
            optim.zero_grad()
            logits = model(xb)
            loss = criterion(logits, yb)
            loss.backward()
            optim.step()
            total_loss += loss.item()

        print(f"epoch={epoch + 1} loss={total_loss / len(loader):.6f}")

    torch.save(model.state_dict(), "cnn_ob.pt")


if __name__ == "__main__":
    train()
