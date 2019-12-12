# cfspack

A tool/library to pack files into a CFS blob and unpack a CFS blob into
a directory.

## Usage

To pack a directory into a CFS blob, run:

    cfspack /path/to/directory

The blob is spit to stdout. If there are subdirectories, they will be prefixes
to the filenames under it.

`cfspack` takes optional -p pattern arguments. If specified, only files
matching at least one of the patterns ("fnmatch" style") will be included.

If path is a file, a CFS with a single file will be spit and its name will
exclude the directory part of that filename.

The chain being spitted is always ended with a "stop block" (a zero-allocation
block that stops the CFS chain). You can call `cfspack` with no argument to get
only a stop block.

The program errors out if a file name is too long (> 26 bytes) or too big
(> 0x10000 - 0x20 bytes).

To unpack a blob to a directory:

    cfsunpack /path/to/dest < blob

If destination exists, files are created alongside existing ones. If a file to
unpack already exists, it is overwritten.
