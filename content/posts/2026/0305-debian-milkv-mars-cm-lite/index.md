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

However, there is a catch with the "Lite" version of the Mars CM: **it lacks the onboard eMMC found on the non-Lite module**. On the CM Lite, that onboard eMMC is replaced by a microSD card (on the same MMC interface). This means we can't install the early bootloader stages to onboard eMMC; we *must* keep a microSD card inserted to house the early bootloader (SPL and U-Boot), which will then hand off the actual OS boot process to our NVMe drive.

If you're looking to replicate this setup, here is the complete, self-contained process I used to get everything up and running.

## Prerequisites

Before we start flashing images, there are two crucial hardware connections you need to make:

1. **Network Connection:** We will be using the Debian `mini.iso` netboot installer. This installer *requires* an active internet connection to download packages during the setup process. You cannot skip this. Plug an Ethernet cable directly from the Waveshare board into your network switch.
2. **Serial Console (UART):** To interrupt the boot process, manually boot from USB, and reconfigure U-Boot later, you will need a serial connection. 

I used an FT232R USB-to-serial adapter. On the Waveshare board's GPIO header, the wiring is:
* **GND:** Pin 6
* **Board TX (to Adapter RX):** Pin 8
* **Board RX (to Adapter TX):** Pin 10

To connect from my terminal, I used `tio` with the following command (adjust your `/dev/tty.*` path as needed):

```shell
tio /dev/tty.usbserial-A5069RR4 -o 1
```

## Bootstrapping SD Card

