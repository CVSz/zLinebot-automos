import WebSocket from "ws";

const SYMBOL = process.env.SYMBOL ?? "BTCUSDT";
const MIN_SPREAD_USDT = Number(process.env.MIN_SPREAD_USDT ?? 5);
const TAKER_FEE_BPS = Number(process.env.TAKER_FEE_BPS ?? 10);
const MAX_LATENCY_MS = Number(process.env.MAX_LATENCY_MS ?? 120);
const MAX_POSITION = Number(process.env.MAX_POSITION ?? 0.1);
const TRADE_SIZE = Number(process.env.TRADE_SIZE ?? 0.01);
const COOLDOWN_MS = Number(process.env.ARB_COOLDOWN_MS ?? 500);

const feesMultiplier = TAKER_FEE_BPS / 10_000;
const feeds = {
  binance: {
    url: `wss://stream.binance.com:9443/ws/${SYMBOL.toLowerCase()}@bookTicker`,
    subscribe: null,
  },
  bybit: {
    url: "wss://stream.bybit.com/v5/public/spot",
    subscribe: {
      op: "subscribe",
      args: [`orderbook.1.${SYMBOL}`],
    },
  },
  okx: {
    url: "wss://ws.okx.com:8443/ws/v5/public",
    subscribe: {
      op: "subscribe",
      args: [{ channel: "bbo-tbt", instId: "BTC-USDT" }],
    },
  },
};

const quotes = {};
const positions = { binance: 0, bybit: 0, okx: 0 };
const pairState = new Map();

function normalize(name, msg) {
  if (name === "binance" && msg.b && msg.a) {
    return { bid: Number(msg.b), ask: Number(msg.a) };
  }

  if (name === "bybit" && msg?.data?.b?.[0]?.[0] && msg?.data?.a?.[0]?.[0]) {
    return {
      bid: Number(msg.data.b[0][0]),
      ask: Number(msg.data.a[0][0]),
    };
  }

  if (name === "okx" && msg?.data?.[0]?.bids?.[0]?.[0] && msg?.data?.[0]?.asks?.[0]?.[0]) {
    return {
      bid: Number(msg.data[0].bids[0][0]),
      ask: Number(msg.data[0].asks[0][0]),
    };
  }

  return null;
}

function updateQuote(name, quote) {
  quotes[name] = {
    ...quote,
    ts: Date.now(),
  };
  checkArb();
}

function stale(q) {
  return !q || Date.now() - q.ts > MAX_LATENCY_MS;
}

function pairKey(sellExchange, buyExchange) {
  return `${sellExchange}:${buyExchange}`;
}

function estimateRoundTripFees(sellPrice, buyPrice, qty) {
  return qty * ((sellPrice * feesMultiplier) + (buyPrice * feesMultiplier));
}

function canTrade(sellExchange, buyExchange) {
  const nextSellPosition = positions[sellExchange] - TRADE_SIZE;
  const nextBuyPosition = positions[buyExchange] + TRADE_SIZE;
  return Math.abs(nextSellPosition) <= MAX_POSITION && Math.abs(nextBuyPosition) <= MAX_POSITION;
}

async function placeBuy(exchange, price, qty) {
  // Wire to signed REST/WebSocket private API in production.
  positions[exchange] += qty;
  console.log(`[EXEC] BUY ${qty} ${SYMBOL} @ ${price} on ${exchange}`);
}

async function placeSell(exchange, price, qty) {
  // Wire to signed REST/WebSocket private API in production.
  positions[exchange] -= qty;
  console.log(`[EXEC] SELL ${qty} ${SYMBOL} @ ${price} on ${exchange}`);
}

async function executeArb(sellExchange, buyExchange, sellQuote, buyQuote) {
  const id = pairKey(sellExchange, buyExchange);
  const state = pairState.get(id) ?? { locked: false, lastTradeAt: 0 };
  const now = Date.now();

  if (state.locked || now - state.lastTradeAt < COOLDOWN_MS) {
    return;
  }

  state.locked = true;
  pairState.set(id, state);

  try {
    await Promise.all([
      placeSell(sellExchange, sellQuote.bid, TRADE_SIZE),
      placeBuy(buyExchange, buyQuote.ask, TRADE_SIZE),
    ]);
    state.lastTradeAt = Date.now();
  } finally {
    state.locked = false;
    pairState.set(id, state);
  }
}

function checkPair(sellExchange, buyExchange) {
  const sellQuote = quotes[sellExchange];
  const buyQuote = quotes[buyExchange];

  if (stale(sellQuote) || stale(buyQuote)) {
    return;
  }

  const grossSpread = sellQuote.bid - buyQuote.ask;
  const fees = estimateRoundTripFees(sellQuote.bid, buyQuote.ask, TRADE_SIZE);
  const netEdge = grossSpread * TRADE_SIZE - fees;

  if (grossSpread >= MIN_SPREAD_USDT && netEdge > 0 && canTrade(sellExchange, buyExchange)) {
    console.log(
      `⚡ ARB ${sellExchange}->${buyExchange} gross=${grossSpread.toFixed(2)} net=${netEdge.toFixed(2)}`,
    );
    executeArb(sellExchange, buyExchange, sellQuote, buyQuote).catch((err) => {
      console.error("Execution failed", err.message);
    });
  }
}

function checkArb() {
  const names = Object.keys(feeds);
  for (const sellExchange of names) {
    for (const buyExchange of names) {
      if (sellExchange !== buyExchange) {
        checkPair(sellExchange, buyExchange);
      }
    }
  }
}

function connect(name, config) {
  const ws = new WebSocket(config.url);

  ws.on("open", () => {
    console.log(`[WS] connected ${name}`);
    if (config.subscribe) {
      ws.send(JSON.stringify(config.subscribe));
    }
  });

  ws.on("message", (raw) => {
    try {
      const msg = JSON.parse(raw.toString());
      const quote = normalize(name, msg);
      if (quote && Number.isFinite(quote.bid) && Number.isFinite(quote.ask)) {
        updateQuote(name, quote);
      }
    } catch (err) {
      console.error(`[WS] parse error ${name}`, err.message);
    }
  });

  ws.on("close", () => {
    console.warn(`[WS] closed ${name}, reconnecting in 1s`);
    setTimeout(() => connect(name, config), 1000);
  });

  ws.on("error", (err) => {
    console.error(`[WS] error ${name}`, err.message);
  });
}

for (const [name, config] of Object.entries(feeds)) {
  connect(name, config);
}
