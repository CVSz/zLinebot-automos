const users = [];

export function register(username, password) {
  const user = {
    id: users.length + 1,
    username,
    password,
    balance: 1000,
    plan: "free",
    usage: 0,
  };
  users.push(user);
  return user;
}

export function login(username, password) {
  return users.find((u) => u.username === username && u.password === password);
}

export function listUsers() {
  return users;
}
