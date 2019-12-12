; *** Consts ***
; Number of rows in the argspec table
.equ	ARGSPEC_TBL_CNT		33
; size in bytes of each row in the primary instructions table
.equ	INSTR_TBL_ROWSIZE	6
; Instruction IDs They correspond to the index of the table in instrNames
.equ	I_ADC	0x00
.equ	I_ADD	0x01
.equ	I_AND	0x02
.equ	I_BIT	0x03
.equ	I_CALL	0x04
.equ	I_CCF	0x05
.equ	I_CP	0x06
.equ	I_CPD	0x07
.equ	I_CPDR	0x08
.equ	I_CPI	0x09
.equ	I_CPIR	0x0a
.equ	I_CPL	0x0b
.equ	I_DAA	0x0c
.equ	I_DEC	0x0d
.equ	I_DI	0x0e
.equ	I_DJNZ	0x0f
.equ	I_EI	0x10
.equ	I_EX	0x11
.equ	I_EXX	0x12
.equ	I_HALT	0x13
.equ	I_IM	0x14
.equ	I_IN	0x15
.equ	I_INC	0x16
.equ	I_IND	0x17
.equ	I_INDR	0x18
.equ	I_INI	0x19
.equ	I_INIR	0x1a
.equ	I_JP	0x1b
.equ	I_JR	0x1c
.equ	I_LD	0x1d
.equ	I_LDD	0x1e
.equ	I_LDDR	0x1f
.equ	I_LDI	0x20
.equ	I_LDIR	0x21
.equ	I_NEG	0x22
.equ	I_NOP	0x23
.equ	I_OR	0x24
.equ	I_OTDR	0x25
.equ	I_OTIR	0x26
.equ	I_OUT	0x27
.equ	I_POP	0x28
.equ	I_PUSH	0x29
.equ	I_RES	0x2a
.equ	I_RET	0x2b
.equ	I_RETI	0x2c
.equ	I_RETN	0x2d
.equ	I_RL	0x2e
.equ	I_RLA	0x2f
.equ	I_RLC	0x30
.equ	I_RLCA	0x31
.equ	I_RR	0x32
.equ	I_RRA	0x33
.equ	I_RRC	0x34
.equ	I_RRCA	0x35
.equ	I_RST	0x36
.equ	I_SBC	0x37
.equ	I_SCF	0x38
.equ	I_SET	0x39
.equ	I_SLA	0x3a
.equ	I_SRL	0x3b
.equ	I_SUB	0x3c
.equ	I_XOR	0x3d

; *** Variables ***
; Args are 3 bytes: argspec, then values of numerical constants (when that's
; appropriate)
.equ	INS_CURARG1	INS_RAMSTART
.equ	INS_CURARG2	INS_CURARG1+3
.equ	INS_UPCODE	INS_CURARG2+3
.equ	INS_RAMEND	INS_UPCODE+4

; *** Code ***
; Checks whether A is 'N' or 'M'
checkNOrM:
	cp	'N'
	ret	z
	cp	'M'
	ret

; Checks whether A is 'n', 'm'
checknm:
	cp	'n'
	ret	z
	cp	'm'
	ret

checklxy:
	cp	'l'
	ret	z
; Checks whether A is 'x', 'y'
checkxy:
	cp	'x'
	ret	z
	cp	'y'
	ret

; Reads string in (HL) and returns the corresponding ID (I_*) in A. Sets Z if
; there's a match.
getInstID:
	push	bc
	push	de
	ld	b, I_XOR+1	; I_XOR is the last
	ld	c, 4
	ld	de, instrNames
	call	findStringInList
	pop	de
	pop	bc
	ret

; Parse the string at (HL) and check if it starts with IX+, IY+, IX- or IY-.
; Sets Z if yes, unset if no. On success, A contains either '+' or '-'.
parseIXY:
	push	hl
	ld	a, (hl)
	call	upcase
	cp	'I'
	jr	nz, .end	; Z already unset
	inc	hl
	ld	a, (hl)
	call	upcase
	cp	'X'
	jr	z, .match1
	cp	'Y'
	jr	z, .match1
	jr	.end		; Z already unset
.match1:
	; Alright, we have IX or IY. Let's see if we have + or - next.
	inc	hl
	ld	a, (hl)
	cp	'+'
	jr	z, .end		; Z is already set
	cp	'-'
	; The value of Z at this point is our final result
.end:
	pop	hl
	ret

; find argspec for string at (HL). Returns matching argspec in A.
; Return value 0xff holds a special meaning: arg is not empty, but doesn't match
; any argspec (A == 0 means arg is empty). A return value of 0xff means an
; error.
;
; If the parsed argument is a number constant, 'N' is returned and IX contains
; the value of that constant.
parseArg:
	call	strlen
	or	a
	ret	z		; empty string? A already has our result: 0

	push	bc
	push	de
	push	hl

	; We always initialize IX to zero so that non-numerical args end up with
	; a clean zero.
	ld	ix, 0

	ld	de, argspecTbl
	; DE now points the the "argspec char" part of the entry, but what
	; we're comparing in the loop is the string next to it. Let's offset
	; DE by one so that the loop goes through strings.
	inc	de
	ld	b, ARGSPEC_TBL_CNT
.loop1:
	ld	a, 4
	call	strncmpI
	jr	z, .found		; got it!
	ld	a, 5
	call	addDE
	djnz	.loop1

	; We exhausted the argspecs. Let's see if we're inside parens.
	call	enterParens
	jr	z, .withParens
	; (HL) has no parens
	call	.maybeParseExpr
	jr	nz, .nomatch
	; We have a proper number in no parens. Number in IX.
	ld	a, 'N'
	jr	.end
.withParens:
	ld	b, 0		; make sure it doesn't hold '-'
	ld	c, 'M'		; C holds the argspec type until we reach
				; .numberInParens
	; We have parens. First, let's see if we have a (IX+d) type of arg.
	call	parseIXY
	jr	nz, .parseNumberInParens	; not I{X,Y}. just parse number.
	; We have IX+/IY+/IX-/IY-.
	; A contains either '+' or '-'. Save it for later, in B.
	ld	b, a
	inc	hl	; (HL) now points to X or Y
	ld	a, (hl)
	call	upcase
	inc	hl	; advance HL to the number part
	inc	hl	; this is the number
	cp	'Y'
	jr	nz, .notY
	ld	c, 'y'
	jr	.parseNumberInParens
