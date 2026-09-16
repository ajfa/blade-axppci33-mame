# DEC AXPpci/33 for MAME

A MAME driver for the DEC AXPpci/33, the board Digital called "Noname", written
from scratch. MAME did not have this machine.

The AXPpci/33 is a 1994 single board computer built around a 21066: a 21064 core
with the memory and PCI controller of the LCA chipset on the same die, running at
166 MHz. Around it sits an ordinary PC south bridge, an 82378 with two 8259
interrupt controllers, an 8254 timer, an MC146818 clock, two 16550 serial ports,
an 82077 floppy controller and a PS/2 keyboard controller.

It needs no proprietary ROM. The PALcode and the MILO loader both ship with the
operating system, and the driver copies them into memory the way the board's SROM
does before it releases the processor.

## Status

The machine boots BLADE 0.3, the Linux/Alpha distribution of November 1995, from
an IDE disk to its login prompt in about 35 seconds. It logs in from the emulated
keyboard, draws its console on the video card, and compiles and runs a C program
with the distribution's own gcc 2.7.0, integers and floating point both correct.
Around 40 per cent of real time on a current machine. A full session leaves no
kernel oops and no complaint from the memory manager.

Emulated: the 21066 running real PALcode, the LCA address windows and its sparse
I/O, both interrupt controllers, the timer, the real time clock, the cascaded DMA
controllers, the 82077 floppy controller, an IDE interface with a hard disk, a VGA
card and the keyboard controller with its keyboard.

Not emulated: the PCI bus itself, beyond configuration space answering that the
slots are empty; the NCR 53C810 SCSI controller; the LCA DMA windows and their
scatter-gather; and the Ethernet.

Known problems:

- The serial line carries the loader and echoes what is typed at it, but long
  output from a program stops after about fifteen bytes. The transmit interrupt
  path is the suspect. The console to use is the video card and the keyboard.
- X11 is on the distribution but its only server is for S3 cards, and this machine
  has a plain VGA.

## Layout

    src/mame/dec/noname.cpp    the driver
    patches/                   changes to the rest of the MAME tree
    tools/console.py           talks to the loader over the serial port
    tools/keyboard.lua         logs in and drives the machine from its keyboard

## Building

Against MAME 0.289. Copy the driver in, apply the patches and build the driver on
its own:

    cp -r src <mame>/

    cd <mame>
    patch -p1 < <this>/patches/0001-alpha-palcode-interrupts-and-floating-point.patch
    patch -p1 < <this>/patches/0002-8042kbdc-translate-scan-codes.patch
    patch -p1 < <this>/patches/0003-mame-add-the-driver-to-the-list.patch
    make SUBTARGET=blade SOURCES=src/mame/dec/noname.cpp

Note that gcc 11.4 crashes compiling `alpha.cpp` and `8042kbdc.cpp` at -O2, with
or without these changes. The first patch works around it by building the last
function of each file at -O1.

## The patches

**0001, the Alpha core.** The core had only ever been exercised by the Jensen
skeleton, so it had never run PALcode. Twelve bugs came out of running an
operating system on it:

1. `icache_fetch` filled its blocks from an unmasked address.
2. `hw_ld` and `hw_st`, the physical accesses PALcode is built on, were missing.
3. The load-locked pass-through handler was never stored.
4. `rpcc` did not write its destination register.
5. `execute_set_input` was empty, so no interrupt ever arrived.
6. The abox was missing the `dcAddr` register.
7. There was no unaligned data trap. The operating system emulates unaligned
   longword and quadword accesses by hand, and reads the partition table that way.
8. The translation buffer was not invalidated on a context switch, so a new
   process ran with its parent's translations and died before its first system
   call.
9. `ldq_l` and `stq_c` installed and removed a memory tap for every pair, which
   rebuilds MAME's dispatch tree. As PALcode does a `stl_c` on every exception
   return, the machine spent 92 per cent of its time there. An address and a flag
   are thirty times faster.
10. `stq_c` wrote its result into its own source register before it knew whether
    the store had happened, so a page fault in the middle lost the data.
11. The high variants of the extract and insert instructions shift by 64 when the
    byte offset is zero, which C++ leaves undefined and x86 answers by returning
    the whole operand. The architecture asks for zero, and Alpha's `memcpy` uses
    that sequence unconditionally.
12. `cmpbge` with a literal compared every byte against the whole literal.