Because the CM Lite has no onboard eMMC (it's replaced by microSD), we need an SD card to provide the initial U-Boot environment. The easiest way to get a working, properly partitioned bootloader is to just use the official vendor image.

1. Download the official vendor image from the [Milk-V Mars CM resources page](https://milkv.io/docs/mars/compute-module/resources/images).
2. Use a tool like **BalenaEtcher** to flash this image onto a microSD card. 

*Note: This will erase all data on the SD card.*

Set this SD card aside for a moment.

## Correct EEPROM Data (Optional but Recommended)

Some Milk-V Mars CM Lite units shipped from the factory with incorrect or uninitialized EEPROM data (for example, wrong values for DRAM size and the eMMC size field). It is highly recommended to fix this before updating U-Boot, as U-Boot relies on these values to properly initialize the hardware.

According to the excellent resource at [freeshell.de](https://freeshell.de/e/riscv64/vf2eeprom/), you can rewrite the EEPROM using the U-Boot console.

1. Boot the board with your vendor-flashed SD card and watch the serial console.
2. **Hit any key to interrupt the autoboot** and drop into the `StarFive #` prompt.

Run the following commands to write the correct EEPROM values.

*Note: The command below assumes D004 represents 4GB DDR, E032 represents 32GB eMMC (for the non-Lite module), and 00001234 represents SN. For CM Lite, the eMMC value should reflect that there is no onboard eMMC. Refer to the [update EEPROM guide](https://milkv.io/docs/mars/compute-module/update-eeprom) to construct the proper string for your specific module.*

```shell
mac product_id MARC-V10-2340-D004E032-00001234
mac write_eeprom
```

Once the EEPROM is corrected, you can proceed to updating U-Boot.

## Update U-Boot on SD Card

The vendor U-Boot included in the official image is too old to properly handle the Debian EFI installation. We need to update the bootloader binaries on the SD card to the newer upstream versions.

1. Download the latest U-Boot release for the StarFive/VisionFive2 family (which supports the Mars CM) from [this repository](https://freeshell.de/e/riscv64/vf2eeprom/). I recommend using `v2026.01` or newer.
2. Extract the downloaded ZIP file to get `u-boot-spl.bin.normal.out` and `u-boot.itb`.
3. Change your working directory to the place where the extracted files are located and start the serial console.
    ```shell
    cd path/to/u-boot
    tio /dev/tty.usbserial-A5069RR4 -o 1
    ```
4. Boot the board with your vendor-flashed SD card and watch the serial console.
5. **Hit any key to interrupt the autoboot** and drop into the `StarFive #` prompt.

We will transfer the new binaries over the serial connection using Y-Modem and write them to the SD card's hidden boot partitions. 

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
...…|
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

After `u-boot.itb` is received, SPL hands off into full U-Boot. From here on, we're no longer "booting a one-off image" - we're using a running U-Boot to update the bootloader stored on the SD's boot area.

One thing that can be confusing when you follow a transcript: the receive step (`loady`) has to be active on the board before you start sending from `tio`. If you're reproducing this live, the reliable pattern is: type the `loady ... && sf update ...` command first (it will wait and print `CCC`), then start the YMODEM send from `tio`.

```shell
sf probe
```

Initialize access to the boot storage with `sf probe`. Once that succeeds, we can write the new U-Boot proper image. The next command will wait for a YMODEM transfer (`loady $loadaddr`) and then immediately write what it received to offset `0` via `sf update` using `$filesize`.

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

Now we do the same thing for the SPL. Offset `100000` is the SPL slot in this layout, so after `loady` receives the file into RAM, `sf update` copies it into place. As before, make sure you don't interrupt power while the update is running.

```shell
loady $loadaddr && sf update $loadaddr 100000 $filesize
```

Press <kbd>CTRL</kbd>+<kbd>T</kbd> and then <kbd>Y</kbd>

```log
[19:56:10.630] Send file with YMODEM
[19:56:10.630] Enter file name: 
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

## Prepare Installer USB

Next, we need to prepare our installation media.

1. Download the RISC-V Debian `mini.iso` (netboot installer). You can usually find the latest Trixie (testing) installer [here](https://deb.debian.org/debian/dists/trixie/main/installer-riscv64/current/images/netboot/mini.iso).
2. Flash this `mini.iso` to a standard USB flash drive. You can use the same tool as previously, e.g. **BalenaEtcher**.

*Note: This will erase all data on the USB drive.*

## Install Debian to NVMe

Now we bring it all together to run the installer.

1. Insert the **vendor-flashed microSD card** into the board.
2. Plug the **Debian installer USB drive** into the top one of the USB ports on the Waveshare board.
3. Ensure your NVMe drive is installed on the base board.
4. Power on the board while watching your `tio` serial console.

When U-Boot starts, allow it to boot automatically. It should detect the USB drive and launch the GRUB bootloader, which will transition into the familiar Debian text-based installer. Walk through the installation steps normally, keeping the following in mind:

* **Network:** Ensure the installer detects your Ethernet connection and configures DHCP successfully.
* **Partitioning:** When asked where to install the system, ensure you select your **NVMe drive**, *not* the SD card or the USB installer.

Let the installation finish. When the installer prompts you to reboot, power off the board and **remove the Debian installer USB drive**.

## Lobotomize SD Card

Here is where things get tricky. We still need the microSD card to hold our initial bootloader payload because the CM Lite has no onboard eMMC. However, if we leave the vendor OS partitions intact on that SD card, U-Boot might default to booting the old vendor system instead of our fresh NVMe Debian install.

We need to permanently erase the old OS rootfs and boot partitions from the SD card, while leaving the hidden U-Boot partitions untouched. I call this "lobotomizing" the SD card. I did this from macOS using `diskutil`.

Take the SD card out of the Mars CM Lite and plug it into your Mac. 

First, find your SD card's disk identifier:
```shell
diskutil list
```

Assuming your SD card is `disk4`, you want to wipe partitions 3 and 4 (which hold the vendor rootfs and boot files). **Be extremely careful here not to wipe your Mac's internal drive!**

```shell
sudo diskutil eraseVolume free none /dev/disk4s3
sudo diskutil eraseVolume free none /dev/disk4s4
```

Eject the SD card and put it back into the Mars CM Lite.

## Redirect U-Boot to NVMe

We are almost done. Power on the board and watch your serial console. Once again, **hit any key to interrupt the autoboot** process.

Now that the SD card is lobotomized, we need to explicitly tell U-Boot to scan the PCIe bus for our NVMe drive, find the Debian GRUB EFI bootloader we just installed, and execute it.

Run the following commands in the U-Boot console:

```shell
setenv bootcmd 'nvme scan; load nvme 0:1 ${kernel_addr_r} EFI/debian/grubriscv64.efi; bootefi ${kernel_addr_r} ${fdtcontroladdr}'
saveenv
```

The `saveenv` command writes this new default boot behavior into the U-Boot environment on the SD card, ensuring this change persists across reboots. 

## Wrapping Up

Once you've saved the environment, you can simply type `boot` (or power cycle the board). 

If everything went according to plan, the board will power on, load the initial SPL and U-Boot from the "dumb" SD card, immediately scan the PCIe bus, initialize the NVMe drive, hand off to GRUB, and boot you straight into a clean, mainline-like Debian environment!

Happy hacking on RISC-V!