.notY:
	ld	c, 'x'
.parseNumberInParens:
	call	.maybeParseExpr
	jr	nz, .nomatch
	; We have a proper number in parens. Number in IX
	; is '-' in B? if yes, we need to negate the low part of IX
	ld	a, b
	cp	'-'
	jr	nz, .dontNegateIX
	; we need to negate the low part of IX
	; TODO: when parsing routines properly support unary negative numbers,
	; We could replace this complicated scheme below with a nice hack where
	; we start parsing our displacement number at the '+' and '-' char.

	; HL isn't needed anymore and can be destroyed.
	push	ix \ pop hl
	ld	a, l
	neg
	ld	l, a
	push	hl \ pop ix
.dontNegateIX:
	ld	a, c	; M, x, or y
	jr	.end
.nomatch:
	; We get no match
	ld	a, 0xff
	jr	.end
.found:
	; found the matching argspec row. Our result is one byte left of DE.
	dec	de
	ld	a, (de)
.end:
	pop	hl
	pop	de
	pop	bc
	ret

.maybeParseExpr:
	; Before we try to parse expr in (HL), first check if we're in first
	; pass if we are, skip parseExpr. Most of the time, that parse is
	; harmless, but in some cases it causes false failures. For example,
	; a "-" operator can cause is to falsely overflow and generate
	; truncation error.
	call	zasmIsFirstPass
	ret	z
	jp	parseExpr

; Returns, with Z, whether A is a groupId
isGroupId:
	or	a
	jp	z, unsetZ	; not a group
	cp	0xd		; max group id + 1
	jp	nc, unsetZ	; >= 0xd? not a group
	; A is a group. ensure Z is set
	cp	a
	ret

; Find argspec A in group id H.
; Set Z according to whether we found the argspec
; If found, the value in A is the argspec value in the group (its index).
findInGroup:
	push	bc
	push	hl

	or	a	; is our arg empty? If yes, we have nothing to do
	jr	z, .notfound

	push	af
	ld	a, h
	cp	0xa
	jr	z, .specialGroupCC
	cp	0xb
	jr	z, .specialGroupABCDEHL
	jr	nc, .notfound	; > 0xb? not a group
	pop	af
	; regular group
	push	de
	ld	de, argGrpTbl
	; group ids start at 1. decrease it, then multiply by 4 to have a
	; proper offset in argGrpTbl
	dec	h
	push	af
	ld	a, h
	rla
	rla
	call	addDE		; At this point, DE points to our group
	pop	af
	ex	de, hl		; And now, HL points to the group
	pop	de

	ld	bc, 4
	jr	.find

.specialGroupCC:
	ld	hl, argGrpCC
	jr	.specialGroupEnd
.specialGroupABCDEHL:
	ld	hl, argGrpABCDEHL
.specialGroupEnd:
	pop	af	; from the push af just before the special group check
	ld	bc, 8

.find:
	; This part is common to regular and special group. We expect HL to
	; point to the group and BC to contain its length.
	push	bc		; save the start value loop index so we can sub
.loop:
	cpi
	jr	z, .found
	jp	po, .notfound
	jr	.loop
.found:
	; we found our result! Now, what we want to put in A is the index of
	; the found argspec.
	pop	hl	; we pop from the "push bc" above. L is now 4 or 8
	ld	a, l
	sub	c
	dec	a	; cpi DECs BC even when there's a match, so C == the
			; number of iterations we've made. But our index is
			; zero-based (1 iteration == 0 index).
	cp	a	; ensure Z is set
	jr	.end
.notfound:
	pop	bc	; from the push bc in .find
	call	unsetZ
.end:
	pop	hl
	pop	bc
	ret

; Compare argspec from instruction table in A with argument in (HL).
; IX must point to argspec row.
; For constant args, it's easy: if A == (HL), it's a success.
; If it's not this, then we check if it's a numerical arg.
; If A is a group ID, we do something else: we check that (HL) exists in the
; groupspec (argGrpTbl). Moreover, we go and write the group's "value" (index)
; in (HL+1). This will save us significant processing later in spitUpcode.
; Set Z according to whether we match or not.
matchArg:
	cp	(hl)
	ret	z
	; not an exact match. Before we continue: is A zero? Because if it is,
	; we have to stop right here: no match possible.
	or	a
	jr	nz, .skip1	; not a zero, we can continue
	; zero, stop here
	cp	1			; unset Z
	ret
.skip1:
	; If our argspec is 'l', then we also match 'x' and 'y'
	cp	'l'
	jr	nz, .skip2
	; Does it accept IX and IY?
	bit	4, (ix+3)
	ld	a, (hl)
	jp	nz, checkxy	; bit set: our result is checkxy
	; doesn't accept? then we don't match
	jp	unsetZ
.skip2:
	; Alright, let's start with a special case. Is it part of the special
	; "BIT" group, 0xc? If yes, we actually expect a number, which will
	; then be ORed like a regular group index.
	cp	0xc
	jr	z, .expectsBIT
	; not an exact match, let's check for numerical constants.
	call	upcase
	call	checkNOrM
	jr	z, .expectsNumber
	jr	.notNumber
.expectsNumber:
	; Our argument is a number N or M. Never a lower-case version. At this
	; point in the processing, we don't care about whether N or M is upper,
	; we do truncation tests later. So, let's just perform the same == test
	; but in a case-insensitive way instead
	cp	(hl)
	ret			; whether we match or not, the result of Z is
				; the good one.
.expectsBIT:
	ld	a, (hl)
	cp	'N'
	inc	hl
	ld	a, (hl)
	dec	hl
	cp	8
	jr	c, .isBit	; A < 8
	; not a bit
	or	a		; unset Z
	ret
.isBit:
	cp	a		; set Z
	ret

.notNumber:
	; A bit of a delicate situation here: we want A to go in H but also
	; (HL) to go in A. If not careful, we overwrite each other. EXX is
	; necessary to avoid invoving other registers.
	push	hl
	exx
	ld	h, a
	push	hl
	exx
	ld	a, (hl)
	pop	hl
	call	findInGroup
	pop	hl
	ret	nz
	; we found our group? let's write down its "value" in (HL+1). We hold
	; this value in A at the moment.
	inc	hl
	ld	(hl), a
	dec	hl
	ret

; Compare primary row at (DE) with ID in A. Sets Z flag if there's a match.
matchPrimaryRow:
	push	hl
	push	ix
	push	de \ pop ix
	cp	(ix)
	jr	nz, .end
	; name matches, let's see the rest
	ld	hl, INS_CURARG1
	ld	a, (ix+1)
	call	matchArg
	jr	nz, .end
	ld	hl, INS_CURARG2
	ld	a, (ix+2)
	call	matchArg
.end:
	pop	ix
	pop	hl
	ret

; *** Special opcodes ***
; The special upcode handling routines below all have the same signature.
; Instruction row is at IX and we're expected to perform the same task as
; spitUpcode. The number of bytes, however, must go in C instead of A
; No need to preserve HL, DE, BC and IX: it's handled by spitUpcode already.

; Handle like a regular "JP (IX+d)" except that we refuse any displacement: if
; a displacement is specified, we error out.
handleJPIXY:
	ld	a, (INS_CURARG1+1)
	or	a		; numerical argument *must* be zero
	jr	nz, .error
	; ok, we're good
	ld	a, 0xe9		; second upcode
	ld	(INS_UPCODE), a
	ld	c, 1
	ret
.error:
	ld	c, 0
	ret

handleBITR:
	ld	b, 0b01000000
	jr	_handleBITR
handleSETR:
	ld	b, 0b11000000
	jr	_handleBITR
handleRESR:
	ld	b, 0b10000000
_handleBITR:
	; get group value
	ld	a, (INS_CURARG2+1)	; group value
	ld	c, a
	; write first upcode
	ld	a, 0xcb		; first upcode
	ld	(INS_UPCODE), a
	; get bit value
	ld	a, (INS_CURARG1+1)	; 0-7
	rlca	; clears cary if any
	rla
	rla
	; Now we have group value in stack, bit value in A (properly shifted)
	; and we want to OR them together
	or	c		; Now we have our ORed value
	or	b		; and with our "base" value and we're good!
	ld	(INS_UPCODE+1), a
	ld	c, 2
	ret

handleIM:
	ld	a, (INS_CURARG1+1)
	cp	0
	jr	z, .im0
	cp	1
	jr	z, .im1
	cp	2
	jr	z, .im2
	; error
	ld	c, 0
	ret
.im0:
	ld	a, 0x46
	jr	.proceed
.im1:
	ld	a, 0x56
	jr	.proceed
.im2:
	ld	a, 0x5e
.proceed:
	ld	(INS_UPCODE+1), a
	ld	a, 0xed
	ld	(INS_UPCODE), a
	ld	c, 2
	ret

handleLDIXYn:
	ld	a, 0x36		; second upcode
	ld	(INS_UPCODE), a
	ld	a, (INS_CURARG1+1)	; IXY displacement
	ld	(INS_UPCODE+1), a
	ld	a, (INS_CURARG2+1)	; N
	ld	(INS_UPCODE+2), a
	ld	c, 3
	ret

handleLDIXYr:
	ld	a, (INS_CURARG2+1)	; group value
	or	0b01110000	; second upcode
	ld	(INS_UPCODE), a
	ld	a, (INS_CURARG1+1)	; IXY displacement
	ld	(INS_UPCODE+1), a
	ld	c, 2
	ret

handleLDrIXY:
	ld	a, (INS_CURARG1+1)	; group value
	rlca \ rla \ rla
	or	0b01000110	; second upcode
	ld	(INS_UPCODE), a
	ld	a, (INS_CURARG2+1)	; IXY displacement
	ld	(INS_UPCODE+1), a
	ld	c, 2
	ret

handleLDrr:
	; first argument is displaced by 3 bits, second argument is not
	; displaced and we or that with a leading 0b01000000
	ld	a, (INS_CURARG1+1)	; group value
	rlca
	rla
	rla
	ld	c, a		; store it
	ld	a, (INS_CURARG2+1)	; other group value
	or	c
	or	0b01000000
	ld	(INS_UPCODE), a
	ld	c, 1
	ret

handleRST:
	ld	a, (INS_CURARG1+1)
	; verify that A is either 0x08, 0x10, 0x18, 0x20, 0x28, 0x30 or 0x38.
	; Good news: the relevant bits (bits 5:3) are already in place. We only
	; have to verify that they're surrounded by zeroes.
	ld	c, 0b11000111
	and	c
	jr	nz, .error
	; We're in range. good.
	ld	a, (INS_CURARG1+1)
	or	c
	ld	(INS_UPCODE), a
	ld	c, 1
	ret
.error:
	ld	c, 0
	ret

; Compute the upcode for argspec row at (DE) and arguments in curArg{1,2} and
; writes the resulting upcode to IO.
; A is zero, with Z set, on success. A is non-zero, with Z unset, on error.
spitUpcode:
	push	ix
	push	de
	push	hl
	push	bc
	; First, let's go in IX mode. It's easier to deal with offsets here.
	push	de \ pop ix

	; before we begin, are we in a 'l' argspec? Is it flagged for IX/IY
	; acceptance? If yes, a 'x' or 'y' instruction? Check this on both
	; args and if we detect a 'x' or 'y', things are *always* the same:
	; the upcode is exactly the same as its (HL) counterpart except that
	; it is preceeded by 0xdd or 0xfd. If we're 'x' or 'y', then it means
	; that we've already been matched to a 'l' argspec, so after spitting
	; 0xdd or 0xfd, we can continue as normal.
	ld	a, (ix+1)
	call	checklxy
	jr	z, .isl
	ld	a, (ix+2)
	call	checklxy
	jr	nz, .begin		; no point in checking further.
.isl:
	ld	a, (INS_CURARG1)
	cp	'x'
	jr	z, .isx
	cp	'y'
	jr	z, .isy
	ld	a, (INS_CURARG2)
	cp	'x'
	jr	z, .isx
	cp	'y'
	jr	z, .isy
	jr	.begin
