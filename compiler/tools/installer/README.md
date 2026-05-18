# Emerald Installer

Cross-platform user-local installer for Emerald.

The installer downloads the latest Emerald release by default, extracts the release archive, installs `emeraldc` plus `stdlib` into the user-local Emerald directory, and configures `EMERALD_HOME`, `EMERALD_STDLIB`, and PATH automatically.

Running the installer without arguments starts the graphical browser UI.

## Install locations

Windows:

```text
%LOCALAPPDATA%\Emerald\bin\emeraldc.exe
%LOCALAPPDATA%\Emerald\stdlib
```

Linux:

```text
$HOME/.local/Emerald/bin/emeraldc
$HOME/.local/Emerald/stdlib
```

## Build

From `compiler/tools/installer`:

```fish
shards build --release
```

## Graphical installer

From `compiler/tools/installer`:

```fish
./bin/emerald-installer
```

Or explicitly:

```fish
./bin/emerald-installer ui
```

The UI opens in your browser with a local-only server and a dark Emerald design. It supports online install, offline payload install, doctor, uninstall, and environment setup.

## Install latest Emerald


The default install command downloads:

```text
https://emerald-lang.eu/install/latest
```

The endpoint must return `Emerald-Latest.zip`.

Run:

```fish
./bin/emerald-installer install --force
```

Environment setup is enabled by default. Use `--no-env` to skip it.

Use a custom URL for testing:

```fish
./bin/emerald-installer install --url https://emerald-lang.eu/install/latest --force
```

## Release archive layout

`Emerald-Latest.zip` must contain:

```text
emeraldc
stdlib/
```

This layout is also accepted:

```text
Emerald-Latest/
  emeraldc
  stdlib/
```

This payload layout remains supported for offline builds:

```text
payload/
  bin/
    emeraldc
  stdlib/
    ...
```

## Install from a local payload

From `compiler/tools/installer`:

```fish
./bin/emerald-installer install --payload payload --force
```

## Install from the repository checkout

From `compiler/tools/installer`:

```fish
./bin/emerald-installer install --payload ../../.. --force
```

The repository root must contain:

```text
compiler/bin/emeraldc
stdlib/
```

## Check installation

```fish
./bin/emerald-installer doctor
```

Check a local payload too:

```fish
./bin/emerald-installer doctor --payload ../../..
```

## Print bin path

```fish
./bin/emerald-installer print-path
```

## Environment setup

The installer configures user-level environment settings by default:

```text
EMERALD_HOME=<install prefix>
EMERALD_STDLIB=<install prefix>/stdlib
PATH includes <install prefix>/bin
```

Linux:
- writes `~/.config/fish/conf.d/emerald.fish`
- writes a managed Emerald block to `~/.profile`

Windows:
- writes user environment variables with PowerShell
- updates user PATH

Use `--no-env` to disable environment changes.


## Uninstall

```fish
./bin/emerald-installer uninstall --yes
```

## Commands

```text
emerald-installer ui [--url <url>]
emerald-installer install [--url <url>] [--prefix <path>] [--force] [--no-env]
emerald-installer install --payload <path> [--prefix <path>] [--force] [--no-env]
emerald-installer uninstall [--prefix <path>] --yes
emerald-installer doctor [--payload <path>] [--prefix <path>] [--url <url>]
emerald-installer print-path [--prefix <path>]
emerald-installer version
emerald-installer help
```
