---
title: "Raspberry Pi 5: A Love‑Hate Relationship"
date: 2025-03-10
draft: true
summary: |
  The Raspberry Pi 5 delivers long-awaited hardware features like PCIe and NVMe support, but the software ecosystem is lagging behind. I'm both thrilled and frustrated by my experience - and why Pi 5 isn't quite ready for serious homelab work without some serious elbow grease.
tags: ["hardware", "homelab"]
authors:
  - "shanduur"
---

## The Experiment Begins

When the Raspberry Pi 5 was announced with native PCIe support, my brain immediately went into homelab mode: *Could I finally build a tiny, quiet, power-efficient Kubernetes node with real NVMe storage?* Maybe even replace one of my noisy x86 NUCs?

I bought the board, the NVMe HAT, and a bunch of accessories. My goal was to run Talos Linux, my current favorite OS for containerized workloads, and get this thing integrated into my k3s cluster.

On paper, it seemed doable.

Spoiler: it *was*, but only barely - and it still isn't stable.

This post walks through everything I've learned and why I'm left with equal parts admiration and frustration. The Pi 5 is a beast of a little board. But it's being held back by the same old problem: the Foundation's closed boot ecosystem and patchy OS support.

## The Hardware Is the Best It's Ever Been

Let's start on a positive note: this board absolutely rips for its size and price.

### PCIe and NVMe: Finally, Freedom from SD Cards

The single-lane PCIe 2.0 interface opens doors. I installed the official Raspberry Pi NVMe HAT and dropped in a Samsung 980 NVMe drive. No surprise - it works, and it works well. Benchmarks hit around 350–400 MB/s, which is more than enough for most lightweight storage tasks.

