import torch

from model import OrderBookLSTM


model = OrderBookLSTM()
model.load_state_dict(torch.load("model.pt", map_location="cpu"))
model.eval()


def predict(x):
    with torch.no_grad():
        tensor = torch.tensor(x, dtype=torch.float32)
        return torch.argmax(model(tensor), dim=1).item()
