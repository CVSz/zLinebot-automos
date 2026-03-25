import WebSocket from "ws";

const SYMBOL = "BTCUSDT";
const MIN_SPREAD_USDT = Number(process.env.MIN_SPREAD_USDT ?? 5);
const MAX_LATENCY_MS = Number(process.env.MAX_LATENCY_MS ?? 120);

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

async function placeBuy(exchange, price) {
  // Wire to signed REST/WebSocket private API in production.
  console.log(`[EXEC] BUY ${SYMBOL} @ ${price} on ${exchange}`);
}

async function placeSell(exchange, price) {
  // Wire to signed REST/WebSocket private API in production.
  console.log(`[EXEC] SELL ${SYMBOL} @ ${price} on ${exchange}`);
}

async function executeArb(sellExchange, buyExchange, sellQuote, buyQuote) {
  await Promise.all([
    placeSell(sellExchange, sellQuote.bid),
    placeBuy(buyExchange, buyQuote.ask),
  ]);
}

function checkPair(sellExchange, buyExchange) {
  const sellQuote = quotes[sellExchange];
  const buyQuote = quotes[buyExchange];

  if (stale(sellQuote) || stale(buyQuote)) {
    return;
  }

  const spread = sellQuote.bid - buyQuote.ask;
  if (spread >= MIN_SPREAD_USDT) {
    console.log(
      `⚡ ARB ${sellExchange}->${buyExchange} spread=${spread.toFixed(2)} bid=${sellQuote.bid} ask=${buyQuote.ask}`,
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
