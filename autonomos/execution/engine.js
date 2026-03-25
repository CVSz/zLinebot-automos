const DEFAULTS = {
  maxSlippage: 0.002,
  maxLatencyMs: 100,
};

export async function smartExecute({ side, size, referencePrice, exchange, config = {} }) {
  const settings = { ...DEFAULTS, ...config };
  const startedAt = Date.now();
  const orderBook = await exchange.getOrderBook();

  const best = side === "buy" ? Number(orderBook.ask) : Number(orderBook.bid);
  const slippage = Math.abs((best - referencePrice) / referencePrice);

  if (slippage > settings.maxSlippage) {
    return {
      status: "skipped",
      reason: "slippage_too_high",
      slippage,
      best,
      side,
      size,
    };
  }

  const order = await exchange.limitOrder(side, size, best);
  const latency = Date.now() - startedAt;

  return {
    status: latency > settings.maxLatencyMs ? "warning" : "filled",
    reason: latency > settings.maxLatencyMs ? "high_latency" : "ok",
    side,
    size,
    price: best,
    slippage,
    latency,
    order,
  };
}

export async function twapOrder({ side, totalSize, referencePrice, exchange, slices = 5, pauseMs = 2_000, config = {} }) {
  const childSize = totalSize / slices;
  const executions = [];

  for (let index = 0; index < slices; index += 1) {
    const result = await smartExecute({
      side,
      size: childSize,
      referencePrice,
      exchange,
      config,
    });

    executions.push({ slice: index + 1, ...result });

    if (index < slices - 1) {
      await sleep(pauseMs);
    }
  }

  return executions;
}

export async function bestExecution(exchanges, order) {
  let selected = null;

  for (const exchange of exchanges) {
    const quote = await exchange.getPrice(order.symbol);
    if (!selected || quote < selected.price) {
      selected = { exchange, price: quote };
    }
  }

  if (!selected) {
    throw new Error("No exchange available for routing");
  }

  return selected.exchange.limitOrder(order.side, order.size, selected.price);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
