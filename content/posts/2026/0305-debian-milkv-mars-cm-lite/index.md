---
title: "Debian on Milk-V Mars CM Lite"
date: 2026-03-05
summary: |
  A detailed walkthrough on installing a mainline-like Debian environment on the RISC-V Milk-V Mars CM Lite using a Waveshare CM4 base board, and configuring U-Boot to boot directly from an NVMe drive.
tags: ["Linux", "RISC-V", "Debian", "SBC"]
authors:
  - "shanduur"
---

Getting Debian running on a new RISC-V board is always a fun adventure. Recently, I've been playing with the **Milk-V Mars CM Lite** - a compute module that brings the StarFive JH7110 RISC-V SoC to the familiar Raspberry Pi CM4 form factor. 

My goal was simple but specific: I wanted a clean Debian installation running entirely off a fast NVMe drive. For this build, I paired the Mars CM Lite with a **Waveshare Compute Module 4/4S Mini Base Board (model B)**.

One important note about the "Lite" module: it has no onboard eMMC. That doesn't matter once we're booting from NVMe, but it does influence how you initially get U-Boot running on the board.

If you're looking to replicate this setup, here is the complete, self-contained process I used to get everything up and running.

## Prerequisites

Before we start flashing images, there are two crucial hardware connections you need to make:

1. **Network Connection:** We will be using Debian Installer's `mini.efi` netboot image. This installer *requires* an active internet connection to download packages during the setup process. You cannot skip this. Plug an Ethernet cable directly from the Waveshare board into your network switch.
2. **Serial Console (UART):** To interrupt the boot process, manually boot from USB, and reconfigure U-Boot later, you will need a serial connection. 

I used an FT232R USB-to-serial adapter. On the Waveshare board's GPIO header, the wiring is:
* **GND:** Pin 6
* **Board TX (to Adapter RX):** Pin 8
* **Board RX (to Adapter TX):** Pin 10

To connect from my terminal, I used `tio` with the following command (adjust your `/dev/tty.*` path as needed):

```shell
tio /dev/tty.usbserial-A5069RR4 -o 1
```

I also kept a vendor-flashed microSD card around as a "known good" recovery path. If your SPI flash is blank or you soft-brick your bootloader while experimenting, booting from a vendor image can be a quick way back to a U-Boot prompt.

## Correct EEPROM Data (Optional but Recommended)

Some Milk-V Mars CM Lite units shipped from the factory with incorrect or uninitialized EEPROM data (for example, wrong values for DRAM size and the eMMC size field). It is highly recommended to fix this before updating U-Boot, as U-Boot relies on these values to properly initialize the hardware.

