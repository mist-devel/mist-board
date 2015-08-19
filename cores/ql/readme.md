QL for MIST
===========

This is an implementation of the Sinclair QL for the MIST board.

It's based on the TG68K CPU core and the t48 core for the IPC.

Features:
- tg68k
  - 128k or 640k
  - roughly twice the original speed
- zx8301
  - all video modes incl. blinking
  - scan doubler for VGA output (can be disabled)
    - optional scan line effect
- zx8302
  - IPC based on t48 using the original firmware
    - audio
    - keyboard
    - PC keyboard shortcuts (backspace, ...)
    - joysticks
  - interrupt handling
  - microdrive emulation
    - qlay format
- qimi mouse
