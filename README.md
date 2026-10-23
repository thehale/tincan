<!--
Copyright (c) 2026 Joseph Hale
SPDX-License-Identifier: MPL-2.0
-->

<div align="center">

# tincan

Pass messages between any two processes, on one machine or across your
devices.

<img src="./tincan.png" width="128" alt="Two green striped tin cans joined by a
curving string, like a toy tin-can telephone">

<!-- BADGES -->
[![License: MPL-2.0](https://badgen.net/github/license/thehale/tincan)](https://github.com/thehale/tincan/blob/main/LICENSE)
[![Sponsor thehale on GitHub](https://badgen.net/badge/icon/Sponsor/pink?icon=github&label)](https://github.com/sponsors/thehale)
[![Joseph Hale's software engineering blog](https://jhale.dev/badges/website.svg)](https://jhale.dev)
[![Follow Joseph Hale on LinkedIn](https://jhale.dev/badges/follow.svg)](https://www.linkedin.com/comm/mynetwork/discovery-see-all?usecase=PEOPLE_FOLLOWS&followMember=thehale)
</div>

## Install

tincan is one bash script for Linux, over socat, jq and openssl. Put
`src/tincan` on your PATH, and source `src/tincan.bash` for completion.

```bash
ln -s "$PWD/src/tincan" ~/.local/bin/tincan
```

## Quickstart

Listen under a name in one terminal, and tell it something from another.

```console
$ tincan --as bob listen
{"from":"alice","message":"hello, bob",…}
```

```bash
tincan --as alice tell bob "hello, bob"
```

Each message arrives as one JSON line, so anything that reads stdin can
listen: an agent, a script, a bot. A message left off the command line is read
whole from stdin.

## Across devices

Give each device a name its peers can dial, and serve it. The name defaults
to the device's hostname.

```bash
tincan init              # once: this device's key and certificate
tincan service install   # let paired devices reach this one, now and at login
```

`tincan service start|stop|status|uninstall` manage it after that, and
`tincan serve` runs the same server in the foreground.

Then pair each device with the other, from either side.

```console
laptop$ tincan pair desktop
code: 41dc-05b5-963f-2766-7832-f41b-cf11-eaf3
Does desktop show the same code? [y/N] y

desktop$ tincan pair laptop
code: 41dc-05b5-963f-2766-7832-f41b-cf11-eaf3
Does laptop show the same code? [y/N] y
```

```console
$ tincan --as alice whoami
alice@laptop
$ tincan list
alice@laptop
bob@desktop
$ tincan --as alice tell bob@desktop "hello from the laptop"
```

- **Only paired devices get in.** A device can tell or list only once the
  other side has paired with it too, and nothing can pose as a paired device.
  `tincan forget desktop` shuts it out at once.
- **The matching code is the check.** A different code means something sits
  between the two devices; answer no.
- **The receiver names the sending device.** `host` comes from the certificate
  it verified, not from the message.
- **Any network.** A name is anything that resolves to the device: a
  hostname, a Tailscale name, an IP.

## License

Copyright (c) 2026 Joseph Hale, All Rights Reserved

Provided under the terms of the [Mozilla Public License, version 2.0](./LICENSE)

<details>

<summary><b>What does the MPL-2.0 license allow/require?</b></summary>

### TL;DR

You can use files from this project in both open source and proprietary
applications, provided you include the above attribution. However, if
you modify any code in this project, or copy blocks of it into your own
code, you must publicly share the resulting files (note, not your whole
program) under the MPL-2.0. The best way to do this is via a Pull
Request back into this project.

If you have any other questions, you may also find Mozilla's [official
FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/) for the MPL-2.0 license
insightful.

If you dislike this license, you can contact me about negotiating a paid
contract with different terms.

**Disclaimer:** This TL;DR is just a summary. All legal questions
regarding usage of this project must be handled according to the
official terms specified in the `LICENSE` file.

### Why the MPL-2.0 license?

I believe that an open-source software license should ensure that code
can be used everywhere.

Strict copyleft licenses, like the GPL family of licenses, fail to
fulfill that vision because they only permit code to be used in other
GPL-licensed projects. Permissive licenses, like the MIT and Apache
licenses, allow code to be used everywhere but fail to prevent
proprietary or GPL-licensed projects from limiting access to any
improvements they make.

In contrast, the MPL-2.0 license allows code to be used in any software
project, while ensuring that any improvements remain available for
everyone.

</details>
