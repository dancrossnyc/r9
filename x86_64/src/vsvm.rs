//! "Vestigial Segmented Virtual Memory"
//!
//! This module is a bit unfortunate; it's simply a grab-bag of
//! x86 legacy.  Nominally, all of this ought to go into dat.rs,
//! but that's already busy enough without polluting it with
//! this goo.

use zerocopy::FromZeros;

pub mod seg {
    use super::Tss;
    use crate::dat;

    use bit_field::BitField;
    use bitstruct::bitstruct;
    use zerocopy::FromZeros;

    bitstruct! {
        /// Segment Descriptors describe memory segments in the GDT.
        #[derive(Clone, Copy, Debug, FromZeros)]
        #[repr(transparent)]
        pub struct Descr(u64) {
            reserved0: u32 = 0..32;
            reserved1: u8 = 32..40;
            pub accessed: bool = 40;
            pub readable: bool = 41;
            pub conforming: bool = 42;
            code: bool = 43;
            system: bool = 44;
            iopl: dat::MachMode = 45..47;
            pub present: bool = 47;
            reserved2: u8 = 48..52;
            available: bool = 52;
            long: bool = 53;
            default32: bool = 54;
            granularity: bool = 55;
            reserved3: u8 = 56..64;
        }
    }

    impl Descr {
        pub const fn empty() -> Descr {
            Descr(0)
        }

        pub const fn null() -> Descr {
            Self::empty()
        }

        pub fn code64() -> Descr {
            Self::empty()
                .with_system(true)
                .with_code(true)
                .with_present(true)
                .with_conforming(true)
                .with_long(true)
                .with_iopl(dat::MachMode::Kernel)
        }
    }

    bitstruct! {
        /// Interrupt Gate Descriptors are entries in the IDT.
        #[derive(Clone, Copy, Default, FromZeros)]
        #[repr(transparent)]
        pub struct IntrGateDescr(u128) {
            pub offset0: u16 = 0..16;
            pub segment_selector: u16 = 16..32;
            pub raw_stack_table_index: u8 = 32..35;
            mbz0: bool = 35;
            mbz1: bool = 36;
            mbz2: u8 = 37..40;
            fixed_type: u8 = 40..44;
            mbz3: bool = 44;
            cpl: dat::MachMode = 45..47;
            pub present: bool = 47;
            pub offset16: u16 = 48..64;
            pub offset32: u32 = 64..96;
            pub reserved0: u32 = 96..128;
        }
    }

    bitstruct! {
        /// The Task State Descriptor provides the hardware with sufficient
        /// information to locate the TSS in memory.  The TSS, in turn,
        /// mostly holds stack pointers.
        #[derive(Clone, Copy, Debug, FromZeros)]
        #[repr(transparent)]
        pub struct TaskStateDescr(u128) {
            pub limit0: u16 = 0..16;
            pub base0: u16 = 16..32;
            pub base16: u8 = 32..40;
            mbo0: bool = 40;
            pub busy: bool = 41;
            mbz0: bool = 42;
            mbo1: bool = 43;
            mbz1: bool = 44;
            cpl: dat::MachMode = 45..47;
            pub present: bool = 47;
            pub limit16: u8 = 48..52;
            pub avl: bool = 52;
            mbz2: bool = 53;
            mbz3: bool = 54;
            pub granularity: bool = 55;
            pub base24: u8 = 56..64;
            pub base32: u32 = 64..96;
            reserved0: u8 = 96..104;
            mbz4: u8 = 104..108;
            reserved1: u32 = 108..128;
        }
    }

    impl TaskStateDescr {
        pub fn empty() -> Self {
            Self(0)
        }

        pub(super) fn new(tss: &Tss) -> Self {
            let ptr: *const Tss = tss;
            let va = ptr.addr() as u64;
            Self::empty()
                .with_limit0(core::mem::size_of::<Tss>() as u16 - 1)
                .with_base0(va.get_bits(0..16) as u16)
                .with_base16(va.get_bits(16..24) as u8)
                .with_cpl(dat::MachMode::Kernel)
                .with_present(true)
                .with_avl(true)
                .with_granularity(true)
                .with_base24(va.get_bits(24..32) as u8)
                .with_base32(va.get_bits(32..64) as u32)
        }
    }
}

#[derive(FromZeros)]
#[repr(C, align(65536))]
pub struct Gdt {
    null: seg::Descr,
    ktext: seg::Descr,
    kdata: seg::Descr,
    udata: seg::Descr,
    utext: seg::Descr,
    unused: seg::Descr,
    task: seg::TaskStateDescr,
}

impl Gdt {
    pub const fn textsel() -> u16 {
        1 << 3
    }

    pub const fn tasksel() -> u16 {
        6 << 3
    }

    pub fn init(&mut self, tss: &Tss) {
        self.null = seg::Descr::empty();
        self.ktext = seg::Descr::code64();
        self.kdata = seg::Descr::empty();
        self.udata = seg::Descr::empty();
        self.utext = seg::Descr::empty();
        self.unused = seg::Descr::empty();
        self.task = seg::TaskStateDescr::new(tss);
    }
}

enum IstIndex {
    Rsp0,
    Ist1,
    Ist2,
    Ist3,
    Ist4,
    Ist5,
    Ist6,
    Ist7,
}

#[derive(FromZeros)]
#[repr(C)]
pub struct Tss {
    _res0: u32,
    rsp0: [u32; 2],
    _rsp1: [u32; 2],
    _rsp2: [u32; 2],
    _res1: u32,
    ist1: [u32; 2],
    ist2: [u32; 2],
    ist3: [u32; 2],
    ist4: [u32; 2],
    ist5: [u32; 2],
    ist6: [u32; 2],
    ist7: [u32; 2],
    _res3: u32,
    _res4: u32,
    _res5: u16,
    iomb: u16,
}

#[derive(FromZeros)]
#[repr(C, align(4096))]
pub struct Idt([seg::IntrGateDescr; 256]);