.isx:
	ld	a, 0xdd
	call	ioPutB
	jr	.begin
.isy:
	ld	a, 0xfd
	call	ioPutB
.begin:
	; Are we a "special instruction"?
	bit	5, (ix+3)
	jr	z, .normalInstr		; not set: normal instruction
	; We are a special instruction. Fetch handler (little endian, remember).
	ld	l, (ix+4)
	ld	h, (ix+5)
	call	callHL
	; We have our result written in INS_UPCODE and C is set.
	jp	.writeIO

.normalInstr:
	; we begin by writing our "base upcode", which can be one or two bytes
	ld	a, (ix+4)	; first upcode
	ld	(INS_UPCODE), a
	; from this point, DE points to "where we are" in terms of upcode
	; writing.
	ld	de, INS_UPCODE+1
	ld	c, 1		; C holds our upcode count

	; Now, let's determine if we have one or two upcode. As a general rule,
	; we simply have to check if (ix+5) == 0, which means one upcode.
	; However, some two-upcodes instructions have a 0 (ix+5) because they
	; expect group OR-ing into it and all other bits are zero. See "RLC r".
	; To handle those cases, we *also* check for Bit 6 in (ix+3).
	ld	a, (ix+5)	; second upcode
	or	a		; do we have a second upcode?
	jr	nz, .twoUpcodes
	bit	6, (ix+3)
	jr	z, .onlyOneUpcode	; not set: single upcode
.twoUpcodes:
	; we have two upcodes
	ld	(de), a
	inc	de
	inc	c
.onlyOneUpcode:
	; now, let's see if we're dealing with a group here
	ld	a, (ix+1)	; first argspec
	call	isGroupId
	jr	z, .firstArgIsGroup
	; First arg not a group. Maybe second is?
	ld	a, (ix+2)	; 2nd argspec
	call	isGroupId
	jr	nz, .writeExtraBytes	; not a group? nothing to do. go to
					; next step: write extra bytes
	; Second arg is group
	ld	hl, INS_CURARG2
	jr	.isGroup
.firstArgIsGroup:
	ld	hl, INS_CURARG1
.isGroup:
	; A is a group, good, now let's get its value. HL is pointing to
	; the argument. Our group value is at (HL+1).
	inc	hl
	ld	a, (hl)
	; Now, we have our arg "group value" in A. Were going to need to
	; displace it left by the number of steps specified in the table.
	push	af
	ld	a, (ix+3)	; displacement bit
	and	0xf		; we only use the lower nibble.
	ld	b, a
	pop	af
	call	rlaX

	; At this point, we have a properly displaced value in A. We'll want
	; to OR it with the opcode.
	; However, we first have to verify whether this ORing takes place on
	; the second upcode or the first.
	bit	6, (ix+3)
	jr	z, .firstUpcode	; not set: first upcode
	or	(ix+5)		; second upcode
	ld	(INS_UPCODE+1), a
	jr	.writeExtraBytes
.firstUpcode:
	or	(ix+4)		; first upcode
	ld	(INS_UPCODE), a
	jr	.writeExtraBytes
.writeExtraBytes:
	; Good, we are probably finished here for many primary opcodes. However,
	; some primary opcodes take 8 or 16 bit constants as an argument and
	; if that's the case here, we need to write it too.
	; We still have our instruction row in IX and we have DE pointing to
	; where we should write next (which could be the second or the third
	; byte of INS_UPCODE).
	ld	a, (ix+1)	; first argspec
	ld	hl, INS_CURARG1
	call	checkNOrM
	jr	z, .withWord
	call	checknm
	jr	z, .withByte
	ld	a, (INS_CURARG1)
	call	checkxy
	jr	z, .withByte
	ld	a, (ix+2)	; second argspec
	ld	hl, INS_CURARG2
	call	checkNOrM
	jr	z, .withWord
	call	checknm
	jr	z, .withByte
	ld	a, (INS_CURARG2)
	call	checkxy
	jr	z, .withByte
	; nope, no number, alright, we're finished here
	jr	.writeIO
.withByte:
	inc	hl
	; HL points to our number (LSB), with (HL+1) being our MSB which should
	; normally by zero. However, if our instruction is jr or djnz, that
	; number is actually a 2-bytes address that has to be relative to PC,
	; so it's a special case. Let's check for this special case.
	bit	7, (ix+3)
	jr	z, .absoluteValue	; bit not set? regular byte value,
	; Our argument is a relative address ("e" type in djnz and jr). We have
	; to subtract PC from it.

	; First, check whether we're on first pass. If we are, skip processing
	; below because not having real symbol value makes relative address
	; verification falsely fail.
	inc	c		; one extra byte is written
	call	zasmIsFirstPass
	jr	z, .writeIO

	; We're on second pass
	push	de		; Don't let go of this, that's our dest
	push	hl
	call	zasmGetPC	; --> HL
	ex	de, hl
	pop	hl
	call	intoHL
	dec	hl		; what we write is "e-2"
	dec	hl
	call	subDEFromHL
	pop	de		; Still have it? good
	; HL contains our number and we'll check its bounds. If It's negative,
	; H is going to be 0xff and L has to be >= 0x80. If it's positive,
	; H is going to be 0 and L has to be < 0x80.
	ld	a, l
	cp	0x80
	jr	c, .skipHInc	; a < 0x80, H is expected to be 0
	; A being >= 0x80 is only valid in cases where HL is negative and
	; within bounds. This only happens is H == 0xff. Let's increase it to 0.
	inc	h
.skipHInc:
	; Let's write our value now even though we haven't checked our bounds
	; yet. This way, we don't have to store A somewhere else.
	ld	(de), a
	ld	a, h
	or	a		; cp 0
	jr	nz, .numberTruncated	; if A is anything but zero, we're out
					; of bounds.
	jr	.writeIO

.absoluteValue:
	; verify that the MSB in argument is zero
	inc	hl	; MSB is 2nd byte
	ld	a, (hl)
	dec	hl	; HL now points to LSB
	or	a	; cp 0
	jr	nz, .numberTruncated
	push	bc
	ldi
	pop	bc
	inc	c
	jr	.writeIO

