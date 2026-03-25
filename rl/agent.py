import random
from collections import deque

import torch
from torch import nn

from model import DQN


class Agent:
    def __init__(self, state_dim: int, lr: float = 1e-3) -> None:
        self.model = DQN(state_dim)
        self.target = DQN(state_dim)
        self.target.load_state_dict(self.model.state_dict())
        self.memory = deque(maxlen=10_000)
        self.gamma = 0.99
        self.epsilon = 0.1
        self.optimizer = torch.optim.Adam(self.model.parameters(), lr=lr)
        self.loss_fn = nn.MSELoss()

    def act(self, state):
        if random.random() < self.epsilon:
            return random.randint(0, 2)
        with torch.no_grad():
            q_values = self.model(torch.FloatTensor(state))
            return torch.argmax(q_values).item()

    def remember(self, exp):
        self.memory.append(exp)

    def train(self, batch_size: int = 32):
        if len(self.memory) < batch_size:
            return None

        batch = random.sample(self.memory, batch_size)
        losses = []

        for state, action, reward, next_state in batch:
            target = torch.tensor(reward, dtype=torch.float32)
            if next_state is not None:
                next_q = self.target(torch.FloatTensor(next_state)).max().detach()
                target = target + self.gamma * next_q

            pred = self.model(torch.FloatTensor(state))[action]
            loss = self.loss_fn(pred, target)

            self.optimizer.zero_grad()
            loss.backward()
            self.optimizer.step()
            losses.append(loss.item())

        return sum(losses) / len(losses)

    def sync_target(self):
        self.target.load_state_dict(self.model.state_dict())
