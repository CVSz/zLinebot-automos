export function walkForward<TData, TParams>(
  data: TData[],
  optimize: (train: TData[]) => TParams,
  evaluate: (test: TData[], params: TParams) => unknown,
) {
  const split = Math.floor(data.length * 0.7);
  const train = data.slice(0, split);
  const test = data.slice(split);

  const params = optimize(train);
  return evaluate(test, params);
}