.withWord:
	inc	hl	; HL now points to LSB
	; Clear to proceed. HL already points to our number
	push	bc
	ldi	; LSB written, we point to MSB now
	ldi	; MSB written
	pop	bc
	inc	c		; two extra bytes are written
	inc	c
	; to writeIO
.writeIO:
	; Before we write IO, let's check a very specific case: is our first
	; upcode 0xcb and our byte count == 3? If yes, then swap the two last
	; bytes. In all instructions except 0xcb ones, IX/IY displacement comes
	; last, but in all 0xcb instructions, they come 2nd last.
	call	.checkCB
	; Let's write INS_UPCODE to IO
	dec	c \ inc	c	; is C zero?
	jr	z, .numberTruncated
	ld	b, c		; save output byte count
	ld	hl, INS_UPCODE
.loopWrite:
	ld	a, (hl)
	call	ioPutB
	jr	nz, .ioError
	inc	hl
	djnz	.loopWrite
	cp	a	; ensure Z
	jr	.end
.numberTruncated:
	; Z already unset
	ld	a, ERR_OVFL
	jr	.end
.ioError:
	; Z already unset
	ld	a, SHELL_ERR_IO_ERROR
	; continue to .end
.end:
	pop	bc
	pop	hl
	pop	de
	pop	ix
	ret
.checkCB:
	ld	a, (INS_UPCODE)
	cp	0xcb
	ret	nz
	ld	a, c
	cp	3
	ret	nz
	; We are in 0xcb + displacement situation. Swap bytes 2 and 3.
	ld	a, (INS_UPCODE+1)
	ex	af, af'
	ld	a, (INS_UPCODE+2)
	ld	(INS_UPCODE+1), a
	ex	af, af'
	ld	(INS_UPCODE+2), a
	ret

; Parse argument in (HL) and place it in (DE)
; Sets Z on success, reset on error.
processArg:
	call	parseArg
	cp	0xff
	jr	z, .error
	ld	(de), a
	; When A is a number, IX is set with the value of that number. Because
	; We don't use the space allocated to store those numbers in any other
	; occasion, we store IX there unconditonally, LSB first.
	inc	de
	push	hl
		push	ix \ pop hl
		call	writeHLinDE
	pop	hl
	cp	a		; ensure Z is set
	ret
.error:
	ld	a, ERR_BAD_ARG
	call	unsetZ
	ret

; Parse instruction specified in A (I_* const) with args in I/O and write
; resulting opcode(s) in I/O.
; Sets Z on success. On error, A contains an error code (ERR_*)
parseInstruction:
	push	bc
	push	hl
	push	de
	; A is reused in matchPrimaryRow but that register is way too changing.
	; Let's keep a copy in a more cosy register.
	ld	c, a
	xor	a
	ld	(INS_CURARG1), a
	ld	(INS_CURARG2), a
	call	readWord
	jr	nz, .nomorearg
	ld	de, INS_CURARG1
	call	processArg
	jr	nz, .error	; A is set to error
	call	readComma
	jr	nz, .nomorearg
	call	readWord
	jr	nz, .badfmt
	ld	de, INS_CURARG2
	call	processArg
	jr	nz, .error	; A is set to error
.nomorearg:
	; Parsing done, no error, let's move forward to instr row matching!
	; To speed up things a little, we use a poor man's indexing. Full
	; bisecting would involve too much complexity.
	ld	a, c			; recall A param
	ld	de, instrTBl
	cp	I_EX
	jr	c, .loop
	ld	de, instrTBlEX
	cp	I_LD
	jr	c, .loop
	ld	de, instrTBlLD
	cp	I_RET
	jr	c, .loop
	ld	de, instrTBlRET
.loop:
	ld	a, c			; recall A param
	call	matchPrimaryRow
	jr	z, .match
	ld	a, INSTR_TBL_ROWSIZE
	call	addDE
	ld	a, (de)
	cp	0xff
	jr	nz, .loop
	; No signature match
	ld	a, ERR_BAD_ARG
	jr	.error
.match:
	; We have our matching instruction row. We're getting pretty near our
	; goal here!
	call	spitUpcode
	jr	.end		; Z and A set properly, even on error
.badfmt:
	; Z already unset
	ld	a, ERR_BAD_FMT
.error:
	; A is set to error already
	call	unsetZ
.end:
	pop	de
	pop	hl
	pop	bc
	ret


; In instruction metadata below, argument types arge indicated with a single
; char mnemonic that is called "argspec". This is the table of correspondence.
; Single letters are represented by themselves, so we don't need as much
; metadata.
; Special meaning:
; 0 : no arg
; 1-10 : group id (see Groups section)
; 0xff: error

; Format: 1 byte argspec + 4 chars string
argspecTbl:
	.db	'A', "A", 0, 0, 0
	.db	'B', "B", 0, 0, 0
	.db	'C', "C", 0, 0, 0
	.db	'k', "(C)", 0
	.db	'D', "D", 0, 0, 0
	.db	'E', "E", 0, 0, 0
	.db	'H', "H", 0, 0, 0
	.db	'L', "L", 0, 0, 0
	.db	'I', "I", 0, 0, 0
	.db	'R', "R", 0, 0, 0
	.db	'h', "HL", 0, 0
	.db	'l', "(HL)"
	.db	'd', "DE", 0, 0
	.db	'e', "(DE)"
	.db	'b', "BC", 0, 0
	.db	'c', "(BC)"
	.db	'a', "AF", 0, 0
	.db	'f', "AF'", 0
	.db	'X', "IX", 0, 0
	.db	'Y', "IY", 0, 0
	.db	'x', "(IX)"		; always come with displacement
	.db	'y', "(IY)"		; with JP
	.db	's', "SP", 0, 0
	.db	'p', "(SP)"
; we also need argspecs for the condition flags
	.db	'Z', "Z", 0, 0, 0
	.db	'z', "NZ",   0, 0
	; C is in conflict with the C register. The situation is ambiguous, but
	; doesn't cause actual problems.
	.db	'=', "NC",   0, 0
	.db	'+', "P", 0, 0, 0
	.db	'-', "M", 0, 0, 0
	.db	'1', "PO",   0, 0
	.db	'2', "PE",   0, 0

