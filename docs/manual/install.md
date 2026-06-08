# Installation and Build

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

This document states the prerequisites for building and running the system, the build steps, and how to confirm that the build succeeded and the node boots. It assumes the reader has read [overview.md](overview.md) and uses the terms defined in the [glossary](glossary.md).

For a guided path from a clone to a first authenticated subscriber, see [quickstart.md](quickstart.md).

## 1. Prerequisites

The following items are needed to build and run the system.

| Prerequisite | Version | Required for | Notes |
| --- | --- | --- | --- |
| [Erlang/OTP](glossary.md) | 29 or later | Build and run | The minimum OTP version is `29`, set by `minimum_otp_vsn` in `rebar.config`. |
| [rebar3](glossary.md) | Any recent release | Build, test, release | The build, test, and release tool. |
| [MongoDB](glossary.md) | — | The MongoDB backend only | **Optional.** The default [ETS](glossary.md) backend needs no external database. |

> [!IMPORTANT]
> The default data backend is in-memory [ETS](glossary.md). A node built and started with the shipped configuration needs no database. [MongoDB](glossary.md) `may` be installed and selected later in place of ETS; it is not needed to build, boot, or complete the [quickstart](quickstart.md).

The system `shall` be built and run on Erlang/OTP 29 or later. Earlier OTP releases are not supported, because the code uses OTP-29 features (for example the native-record syntax in `udr_crypto`).

## 2. Obtain the source

The source is a [rebar3](glossary.md) umbrella project. Obtain a working copy with the project's normal version-control method (for example a `git clone`), then work from the resulting directory.

## 3. Build

> [!NOTE]
> The commands below are run from the project root — the directory that contains `rebar.config`.

To compile every umbrella application:

```sh
rebar3 compile
```

### Verify (build)

The build is successful when `rebar3 compile` exits with status `0` and prints no error. Confirm the exit status:

```sh
rebar3 compile; echo "exit=$?"
```

The expected final line is:

```
exit=0
```

## 4. Run

The node can be started two ways. The development shell is the path used by the [quickstart](quickstart.md).

### 4.1 Development shell

To start an interactive node with all listeners running:

```sh
rebar3 shell
```

This starts the [S6a](glossary.md) Diameter listener, the [SBI](glossary.md) listener, and the provisioning listener, and applies `config/sys.config` and `config/vm.args`.

### 4.2 Release

A [relx](glossary.md) release is configured in `rebar.config` under the `relx` section, as release `udr` version `0.1.0`. It bundles `config/sys.config` and `config/vm.args`.

To assemble and run a development-mode release:

```sh
rebar3 release
_build/default/rel/udr/bin/udr console
```

> [!NOTE]
> The default release `mode` is `dev`. A production release is built with the `prod` profile (`rebar3 as prod release`), which assembles the release in `prod` mode. Production tuning is covered in the [deploy runbook](operations/deploy.md) (`RUN-DEPLOY-001`).

### Verify (boot)

The node has booted when the Erlang shell prompt appears and the three listeners are bound. With the default `config/sys.config`, the listeners are:

| Interface | Application | Default address | Default port | Transport |
| --- | --- | --- | --- | --- |
| [S6a](glossary.md) Diameter | `udr_diameter` | `127.0.0.1` | `3868` | TCP |
| [SBI](glossary.md) (Nudr-DR) | `udr_sbi` | `127.0.0.1` | `8080` | HTTP |
| Provisioning | `udr_provision` | `127.0.0.1` | `8090` | HTTP |

From the running Erlang shell, confirm that the umbrella applications are running:

```erlang
[ A || {A,_,_} <- application:which_applications(),
       lists:member(A, [udr, udr_hss, udr_diameter, udr_sbi, udr_provision]) ].
```

The expected result lists all five applications (order may vary):

```erlang
[udr_provision,udr_sbi,udr_diameter,udr_hss,udr]
```

To confirm the SBI listener is accepting TCP connections, from another terminal:

```sh
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/nudr-dr/v1/subscription-data/imsi-001010000000001/provisioned-data/am-data
```

A reachable-but-empty node returns `404` for an unprovisioned subscriber, which confirms the listener is up:

```
404
```

> [!NOTE]
> A `404` here means the listener answered and no such subscriber exists yet — exactly the expected state on a fresh node. Provisioning a subscriber is the subject of [quickstart.md](quickstart.md).

## 5. Next steps

- To provision a subscriber and exercise authentication, see [quickstart.md](quickstart.md).
- For backend selection, identities, and listener addresses, see the [configuration references](configuration/README.md).
