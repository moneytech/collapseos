; *** CONSTS ***

.equ	D_DB	0x00
.equ	D_DW	0x01
.equ	D_EQU	0x02
.equ	D_ORG	0x03
.equ	D_FIL	0x04
.equ	D_OUT	0x05
.equ	D_INC	0x06
.equ	D_BIN	0x07
.equ	D_BAD	0xff

; *** Variables ***
; Result of the last .equ evaluation. Used for "@" symbol.
.equ	DIREC_LASTVAL		DIREC_RAMSTART
.equ	DIREC_SCRATCHPAD	DIREC_LASTVAL+2
.equ	DIREC_RAMEND		DIREC_SCRATCHPAD+SCRATCHPAD_SIZE
; *** CODE ***

; 3 bytes per row, fill with zero
dirNames:
	.db	"DB", 0
	.db	"DW", 0
	.db	"EQU"
	.db	"ORG"
	.db	"FIL"
	.db	"OUT"
	.db	"INC"
	.db	"BIN"

; This is a list of handlers corresponding to indexes in dirNames
dirHandlers:
	.dw	handleDB
	.dw	handleDW
	.dw	handleEQU
	.dw	handleORG
	.dw	handleFIL
	.dw	handleOUT
	.dw	handleINC
	.dw	handleBIN

handleDB:
	push	hl
.loop:
	call	readWord
	jr	nz, .badfmt
	ld	hl, scratchpad
	call	enterDoubleQuotes
	jr	z, .stringLiteral
	call	parseExpr
	jr	nz, .badarg
	push	ix \ pop hl
	ld	a, h
	or	a		; cp 0
	jr	nz, .overflow	; not zero? overflow
	ld	a, l
	call	ioPutB
	jr	nz, .ioError
.stopStrLit:
	call	readComma
	jr	z, .loop
	cp	a		; ensure Z
	pop	hl
	ret
.ioError:
	ld	a, SHELL_ERR_IO_ERROR
	jr	.error
.badfmt:
	ld	a, ERR_BAD_FMT
	jr	.error
.badarg:
	ld	a, ERR_BAD_ARG
	jr	.error
.overflow:
	ld	a, ERR_OVFL
.error:
	call	unsetZ
	pop	hl
	ret

.stringLiteral:
	ld	a, (hl)
	inc	hl
	or	a		; when we encounter 0, that was what used to
	jr	z, .stopStrLit	; be our closing quote. Stop.
	; Normal character, output
	call	ioPutB
	jr	nz, .ioError
	jr	.stringLiteral

handleDW:
	push	hl
.loop:
	call	readWord
	jr	nz, .badfmt
	ld	hl, scratchpad
	call	parseExpr
	jr	nz, .badarg
	push	ix \ pop hl
	ld	a, l
	call	ioPutB
	jr	nz, .ioError
	ld	a, h
	call	ioPutB
	jr	nz, .ioError
	call	readComma
	jr	z, .loop
	cp	a		; ensure Z
	pop	hl
	ret
.ioError:
	ld	a, SHELL_ERR_IO_ERROR
	jr	.error
.badfmt:
	ld	a, ERR_BAD_FMT
	jr	.error
.badarg:
	ld	a, ERR_BAD_ARG
.error:
	call	unsetZ
	pop	hl
	ret

handleEQU:
	call	zasmIsLocalPass	; Are we in local pass? Then ignore all .equ.
	jr	z, .skip		; they mess up duplicate symbol detection.
	; We register constants on both first and second pass for one little
	; reason: .org. Normally, we'd register constants on second pass only
	; so that we have values for forward label references, but we need .org
	; to be effective during the first pass and .org needs to support
	; expressions. So, we double-parse .equ, clearing the const registry
	; before the second pass.
	push	hl
	push	de
	push	bc
	; Read our constant name
	call	readWord
	jr	nz, .badfmt
	; We can't register our symbol yet: we don't have our value!
	; Let's copy it over.
	ld	de, DIREC_SCRATCHPAD
	ld	bc, SCRATCHPAD_SIZE
	ldir

	; Now, read the value associated to it
	call	readWord
	jr	nz, .badfmt
	ld	hl, scratchpad
	call	parseExpr
	jr	nz, .badarg
	ld	hl, DIREC_SCRATCHPAD
	push	ix \ pop de
	; Save value in "@" special variable
	ld	(DIREC_LASTVAL), de
	call	symRegisterConst	; A and Z set
	jr	z, .end			; success
	; register ended up in error. We need to figure which error. If it's
	; a duplicate error, we ignore it and return success because, as per
	; ".equ" policy, it's fine to define the same const twice. The first
	; value has precedence.
	cp	ERR_DUPSYM
	; whatever the value of Z, it's the good one, return
	jr	.end
