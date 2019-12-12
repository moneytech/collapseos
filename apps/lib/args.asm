; *** Requirements ***
; lib/parse
;
; *** Consts ***
; maximum number of bytes to receive as args in all commands. Determines the
; size of the args variable.
.equ	PARSE_ARG_MAXCOUNT	3

; *** Code ***

; Parse arguments at (HL) with specifiers at (DE) into (IX).
;
; Args specifiers are a series of flag for each arg:
; Bit 0 - arg present: if unset, we stop parsing there
; Bit 1 - is word: this arg is a word rather than a byte. Because our
;                  destination are bytes anyway, this doesn't change much except
;                  for whether we expect a space between the hex pairs. If set,
;                  you still need to have a specifier for the second part of
;                  the multibyte.
; Bit 2 - optional: If set and not present during parsing, we don't error out
;		    and write zero
;
; Bit 3 - String argument: If set, this argument is a string. A pointer to the
;                          read string, null terminated (max 0x20 chars) will
;                          be placed in the next two bytes. This has to be the
;                          last argument of the list and it stops parsing.
; Sets A to nonzero if there was an error during parsing, zero otherwise.
parseArgs:
	push	bc
	push	de
	push	hl
	push	ix

	; init the arg value to a default 0
	xor	a
	ld	(ix), a
	ld	(ix+1), a
	ld	(ix+2), a
	ld	b, PARSE_ARG_MAXCOUNT
.loop:
	ld	a, (hl)
	; is this the end of the line?
	or	a		; cp 0
	jr	z, .endofargs

	; Get the specs
	ld	a, (de)
	bit	0, a		; do we have an arg?
	jr	z, .error	; not set? then we have too many args

	ld	c, a		; save the specs for multibyte check later
	bit	3, a		; is our arg a string?
	jr	z, .notAString
	; our arg is a string. Let's place HL in our next two bytes and call
	; it a day. Little endian, remember
	ld	(ix), l
	ld	(ix+1), h
	jr	.success	; directly to success: skip endofargs checks

.notAString:
	call	parseHexPair
	jr	c, .error

	; we have a good arg and we need to write A in (IX).
	ld	(ix), a

	; Good! increase counters
	inc	de
	inc	ix
	inc	hl		; get to following char (generally a space)

	; Our arg is parsed, our pointers are increased. Normally, HL should
	; point to a space *unless* our argspec indicates a multibyte arg.
	bit	1, c
	jr	nz, .nospacecheck	; bit set? no space check
	; do we have a proper space char (or null char)?
	ld	a, (hl)
	or	a
	jr	z, .endofargs
	cp	' '
	jr	nz, .error
	inc	hl
.nospacecheck:
	djnz	.loop
	; If we get here, it means that our next char *has* to be a null char
	ld	a, (hl)
	or	a		; cp 0
	jr	z, .success	; zero? great!
	jr	.error

.endofargs:
	; We encountered our null char. Let's verify that we either have no
	; more args or that they are optional
	ld	a, (de)
	or	a
	jr	z, .success	; no arg? success
	bit	2, a
	jr	z, .error	; if unset, arg is not optional. error
	; success
.success:
	xor	a
	jr	.end
.error:
	inc	a
.end:
	pop	ix
	pop	hl
	pop	de
	pop	bc
	ret