; argspecs not in the list:
; n -> N
; N -> NN
; m -> (N)  (running out of mnemonics. 'm' for 'memory pointer')
; M -> (NN)

; Groups
; Groups are specified by strings of argspecs. To facilitate jumping to them,
; we have a fixed-sized table. Because most of them are 2 or 4 bytes long, we
; have a table that is 4 in size to minimize consumed space. We treat the two
; groups that take 8 bytes in a special way.
;
; The table below is in order, starting with group 0x01
argGrpTbl:
	.db	"bdha"		; 0x01
	.db	"ZzC="		; 0x02
	.db	"bdhs"		; 0x03
	.db	"bdXs"		; 0x04
	.db	"bdYs"		; 0x05

argGrpCC:
	.db	"zZ=C12+-"	; 0xa
argGrpABCDEHL:
	.db	"BCDEHL_A"	; 0xb

; SPECIAL GROUP "BIT": 0xc
; When special group "0xc" shows up in argspec, it means: accept a number
; between 0 and 7. The value is then treated like a regular group value.

; Each row is 4 bytes wide, fill with zeroes
instrNames:
	.db "ADC", 0
	.db "ADD", 0
	.db "AND", 0
	.db "BIT", 0
	.db "CALL"
	.db "CCF", 0
	.db "CP",0,0
	.db "CPD", 0
	.db "CPDR"
	.db "CPI", 0
	.db "CPIR"
	.db "CPL", 0
	.db "DAA", 0
	.db "DEC", 0
	.db "DI",0,0
	.db "DJNZ"
	.db "EI",0,0
	.db "EX",0,0
	.db "EXX", 0
	.db "HALT"
	.db "IM",0,0
	.db "IN",0,0
	.db "INC", 0
	.db "IND", 0
	.db "INDR"
	.db "INI", 0
	.db "INIR"
	.db "JP",0,0
	.db "JR",0,0
	.db "LD",0,0
	.db "LDD", 0
	.db "LDDR"
	.db "LDI", 0
	.db "LDIR"
	.db "NEG", 0
	.db "NOP", 0
	.db "OR",0,0
	.db "OTDR"
	.db "OTIR"
	.db "OUT", 0
	.db "POP", 0
	.db "PUSH"
	.db "RES", 0
	.db "RET", 0
	.db "RETI"
	.db "RETN"
	.db "RL", 0, 0
	.db "RLA", 0
	.db "RLC", 0
	.db "RLCA"
	.db "RR", 0, 0
	.db "RRA", 0
	.db "RRC", 0
	.db "RRCA"
	.db "RST", 0
	.db "SBC", 0
	.db "SCF", 0
	.db "SET", 0
	.db "SLA", 0
	.db "SRL", 0
	.db "SUB", 0
	.db "XOR", 0

; This is a list of all supported instructions. Each row represent a combination
; of instr/argspecs (which means more than one row per instr). Format:
;
; 1 byte for the instruction ID
; 1 byte for arg constant
; 1 byte for 2nd arg constant
; 1 byte displacement for group arguments + flags
; 2 bytes for upcode (2nd byte is zero if instr is one byte)
;
; An "arg constant" is a char corresponding to either a row in argspecTbl or
; a group index in argGrpTbl (values < 0x10 are considered group indexes).
;
; The displacement bit is split in 2 nibbles: lower nibble is the displacement
; value, upper nibble is for flags:
;
; Bit 7: indicates that the numerical argument is of the 'e' type and has to be
; decreased by 2 (djnz, jr).
; Bit 6: it indicates that the group argument's value is to be placed on the
; second upcode rather than the first.
; Bit 5: Indicates that this row is handled very specially: the next two bytes
; aren't upcode bytes, but a routine address to call to handle this case with
; custom code.
; Bit 4: When in an 'l' argspec, this means "I accept IX and IY variants".

; This table needs to be kept in ascending order of I_* value.
instrTBl:
	.db I_ADC, 'A', 'l', 0,    0x8e		, 0	; ADC A, (HL)
	.db I_ADC, 'A', 0xb, 0,    0b10001000	, 0	; ADC A, r
	.db I_ADC, 'A', 'n', 0,    0xce		, 0	; ADC A, n
	.db I_ADC, 'h', 0x3, 0x44, 0xed, 0b01001010	; ADC HL, ss
	.db I_ADD, 'A', 'l', 0x10, 0x86		, 0	; ADD A, (HL) + (IX/Y)
	.db I_ADD, 'A', 0xb, 0,    0b10000000	, 0	; ADD A, r
	.db I_ADD, 'A', 'n', 0,    0xc6 	, 0	; ADD A, n
	.db I_ADD, 'h', 0x3, 4,    0b00001001 	, 0	; ADD HL, ss
	.db I_ADD, 'X', 0x4, 0x44, 0xdd, 0b00001001	; ADD IX, pp
	.db I_ADD, 'Y', 0x5, 0x44, 0xfd, 0b00001001	; ADD IY, rr
	.db I_AND, 'l', 0,   0x10, 0xa6		, 0	; AND (HL) + (IX/Y)
	.db I_AND, 0xb, 0,   0,    0b10100000	, 0	; AND r
	.db I_AND, 'n', 0,   0,    0xe6		, 0	; AND n
	.db I_BIT, 0xc, 'l', 0x53, 0xcb, 0b01000110	; BIT b, (HL) + (IX/Y)
	.db I_BIT, 0xc, 0xb, 0x20 \ .dw handleBITR	; BIT b, r
	.db I_CALL,0xa, 'N', 3,    0b11000100	, 0	; CALL cc, NN
	.db I_CALL,'N', 0,   0,    0xcd		, 0	; CALL NN
	.db I_CCF, 0,   0,   0,    0x3f		, 0	; CCF
	.db I_CP,  'l', 0,   0x10, 0xbe		, 0	; CP (HL) + (IX/Y)
	.db I_CP,  0xb, 0,   0,    0b10111000	, 0	; CP r
	.db I_CP,  'n', 0,   0,    0xfe		, 0	; CP n
	.db I_CPD, 0,   0,   0,    0xed, 0xa9		; CPD
	.db I_CPDR,0,   0,   0,    0xed, 0xb9		; CPDR
	.db I_CPI, 0,   0,   0,    0xed, 0xa1		; CPI
	.db I_CPIR,0,   0,   0,    0xed, 0xb1		; CPIR
	.db I_CPL, 0,   0,   0,    0x2f		, 0	; CPL
	.db I_DAA, 0,   0,   0,    0x27		, 0	; DAA
	.db I_DEC, 'l', 0,   0x10, 0x35		, 0	; DEC (HL) + (IX/Y)
	.db I_DEC, 'X', 0,   0,    0xdd, 0x2b		; DEC IX
	.db I_DEC, 'Y', 0,   0,    0xfd, 0x2b		; DEC IY
	.db I_DEC, 0xb, 0,   3,    0b00000101	, 0	; DEC r
	.db I_DEC, 0x3, 0,   4,    0b00001011	, 0	; DEC ss
	.db I_DI,  0,   0,   0,    0xf3		, 0	; DI
	.db I_DJNZ,'n', 0,   0x80, 0x10		, 0	; DJNZ e
	.db I_EI,  0,   0,   0,    0xfb		, 0	; EI
