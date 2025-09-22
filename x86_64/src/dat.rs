pub use crate::vsvm::{Gdt, Idt, Tss};

use bitstruct::bitstruct;
use port::dat as portdat;
use zerocopy::FromZeros;

pub const UREG_TRAPNO_OFFSET: usize = 19 * core::mem::size_of::<u64>();
pub const UREG_CS_OFFSET: usize = 22 * core::mem::size_of::<u64>();

#[derive(Clone, Debug)]
#[repr(C)]
pub struct Ureg {
    // Pushed by software.
    ax: u64,
    bx: u64,
    cx: u64,
    dx: u64,
    si: u64,
    di: u64,
    bp: u64,
    r8: u64,
    r9: u64,
    r10: u64,
    r11: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,

    // It is arguable whether we should care about
    // these registers.  x86 segmentation (aside from
    // FS and GS) isn't used once we're in long mode,
    // and r9 doesn't support real or compatibility
    // mode, so these are effectively unused.
    //
    // Regardless, they exist, so we save and restore
    // them.  Some kernels do this, some do not.  Note
    // that %fs and %gs are special.
    ds: u64, // Really these are u16s, but
    es: u64, // we waste a few bytes to keep
    fs: u64, // the stack aligned.  Thank
    gs: u64, // you, x86 segmentation.

    trapno: u64,

    // Sometimes pushed by hardware.
    pub ecode: u64,

    // Pushed by hardware.
    pub pc: u64,
    cs: u64,
    flags: u64,
    sp: u64,
    ss: u64,
}

#[derive(Clone, Debug, FromZeros)]
#[repr(C)]
pub struct Label {
    pub pc: u64,
    pub sp: u64,
    pub fp: u64,
    rbx: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
}

impl Label {
    pub const fn new() -> Label {
        Label { pc: 0, sp: 0, fp: 0, rbx: 0, r12: 0, r13: 0, r14: 0, r15: 0 }
    }
}

impl Default for Label {
    fn default() -> Self {
        Self::new()
    }
}

/// The machine structure, which describes a CPU.
///
/// Warning: the layout of this structure is known to assembly
/// language.
#[derive(FromZeros)]
#[repr(C, align(65536))]
pub struct Mach {
    me: *mut Mach,            // %gs:0 is a `*mut Mach` pointing to this `Mach`.
    scratch: usize,           // A scratch word used on entry to kernel
    splpc: usize,             // PC of last caller to ` k`.  Cleared by `spllo`.
    proc: *mut portdat::Proc, // Current process on this process.

    machno: u32,  // Logical ID of CPU.
    cpuno: u32,   // Physical ID of CPU.
    online: bool, // Is this CPU online?
    cpuhz: u64,

    // Various stats that the kernel keeps track of
    ticks: u64,
    tlbfaults: u64,
    ulbpurges: u64,
    pfaults: u64,
    syscalls: u64,
    mmuflushes: u64,

    sched: Label,

    // Architecturally defined.
    tss: Tss,

    // All preceding data fits within a single 4KiB page.  Structures
    // that follow are sized in page multiples and aligned.
    pml4: Page,           // PML4 root page table for this Mach
    pml3: Page,           // The PML3 that maps the kernel for this mach
    pml2: Page,           // PML2 for low 1GiB
    pml1: Page,           // PML1 for low 2MiB
    idt: Idt,             // Interrupt descriptor table
    zero: Page,           // Read-only, zeroed page
    df_stack: ExStack,    // Stack for double faults
    debug_stack: ExStack, // Stack for debug exceptions
    nmi_stack: ExStack,   // Stack for NMIs
    stack: KStack,        // Kernel stack for scheduler
    gdt: Gdt,             // Gdt is aligned to 64KiB.
}
static_assertions::const_assert_eq!(core::mem::offset_of!(Mach, pml4), 4096);
static_assertions::const_assert_eq!(core::mem::offset_of!(Mach, stack), 65536);

#[repr(u8)]
pub enum MachMode {
    Kernel,
    Ring1,
    Ring2,
    User,
}

impl From<u8> for MachMode {
    fn from(raw: u8) -> Self {
        match raw {
            0b00 => MachMode::Kernel,
            0b01 => MachMode::Ring1,
            0b10 => MachMode::Ring2,
            0b11 => MachMode::User,
            _ => panic!("invalid machine mode: {raw:x}"),
        }
    }
}

impl From<MachMode> for u8 {
    fn from(mode: MachMode) -> u8 {
        match mode {
            MachMode::Kernel => 0b00,
            MachMode::Ring1 => 0b01,
            MachMode::Ring2 => 0b10,
            MachMode::User => 0b11,
        }
    }
}

bitstruct! {
    #[derive(Clone, Copy, Debug)]
    #[repr(transparent)]
    pub struct Flags(u64) {
        pub carry: bool = 0;
        mb1: bool = 1;
        pub parity: bool = 2;
        pub aux_carry: bool = 4;
        pub zero: bool = 6;
        pub sign: bool = 7;
        pub trap: bool = 8;
        pub intr: bool = 9;
        pub dir: bool = 10;
        pub overflow: bool = 11;
        pub iopl: MachMode = 12..=13;
        pub nestedt: bool = 14;
        pub resume: bool = 16;
        pub virt8086: bool = 17;
        pub access: bool = 18;
        pub virt_intr: bool = 19;
        pub virt_intr_pending: bool = 20;
        pub id_flag: bool = 21;
    }
}

impl Flags {
    pub fn new(raw: u64) -> Self {
        Self(raw).with_mb1(true)
    }
}

/// The smallest basic page type.
#[derive(FromZeros)]
#[repr(C, align(4096))]
pub struct Page([u8; 4096]);

impl Page {
    pub const fn empty() -> Page {
        Page([0; 4096])
    }
}

impl Default for Page {
    fn default() -> Page {
        Page::empty()
    }
}

/// A small stack that we can use for exception handlers
/// that require their own stack (NMI, Debug, and Double
/// Fault).
#[derive(FromZeros)]
#[repr(C, align(8192))]
pub struct ExStack([u8; 4096]);

/// A kernel stack for a proc.
#[derive(FromZeros)]
#[repr(C, align(65536))]
pub struct KStack([Page; 16]);
