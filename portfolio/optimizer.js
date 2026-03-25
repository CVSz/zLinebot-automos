import { inv, matrix, mean, multiply, ones } from "mathjs";

function normalize(weights) {
  const total = weights.reduce((acc, w) => acc + Math.max(0, w), 0);
  if (total === 0) {
    const equal = 1 / weights.length;
    return weights.map(() => equal);
  }
  return weights.map((w) => Math.max(0, w) / total);
}

function covarianceMatrix(returnsByAsset) {
  const n = returnsByAsset.length;
  const means = returnsByAsset.map((series) => mean(series));
  const sampleSize = returnsByAsset[0].length;

  const cov = Array.from({ length: n }, () => Array.from({ length: n }, () => 0));

  for (let i = 0; i < n; i += 1) {
    for (let j = 0; j < n; j += 1) {
      let value = 0;
      for (let t = 0; t < sampleSize; t += 1) {
        value += (returnsByAsset[i][t] - means[i]) * (returnsByAsset[j][t] - means[j]);
      }
      cov[i][j] = value / Math.max(1, sampleSize - 1);
    }
  }
  return cov;
}

export function optimize(returnsByAsset, riskAversion = 1.0) {
  if (!Array.isArray(returnsByAsset) || returnsByAsset.length < 2) {
    throw new Error("Pass returnsByAsset as an array of >=2 return series");
  }

  const mu = matrix(returnsByAsset.map((series) => [mean(series)]));
  const sigma = matrix(covarianceMatrix(returnsByAsset));
  const sigmaInv = inv(sigma);

  // Approximate mean-variance weights: w ∝ Σ^-1 μ / λ
  const raw = multiply(1 / riskAversion, multiply(sigmaInv, mu)).toArray().map((v) => v[0]);
  const weights = normalize(raw);

  const gross = weights.reduce((acc, v) => acc + Math.abs(v), 0);
  const diversification = 1 / gross;

  return {
    weights,
    diversification,
    budgetCheck: weights.reduce((acc, v) => acc + v, 0),
    target: multiply(ones([1, returnsByAsset.length]), matrix(weights)).toArray()[0][0],
  };
}

export { normalize };
