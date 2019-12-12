; *** Variables ***

; A bool flag indicating that we're on first pass. When we are, we don't care
; about actual output, but only about the length of each upcode. This means
; that when we parse instructions and directive that error out because of a
; missing symbol, we don't error out and just write down a dummy value.
.equ	ZASM_FIRST_PASS		ZASM_RAMSTART
; whether we're in "local pass", that is, in local label scanning mode. During
; this special pass, ZASM_FIRST_PASS will also be set so that the rest of the
; code behaves as is we were in the first pass.
.equ	ZASM_LOCAL_PASS		@+1
; What IO_PC was when we started our context
.equ	ZASM_CTX_PC		@+1
; current ".org" offset, that is, what we must offset all our label by.
.equ	ZASM_ORG		@+2
.equ	ZASM_RAMEND		@+2

; Takes 2 byte arguments, blkdev in and blkdev out, expressed as IDs.
; Can optionally take a 3rd argument which is the high byte of the initial
; .org. For example, passing 0x42 to this 3rd arg is the equivalent of beginning
; the unit with ".org 0x4200".
; Read file through blkdev in and outputs its upcodes through blkdev out.
; HL is set to the last lineno to be read.
; Sets Z on success, unset on error. On error, A contains an error code (ERR_*)
zasmMain:
	; Parse args. HL points to string already
	; We don't allocate memory just to hold this. Because this happens
	; before initialization, we don't really care where those args are
	; parsed. That's why we borrow zasm's RAMSTART for a little while.
	ld	de, .argspecs
	ld	ix, ZASM_RAMSTART
	call	parseArgs
	jr	z, .goodargs
	; bad args
	ld	hl, 0
	ld	de, 0
	ld	a, SHELL_ERR_BAD_ARGS
	ret

.goodargs:
	; HL now points to parsed args
	; Init I/O
	ld	a, (ZASM_RAMSTART)	; blkdev in ID
	ld	de, IO_IN_BLK
	call	blkSel
	ld	a, (ZASM_RAMSTART+1)	; blkdev out ID
	ld	de, IO_OUT_BLK
	call	blkSel

	; Init .org
	; This is the 3rd argument, optional, will be zero if not given.
	; Save in "@" too
	ld	a, (ZASM_RAMSTART+2)
	ld	(ZASM_ORG+1), a		; high byte of .org
	ld	(DIREC_LASTVAL+1), a
	xor	a
	ld	(ZASM_ORG), a		; low byte zero in all cases
	ld	(DIREC_LASTVAL), a

	; And then the rest.
	ld	(ZASM_LOCAL_PASS), a
	call	ioInit
	call	symInit

	; First pass
	ld	hl, .sFirstPass
	call	ioPrintLN
	ld	a, 1
	ld	(ZASM_FIRST_PASS), a
	call	zasmParseFile
	jr	nz, .end
	; Second pass
	ld	hl, .sSecondPass
	call	ioPrintLN
	xor	a
	ld	(ZASM_FIRST_PASS), a
	; before parsing the file for the second pass, let's clear the const
	; registry. See comment in handleEQU.
	ld	ix, SYM_CONST_REGISTRY
	call	symClear
	call	zasmParseFile
.end:
	jp	ioLineNo		; --> HL, --> DE, returns

.argspecs:
	.db	0b001, 0b001, 0b101
.sFirstPass:
	.db	"First pass", 0
.sSecondPass:
	.db	"Second pass", 0

; Sets Z according to whether we're in first pass.
zasmIsFirstPass:
	ld	a, (ZASM_FIRST_PASS)
	cp	1
	ret

; Sets Z according to whether we're in local pass.
zasmIsLocalPass:
	ld	a, (ZASM_LOCAL_PASS)
	cp	1
	ret

; Set ZASM_ORG to specified number in HL
zasmSetOrg:
	ld	(ZASM_ORG), hl
	ret

