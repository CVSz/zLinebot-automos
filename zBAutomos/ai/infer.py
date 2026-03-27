import torch

from model import OrderBookLSTM


model = OrderBookLSTM()
model.load_state_dict(torch.load("model.pt", map_location="cpu"))
model.eval()


def predict(x):
    with torch.no_grad():
        tensor = torch.tensor(x, dtype=torch.float32)
        if tensor.ndim == 2:
            tensor = tensor.unsqueeze(0)
        if tensor.ndim != 3:
            raise ValueError("Expected input shape (seq, features) or (batch, seq, features)")
        return torch.argmax(model(tensor), dim=1).item()
