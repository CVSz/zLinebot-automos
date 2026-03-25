import torch

from cnn_ob import OrderBookCNN


device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model = OrderBookCNN().to(device)
model.load_state_dict(torch.load("cnn_ob.pt", map_location=device))
model.eval()


def predict(x_np):
    x = torch.tensor(x_np, dtype=torch.float32, device=device).unsqueeze(0)
    with torch.no_grad():
        logits = model(x)
        return int(torch.argmax(logits, dim=1).item())
