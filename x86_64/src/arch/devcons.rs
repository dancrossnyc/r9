// Racy to start.

use core::fmt;
use port::devcons::ConsoleDriver;

struct Console {
    port: u16,
}

impl ConsoleDriver for Console {
    fn uartputb(&self, b: u8) {
        crate::x86_64::uart16550::putb(self.port, b);
    }
}

// It would be nice if most the below code was in port....

impl fmt::Write for Console {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        self.putstr(s);
        Ok(())
    }
}

pub fn print(args: fmt::Arguments) {
    use core::fmt::Write;
    let mut cons = Console { port: 0x3f8 };
    cons.write_fmt(args).unwrap();
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
