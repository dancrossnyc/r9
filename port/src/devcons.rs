use crate::mcslock::{Lock, LockNode};

const fn ctrl(b: u8) -> u8 {
    b - b'@'
}

#[allow(dead_code)]
const BACKSPACE: u8 = ctrl(b'H');
#[allow(dead_code)]
const DELETE: u8 = 0x7F;
#[allow(dead_code)]
const CTLD: u8 = ctrl(b'D');
#[allow(dead_code)]
const CTLP: u8 = ctrl(b'P');
#[allow(dead_code)]
const CTLU: u8 = ctrl(b'U');

pub trait ConsoleDriver {
    fn uartputb(&self, b: u8);

    fn putb(&mut self, b: u8) {
        if b == b'\n' {
            self.uartputb(b'\r');
        } else if b == BACKSPACE {
            self.uartputb(b);
            self.uartputb(b' ');
        }
        self.uartputb(b);
    }

    fn putstr(&mut self, s: &str) {
        static LOCK: Lock<()> = Lock::new("println", ());
        // XXX: Just for testing.
        static mut NODE: LockNode = LockNode::new();
        let _guard = LOCK.lock(unsafe { &NODE });
        for b in s.bytes() {
            self.putb(b);
        }
    }
}
