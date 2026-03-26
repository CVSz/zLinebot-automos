const fs = require("fs");
const path = require("path");

function processFile(file) {
  let content = fs.readFileSync(file, "utf-8");

  // enforce no console.log
  content = content.replace(/console\.log/g, "console.info");

  fs.writeFileSync(file, content);
}

function walk(dir) {
  for (const f of fs.readdirSync(dir)) {
    const full = path.join(dir, f);
    if (fs.statSync(full).isDirectory()) walk(full);
    else if (
      full.endsWith(".ts") ||
      full.endsWith(".tsx") ||
      full.endsWith(".js") ||
      full.endsWith(".jsx")
    ) {
      processFile(full);
    }
  }
}

walk("frontend");
