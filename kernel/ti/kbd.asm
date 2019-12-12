; kbd
;
; Control TI-84+'s keyboard.
;
; *** Constants ***
.equ	KBD_PORT	0x01

; Keys that have a special meaning in GetC. All >= 0x80. They are interpreted
; by GetC directly and are never returned as-is.
.equ	KBD_KEY_ALPHA	0x80
.equ	KBD_KEY_2ND	0x81

; *** Variables ***
; active long-term modifiers, such as a-lock
; bit 0: A-Lock
.equ	KBD_MODS	KBD_RAMSTART
.equ	KBD_RAMEND	@+1

; *** Code ***

kbdInit:
	ld	a, 1		; begin with A-Lock on
	ld	(KBD_MODS), a
	ret

; Wait for a digit to be pressed and sets the A register ASCII value
; corresponding to that key press.
;
; This routine waits for a key to be pressed, but before that, it waits for
; all keys to be de-pressed. It does that to ensure that two calls to
; waitForKey only go through after two actual key presses (otherwise, the user
; doesn't have enough time to de-press the button before the next waitForKey
; routine registers the same key press as a second one).
;
; Sending 0xff to the port resets the keyboard, and then we have to send groups
; we want to "listen" to, with a 0 in the group bit. Thus, to know if *any* key
; is pressed, we send 0xff to reset the keypad, then 0x00 to select all groups,
; if the result isn't 0xff, at least one key is pressed.
kbdGetC:
	push	bc
	push	hl

	; During this GetC loop, register C holds the modificators
	; bit 0: Alpha
	; bit 1: 2nd
	; Initial value should be zero, but if A-Lock is on, it's 1
	ld	a, (KBD_MODS)
	and	1
	ld	c, a

	; loop until a digit is pressed
.loop:
	ld	hl, .dtbl
	; we go through the 7 rows of the table
	ld	b, 7
	; is alpha mod enabled?
	bit	0, c
	jr	z, .inner	; unset? skip next
	ld	hl, .atbl	; set? we're in alpha mode
.inner:
	ld	a, (hl)		; group mask
	call	.get
	cp	0xff
	jr	nz, .something
	; nothing for that group, let's scan the next group
	ld	a, 9
	call	addHL		; go to next row
	djnz	.inner
	; found nothing, loop
	jr	.loop
.something:
	; We have something on that row! Let's find out which char. Register A
	; currently contains a mask with the pressed char bit unset.
	ld	b, 8
	inc	hl
.findchar:
	rrca			; is next bit unset?
	jr	nc, .gotit	; yes? we have our char!
	inc	hl
	djnz	.findchar
.gotit:
	ld	a, (hl)
	or	a		; is char 0?
	jr	z, .loop	; yes? unsupported. loop.
	call	.debounce
	cp	KBD_KEY_ALPHA
	jr	c, .result	; A < 0x80? valid char, return it.
	jr	z, .handleAlpha
	cp	KBD_KEY_2ND
	jr	z, .handle2nd
	jp	.loop
.handleAlpha:
	; Toggle Alpha bit in C. Also, if 2ND bit is set, toggle A-Lock mod.
	ld	a, 1	; mask for Alpha
	xor	c
	ld	c, a
	bit	1, c		; 2nd set?
	jp	z, .loop	; unset? loop
	; we've just hit Alpha with 2nd set. Toggle A-Lock and set Alpha to
	; the value A-Lock has.
	ld	a, (KBD_MODS)
	xor	1
	ld	(KBD_MODS), a
	ld	c, a
	jp	.loop
.handle2nd:
	; toggle 2ND bit in C
	ld	a, 2	; mask for 2ND
	xor	c
	ld	c, a
	jp	.loop

.result:
	; We have our result in A, *almost* time to return it. One last thing:
	; Are in in both Alpha and 2nd mode? If yes, then it means that we
	; should return the upcase version of our letter (if it's a letter).
	bit	0, c
	jr	z, .end		; nope
	bit	1, c
	jr	z, .end		; nope
	; yup, we have Alpha + 2nd. Upcase!
	call	upcase
.end:
	pop	hl
	pop	bc
	ret
.get:
	ex	af, af'
	ld	a, 0xff
	di
	out	(KBD_PORT), a
	ex	af, af'
	out	(KBD_PORT), a
	in	a, (KBD_PORT)
	ei
	ret
.debounce:
	; wait until all keys are de-pressed
	; To avoid repeat keys, we require 64 subsequent polls to indicate all
	; depressed keys
	push	af		; --> lvl 1
	push	bc		; --> lvl 2
.pressed:
	ld	b, 64
.wait:
	xor	a
	call	.get
	inc	a		; if a was 0xff, will become 0 (nz test)
	jr	nz, .pressed	; non-zero? something is pressed
	djnz	.wait

	pop	bc		; <-- lvl 2
	pop	af		; <-- lvl 1
	ret

; digits table. each row represents a group. first item is group mask.
; 0 means unsupported. no group 7 because it has no keys.
.dtbl:
	.db	0xfe, 0, 0, 0, 0, 0, 0, 0, 0
	.db	0xfd, 0x0d, '+' ,'-' ,'*', '/', '^', 0, 0
	.db	0xfb, 0, '3', '6', '9', ')', 0, 0, 0
	.db	0xf7, '.', '2', '5', '8', '(', 0, 0, 0
	.db	0xef, '0', '1', '4', '7', ',', 0, 0, 0
	.db	0xdf, 0, 0, 0, 0, 0, 0, 0, KBD_KEY_ALPHA
	.db	0xbf, 0, 0, 0, 0, 0, KBD_KEY_2ND, 0, 0x7f

; alpha table. same as .dtbl, for when we're in alpha mode.
.atbl:
	.db	0xfe, 0, 0, 0, 0, 0, 0, 0, 0
	.db	0xfd, 0x0d, '"' ,'w' ,'r', 'm', 'h', 0, 0
	.db	0xfb, '?', 0, 'v', 'q', 'l', 'g', 0, 0
	.db	0xf7, ':', 'z', 'u', 'p', 'k', 'f', 'c', 0
	.db	0xef, ' ', 'y', 't', 'o', 'j', 'e', 'b', 0
	.db	0xdf, 0, 'x', 's', 'n', 'i', 'd', 'a', KBD_KEY_ALPHA
	.db	0xbf, 0, 0, 0, 0, 0, KBD_KEY_2ND, 0, 0x7f
