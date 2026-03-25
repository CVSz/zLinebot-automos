import Binance from "binance-api-node";

const client = Binance({
  apiKey: process.env.BINANCE_API_KEY,
  apiSecret: process.env.BINANCE_SECRET,
});

export async function marketBuy(symbol, quantity) {
  return client.order({ symbol, side: "BUY", type: "MARKET", quantity });
}

export async function marketSell(symbol, quantity) {
  return client.order({ symbol, side: "SELL", type: "MARKET", quantity });
}

