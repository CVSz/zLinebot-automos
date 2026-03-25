import json
import os

import torch

from model import DQN


def main() -> None:
    raw = os.environ.get("RL_STATE", "[]")
    state = json.loads(raw)
    state_dim = len(state)

    if state_dim == 0:
        print(json.dumps({"action": 0, "label": "HOLD"}))
        return

    model = DQN(state_dim)
    model_path = os.environ.get("RL_MODEL_PATH", "rl/model.pt")
    if os.path.exists(model_path):
        model.load_state_dict(torch.load(model_path, map_location="cpu"))

    with torch.no_grad():
        action = int(torch.argmax(model(torch.FloatTensor(state))).item())

    labels = {0: "HOLD", 1: "BUY", 2: "SELL"}
    print(json.dumps({"action": action, "label": labels[action]}))


if __name__ == "__main__":
    main()
