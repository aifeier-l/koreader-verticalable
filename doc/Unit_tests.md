# Unit Tests

Unit tests are written for [busted](https://lunarmodules.github.io/busted/)
(a version is automatically provided by the build system), and executed in
parallel with the meson test runner.

You can run them with `./kodev test`, examples:

- to run all tests (frontend & base): `./kodev test`
- frontend only: `./kodev test front`
- to run one specific base test: `./kodev test base util`
- to list available tests: `./kodev test -l`

Check the output of `./kodev test -h` for the full usage.

## Nix Flakes Development Environment

A `flake.nix` file is provided at the project root for setting up a development environment with all required dependencies.

### Entering the dev shell

```bash
nix develop
```

This provides a shell with:
- Build toolchain: gcc, cmake, ninja, meson, autoconf, automake, libtool
- Libraries: SDL3, libGL, libusb1, ImageMagick
- Lua: LuaJIT, luarocks, busted (test framework)
- Code quality tools: luacheck, shellcheck, shfmt

### Available aliases

Once in the dev shell, the following aliases are available:

```bash
koreader-build          # Build emulator (make -C base)
koreader-run            # Run emulator (make -C base run)
koreader-test-base      # Run base/ unit tests
koreader-test-front     # Run frontend unit tests
koreader-test-vertical  # Run vertical text screenshot tests
koreader-create-epub    # Create test EPUB fixture
```

### Setting up Lua test dependencies

Before running tests, install Lua test rocks into the KOReader build tree:

```bash
nix develop .#setup-luarocks
```

This installs busted and dependencies into `base/build/*/luarocks/`. After setup, set the following environment variables before running busted directly:

```bash
export LUA_PATH="/path/to/base/build/*/luarocks/share/lua/5.1/?.lua;/path/to/base/build/*/luarocks/share/lua/5.1/?/init.lua;;"
export LUA_CPATH="/path/to/base/build/*/luarocks/lib/lua/5.1/?.so;;"
```

### Running tests outside nix shell

For running tests without entering the nix shell, copy the required Lua modules from the nix store:

```bash
# Copy busted
cp -r /nix/store/*-luajit2.1-busted-*/share/lua/5.1/* base/spec/rocks/share/lua/5.1/

# Copy luasystem
cp /nix/store/*-luajit2.1-luasystem-*/lib/lua/5.1/system/core.so base/spec/rocks/lib/lua/5.1/system.so

# Copy luafilesystem
cp /nix/store/*-luajit2.1-luafilesystem-*/lib/lua/5.1/lfs.so base/spec/rocks/lib/lua/5.1/

# Make files writable
chmod -R +w base/spec/rocks
```

Then run tests from the base directory:
```bash
cd base
./test-runner/runtests spec/unit
```

### Headless testing

For CI or headless environments, set the SDL video driver to dummy:

```bash
SDL_VIDEODRIVER=dummy ./kodev test
```
