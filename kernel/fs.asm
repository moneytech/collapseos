; fs
;
; Collapse OS filesystem (CFS) is not made to be convenient, but to be simple.
; This is little more than "named storage blocks". Characteristics:
;
; * a filesystem sits upon a blockdev. It needs GetB, PutB, Seek.
; * No directory. Use filename prefix to group.
; * First block of each file has metadata. Others are raw data.
; * No FAT. Files are a chain of blocks of a predefined size. To enumerate
;   files, you go through metadata blocks.
; * Fixed allocation. File size is determined at allocation time and cannot be
;   grown, only shrunk.
; * New allocations try to find spots to fit in, but go at the end if no spot is
;   large enough.
; * Block size is 0x100, max block count per file is 8bit, that means that max
;   file size: 64k - metadata overhead.
;
; *** Selecting a "source" blockdev
;
; This unit exposes "fson" shell command to "mount" CFS upon the currently
; selected device, at the point where its seekptr currently sits. This checks
; if we have a valid first block and spits an error otherwise.
;
; "fson" takes an optional argument which is a number. If non-zero, we don't
; error out if there's no metadata: we create a new CFS fs with an empty block.
;
; The can only be one "mounted" fs at once. Selecting another blockdev through
; "bsel" doesn't affect the currently mounted fs, which can still be interacted
; with (which is important if we want to move data around).
;
; *** Block metadata
;
; At the beginning of the first block of each file, there is this data
; structure:
;
; 3b: Magic number "CFS"
; 1b: Allocated block count, including the first one. Except for the "ending"
;     block, this is never zero.
; 2b: Size of file in bytes (actually written). Little endian.
; 26b: file name, null terminated. last byte must be null.
;
; That gives us 32 bytes of metadata for first first block, leaving a maximum
; file size of 0xffe0.
;
; *** Last block of the chain
;
; The last block of the chain is either a block that has no valid block next to
; it or a block that reports a 0 allocated block count.
;
; However, to simplify processing, whenever fsNext encounter a chain end of the
; first type (a valid block with > 0 allocated blocks), it places an empty block
; at the end of the chain. This makes the whole "end of chain" processing much
; easier: we assume that we always have a 0 block at the end.
;
; *** Deleted files
;
; When a file is deleted, its name is set to null. This indicates that the
; allocated space is up for grabs.
;
; *** File "handles"
;
; Programs will not typically open files themselves. How it works with CFS is
; that it exposes an API to plug target files in a blockdev ID. This all
; depends on how you glue parts together, but ideally, you'll have two
; fs-related blockdev IDs: one for reading, one for writing.
;
; Being plugged into the blockdev system, programs will access the files as they
; would with any other block device.
;
; *** Creating a new FS
;
; A valid Collapse OS filesystem is nothing more than the 3 bytes 'C', 'F', 'S'
; next to each other. Placing them at the right place is all you have to do to
; create your FS.

; *** DEFINES ***
; Number of handles we want to support
; FS_HANDLE_COUNT
;
; *** VARIABLES ***
; A copy of BLOCKDEV_SEL when the FS was mounted. 0 if no FS is mounted.
.equ	FS_BLK		FS_RAMSTART
; Offset at which our FS start on mounted device
; This pointer is 32 bits. 32 bits pointers are a bit awkward: first two bytes
; are high bytes *low byte first*, and then the low two bytes, same order.
; When loaded in HL/DE, the four bytes are loaded in this order: E, D, L, H
.equ	FS_START	@+BLOCKDEV_SIZE
; This variable below contain the metadata of the last block we moved
; to. We read this data in memory to avoid constant seek+read operations.
.equ	FS_META		@+4
.equ	FS_HANDLES	@+FS_METASIZE
.equ	FS_RAMEND	@+FS_HANDLE_COUNT*FS_HANDLE_SIZE

; *** DATA ***
P_FS_MAGIC:
	.db	"CFS", 0

; *** CODE ***

fsInit:
	xor	a
	ld	hl, FS_BLK
	ld	b, FS_RAMEND-FS_BLK
	jp	fill

; *** Navigation ***

; Seek to the beginning. Errors out if no FS is mounted.
; Sets Z if success, unset if error
fsBegin:
	call	fsIsOn
	ret	nz
	push	hl
	push	de
	push	af
	ld	de, (FS_START)
	ld	hl, (FS_START+2)
	ld	a, BLOCKDEV_SEEK_ABSOLUTE
	call	fsblkSeek
	pop	af
	pop	de
	pop	hl
	call	fsReadMeta
	jp	fsIsValid	; sets Z, returns

; Change current position to the next block with metadata. If it can't (if this
; is the last valid block), doesn't move.
; Sets Z according to whether we moved.
fsNext:
	push	bc
	push	hl
	ld	a, (FS_META+FS_META_ALLOC_OFFSET)
	or	a		; cp 0
	jr	z, .error	; if our block allocates 0 blocks, this is the
				; end of the line.
	ld	b, a		; we will seek A times
.loop:
	ld	a, BLOCKDEV_SEEK_FORWARD
	ld	hl, FS_BLOCKSIZE
	call	fsblkSeek
	djnz	.loop
	call	fsReadMeta
	jr	nz, .createChainEnd
	call	fsIsValid
	jr	nz, .createChainEnd
	; We're good! We have a valid FS block.
	; Meta is already read. Nothing to do!
	cp	a	; ensure Z
	jr	.end
.createChainEnd:
	; We are on an invalid block where a valid block should be. This is
	; the end of the line, but we should mark it a bit more explicitly.
	; Let's initialize an empty block
	call	fsInitMeta
	call	fsWriteMeta
	; continue out to error condition: we're still at the end of the line.
.error:
	call	unsetZ
.end:
	pop	hl
	pop	bc
	ret

; Reads metadata at current fsblk and place it in FS_META.
; Returns Z according to whether the operation succeeded.
fsReadMeta:
	push	bc
	push	hl
	ld	b, FS_METASIZE
	ld	hl, FS_META
	call	fsblkRead	; Sets Z
	pop	hl
	pop	bc
	ret	nz
	; Only rewind on success
	jr	_fsRewindAfterMeta

; Writes metadata in FS_META at current fsblk.
; Returns Z according to whether the fsblkWrite operation succeeded.
fsWriteMeta:
	push	bc
	push	hl
	ld	b, FS_METASIZE
	ld	hl, FS_META
	call	fsblkWrite	; Sets Z
	pop	hl
	pop	bc
	ret	nz
	; Only rewind on success
	jr	_fsRewindAfterMeta

_fsRewindAfterMeta:
	; return back to before the read op
	push	af
	push	hl
	ld	a, BLOCKDEV_SEEK_BACKWARD
	ld	hl, FS_METASIZE
	call	fsblkSeek
	pop	hl
	pop	af
	ret

; Initializes FS_META with "CFS" followed by zeroes
fsInitMeta:
	push	af
	push	bc
	push	de
	push	hl
	ld	hl, P_FS_MAGIC
	ld	de, FS_META
	ld	bc, 3
	ldir
	xor	a
	ld	hl, FS_META+3
	ld	b, FS_METASIZE-3
	call	fill
	pop	hl
	pop	de
	pop	bc
	pop	af
	ret

; Create a new file with A blocks allocated to it and with its new name at
; (HL).
; Before doing so, enumerate all blocks in search of a deleted file with
; allocated space big enough. If it does, it will either take the whole space
; if the allocated space asked is exactly the same, or of it isn't, split the
; free space in 2 and create a new deleted metadata block next to the newly
; created block.
; Places fsblk to the newly allocated block. You have to write the new
; filename yourself.
fsAlloc:
	push	bc
	push	de
	ld	c, a		; Let's store our A arg somewhere...
	call	fsBegin
	jr	nz, .end	; not a valid block? hum, something's wrong
	; First step: find last block
	push	hl		; keep HL for later
.loop1:
	call	fsNext
	jr	nz, .found	; end of the line
	call	fsIsDeleted
	jr	nz, .loop1	; not deleted? loop
	; This is a deleted block. Maybe it fits...
	ld	a, (FS_META+FS_META_ALLOC_OFFSET)
	cp	c		; Same as asked size?
	jr	z, .found	; yes? great!
	; TODO: handle case where C < A (block splitting)
	jr	.loop1
.found:
	; We've reached last block. Two situations are possible at this point:
	; 1 - the block is the "end of line" block
	; 2 - the block is a deleted block that we we're re-using.
	; In both case, the processing is the same: write new metadata.
	; At this point, the blockdev is placed right where we want to allocate
	; But first, let's prepare the FS_META we're going to write
	call	fsInitMeta
	ld	a, c		; C == the number of blocks user asked for
	ld	(FS_META+FS_META_ALLOC_OFFSET), a
	pop	hl		; now we want our HL arg
	; TODO: stop after null char. we're filling meta with garbage here.
	ld	de, FS_META+FS_META_FNAME_OFFSET
	ld	bc, FS_MAX_NAME_SIZE
	ldir
	; Good, FS_META ready.
	; Ok, now we can write our metadata
	call	fsWriteMeta
.end:
	pop	de
	pop	bc
	ret

; Place fsblk to the filename with the name in (HL).
; Sets Z on success, unset when not found.
fsFindFN:
	push	de
	call	fsBegin
	jr	nz, .end	; nothing to find, Z is unset
	ld	a, FS_MAX_NAME_SIZE
.loop:
	ld	de, FS_META+FS_META_FNAME_OFFSET
	call	strncmp
	jr	z, .end		; Z is set
	call	fsNext
	jr	z, .loop
	; End of the chain, not found
	; Z already unset
.end:
	pop	de
	ret

; *** Metadata ***

; Sets Z according to whether the current block in FS_META is valid.
; Don't call other FS routines without checking block validity first: other
; routines don't do checks.
fsIsValid:
	push	hl
	push	de
	ld	a, 3
	ld	hl, FS_META
	ld	de, P_FS_MAGIC
	call	strncmp
	; The result of Z is our result.
	pop	de
	pop	hl
	ret

; Returns whether current block is deleted in Z flag.
fsIsDeleted:
	ld	a, (FS_META+FS_META_FNAME_OFFSET)
	or	a	; Z flag is our answer
	ret

; *** blkdev methods ***
; When "mounting" a FS, we copy the current blkdev's routine privately so that
; we can still access the FS even if blkdev selection changes. These routines
; below mimic blkdev's methods, but for our private mount.

fsblkGetB:
	push	ix
	ld	ix, FS_BLK
	call	_blkGetB
	pop	ix
	ret

fsblkRead:
	push	ix
	ld	ix, FS_BLK
	call	_blkRead
	pop	ix
	ret

fsblkPutB:
	push	ix
	ld	ix, FS_BLK
	call	_blkPutB
	pop	ix
	ret

fsblkWrite:
	push	ix
	ld	ix, FS_BLK
	call	_blkWrite
	pop	ix
	ret

fsblkSeek:
	push	ix
	ld	ix, FS_BLK
	call	_blkSeek
	pop	ix
	ret

fsblkTell:
	push	ix
	ld	ix, FS_BLK
	call	_blkTell
	pop	ix
	ret

; *** Handling ***

; Open file at current position into handle at (IX)
fsOpen:
	push	hl
	push	af
	; Starting pos
	ld	a, (FS_BLK+4)
	ld	(ix), a
	ld	a, (FS_BLK+5)
	ld	(ix+1), a
	ld	a, (FS_BLK+6)
	ld	(ix+2), a
	ld	a, (FS_BLK+7)
	ld	(ix+3), a
	; file size
	ld      hl, (FS_META+FS_META_FSIZE_OFFSET)
	ld	(ix+4), l
	ld	(ix+5), h
	pop	af
	pop	hl
	ret

; Place FS blockdev at proper position for file handle in (IX) at position HL.
fsPlaceH:
	push	af
	push	de
	push	hl
	; Move fsdev to beginning of block
	ld	e, (ix)
	ld	d, (ix+1)
	ld	l, (ix+2)
	ld	h, (ix+3)
	ld	a, BLOCKDEV_SEEK_ABSOLUTE
	call	fsblkSeek

	; skip metadata
	ld	a, BLOCKDEV_SEEK_FORWARD
	ld	hl, FS_METASIZE
	call	fsblkSeek

	pop	hl
	pop	de

	; go to specified pos
	ld	a, BLOCKDEV_SEEK_FORWARD
	call	fsblkSeek
	pop	af
	ret

; Sets Z according to whether HL is within bounds for file handle at (IX), that
; is, if it is smaller than file size.
fsWithinBounds:
	push	de
	; file size
	ld	e, (ix+4)
	ld	d, (ix+5)
	call	cpHLDE
	pop	de
	jr	nc, .outOfBounds	; HL >= DE
	cp	a			; ensure Z
	ret
.outOfBounds:
	jp	unsetZ			; returns

