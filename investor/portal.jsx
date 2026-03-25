import React from "react";

const ROLES = ["user", "admin", "investor"];

function hasInvestorAccess(role) {
  return role === "investor" || role === "admin";
}

export default function InvestorPortal({ user, portfolio }) {
  if (!ROLES.includes(user?.role)) {
    return <p>Unauthorized role.</p>;
  }

  if (!hasInvestorAccess(user.role)) {
    return <p>Your role does not have investor dashboard access.</p>;
  }

  return (
    <section>
      <h1>💼 Fund Dashboard</h1>
      <p>Welcome, {user.name}</p>
      <p>Value: ${portfolio.value?.toLocaleString?.() ?? portfolio.value}</p>
      <p>PnL: ${portfolio.pnl?.toLocaleString?.() ?? portfolio.pnl}</p>
      <p>Sharpe: {portfolio.sharpe}</p>
      <p>Max Drawdown: {portfolio.maxDrawdown}%</p>
    </section>
  );
}

export { ROLES, hasInvestorAccess };
