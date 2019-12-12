#!/usr/bin/env python3
# Generate almost all possible combination for instructions from instruction
# tables
# When zasm supported instructions change, use this script to update
# allinstrs.asm

import sys

argspecTbl = {
    'A': "A",
    'B': "B",
    'C': "C",
    'k': "(C)",
    'D': "D",
    'E': "E",
    'H': "H",
    'L': "L",
    'I': "I",
    'R': "R",
    'h': "HL",
    'l': "(HL)",
    'd': "DE",
    'e': "(DE)",
    'b': "BC",
    'c': "(BC)",
    'a': "AF",
    'f': "AF'",
    'X': "IX",
    'x': "(IX)",
    'Y': "IY",
    'y': "(IY)",
    's': "SP",
    'p': "(SP)",
    'Z': "Z",
    'z': "NZ",
    '=': "NC",
    '+': "P",
    '-': "M",
    '1': "PO",
    '2': "PE",
}

argGrpTbl = {
    chr(0x01): "bdha",
    chr(0x02): "ZzC=",
    chr(0x03): "bdhs",
    chr(0x04): "bdXs",
    chr(0x05): "bdYs",
    chr(0x0a): "ZzC=+-12",
    chr(0x0b): "BCDEHLA",
}

# whenever we encounter the "(HL)" version of these instructions, spit IX/IY
# too.
instrsWithIXY = {
    'ADD', 'AND', 'BIT', 'CP', 'DEC', 'INC', 'OR', 'RES', 'RL', 'RR', 'SET',
    'SRL'}

def cleanupLine(line):
    line = line.strip()
    idx = line.rfind(';')
    if idx >= 0:
        line = line[:idx]
    return line

def getDbLines(fp, tblname):
    lookingFor = f"{tblname}:"
    line = fp.readline()
    while line:
        line = cleanupLine(line)
        if line == lookingFor:
            break
        line = fp.readline()
    else:
        raise Exception(f"{tblname} not found")

    result = []
    line = fp.readline()
    while line:
        line = cleanupLine(line)
        if line == '.db 0xff':
            break
        # skip index labels lines
        if line.startswith('.db'):
            result.append([s.strip() for s in line[4:].split(',')])
        line = fp.readline()
    return result

def genargs(argspec):
    if not argspec:
        return ''
    if not isinstance(argspec, str):
        argspec = chr(argspec)
    if argspec in 'nmNM':
        bits = 16 if argspec in 'NM' else 8
        nbs = [str(1 << i) for i in range(bits)]
        if argspec in 'mM':
            nbs = [f"({n})" for n in nbs]
        return nbs
    if argspec in 'xy':
        # IX/IY displacement is special
        base = argspecTbl[argspec]
        result = [base]
        argspec = argspec.upper()
        for n in [1, 10, 100, 127]:
            result.append(f"(I{argspec}+{n})")
            result.append(f"(I{argspec}-{n})")
        return result
    if argspec in argspecTbl:
        return [argspecTbl[argspec]]
    if argspec == chr(0xc): # special BIT "b" group
        return ['0', '3', '7']
    grp = argGrpTbl[argspec]
    return [argspecTbl[a] for a in grp]

# process a 'n' arg into an 'e' one
def eargs(args):
    newargs = ['$+'+s for s in args[:-1]]
    return newargs + ['$-'+s for s in args[:-1]]

def main():
    asmfile = sys.argv[1]
    with open(asmfile, 'rt') as fp:
        instrTbl = getDbLines(fp, 'instrTBl')
    for row in instrTbl:
        n = row[0][2:] # remove I_
        # we need to adjust for zero-char name filling
        a1 = eval(row[1])
        a2 = eval(row[2])
        args1 = genargs(a1)
        # special case handling
        if n in instrsWithIXY and a1 == 'l':
            args1 += genargs('x')
            args1 += genargs('y')

        if n == 'JP' and isinstance(a1, str) and a1 in 'xy':
            # we don't test the displacements for IX/IY because there can't be
            # any.
            args1 = args1[:1]
        if n in {'JR', 'DJNZ'} and a1 == 'n':
            args1 = eargs(args1)
        if n == 'IM':
            args1 = [0, 1, 2]
        if n == 'RST':
            args1 = [i*8 for i in range(8)]
        if args1:
            for arg1 in args1:
                args2 = genargs(a2)
                if n in instrsWithIXY and a2 == 'l':
                    args2 += genargs('x')
                    args2 += genargs('y')
                if args2:
                    if n in {'JR', 'DJNZ'} and a2 == 'n':
                        args2 = eargs(args2)
                    for arg2 in args2:
                        print(f"{n} {arg1}, {arg2}")
                else:
                    print(f"{n} {arg1}")
        else:
            print(n)
    pass

if __name__ == '__main__':
    main()
