; at28w - Write to AT28 EEPROM
;
; Write data from the active block device into an eeprom device geared as
; regular memory. Implements write polling to know when the next byte can be
; written and verifies that data is written properly.
;
; Optionally receives a word argument that specifies the number or bytes to
; write. If unspecified, will write until max bytes (0x2000) is reached or EOF
; is reached on the block device.

; *** Requirements ***
; blkGetB
;
; *** Includes ***

.inc "user.h"
.inc "err.h"
.equ	AT28W_RAMSTART	USER_RAMSTART

jp	at28wMain

.inc "core.asm"
.inc "lib/util.asm"
.inc "lib/parse.asm"
.inc "lib/args.asm"
.inc "at28w/main.asm"
USER_RAMSTART:
