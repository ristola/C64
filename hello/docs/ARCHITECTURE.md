# SHACKMATE Cartridge — Software Architecture

Current, working state of the `hello/` cartridge project: a multi-bank EasyFlash-format C64 cartridge with a BASIC+ language extension, built and tested in VICE.

Two build targets share the same source:

- **Plain PRG** (`hello.asm`, `SYS 2064`): splash screen + permanent F1-menu takeover. The original always-on demo.
- **8K autostart cartridge** (`hello_cart.asm` → `build/hello.crt`): boots to a normal `READY.` prompt with an F1 hotkey menu layered on top. This is where all the interesting work has gone, and what the rest of this document describes.
- **13-bank EasyFlash cartridge** (`bank_driver.asm` + `build_cart.sh` → `build/hello.crt`): a newer, separate build that extends the single 8K cartridge into a full BASIC+ language extension across 13 EasyFlash banks. This is the active area of development.

## Boot flow

EasyFlash cartridges always boot in **Ultimax mode** (`EXROM` deasserted-high / `GAME` asserted-low, per `cartconv`'s own reporting of the built `.crt`), which maps ROMH — not the KERNAL — at `$E000-$FFFF`. That's what puts the cartridge's own reset vector in control before the KERNAL has run any of its own init.

`cart_start` (Bank 0) therefore has to replicate the KERNAL's own boot sequence itself, in this order:

1. `SEI` / `CLD`, set up the stack.
2. `IOINIT` → `RAMTAS` → `RESTOR` → `CINT` (the same calls the real KERNAL reset vector would make).
3. Install `irq_hook` on the jiffy IRQ vector (`$0314`/`$0315`).
4. Flash the splash banner for about a second.
5. Switch out of Ultimax mode into 8K mode (`EASYFLASH_CONTROL = EASYFLASH_8K_MODE`, see below) — BASIC ROM and KERNAL become visible again, only `$8000-$9FFF` stays cartridge ROM.
6. `JMP ($A000)` — the real, indirect BASIC cold-start vector. This lands at a normal `READY.` prompt, not a takeover.

## F1 hotkey menu

`irq_hook` (resident, Bank 0) reads the keyboard matrix directly (not `GETIN`), so it never steals keystrokes destined for BASIC. On a fresh F1 press it waits for physical key-up *before* doing anything else — the default IRQ handler's own keyboard scan would otherwise buffer a stray F1 keypress that the menu's first `GETIN` call could misread as "open Help".

Once clear, it `CLI`s and calls `menu_open` (Bank 0) reentrantly: nested jiffy IRQs keep BASIC's keyboard buffer and clock running while the menu blocks on `GETIN`. `zp_save`/`zp_restore` and `save_screen`/`restore_screen` bracket the call so neither the menu's zero-page scratch nor its screen output leak into whatever BASIC program was running. RUN/STOP (mapped to host **Escape** in VICE's default keymap) exits the menu back to BASIC exactly where F1 interrupted it.

## Multi-bank architecture

`build_cart.sh` assembles `bank_driver.asm` once per bank (`-DBANKNUM=n`, 13 banks: 0–12). Each bank's 8K ROML window (`$8000-$9FFF`) is laid out as:

- `$8000-$97FF`: bank-specific content (up to ~6KB)
- `$9800-$9FFF`: the **resident kernel** (`resident.asm`) — assembled byte-identically into every single bank, so it works no matter which bank happens to be switched in when it's needed.

Only Bank 0 has real ROMH content (`romh_boot.asm`, 8K, holds the hardware reset vector required for Ultimax boot). Banks 1–12 have no ROMH — `cartconv` correctly omits those chunks as dead space rather than padding to EasyFlash's full 64-bank capacity.

### The resident kernel

Two things *must* be reachable regardless of which bank is currently switched in, and everything else in `resident.asm` exists to support them:

- `irq_hook`, wired to `$0314`/`$0315` — the F1 menu has to work no matter what a previous BASIC+ command left switched in.
- The BASIC-extension dispatch vectors (`$0304`-`$030B`) — tokenizing/detokenizing/executing/evaluating can happen at any time.

**Cross-bank calling** (`bank_call`/`bank_return`/`bank_return_basic`/`bank_commit`): switches to a target bank, runs code there, and switches back — the *old* bank is pushed on the CPU stack (not a side variable), which makes it correctly reentrant if an IRQ (e.g. F1) fires mid-call and itself needs a nested bank switch. The actual `EASYFLASH_BANK` ($DE00) write happens via a 7-byte trampoline copied into RAM at `$0380` (`ram_bank_switch`) — writing that register from ROM code living inside the very $8000-$9FFF window being switched crashes every time (confirmed empirically), so the write has to execute from RAM instead.

**Fixed-slot jump table** (`slots.asm`, `$8010`-`$80FF`, 60 slots × 4 bytes): every bank reserves the same slot range at the same addresses; a bank only fills in the slots it implements, each holding a plain `JMP <real address>`. `resident.asm`'s dispatch tables store `(bank, slot)` pairs — never a raw label — since a slot address is the only thing guaranteed valid before that bank is even switched in.

### BASIC+ language extension

New keyword tokens use a 2-byte escape rather than direct single-byte tokens, since the full command roadmap needs far more than BASIC V2's ~51 free single-byte token slots (`$CC`-`$FE`):

- `EXTTOK` (`$CE`) + a 1-based index byte, for **statements**.
- `EXTFUNCTOK` (`$CF`) + a 1-based index byte, for **functions** (dispatched through `IEVAL`, `$030A`/`$030B`). Statements and functions use *independent* counters/tables — sharing one counter across both caused a real bug (a function reading one byte past its own table).

`CLS` and the retired `HEX` command still use the original direct single-byte token (`$CC`) from the project's earliest phase.

Real BASIC string results (`HEX$`/`DEC$`) use BASIC ROM's own string-descriptor convention: `$B47D` allocates N bytes (returns a data pointer in `$62`/`$63`), the caller writes the bytes, then `$B4CA` finalizes it (sets `VALTYP=$FF` and builds the descriptor) — the same mechanism BASIC's own `CHR$` uses internally. `EvaluateFunction` was extended with a `func_is_string` flag (cleared before every call) so it can tell a real string result apart from the default numeric `func_result_hi`/`lo` + `$B391` (FAC1) path, without touching any existing numeric function.

### Bank purposes (current)

| Bank | Category | Status |
|---|---|---|
| 0 | Boot / F1 menu / graphics demo / sprite editor | Working |
| 1 | BASIC+ core (tokenizer/dispatcher engine + `CLS`/`HEX`) | Working |
| 2 | GRAPHICS (`HIRES`/`MULTI`/`TEXT`/`PLOT`/`LINE`/`BOX`/`CIRCLE`/`PAINT`) | Stub |
| 3 | SPRITES (`SPRITE`/`SPRITEON`/`SPRITEOFF`/`SPRITECOLOR`) | Stub |
| 4 | INPUT (`JOY`/`JOYUP`/`JOYDOWN`/`JOYLEFT`/`JOYRIGHT`/`JOYFIRE`) | Stub |
| 5 | MEMORY (`DOKE`/`DUMP`/`FILL`/`MOVE`/`DEEK`/`FIND` stubs; **`HEX$`/`DEC$` real**) | Partial |
| 6 | CARTRIDGE non-flash (`CARTINFO`/`BANK`/`BANKS`) | Working |
| 7 | Inline-ASM engine | Not started |
| 8 | SOUND (`SOUND`/`VOLUME`/`WAVE`/`ADSR`/`FILTER`) | Stub |
| 9 | CARTRIDGE-flash (`FLASHERASE`/`FLASHLOAD`/`FLASHVERIFY`) | Deliberately stubbed — needs a separately-verified EAPI erase/write sequence |
| 10 | DISK (`DIR`/`DEVICE`/`CD`/`DELETE`/`RENAME`/`DLOAD`/`DSAVE`) | Working, KERNAL-verified live in VICE |
| 11–12 | Reserved for a later SERIAL/DEVELOPMENT plan | Unused |

## RAM addressing (current EasyFlash build)

### Zero page

Only `$02` and `$FB`-`$FE` are genuinely free on a stock C64 — everything else is live BASIC/KERNAL interpreter state. This project's own scratch is packed into the otherwise-"free-looking" `$02`-`$38` range, which really does collide with real BASIC/KERNAL variables (`RESHO`, `TXTTAB`/`VARTAB`/`ARYTAB`/`STREND`/`FRETOP`/`MEMSIZ`, etc.) — see `docs` note below.

| Range | Owner |
|---|---|
| `$02`-`$08` | `common.asm` |
| `$10`-`$17` | `ultimate_sdk.asm` (Ultimate 64/1541U Command Interface SDK — untested, no way to verify against real hardware from an emulator) |
| `$18`-`$28` | `features.asm` |
| `$2B`-`$38` | `bitmap.asm` |

`hello_cart.asm`'s `zp_save`/`zp_restore` protects the whole `$02`-`$38` span around any F1-menu invocation, so the menu's own use of this range never corrupts whatever BASIC program was running. New scratch that doesn't need indirect (`,X`/`,Y`/`($nn),Y`) addressing goes in plain RAM instead — zero page has essentially no room left.

### Plain RAM (`slots.asm`)

| Address | Name | Purpose |
|---|---|---|
| `$0373` | `f1_state` | `irq_hook`'s F1 debounce latch |
| `$0374` | `basic_ext_countdown` | Jiffies until `install_basic_ext` runs |
| `$0375` | `cur_bank` | RAM shadow of the selected EasyFlash bank |
| `$0376` | `bank_tmp` | `bank_call`/`bank_return` scratch |
| `$0377`-`$0378` | `call_ptr` | `bank_call`'s JMP target (2 bytes) |
| `$0379` | `ext_count` | `ConvertToTokens`' 1-based `ExtTab` match counter |
| `$037A`-`$037B` | `func_result_hi`/`lo` | Extended-function numeric result |
| `$037C` | `resting_bank` | The bank BASIC was resting on just before the current `bank_call` (what `CARTINFO`/`BANKS` actually read) |
| `$0380`-`$0386` | `ram_bank_switch` | 7-byte trampoline (`LDA bank_tmp / STA $DE00 / RTS`), copied into RAM once at boot |
| `$0387`-`$0388` | `pdw_lo`/`pdw_hi` | `print_decimal_word`'s 16-bit working value |
| `$0389` | `pdw_count` | Current digit's subtraction count |
| `$038A` | `pdw_started` | 0 until the first non-suppressed digit prints |
| `$038B` | `disk_device` | Default device number for DISK commands (boot default: 8) |
| `$038C`-`$038D` | `disk_namelen`/`disk_namelen2` | RENAME's old/new name lengths |
| `$038E` | `func_is_string` | `EvaluateFunction`'s numeric-vs-string result flag |
| `$038F` | `dtb_outpos` | `DEC$`'s digit-buffer write index |
| `$0390`-`$0394` | `dec_buf` | `DEC$`'s digit scratch (up to 5 bytes, 65535 max) |
| `$033C`+ (55 bytes) | `zp_save_buf` | F1 menu's zero-page save area |
| `$C000`-`$C3FF` | `scr_save_buf` | F1 menu's screen save buffer |
| `$C400`-`$C7FF` | `col_save_buf` | F1 menu's color RAM save buffer |
| `$C800`-`$CBFF` | `misc_save_buf` | F1 menu's misc state (only 3 bytes actually used: border/background/text color) |
| `$C900`-`$C91F` | `filename_buf` | DISK commands' filename argument (16-byte CBM DOS limit) |
| `$C920`-`$C93F` | `filename2_buf` | RENAME's second (new) filename |
| `$C940`-`$CFFF` | `dir_buffer` | `DIR`'s `"$"` directory-listing load target (1728 bytes) |

### EasyFlash hardware registers (current build)

| Address | Name | Notes |
|---|---|---|
| `$DE00` | `EASYFLASH_BANK` | Selected ROM bank |
| `$DE02` | `EASYFLASH_CONTROL` | Mode control; `$06` = `MEMCTRL\|EXROM` (8K mode, BASIC ROM stays visible) |

These addresses are specific to EasyFlash-format cartridges (hardware ID 32) and **do not carry over** to the custom hardware platform described in `HARDWARE_PLATFORM.md` — see that document for the new register map and why it deliberately avoids this address range.

## Testing

Testing is done by the user in VICE (via VS64's F5 launch, or a standalone `/Applications/VICE (C64).app` wrapper pointing at the Homebrew `x64sc`). Development sandboxes without display access verify builds by clean assembly only, and — when needed — by statically disassembling VICE's own bundled BASIC/KERNAL ROM images (`$(brew --prefix vice)/share/vice/C64/basic-901226-01.bin`, `kernal-901227-03.bin`) rather than trusting recalled ROM knowledge. Behavior is confirmed by the user reporting back, often with screenshots.

## Build

```sh
cd hello
./build_cart.sh        # 13-bank EasyFlash build -> ../build/hello.crt
```

or, for the single-bank cartridge:

```sh
acme -f plain -o ../build/hello_cart.bin hello_cart.asm
cartconv -t normal -i ../build/hello_cart.bin -o ../build/hello.crt -l 0x8000 -n HELLO -p -q
```
