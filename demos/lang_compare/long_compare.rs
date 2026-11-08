use std::fs;
use std::rc::Rc;
use std::cell::RefCell;
use std::time::Instant;

struct Node {
    label: String,
    values: Vec<i64>,
    child: Option<Rc<RefCell<Node>>>,
}

impl Node {
    fn new(label: String) -> Self {
        Node { label, values: Vec::new(), child: None }
    }

    fn fill(&mut self, count: i64) {
        for i in 0..count {
            self.values.push(i * i);
        }
    }

    fn attach_child(&mut self, node: Rc<RefCell<Node>>) {
        self.child = Some(node);
    }

    fn sum(&self) -> i64 {
        let mut total: i64 = self.values.iter().sum();
        if let Some(child) = &self.child {
            total += child.borrow().sum();
        }
        total
    }

    fn describe(&self) -> String {
        format!("{} sum={}", self.label, self.sum())
    }
}

fn rss_kb() -> i64 {
    let status = fs::read_to_string("/proc/self/status").unwrap_or_default();
    for line in status.lines() {
        if line.starts_with("VmRSS:") {
            let rest = line.replace("VmRSS:", "").replace("kB", "");
            return rest.trim().parse().unwrap_or(-1);
        }
    }
    -1
}

fn main() {
    let checkpoint = std::time::Duration::from_secs(5);
    let start = Instant::now();
    let mut last_checkpoint = start;
    let mut i: i64 = 0;

    loop {
        let root = Rc::new(RefCell::new(Node::new(format!("root-{}", i))));
        root.borrow_mut().fill(300);

        let inner = Rc::new(RefCell::new(Node::new(format!("inner-{}", i))));
        inner.borrow_mut().fill(150);
        root.borrow_mut().attach_child(inner);

        let _description = root.borrow().describe();

        let mut scratch: Vec<String> = Vec::new();
        for j in 0..80 {
            scratch.push(format!("entry-{}-{}", j, i));
        }

        let _scratch_load = scratch.len();

        let now = Instant::now();
        if now.duration_since(last_checkpoint) >= checkpoint {
            last_checkpoint = now;
            let elapsed = now.duration_since(start).as_secs_f64();
            println!("t={:.1}s iteration={} VmRSS={} kB", elapsed, i, rss_kb());
        }

        i += 1;
    }
}