And the one that took longest: **the interrupt enable and request registers are
not in the same format.** The enable register takes the Irq<5:0> bits at 14 to 9
and the request register reports them at 12 to 10, one bit apart. Compared
directly, device interrupts stayed enabled while the operating system was serving
one, so they nested on themselves until the kernel stack ate the page directory
underneath it.

The same patch adds IEEE floating point, which was not implemented at all.

**0002, the keyboard controller.** The keyboard sends set 2 scan codes and the
host expects set 1. Translating between them is the controller's job and MAME did
not do it. The table added is the exact inverse of the one the keyboard device
uses, so the pair agrees.

**0003, the driver list.** Registers the new driver so the build finds it.

These are kept here as patches on purpose. They are not submitted anywhere.

## The firmware this board does not have

Nothing runs before the operating system, so the driver leaves behind what a
console firmware would have left, in `machine_reset`:

- The real time clock generating its 1024 Hz periodic interrupt, which is the
  system clock. Without it nothing advances and every driver waits forever.
- Both interrupt controllers initialised, with the slave on line 2 of the master.
- Channel 0 of the master DMA controller in cascade mode, which is what lets the
  slave chain onto the bus. Without it the floppy asks for a transfer and never
  gets one.
- The keyboard controller self test, which is what starts it polling the keyboard,
  and a command byte that asks for interrupts and for translated scan codes.
- The video card in 80 by 25 text with a character generator loaded, which is
  normally the video BIOS's job. There is no video BIOS here, and the symptom of
  leaving it out is not a hang but a black screen: the system writes its text into
  video memory and nothing draws it. The font is the one the MILO console carries
  in `vgafonts.c`.

One trap worth writing down: the mode 3 value of CRTC register 0x11 has the write
protect bit set, so writing that register first to unprotect the timing registers
does the opposite and leaves registers 0 to 7 at zero.

## Getting the firmware and the media

Nothing from the distribution is redistributed here. BLADE 0.3 is on the New
Zealand mirror of Digital's FTP site:

    https://ftp.zx.net.nz/pub/archive/ftp.digital.com/pub/DEC/Linux-Alpha/ARCHIVES/BLADE_0.3/

The two files the driver loads come from there:

    mcopy -i BLADE_0.3/MILO_FLOPPIES/noname_arc_milo_disk ::MILO roms/noname/milo

and `osfpal.nh`, from the MILO sources the distribution installs in
`/usr/src/milo-1.3.31/palcode/noname/osfpal.nh`. Both are also in the `lsrc`
subset of the distribution itself.

The subsets are floppy images holding an ext2 filesystem with one numbered piece
of a tar file each. Concatenating the pieces in the order `Subset.list` gives and
passing them through `gunzip | tar x` unpacks a subset, all of it from the host
with `debugfs`, with nothing mounted and no privileges.

## Running

    mame -rompath <roms> noname -hard blade.hd -com1 null_modem -bitb socket.127.0.0.1:1234

MILO takes its orders on the first serial port, and MAME opens that port as a
client, so something has to be listening before the machine starts:

    python3 tools/console.py 1234

It waits for the `MILO>` prompt and types `boot hda2:vmlinux.gz root=/dev/hda2`
one character at a time, which is the only way the loader does not drop
characters.

The console is the window: log in as `root`, with no password. MAME keeps the
keyboard for its own menu until Scroll Lock hands it over.

To shut down cleanly, `shutdown -h now`, answer the `Why?` it asks with anything,
and wait for `Now you can turn off the power...` before closing the window. The
line under that message, `<sc 55(...)>`, is the kernel asking the console firmware
to halt the machine, and there is no console firmware to answer.

Without a window, `-video none` and `-autoboot_script tools/keyboard.lua` log in
and run a few commands on their own. That script reads the text screen back
through the bus, so it needs no rendering: the characters live in the sparse PCI
window, one every 32 bytes, and each byte arrives in the lane its low address bits
select. The kernel scrolls by moving the CRTC start address, so anything looking
for text has to sweep the whole 32 KB window rather than the first 25 lines.

## A note on MAME's warning screen

The machine is marked as having no sound hardware, which is true, and MAME still
shows a startup warning about it that waits for a key. Its `skip_warnings` option
is only honoured when the same warnings were already shown within the week, which
is never the case on a machine that has just been set up. One line in
`src/frontend/mame/ui/ui.cpp` makes the option mean what it says:

    bool show_warnings = !options().skip_warnings();

It is not included as a patch because that file moves between releases, and
nothing here needs it to run.

## License

BSD-3-Clause, the same as the MAME source it is built against. See LICENSE.
