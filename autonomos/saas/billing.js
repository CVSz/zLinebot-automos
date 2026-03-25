export function checkPlan(user) {
  if (user.plan === "free" && user.usage > 100) {
    throw new Error("Upgrade required");
  }
}