; Return current PC (properly .org offsetted) in HL
zasmGetPC:
	push	de
	ld	hl, (ZASM_ORG)
	ld	de, (IO_PC)
	add	hl, de
	pop	de
	ret

; Repeatedly reads lines from IO, assemble them and spit the binary code in
; IO. Z is set on success, unset on error. DE contains the last line number to
; be read (first line is 1).
zasmParseFile:
	call	ioRewind
.loop:
	call	parseLine
	ret	nz		; error
	ld	a, b		; TOK_*
	cp	TOK_EOF
	jr	z, .eof
	jr	.loop
.eof:
	call	zasmIsLocalPass
	jr	nz, .end	; EOF and not local pass
	; we're in local pass and EOF. Unwind this
	call	_endLocalPass
	jr	.loop
.end:
	cp	a		; ensure Z
	ret

; Parse next token and accompanying args (when relevant) in I/O, write the
; resulting opcode(s) through ioPutB and increases (IO_PC) by the number of
; bytes written. BC is set to the result of the call to tokenize.
; Sets Z if parse was successful, unset if there was an error. EOF is not an
; error. If there is an error, A is set to the corresponding error code (ERR_*).
parseLine:
	call	tokenize
	ld	a, b		; TOK_*
	cp	TOK_INSTR
	jp	z, _parseInstr
	cp	TOK_DIRECTIVE
	jp	z, _parseDirec
	cp	TOK_LABEL
	jr	z, _parseLabel
	cp	TOK_EOF
	ret	z		; We're finished, no error.
	; Bad token
	ld	a, ERR_UNKNOWN
	jp	unsetZ		; return with Z unset

_parseInstr:
	ld	a, c		; I_*
	jp	parseInstruction

_parseDirec:
	ld	a, c		; D_*
	jp	parseDirective

_parseLabel:
	; The string in (scratchpad) is a label with its trailing ':' removed.
	ld	hl, scratchpad

	call	zasmIsLocalPass
	jr	z, .processLocalPass

	; Is this a local label? If yes, we don't process it in the context of
	; parseLine, whether it's first or second pass. Local labels are only
	; parsed during the Local Pass
	call	symIsLabelLocal
	jr	z, .success		; local? don't do anything.

	ld	ix, SYM_GLOBAL_REGISTRY
	call	zasmIsFirstPass
	jr	z, .registerLabel	; When we encounter a label in the first
					; pass, we register it in the symbol
					; list
	; At this point, we're in second pass, we've encountered a global label
	; and we'll soon continue processing our file. However, before we do
	; that, we should process our local labels.
	call	_beginLocalPass
	jr	.success
.processLocalPass:
	ld	ix, SYM_LOCAL_REGISTRY
	call	symIsLabelLocal
	jr	z, .registerLabel	; local label? all good, register it
					; normally
	; not a local label? Then we need to end local pass
	call	_endLocalPass
	jr	.success
.registerLabel:
	push	hl
	call	zasmGetPC
	ex	de, hl
	pop	hl
	call	symRegister
	jr	nz, .error
	; continue to .success
.success:
	xor	a		; ensure Z
	ret
.error:
	call	unsetZ
	ret

_beginLocalPass:
	; remember were I/O was
	call	ioSavePos
	; Remember where PC was
	ld	hl, (IO_PC)
	ld	(ZASM_CTX_PC), hl
	; Fake first pass
	ld	a, 1
	ld	(ZASM_FIRST_PASS), a
	; Set local pass
	ld	(ZASM_LOCAL_PASS), a
	; Empty local label registry
	ld	ix, SYM_LOCAL_REGISTRY
	jp	symClear


_endLocalPass:
	; recall I/O pos
	call	ioRecallPos
	; recall PC
	ld	hl, (ZASM_CTX_PC)
	ld	(IO_PC), hl
	; unfake first pass
	xor	a
	ld	(ZASM_FIRST_PASS), a
	; Unset local pass
	ld	(ZASM_LOCAL_PASS), a
	cp	a		; ensure Z
	ret