No more worrying about SD card corruption. No more babysitting tiny storage volumes. You can run a real file system (like ext4 or even btrfs if you're brave) and not feel like you're pushing the limits of what's safe on an SBC.

### Improved CPU, RAM Options, and Video Output

The Pi 5 is genuinely snappy - running an A76-based quad-core CPU at 2.4GHz. With 8GB RAM and dual 4K display support, it's almost laughably overpowered compared to where Raspberry Pis started.

I ran Pi OS and then Ubuntu just for fun - desktop usage is surprisingly tolerable, though still not my main use case.

## But Then... You Try to Boot Something Else

Here's where the love turns into frustration.

My goal was to install **Talos Linux**, a Kubernetes-native, immutable OS. It works great on x86, and I've run it on Pi 4 before (with effort). On Pi 5, I hit the wall hard.

### The Bootloader Is Still a Black Box

The Raspberry Pi bootloader is proprietary and baked into the board's firmware. Unlike U-Boot or coreboot on other platforms, there's no official way to replace it with something that gives full control over boot order, devices, or OS support.

By default, it expects `start4.elf`, `config.txt`, and `cmdline.txt` in an MSDOS-formatted `/boot` partition. This boot process is completely different from how literally every other board in the ARM SBC world does it.

That's a problem. Especially for UEFI and modern OSes.

### The Death of UEFI on Pi 5

For a while, the [`rpi5-uefi`](https://github.com/worproject/rpi5-uefi) project had promise. Maintainers reverse-engineered enough of the Pi's startup sequence to run EDK2 and boot into UEFI mode. This enabled dual-booting Windows on ARM (WOA), Linux, and other OSes that expect a standard UEFI interface.

But that project is now archived.

Why? Several reasons:

- **Constant firmware breakage**: Pi firmware updates frequently broke compatibility.
- **Lack of documentation/support**: Raspberry Pi Ltd. offered no help, no specs, and no stability guarantees.
- **Missing hardware support in UEFI**: Things like USB, PCIe initialization, and power control were all unstable or missing.

Ultimately, it became a maintenance nightmare. One update to the official bootloader and the entire UEFI stack could fail. So the community moved on.

Today, UEFI on Pi 5 is basically dead - and that's a massive loss for people wanting to run ARM OSes the “right” way.

## Talos on Pi 5: Built on Hope (and Hacks)

I'm a huge fan of [Talos Linux](https://www.talos.dev). It's an immutable OS purpose-built for Kubernetes. It runs as close to metal as possible, with a minimal surface area and no traditional package manager or SSH. Just an API. It's perfect for running secure, low-maintenance clusters.

Naturally, I wanted Talos on my Pi 5 node. There's even a dedicated community repo: [`talos-on-pi5`](https://github.com/talos-on-pi5).

### Getting It to Work

To boot Talos on Pi 5, here's what I had to do:

- Manually compile U-Boot with Pi 5 patches.
- Use a custom device tree overlay to enable Ethernet and PCIe.
- Boot from SD card just to get the U-Boot handoff right.
- Manually set up kernel parameters via `config.txt` because UEFI isn't supported.

Even after all that, networking was flaky, USB peripherals weren't always detected, and updates broke things unpredictably.

There's a discussion on the [SideroLabs GitHub](https://github.com/siderolabs/talos/issues/7978) where developers explain why there's no official Talos support yet:

> “We won't support Pi 5 until either U-Boot upstream gains full support or the Raspberry Pi Foundation releases a bootloader that behaves more like UEFI/U-Boot.”

Fair enough. Maintaining support for a rapidly changing, poorly documented platform is a recipe for burnout.

## Other Pain Points

### USB Power and PCIe Weirdness

Some NVMe drives don't power on correctly. Others draw too much current and crash the board unless you provide separate power. I had to switch power adapters and cables more than once to get consistent behavior.

And don't even think about attaching a PCIe riser and trying to use other devices. The bus is finicky. You'll need a powered hub and maybe a kernel overlay or two.

### Ethernet + USB Don't Always Work

Even in fully booted Talos or Linux, the onboard Ethernet sometimes won't come up. You'll need patched device trees and overlays from forks like [`siderolabs/sbc-raspberrypi`](https://github.com/siderolabs/sbc-raspberrypi/issues/23).

Talos boots. That's great. But without networking, it's not a cluster node - it's a glowing brick.

## So... Do I Regret Buying It?

Not exactly. I'm glad I got it. I've learned a lot, and I enjoy hacking around hardware that's on the bleeding edge.

But I can't recommend it yet for homelabbers who just want things to work.

You'll spend more time troubleshooting overlays, re-flashing firmware, and tweaking boot configs than actually running workloads. If you're into that - go for it. It's a great platform for hacking.

But if you're looking for a low-maintenance, high-uptime ARM node for Kubernetes or storage, look elsewhere. Something like the Orange Pi 5, Radxa ROCK 5B, or even a used Intel NUC will save you a lot of pain.

## What Needs to Happen

Here's what I think the Pi Foundation and broader community need to prioritize:

- **Open bootloader**: or at least better documentation and configuration options.
- **Upstream U-Boot support**: so we don't rely on forks and hacks.
- **Mainline kernel overlays**: Ethernet, PCIe, USB - all should work without patching.
- **Community documentation hub**: Right now everything's scattered in GitHub issues and Discord logs.

Until then, Pi 5 will remain more of a tinker board than a platform for real infrastructure.

## TL;DR

| ❤️ What's Awesome                 | 💔 What's Annoying                          |
|-------------------------------|---------------------------------------------|
| PCIe support & NVMe boot      | Bootloader is closed, undocumented          |
| 8GB RAM + fast CPU            | No official UEFI support                    |
| Community Talos efforts       | Ethernet/USB require patching               |
| NVMe storage is fast & stable | Boot process is fragile and non-standard    |

## Useful Links

- [rpi5-uefi (archived)](https://github.com/worproject/rpi5-uefi)
- [talos-on-pi5](https://github.com/talos-on-pi5)
- [Talos issue #7978](https://github.com/siderolabs/talos/issues/7978)
- [siderolabs/sbc-raspberrypi issue #23](https://github.com/siderolabs/sbc-raspberrypi/issues/23)

## Closing Thoughts

The Raspberry Pi 5 shows a lot of promise. The hardware is finally catching up to what tinkerers and homelabbers want: high-speed storage, more RAM, and real I/O.

But until the software ecosystem stabilizes - and Raspberry Pi Ltd. either opens up the bootloader or works *with* the community to provide proper support - the Pi 5 will stay in this weird limbo: too good to ignore, too broken to rely on.

Still... I don't regret the challenge.

Got your own Pi 5 story? Reach out - I'd love to hear it.
