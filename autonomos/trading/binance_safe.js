import Binance from "binance-api-node";

const MAX_TRADE_USD = Number(process.env.MAX_TRADE_USD || 50);

export function createClient() {
  return Binance({
    apiKey: process.env.BINANCE_API_KEY,
    apiSecret: process.env.BINANCE_SECRET,
    httpBase: "https://testnet.binance.vision",
  });
}

export function validateTrade(amountUSD) {
  if (amountUSD > MAX_TRADE_USD) {
    throw new Error("❌ Trade too large");
  }
}

export async function safeBuy(client, symbol, qty) {
  validateTrade(qty);

  return client.order({
    symbol,
    side: "BUY",
    type: "MARKET",
    quantity: qty,
  });
}

export async function safeSell(client, symbol, qty) {
  validateTrade(qty);

  return client.order({
    symbol,
    side: "SELL",
    type: "MARKET",
    quantity: qty,
  });
}
