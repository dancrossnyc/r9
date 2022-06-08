// Racy to start.

use core::fmt;
use port::devcons::{Console, Uart};

struct Uart16550 {
    port: u16,
}

impl Uart for Uart16550 {
    fn putb(&self, b: u8) {
        crate::x86_64::uart16550::putb(self.port, b);
    }
}

static mut CONSOLE: Console<Uart16550> = Console {
    uart: Uart16550 { port: 0x3f8 },
};

// It would be nice if most the below code was in port....

pub fn print(args: fmt::Arguments) {
    use core::fmt::Write;
    // Todo make threadsafe
    unsafe {
        CONSOLE.write_fmt(args).unwrap();
    }
}

#[macro_export]
macro_rules! println {
    () => ($crate::print!("\n"));
    ($($arg:tt)*) => ($crate::print!("{}\n", format_args!($($arg)*)));
}

#[macro_export]
macro_rules! print {
    ($($args:tt)*) => {{
        $crate::arch::devcons::print(format_args!($($args)*))
    }};
}
