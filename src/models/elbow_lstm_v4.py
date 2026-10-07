"""Architecture matching the upstream elbow_lstm_v4.pth checkpoint."""
from torch import nn


class ElbowLSTM(nn.Module):
    def __init__(self, input_size=22, hidden_size=64, num_layers=2, dropout=.3):
        super().__init__()
        self.lstm = nn.LSTM(input_size, hidden_size, num_layers, batch_first=True, dropout=dropout)
        self.fc = nn.Sequential(nn.Linear(hidden_size, 32), nn.ReLU(), nn.Dropout(.3), nn.Linear(32, 1))

    def forward(self, x):
        out, _ = self.lstm(x)
        return self.fc(out[:, -1, :])
