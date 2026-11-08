const fs = require("fs");

class Node {
  constructor(label) {
    this.label = label;
    this.values = [];
    this.child = null;
    this.hasChild = false;
  }

  fill(count) {
    for (let i = 0; i < count; i++) {
      this.values.push(i * i);
    }
  }

  attachChild(node) {
    this.child = node;
    this.hasChild = true;
  }

  sum() {
    let total = 0;
    for (const v of this.values) {
      total += v;
    }
    if (this.hasChild) {
      total += this.child.sum();
    }
    return total;
  }

  describe() {
    return this.label + " sum=" + this.sum();
  }
}

function rssKb() {
  const status = fs.readFileSync("/proc/self/status", "utf8");
  for (const line of status.split("\n")) {
    if (line.startsWith("VmRSS:")) {
      return parseInt(line.replace("VmRSS:", "").replace("kB", "").trim(), 10);
    }
  }
  return -1;
}

function main() {
  const checkpointMs = 5000;
  const start = Date.now();
  let lastCheckpoint = start;
  let i = 0;

  for (;;) {
    const root = new Node("root-" + i);
    root.fill(300);

    const inner = new Node("inner-" + i);
    inner.fill(150);
    root.attachChild(inner);

    const description = root.describe();

    const scratch = [];
    for (let j = 0; j < 80; j++) {
      scratch.push("entry-" + j + "-" + i);
    }

    const scratchLoad = scratch.length;

    const now = Date.now();
    if (now - lastCheckpoint >= checkpointMs) {
      lastCheckpoint = now;
      const elapsed = ((now - start) / 1000).toFixed(1);
      console.log("t=" + elapsed + "s iteration=" + i + " VmRSS=" + rssKb() + " kB");
    }

    i++;
  }
}

main();
