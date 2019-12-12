; *** Requirements ***
; BLOCKDEV_SIZE
; FS_HANDLE_SIZE
; _blkGetB
; _blkPutB
; _blkSeek
; _blkTell
; fsFindFN
; fsOpen
; fsGetB
; fsPutB
; fsSetSize
; printstr
; printcrlf
; stdioReadLine
; stdioPutC
;
.inc "user.h"

; *** Overridable consts ***
; Maximum number of lines allowed in the buffer.
.equ	ED_BUF_MAXLINES		0x800
; Size of our scratchpad
.equ	ED_BUF_PADMAXLEN	0x1000

; ******

.inc "err.h"
.inc "fs.h"
.inc "blkdev.h"
	jp	edMain

.inc "core.asm"
.inc "lib/util.asm"
.inc "lib/parse.asm"
.equ	IO_RAMSTART	USER_RAMSTART
.inc "ed/io.asm"
.equ	BUF_RAMSTART	IO_RAMEND
.inc "ed/buf.asm"
.equ	CMD_RAMSTART	BUF_RAMEND
.inc "ed/cmd.asm"
.equ	ED_RAMSTART	CMD_RAMEND
.inc "ed/main.asm"
USER_RAMSTART:
