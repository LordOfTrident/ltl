import std/[parseutils, strutils]

import vals

const separators = ['(', ')', '$', '`']

type Parser = object
    pos: int
    ch:  char
    src, expanded: string

proc consume(par: var Parser): bool =
    inc par.pos
    if par.pos <= par.src.len:
        par.ch = par.src[par.pos - 1]
        return true

    par.ch = 0.char

proc retreat(par: var Parser) =
    if par.pos > 0:
        dec par.pos

    par.ch = if par.pos < par.src.len: par.src[par.pos] else: 0.char

proc peek(par: var Parser): char =
    if par.pos < par.src.len:
        return par.src[par.pos]

proc isEscaped(par: var Parser): bool =
    if par.pos < 2:
        return false

    var count = 0
    for i in (par.pos - 2).countdown(0):
        if par.src[i] != '\\':
            break
        inc count
    return count mod 2 != 0

proc parseAtom(par: var Parser): Val

proc parseList(par: var Parser): Val =
    result = listVal()
    discard par.consume() # Skip '('
    while par.ch != ')' and par.ch > 0.char:
        if par.ch in Whitespace:
            discard par.consume()
        else:
            result.list &= par.parseAtom()
    discard par.consume() # Skip ')'

proc parseQuoted(par: var Parser): Val =
    result = listVal()
    var raw: string
    while par.consume() and (par.ch != '`' or par.isEscaped()):
        if par.isEscaped():
            case par.ch
            of 'n': raw = raw[0 ..< ^1] & '\n'
            of 't': raw = raw[0 ..< ^1] & '\t'
            else:
                raw &= par.ch
        elif par.ch == '$' and par.peek() == '(':
            discard par.consume()
            if raw.len > 0:
                result.list &= textVal raw
                raw          = ""

            result.list &= par.parseList()
            par.retreat()
        else:
            raw &= par.ch

    discard par.consume() # Skip '`'
    if raw.len > 0:
        result.list &= textVal raw

    if result.list.len == 0:
        return textVal()
    elif result.list.len == 1 and result.list[0].kind == ValText:
        return result.list[0]
    else:
        return listVal(@[textVal "join", textVal ""] & result.list)

proc parsePlain(par: var Parser): Val =
    result = textVal($par.ch)
    while par.consume():
        if par.ch in Whitespace or par.ch in separators:
            break
        result.text &= par.ch

    # TODO: Better number parser
    # These should not be parsed as numbers:
    # +.
    # -.
    # 88x31
    # -88x31
    # +88x31
    var num: BiggestFloat
    if result.text[0] != '.' and result.text.parseBiggestFloat(num) != 0:
        return numVal num.float64

proc parseShortcut(par: var Parser): Val =
    result = listVal(@[textVal()])
    while par.consume():
        if par.ch in Whitespace or par.ch in separators:
            break
        result.list[0].text &= par.ch

proc parseAtom(par: var Parser): Val =
    case par.ch
    of '(': par.parseList()
    of '`': par.parseQuoted()
    of '$': par.parseShortcut()
    else:   par.parsePlain()

proc parse*(input: string): seq[Val] =
    var
        par = Parser(src: input)
        raw: string
    while par.consume():
        if par.ch == '$' and par.peek() == '(' and not par.isEscaped():
            discard par.consume()
            if raw.len > 0:
                result &= textVal raw
                raw     = ""

            result &= par.parseList()
            par.retreat()
        else:
            raw &= par.ch

    if raw.len > 0:
        result &= textVal raw