; Set size of file handle (IX) to value in HL.
; This writes directly in handle's metadata.
fsSetSize:
	push	hl		; --> lvl 1
	ld	hl, 0
	call	fsPlaceH	; fs blkdev is now at beginning of content
	; we need the blkdev to be on filesize's offset
	ld	hl, FS_METASIZE-FS_META_FSIZE_OFFSET
	ld	a, BLOCKDEV_SEEK_BACKWARD
	call	fsblkSeek
	pop	hl		; <-- lvl 1
	; blkdev is at the right spot, HL is back to its original value, let's
	; write it both in the metadata block and in its file handle's cache.
	push	hl		; --> lvl 1
	; now let's write our new filesize both in blkdev and in file handle's
	; cache.
	ld	a, l
	ld	(ix+4), a
	call	fsblkPutB
	ld	a, h
	ld	(ix+5), a
	call	fsblkPutB
	pop	hl		; <-- lvl 1
	xor	a	; ensure Z
	ret

; Read a byte in handle at (IX) at position HL and put it into A.
; Z is set on success, unset if handle is at the end of the file.
fsGetB:
	call	fsWithinBounds
	jr	z, .proceed
	; We want to unset Z, but also return 0 to ensure that a GetB that
	; doesn't check Z doesn't end up with false data.
	xor	a
	jp	unsetZ		; returns
.proceed:
	push	hl
	call	fsPlaceH
	call	fsblkGetB
	cp	a		; ensure Z
	pop	hl
	ret

; Write byte A in handle (IX) at position HL.
; Z is set on success, unset if handle is at the end of the file.
; TODO: detect end of block alloc
fsPutB:
	push	hl
	call	fsPlaceH
	call	fsblkPutB
	pop	hl
	; if HL is out of bounds, increase bounds
	call	fsWithinBounds
	ret	z
	inc	hl		; our filesize is now HL+1
	jp	fsSetSize

; Mount the fs subsystem upon the currently selected blockdev at current offset.
; Verify is block is valid and error out if its not, mounting nothing.
; Upon mounting, copy currently selected device in FS_BLK.
fsOn:
	push	hl
	push	de
	push	bc
	; We have to set blkdev routines early before knowing whether the
	; mounting succeeds because methods like fsReadMeta uses fsblk* methods.
	ld	hl, BLOCKDEV_SEL
	ld	de, FS_BLK
	ld	bc, BLOCKDEV_SIZE
	ldir			; copy!
	call	fsblkTell
	ld	(FS_START), de
	ld	(FS_START+2), hl
	call	fsReadMeta
	jr	nz, .error
	call	fsIsValid
	jr	nz, .error
	; success
	xor	a
	jr	.end
.error:
	; couldn't mount. Let's reset our variables.
	call	fsInit
	ld	a, FS_ERR_NO_FS
	or	a	; unset Z
.end:
	pop	bc
	pop	de
	pop	hl
	ret

; Sets Z according to whether we have a filesystem mounted.
fsIsOn:
	; check whether (FS_BLK) is zero
	push	hl
	ld	hl, (FS_BLK)
	ld	a, h
	or	l
	jr	nz, .mounted
	; not mounted, unset Z
	inc	a
	jr	.end
.mounted:
	cp	a	; ensure Z
.end:
	pop	hl
	ret

; Iterate over files in active file system and, for each file, call (IY) with
; the file's metadata currently placed. HL is set to FS_META.
; Sets Z on success, unset on error.
; There are no error condition happening midway. If you get an error, then (IY)
; was never called.
fsIter:
	call	fsBegin
	ret	nz
.loop:
	call	fsIsDeleted
	ld	hl, FS_META
	call	nz, callIY
	call	fsNext
	jr	z, .loop	; Z set? fsNext was successful
	cp	a		; ensure Z
	ret

; Delete currently active file
; Sets Z on success, unset on error.
fsDel:
	call	fsIsValid
	ret	nz
	xor	a
	; Set filename to zero to flag it as deleted
	ld	(FS_META+FS_META_FNAME_OFFSET), a
	jp	fsWriteMeta

; Given a handle index in A, set DE to point to the proper handle.
fsHandle:
	ld	de, FS_HANDLES
	or	a		; cp 0
	ret	z	; DE already point to correct handle
	push	bc
	ld	b, a
.loop:
	ld	a, FS_HANDLE_SIZE
	call	addDE
	djnz	.loop
	pop	bc
	ret
