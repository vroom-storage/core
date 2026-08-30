# Vroom Storage

> Patches to [UltiHash](https://github.com/UltiHash/core) aiming to keep
> the project alive.

## Overview

This repository is a fork of
[UltiHash Core](https://github.com/UltiHash/core). It extends the
upstream codebase with additional patches and modifications maintained
independently.

The fork is **not intended to contribute patches upstream**. Changes
made here are maintained separately and licensed under different terms
than the original project.

---

## Building

### Requirements

```
apt install -y cmake clang-18 ninja libpq-dev postgresql liblmdb++-dev \
    protobuf-compiler-grpc libprotoc-dev libgrpc++-dev libgrpc-dev
```

Also install:

- Boost 1.88 or newer

### Building

```
git submodule update --init --recursive && \
cmake --preset default &&
cmake --build build
```

---

## Licensing

This repository contains code under **two distinct licenses**,
separated by a git tag: `ultihash-apache-2.0-license`

### Apache License 2.0 — upstream code

All code up to and including tag [`ultihash-apache-2.0-license`] originates from
[UltiHash Core](https://github.com/UltiHash/core) and is licensed under the
**Apache License 2.0**.

See [`LICENSE-APACHE`](./LICENSE-APACHE) for the full license text.

### GNU General Public License v3.0 — fork additions

All modifications, additions, and new files introduced **after** tag
`ultihash-apache-2.0-license` are licensed under the **GNU General Public
License v3.0**.

See [`LICENSE-GPL`](./LICENSE-GPL) for the full license text.

Copyright (c) 2026 Stefan Jank

---

### License Boundary

The tag `ultihash-apache-2.0-license` marks the exact point at which the license
boundary occurs:

```
[upstream history] ──── [ultihash-apache-2.0-license] ──── [GPL v3 patches]
                         Apache 2.0 ↑                       ↑ GPL v3
```

To inspect the boundary:

```bash
# Show the tag
git show ultihash-apache-2.0-license

# List all commits after the tag (GPL v3 territory)
git log ultihash-apache-2.0-license..HEAD --oneline

# List all commits up to and including the tag (Apache 2.0 territory)
git log ultihash-apache-2.0-license --oneline
```

---

### File-Level Copyright Headers

New files introduced after `ultihash-apache-2.0-license` carry the following
header:

```
// Copyright (c) 2026 Stefan Jank
// SPDX-License-Identifier: GPL-3.0-only
```

Files from the upstream codebase that were modified after
`ultihash-apache-2.0-license` carry both copyright notices:

```
// Copyright (c) [UPSTREAM YEAR] [UPSTREAM AUTHORS]
// Copyright (c) 2026 Stefan Jank — modifications
// SPDX-License-Identifier: GPL-3.0-only
```

---

## Upstream Compatibility

The GPL v3 is compatible with the Apache License 2.0 in the following
sense:

- The upstream Apache 2.0 code can be combined with GPL v3 additions;
  the combined work is governed by GPL v3.
- Code introduced after `ultihash-apache-2.0-license` **cannot** be incorporated
  into the upstream Apache 2.0 project or any other Apache 2.0-licensed
  codebase without relicensing.

This is an intentional design decision to maintain clear separation of
intellectual property.

---

## Syncing with Upstream

This fork does not track or synchronize with the upstream repository.
The codebase diverges intentionally from upstream as of tag
`ultihash-apache-2.0-license`.