.badfmt:
	ld	a, ERR_BAD_FMT
	jr	.error
.badarg:
	ld	a, ERR_BAD_ARG
.error:
	call	unsetZ
.end:
	pop	bc
	pop	de
	pop	hl
	ret
.skip:
	; consume args and return
	call	readWord
	jp	readWord

handleORG:
	call	readWord
	jr	nz, .badfmt
	call	parseExpr
	jr	nz, .badarg
	push	ix \ pop hl
	ld	(DIREC_LASTVAL), hl
	call	zasmSetOrg
	cp	a		; ensure Z
	ret
.badfmt:
	ld	a, ERR_BAD_FMT
	jr	.error
.badarg:
	ld	a, ERR_BAD_ARG
.error:
	call	unsetZ
	ret

handleFIL:
	call	readWord
	jr	nz, .badfmt
	call	parseExpr
	jr	nz, .badarg
	push	bc	; --> lvl 1
	push	ix \ pop bc
	ld	a, b
	cp	0xd0
	jr	nc, .overflow
.loop:
	ld	a, b
	or	c
	jr	z, .loopend
	xor	a
	call	ioPutB
	jr	nz, .ioError
	dec	bc
	jr	.loop
.loopend:
	cp	a	; ensure Z
	pop	bc	; <-- lvl 1
	ret
.ioError:
	ld	a, SHELL_ERR_IO_ERROR
	jp	unsetZ
.badfmt:
	ld	a, ERR_BAD_FMT
	jp	unsetZ
.badarg:
	ld	a, ERR_BAD_ARG
	jp	unsetZ
.overflow:
	pop	bc	; <-- lvl 1
	ld	a, ERR_OVFL
	jp	unsetZ

handleOUT:
	push	hl
	; Read our expression
	call	readWord
	jr	nz, .badfmt
	call	zasmIsFirstPass		; No .out during first pass
	jr	z, .end
	ld	hl, scratchpad
	call	parseExpr
	jr	nz, .badarg
	push	ix \ pop hl
	ld	a, h
	out	(ZASM_DEBUG_PORT), a
	ld	a, l
	out	(ZASM_DEBUG_PORT), a
	jr	.end
.badfmt:
	ld	a, ERR_BAD_FMT
	jr	.error
.badarg:
	ld	a, ERR_BAD_ARG
.error:
	call	unsetZ
.end:
	pop	hl
	ret

handleINC:
	call	readWord
	jr	nz, .badfmt
	; HL points to scratchpad
	call	enterDoubleQuotes
	jr	nz, .badfmt
	call	ioOpenInclude
	jr	nz, .badfn
	cp	a		; ensure Z
	ret
.badfmt:
	ld	a, ERR_BAD_FMT
	jr	.error
.badfn:
	ld	a, ERR_FILENOTFOUND
.error:
	call	unsetZ
	ret

handleBIN:
	call	readWord
	jr	nz, .badfmt
	; HL points to scratchpad
	call	enterDoubleQuotes
	jr	nz, .badfmt
	call	ioSpitBin
	jr	nz, .badfn
	cp	a		; ensure Z
	ret
.badfmt:
	ld	a, ERR_BAD_FMT
	jr	.error
.badfn:
	ld	a, ERR_FILENOTFOUND
.error:
	call	unsetZ
	ret

; Reads string in (HL) and returns the corresponding ID (D_*) in A. Sets Z if
; there's a match.
getDirectiveID:
	ld	a, (hl)
	cp	'.'
	ret	nz
	push	hl
	push	bc
	push	de
	inc	hl
	ld	b, D_BIN+1		; D_BIN is last
	ld	c, 3
	ld	de, dirNames
	call	findStringInList
	pop	de
	pop	bc
	pop	hl
	ret

; Parse directive specified in A (D_* const) with args in I/O and act in
; an appropriate manner. If the directive results in writing data at its
; current location, that data is directly written through ioPutB.
; Each directive has the same return value pattern: Z on success, not-Z on
; error, A contains the error number (ERR_*).
parseDirective:
	push	de
	; double A to have a proper offset in dirHandlers
	add	a, a
	ld	de, dirHandlers
	call	addDE
	call	intoDE
	push	de \ pop ix
	pop	de
	jp	(ix)
