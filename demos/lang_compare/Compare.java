import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

public class Compare {
    static class Node {
        String label;
        List<Integer> values = new ArrayList<>();
        Node child;
        boolean hasChild = false;

        Node(String label) {
            this.label = label;
        }

        void fill(int count) {
            for (int i = 0; i < count; i++) {
                values.add(i * i);
            }
        }

        void attachChild(Node node) {
            this.child = node;
            this.hasChild = true;
        }

        long sum() {
            long total = 0;
            for (int v : values) {
                total += v;
            }
            if (hasChild) {
                total += child.sum();
            }
            return total;
        }

        String describe() {
            return label + " sum=" + sum();
        }
    }

    static long rssKb() throws IOException {
        try (BufferedReader reader = new BufferedReader(new FileReader("/proc/self/status"))) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.startsWith("VmRSS:")) {
                    String rest = line.replace("VmRSS:", "").replace("kB", "").trim();
                    return Long.parseLong(rest);
                }
            }
        }
        return -1;
    }

    public static void main(String[] args) throws IOException {
        int total = 500000;

        for (int i = 0; i < total; i++) {
            Node root = new Node("root-" + i);
            root.fill(300);

            Node inner = new Node("inner-" + i);
            inner.fill(150);
            root.attachChild(inner);

            String description = root.describe();

            List<String> scratch = new ArrayList<>();
            for (int j = 0; j < 80; j++) {
                scratch.add("entry-" + j + "-" + i);
            }

            int scratchLoad = scratch.size();
        }

        System.out.println("iterations=" + total + " VmRSS=" + rssKb() + " kB");
    }
}