According to the excellent resource at [freeshell.de](https://freeshell.de/e/riscv64/vf2eeprom/), you can rewrite the EEPROM using the U-Boot console.

1. Boot the board with your vendor-flashed SD card and watch the serial console.
2. **Hit any key to interrupt the autoboot** and drop into the `StarFive #` prompt.

Run the following commands to write the correct EEPROM values.

*Note: The command below assumes D004 represents 4GB DDR, E032 represents 32GB eMMC (for the non-Lite module), and 00001234 represents SN. For CM Lite, the eMMC value should reflect that there is no onboard eMMC. Refer to the [update EEPROM guide](https://milkv.io/docs/mars/compute-module/update-eeprom) to construct the proper string for your specific module and enable write access to EEPROM.*

```shell
mac product_id MARC-V10-2340-D004E032-00001234
mac write_eeprom
```

Once the EEPROM is corrected, you can proceed to updating U-Boot.

## Update U-Boot

The stock/vendor U-Boot that ships on the Mars CM is old and heavily board-patched. In practice that means rough edges with EFI booting (needed for Debian's netboot `mini.efi`), less reliable NVMe enumeration, and confusing environment defaults.

For this walkthrough, we want a recent upstream-ish U-Boot in SPI flash so we can:

- Boot the Debian Installer EFI image directly from U-Boot
- Use U-Boot's standard distro-boot logic to find GRUB on the NVMe
- Prefer NVMe early in the boot order

1. Download the latest U-Boot release for the StarFive/VisionFive2 family (which supports the Mars CM) from [this repository](https://freeshell.de/e/riscv64/vf2eeprom/). I've been using the [`v2026.04-rc3`](https://freeshell.de/e/riscv64/vf2eeprom/u-boot-v2026.04rc3-starfive-visionfive2.zip) which is a pre-release build, but please use latest available - `v2026.04-rc3` or later is needed for this tutorial.
2. Extract the downloaded ZIP file to get `u-boot-spl.bin.normal.out` and `u-boot.itb`.
3. Change your working directory to the place where the extracted files are located and start the serial console.
    ```shell
    cd path/to/u-boot
    tio /dev/tty.usbserial-A5069RR4 -o 1
    ```
4. Boot the board (using whatever currently boots on your setup: a vendor SD card, or an existing U-Boot in SPI).
5. **Hit any key to interrupt the autoboot** and drop into the `StarFive #` prompt.

We will transfer the new binaries over the serial connection using Y-Modem and write them to the SPI Flash storage. 

At this point we're going to "sneak" the new U-Boot binaries into the board over the serial console. The mental model is straightforward:

1. U-Boot receives a file into RAM at `$loadaddr`.
2. The received size is exposed as `$filesize`.
3. We then write that RAM buffer into the boot storage using `sf update` (as exposed by this U-Boot build).

The one detail that matters: make sure U-Boot is already sitting in a receive command before you start the transfer from `tio`. Otherwise you'll just watch the host side time out.

Press <kbd>CTRL</kbd>+<kbd>T</kbd> and then <kbd>X</kbd>

```log
[19:51:55.164] Please enter which X modem protocol to use:
[19:51:55.164]  (0) XMODEM-1K send
[19:51:55.164]  (1) XMODEM-CRC send
[19:51:55.164]  (2) XMODEM-CRC receive
```

Select <kbd>0</kbd>

```log
[19:51:55.928] Send file with XMODEM-1K
[19:51:55.928] Enter file name: 
```

Write `u-boot-spl.bin.normal.out`

```log
[19:52:10.856] Sending file 'u-boot-spl.bin.normal.out'
[19:52:10.856] Press any key to abort transfer
...
[19:52:24.880] Done
U-Boot SPL 2025.01-3 (Apr 08 2025 - 23:07:41 +0000)
DDR version: dc2e84f0.
Trying to boot from UART
CCC
```

The SPL we just pushed is now running, and it immediately switches into "UART boot" mode. That `CCC` spam is a good sign: it means the board is sitting there waiting for the next stage to arrive over the serial link.

Next, we send `u-boot.itb`, which contains the full U-Boot image we actually want to run.

Press <kbd>CTRL</kbd>+<kbd>T</kbd> and then <kbd>Y</kbd>

```log
[19:52:42.978] Send file with YMODEM
[19:52:42.978] Enter file name: 
```

Write `u-boot.itb`

```log
[19:53:13.244] Sending file 'u-boot.itb'
[19:53:13.244] Press any key to abort transfer
```

After `u-boot.itb` is received, SPL hands off into full U-Boot. From here on, we're no longer "booting a one-off image" - we're using a running U-Boot to update the bootloader stored on the SPI flash.

One thing that can be confusing when you follow a transcript: the receive step (`loady`) has to be active on the board before you start sending from `tio`. If you're reproducing this live, the reliable pattern is: type the `loady ... && sf update ...` command first (it will wait and print `CCC`), then start the YMODEM send from `tio`.

```shell
sf probe
```

Now that we're running the newer U-Boot, we'll flash it permanently to the module's SPI.

The layout we use here matches the common VisionFive2/Mars CM convention:

- SPL at SPI offset `0x000000`
- U-Boot proper (FIT/ITB) at SPI offset `0x100000`

```shell
loady $loadaddr && sf update $loadaddr 0 $filesize
```

Once the transfer completes, the SPL binary is now in memory. The `loady $loadaddr` part is the receive step (it places the incoming data at `$loadaddr` and sets `$filesize`). The `sf update` part then copies that RAM buffer into the boot storage at a fixed offset.

Do not power-cycle the board while `sf update` is running.

Press <kbd>CTRL</kbd>+<kbd>T</kbd> and then <kbd>Y</kbd>

```log
[19:56:10.630] Send file with YMODEM
[19:56:10.630] Enter file name: 
```

Write `u-boot-spl.bin.normal.out`

```log
[19:56:24.803] Sending file 'u-boot-spl.bin.normal.out'
[19:56:24.803] Press any key to abort transfer
```

With SPL written, we do the same for `u-boot.itb` (U-Boot proper) at offset `0x100000`.

```shell
loady $loadaddr && sf update $loadaddr 100000 $filesize
```

Press <kbd>CTRL</kbd>+<kbd>T</kbd> and then <kbd>Y</kbd>

```log
[19:57:12.273] Send file with YMODEM
[19:57:12.273] Enter file name: 
```

Write `u-boot.itb`

```log
[19:58:01.384] Sending file 'u-boot.itb'
[19:58:01.384] Press any key to abort transfer
```

Finally, wipe the persisted U-Boot environment. After swapping bootloader binaries, keeping an old vendor environment around can lead to confusing behavior (stale `bootcmd`, unexpected boot targets, and defaults that no longer make sense). `env erase` resets things back to the compiled-in defaults so we can build a clean NVMe boot flow in the next steps.

```shell
env erase
```

## Install Debian to NVMe

With U-Boot updated, installing Debian is straightforward: boot the Debian Installer's EFI binary from U-Boot, then install onto the NVMe.

1. Insert the NVMe drive.
2. Make sure Ethernet is connected.
3. Boot and interrupt autoboot to get the `StarFive #` prompt.

Then run:

```shell
dhcp && wget https://deb.debian.org/debian/dists/trixie/main/installer-riscv64/current/images/netboot/mini.efi && bootefi $loadaddr
```

Proceed through the installer normally.

Important: when the installer asks about installing GRUB to the fallback "removable media path", answer **Yes**.

```terminal
It seems that this computer is configured to boot via EFI, but maybe
that configuration will not work for booting from the hard drive.
Some EFI firmware implementations do not meet the EFI specification
(i.e. they are buggy!) and do not support proper configuration of
boot options from system hard drives.

A workaround for this problem is to install an extra copy of the EFI
version of the GRUB boot loader to a fallback location, the
"removable media path". Almost all EFI systems, no matter how buggy,
will boot GRUB that way.

[...]
```

That fallback path (`EFI/BOOT/BOOTRISCV64.EFI`) is what U-Boot typically finds during its EFI scan.

## Wrapping Up

At this point, you should have a Debian system installed on NVMe and a recent U-Boot living in SPI flash.

Happy hacking on RISC-V!