instrTBlEX:
	.db I_EX, 'p', 'h',  0,    0xe3		, 0	; EX (SP), HL
	.db I_EX, 'p', 'X',  0,    0xdd, 0xe3		; EX (SP), IX
	.db I_EX, 'p', 'Y',  0,    0xfd, 0xe3		; EX (SP), IY
	.db I_EX, 'a', 'f',  0,    0x08		, 0	; EX AF, AF'
	.db I_EX, 'd', 'h',  0,    0xeb		, 0	; EX DE, HL
	.db I_EXX, 0,   0,   0,    0xd9		, 0	; EXX
	.db I_HALT,0,   0,   0,    0x76		, 0	; HALT
	.db I_IM,  'n', 0,   0x20 \ .dw handleIM	; IM {0,1,2}
	.db I_IN,  'A', 'm', 0,    0xdb		, 0	; IN A, (n)
	.db I_IN,  0xb, 'k', 0x43, 0xed, 0b01000000	; IN r, (C)
	.db I_INC, 'l', 0,   0x10, 0x34		, 0	; INC (HL) + (IX/Y)
	.db I_INC, 'X', 0,   0,    0xdd , 0x23		; INC IX
	.db I_INC, 'Y', 0,   0,    0xfd , 0x23		; INC IY
	.db I_INC, 0xb, 0,   3,    0b00000100	, 0	; INC r
	.db I_INC, 0x3, 0,   4,    0b00000011	, 0	; INC ss
	.db I_IND, 0,   0,   0,    0xed, 0xaa		; IND
	.db I_INDR,0,   0,   0,    0xed, 0xba		; INDR
	.db I_INI, 0,   0,   0,    0xed, 0xa2		; INI
	.db I_INIR,0,   0,   0,    0xed, 0xb2		; INIR
	.db I_JP,  'x', 0,   0x20 \ .dw handleJPIXY	; JP (IX)
	.db I_JP,  'y', 0,   0x20 \ .dw handleJPIXY	; JP (IY)
	.db I_JP,  'l', 0,   0,    0xe9		, 0	; JP (HL)
	.db I_JP,  0xa, 'N', 3,    0b11000010	, 0	; JP cc, NN
	.db I_JP,  'N', 0,   0,    0xc3		, 0	; JP NN
	.db I_JR,  'n', 0,   0x80, 0x18		, 0	; JR e
	.db I_JR,  'C', 'n', 0x80, 0x38		, 0	; JR C, e
	.db I_JR,  '=', 'n', 0x80, 0x30		, 0	; JR NC, e
	.db I_JR,  'Z', 'n', 0x80, 0x28		, 0	; JR Z, e
	.db I_JR,  'z', 'n', 0x80, 0x20		, 0	; JR NZ, e
