import time


class Node:
    __slots__ = ("label", "values", "child", "has_child")

    def __init__(self, label):
        self.label = label
        self.values = []
        self.child = None
        self.has_child = False

    def fill(self, count):
        for i in range(count):
            self.values.append(i * i)

    def attach_child(self, node):
        self.child = node
        self.has_child = True

    def sum(self):
        total = 0
        for v in self.values:
            total += v
        if self.has_child:
            total += self.child.sum()
        return total

    def describe(self):
        return self.label + " sum=" + str(self.sum())


def rss_kb():
    with open("/proc/self/status") as f:
        for line in f:
            if line.startswith("VmRSS:"):
                return int(line.replace("VmRSS:", "").replace("kB", "").strip())
    return -1


def main():
    checkpoint_seconds = 5.0
    start = time.monotonic()
    last_checkpoint = start
    i = 0

    while True:
        root = Node("root-" + str(i))
        root.fill(300)

        inner = Node("inner-" + str(i))
        inner.fill(150)
        root.attach_child(inner)

        description = root.describe()

        scratch = []
        for j in range(80):
            scratch.append("entry-" + str(j) + "-" + str(i))

        scratch_load = len(scratch)

        now = time.monotonic()
        if now - last_checkpoint >= checkpoint_seconds:
            last_checkpoint = now
            elapsed = now - start
            print("t=%.1fs iteration=%d VmRSS=%d kB" % (elapsed, i, rss_kb()), flush=True)

        i += 1


if __name__ == "__main__":
    main()
