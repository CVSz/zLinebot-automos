const followers = new Map();

export function follow(userId, masterId) {
  followers.set(userId, masterId);
  return { userId, masterId };
}

export function unfollow(userId) {
  followers.delete(userId);
}

export function getFollowers(masterId) {
  return Array.from(followers.entries())
    .filter(([, master]) => master === masterId)
    .map(([user]) => user);
}

export function propagateTrade(masterId, trade, executor = (userId, copiedTrade) => ({ userId, copiedTrade })) {
  const copied = [];

  for (const [userId, followedMaster] of followers.entries()) {
    if (followedMaster !== masterId) continue;
    copied.push(executor(userId, { ...trade, source: masterId }));
  }

  return copied;
}

export function rankBots(bots) {
  return [...bots].sort((a, b) => b.profit - a.profit);
}