instrTBlLD:
	.db I_LD,  'c', 'A', 0,    0x02		, 0	; LD (BC), A
	.db I_LD,  'e', 'A', 0,    0x12		, 0	; LD (DE), A
	.db I_LD,  'A', 'c', 0,    0x0a		, 0	; LD A, (BC)
	.db I_LD,  'A', 'e', 0,    0x1a		, 0	; LD A, (DE)
	.db I_LD,  's', 'h', 0,    0xf9		, 0	; LD SP, HL
	.db I_LD,  'A', 'I', 0,    0xed, 0x57		; LD A, I
	.db I_LD,  'I', 'A', 0,    0xed, 0x47		; LD I, A
	.db I_LD,  'A', 'R', 0,    0xed, 0x5f		; LD A, R
	.db I_LD,  'R', 'A', 0,    0xed, 0x4f		; LD R, A
	.db I_LD,  'l', 0xb, 0,    0b01110000	, 0	; LD (HL), r
	.db I_LD,  0xb, 'l', 3,    0b01000110	, 0	; LD r, (HL)
	.db I_LD,  'l', 'n', 0,    0x36		, 0	; LD (HL), n
	.db I_LD,  0xb, 'n', 3,    0b00000110	, 0	; LD r, n
	.db I_LD,  0xb, 0xb, 0x20  \ .dw handleLDrr	; LD r, r'
	.db I_LD,  0x3, 'N', 4,    0b00000001	, 0	; LD dd, nn
	.db I_LD,  'X', 'N', 0,    0xdd, 0x21		; LD IX, NN
	.db I_LD,  'Y', 'N', 0,    0xfd, 0x21		; LD IY, NN
	.db I_LD,  'M', 'A', 0,    0x32		, 0	; LD (NN), A
	.db I_LD,  'A', 'M', 0,    0x3a		, 0	; LD A, (NN)
	.db I_LD,  'M', 'h', 0,    0x22		, 0	; LD (NN), HL
	.db I_LD,  'h', 'M', 0,    0x2a		, 0	; LD HL, (NN)
	.db I_LD,  'M', 'X', 0,    0xdd, 0x22		; LD (NN), IX
	.db I_LD,  'X', 'M', 0,    0xdd, 0x2a		; LD IX, (NN)
	.db I_LD,  'M', 'Y', 0,    0xfd, 0x22		; LD (NN), IY
	.db I_LD,  'Y', 'M', 0,    0xfd, 0x2a		; LD IY, (NN)
	.db I_LD,  'M', 0x3, 0x44, 0xed, 0b01000011	; LD (NN), dd
	.db I_LD,  0x3, 'M', 0x44, 0xed, 0b01001011	; LD dd, (NN)
	.db I_LD,  'x', 'n', 0x20 \ .dw handleLDIXYn	; LD (IX+d), n
	.db I_LD,  'y', 'n', 0x20 \ .dw handleLDIXYn	; LD (IY+d), n
	.db I_LD,  'x', 0xb, 0x20 \ .dw handleLDIXYr	; LD (IX+d), r
	.db I_LD,  'y', 0xb, 0x20 \ .dw handleLDIXYr	; LD (IY+d), r
	.db I_LD,  0xb, 'x', 0x20 \ .dw handleLDrIXY	; LD r, (IX+d)
	.db I_LD,  0xb, 'y', 0x20 \ .dw handleLDrIXY	; LD r, (IY+d)
	.db I_LDD, 0,   0,   0,    0xed, 0xa8		; LDD
	.db I_LDDR,0,   0,   0,    0xed, 0xb8		; LDDR
	.db I_LDI, 0,   0,   0,    0xed, 0xa0		; LDI
	.db I_LDIR,0,   0,   0,    0xed, 0xb0		; LDIR
	.db I_NEG, 0,   0,   0,    0xed, 0x44		; NEG
	.db I_NOP, 0,   0,   0,    0x00		, 0	; NOP
	.db I_OR,  'l', 0,   0x10, 0xb6		, 0	; OR (HL) + (IX/Y)
	.db I_OR,  0xb, 0,   0,    0b10110000	, 0	; OR r
	.db I_OR,  'n', 0,   0,    0xf6		, 0	; OR n
	.db I_OTDR,0,   0,   0,    0xed, 0xbb		; OTDR
	.db I_OTIR,0,   0,   0,    0xed, 0xb3		; OTIR
	.db I_OUT, 'm', 'A', 0,    0xd3		, 0	; OUT (n), A
	.db I_OUT, 'k', 0xb, 0x43, 0xed, 0b01000001	; OUT (C), r
	.db I_POP, 'X', 0,   0,    0xdd, 0xe1		; POP IX
	.db I_POP, 'Y', 0,   0,    0xfd, 0xe1		; POP IY
	.db I_POP, 0x1, 0,   4,    0b11000001	, 0	; POP qq
	.db I_PUSH,'X', 0,   0,    0xdd, 0xe5		; PUSH IX
	.db I_PUSH,'Y', 0,   0,    0xfd, 0xe5		; PUSH IY
	.db I_PUSH,0x1, 0,   4,    0b11000101	, 0	; PUSH qq
	.db I_RES, 0xc, 'l', 0x53, 0xcb, 0b10000110	; RES b, (HL) + (IX/Y)
	.db I_RES, 0xc, 0xb, 0x20 \ .dw handleRESR	; RES b, r
instrTBlRET:
	.db I_RET, 0,   0,   0,    0xc9		, 0	; RET
	.db I_RET, 0xa, 0,   3,    0b11000000	, 0	; RET cc
	.db I_RETI,0,   0,   0,    0xed, 0x4d		; RETI
	.db I_RETN,0,   0,   0,    0xed, 0x45		; RETN
	.db I_RL,  0xb, 0,0x40,    0xcb, 0b00010000	; RL r
	.db I_RL,  'l', 0,0x10,    0xcb, 0b00010110	; RL (HL) + (IX/Y)
	.db I_RLA, 0,   0,   0,    0x17		, 0	; RLA
	.db I_RLC, 0xb, 0,0x40,    0xcb, 0b00000000	; RLC r
	.db I_RLCA,0,   0,   0,    0x07		, 0	; RLCA
	.db I_RR,  0xb, 0,0x40,    0xcb, 0b00011000	; RR r
	.db I_RR,  'l', 0,0x10,    0xcb, 0b00011110	; RR (HL) + (IX/Y)
	.db I_RRA, 0,   0,   0,    0x1f		, 0	; RRA
	.db I_RRC, 0xb, 0,0x40,    0xcb, 0b00001000	; RRC r
	.db I_RRCA,0,   0,   0,    0x0f		, 0	; RRCA
	.db I_RST, 'n', 0, 0x20 \ .dw handleRST		; RST p
	.db I_SBC, 'A', 'l', 0,    0x9e		, 0	; SBC A, (HL)
	.db I_SBC, 'A', 0xb, 0,    0b10011000	, 0	; SBC A, r
	.db I_SBC,'h',0x3,0x44,    0xed, 0b01000010	; SBC HL, ss
	.db I_SCF, 0,   0,   0,    0x37		, 0	; SCF
	.db I_SET, 0xc, 'l', 0x53, 0xcb, 0b11000110	; SET b, (HL) + (IX/Y)
	.db I_SET, 0xc, 0xb, 0x20 \ .dw handleSETR	; SET b, r
	.db I_SLA, 0xb, 0,0x40,    0xcb, 0b00100000	; SLA r
	.db I_SRL, 0xb, 0,0x40,    0xcb, 0b00111000	; SRL r
	.db I_SRL, 'l', 0,0x10,    0xcb, 0b00111110	; SRL (HL) + (IX/Y)
	.db I_SUB, 'l', 0,   0,    0x96		, 0	; SUB (HL)
	.db I_SUB, 0xb, 0,   0,    0b10010000	, 0	; SUB r
	.db I_SUB, 'n', 0,   0,    0xd6 	, 0	; SUB n
	.db I_XOR, 'l', 0,   0,    0xae		, 0	; XOR (HL)
	.db I_XOR, 0xb, 0,   0,    0b10101000	, 0	; XOR r
	.db I_XOR, 'n', 0,   0,    0xee		, 0	; XOR n
	.db 0xff
