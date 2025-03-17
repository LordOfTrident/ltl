# TODO: Refactor + cltl (LTL interpreter in C)

import std/[tables, times, strformat, os, math, sequtils, strutils]

import parser, vals

type
    SymKind = enum
        SymFn
        SymVal

    Fn  = proc (env: var Env, args: seq[Val]): Val
    Sym = object
        case kind: SymKind
        of SymFn: fn: Fn
        of SymVal:
            val:    Val
            params: seq[string]
            eval:   bool

    Env* = object
        expanded*: string
        syms:      seq[Table[string, Sym]]
        noOutput:  bool

iterator ritems*[T](xs: openarray[T]): T {.inline.} =
    var i = xs.len - 1
    while i > -1:
        yield xs[i]
        dec i

proc expand*(env: var Env, input: string): string
proc newEnv*(output: string): Env
proc eval(env: var Env, val: Val): Val

proc beginScope(env: var Env) = env.syms &= Table[string, Sym]()
proc endScope  (env: var Env) = discard env.syms.pop()

proc setSym(env: var Env, name: string, val: Val, params = seq[string](@[]),
            idx = 0, eval = false) =
    env.syms[idx][name] = Sym(
        kind:   SymVal,
        val:    val,
        params: params,
        eval:   eval,
    )

proc defSym(env: var Env, name: string, val: Val, params = seq[string](@[])) =
    env.setSym(name, val, params, eval = true)

proc paramSym(env: var Env, name: string, val: Val) = env.setSym(name, val, idx = env.syms.len - 1)
proc ourSym  (env: var Env, name: string, val: Val) = env.setSym(name, env.eval(val))
proc mySym   (env: var Env, name: string, val: Val) =
    env.setSym(name, env.eval(val), idx = env.syms.len - 1)

proc callSym(env: var Env, sym: Sym, args: seq[Val]): Val =
    case sym.kind
    of SymFn: return sym.fn(env, args)
    of SymVal:
        var evaledArgs = newSeq[Val](args.len)
        for i, arg in args:
            evaledArgs[i] = env.eval(arg)

        env.beginScope()
        defer: env.endScope()
        for i, param in sym.params:
            env.paramSym(param, if i < evaledArgs.len: evaledArgs[i] else: textVal())
        return if sym.eval: env.eval(sym.val) else: sym.val

proc eval(env: var Env, val: Val): Val =
    case val.kind
    of ValText, ValNum, ValMap: return val
    of ValList:
        if val.list.len == 0:
            return

        let
            name = $env.eval(val.list[0])
            args = val.list[1 .. ^1]
        for i in (env.syms.len - 1).countdown(0):
            if name in env.syms[i]:
                return env.callSym(env.syms[i][name], args)

        return

proc getArg(args: seq[Val], idx: int): Val = (if idx < args.len: args[idx] else: textVal())

proc builtinDo(env: var Env, args: seq[Val]): Val =
    env.beginScope()
    defer: env.endScope()

    for arg in args:
        result = env.eval(arg)

proc builtinList(env: var Env, args: seq[Val]): Val =
    result = listVal()
    for arg in args:
        result.list &= env.eval(arg)

proc builtinMap(env: var Env, args: seq[Val]): Val =
    result = mapVal()
    for i in 0 .. (args.len - 1) div 2:
        let
            key = $env.eval(args[i * 2])
            val = env.eval(args[i * 2 + 1])
        if i + 1 >= args.len:
            result.map[key] = textVal()
            break
        result.map[key] = val

proc builtinEcho(env: var Env, args: seq[Val]): Val =
    for arg in args:
        echo env.eval(arg)

proc builtinInt(env: var Env, args: seq[Val]): Val =
    textVal $env.eval(args.getArg(0)).numify().BiggestInt

proc builtinBool(env: var Env, args: seq[Val]): Val =
    textVal(if env.eval(args.getArg(0)).numify() == 0: "false" else: "true")

proc builtinExists(env: var Env, args: seq[Val]): Val =
    for arg in args:
        let name  = $env.eval(arg)
        var found = false
        for i in (env.syms.len - 1).countdown(0):
            if name in env.syms[i]:
                found = true
                break
        if not found:
            return falseVal
    return trueVal

proc builtinFor(env: var Env, args: seq[Val]): Val =
    env.beginScope()
    defer: env.endScope()

    result = listVal()
    let
        numName = $env.eval(args.getArg(0))
        first   = env.eval(args.getArg(1)).numify()
        last    = env.eval(args.getArg(2)).numify()
        step    = env.eval(args.getArg(3)).numify()
        body    = args.getArg(4)
    var n = first
    while (if step > 0: n <= last else: n >= last):
        env.paramSym(numName, numVal n)
        result.list &= env.eval(body)
        n += step

proc builtinEach(env: var Env, args: seq[Val]): Val =
    env.beginScope()
    defer: env.endScope()

    result = listVal()
    let
        keyName = $env.eval(args.getArg(0))
        valName = $env.eval(args.getArg(1))
        subject = env.eval(args.getArg(2))
        body    = args.getArg(3)
    case subject.kind
    of ValText, ValNum:
        for i, v in (if subject.kind == ValText: subject.text else: $subject.num):
            env.paramSym(keyName, numVal  i.BiggestFloat)
            env.paramSym(valName, textVal $v)
            result.list &= env.eval(body)
    of ValList:
        for i, v in subject.list:
            env.paramSym(keyName, numVal i.BiggestFloat)
            env.paramSym(valName, v)
            result.list &= env.eval(body)
    of ValMap:
        for i, v in subject.map:
            env.paramSym(keyName, textVal i)
            env.paramSym(valName, v)
            result.list &= env.eval(body)

proc builtinIf(env: var Env, args: seq[Val]): Val =
    if env.eval(args.getArg(0)).numify() != 0:
        return env.eval(args.getArg(1))
    else:
        return env.eval(args.getArg(2))

proc builtinUnless(env: var Env, args: seq[Val]): Val =
    if env.eval(args.getArg(0)).numify() == 0:
        return env.eval(args.getArg(1))
    else:
        return env.eval(args.getArg(2))

proc builtinCond(env: var Env, args: seq[Val]): Val =
    for i in 0 .. (args.len - 1) div 2:
        if env.eval(args[i * 2]).numify() != 0:
            return env.eval(args[i * 2 + 1])

proc builtinDef(env: var Env, args: seq[Val]): Val =
    var params: seq[string]
    if args.len > 2:
        for arg in args[1 ..< ^1]:
            params &= $env.eval(arg)

    env.defSym($env.eval(args.getArg(0)), if args.len > 1: args[^1] else: textVal(), params)

proc builtinOur(env: var Env, args: seq[Val]): Val =
    env.ourSym($env.eval(args.getArg(0)), args.getArg(1))

proc builtinMy(env: var Env, args: seq[Val]): Val =
    env.mySym($env.eval(args.getArg(0)), args.getArg(1))

proc builtinUndef(env: var Env, args: seq[Val]): Val =
    let name = $env.eval(args.getArg(0))
    for i in (env.syms.len - 1).countdown(0):
        if name in env.syms[i]:
            env.syms[i].del(name)

proc builtinEval(env: var Env, args: seq[Val]): Val = env.eval(env.eval(args.getArg(0)))

proc builtinInc(env: var Env, args: seq[Val]): Val =
    result = textVal()
    for arg in args:
        env.beginScope()
        defer: env.endScope()

        for val in readFile($env.eval(arg)).parse():
            result.text &= $env.eval(val)


proc builtinImp(env: var Env, args: seq[Val]): Val =
    result = textVal()
    for arg in args:
        env.beginScope()
        defer: env.endScope()

        for val in readFile($env.eval(arg)).parse():
            discard env.eval(val)

proc builtinEnv(env: var Env, args: seq[Val]): Val =
    result = textVal()
    for arg in args:
        result.text &= ($env.eval(arg)).getEnv()

proc builtinAdd(env: var Env, args: seq[Val]): Val =
    result = numVal()
    for arg in args:
        result.num += env.eval(arg).numify()

proc builtinSub(env: var Env, args: seq[Val]): Val =
    if args.len < 2:
        return numVal -env.eval(args.getArg(0)).numify()

    result = numVal env.eval(args.getArg(0)).numify()
    for arg in args[1 .. ^1]:
        result.num -= env.eval(arg).numify()

proc builtinMul(env: var Env, args: seq[Val]): Val =
    result = numVal 1
    for arg in args:
        result.num *= env.eval(arg).numify()

proc builtinDiv(env: var Env, args: seq[Val]): Val =
    result = numVal env.eval(args.getArg(0)).numify()
    if args.len < 2:
        return numVal 1.0/result.num

    for arg in args[1 .. ^1]:
        result.num /= env.eval(arg).numify()

proc builtinMod(env: var Env, args: seq[Val]): Val =
    if args.len < 2:
        return numVal()

    result = numVal env.eval(args.getArg(0)).numify()
    for arg in args[1 .. ^1]:
        result.num = result.num mod env.eval(arg).numify()

proc builtinEq(env: var Env, args: seq[Val]): Val =
    var prev = env.eval(args.getArg(0))
    for arg in args[1 .. ^1]:
        let val = env.eval(arg)
        if prev != val:
            return falseVal
        prev = val
    return trueVal

proc builtinNeq(env: var Env, args: seq[Val]): Val =
    var prev = env.eval(args.getArg(0))
    for arg in args[1 .. ^1]:
        let val = env.eval(arg)
        if prev == val:
            return falseVal
        prev = val
    return trueVal

proc builtinGr(env: var Env, args: seq[Val]): Val =
    var prev = env.eval(args.getArg(0)).numify()
    for arg in args[1 .. ^1]:
        let num = env.eval(arg).numify()
        if prev <= num:
            return falseVal
        prev = num
    return trueVal

proc builtinLe(env: var Env, args: seq[Val]): Val =
    var prev = env.eval(args.getArg(0)).numify()
    for arg in args[1 .. ^1]:
        let num = env.eval(arg).numify()
        if prev >= num:
            return falseVal
        prev = num
    return trueVal

proc builtinGrEq(env: var Env, args: seq[Val]): Val =
    var prev = env.eval(args.getArg(0)).numify()
    for arg in args[1 .. ^1]:
        let num = env.eval(arg).numify()
        if prev < num:
            return falseVal
        prev = num
    return trueVal

proc builtinLeEq(env: var Env, args: seq[Val]): Val =
    var prev = env.eval(args.getArg(0)).numify()
    for arg in args[1 .. ^1]:
        let num = env.eval(arg).numify()
        if prev > num:
            return falseVal
        prev = num
    return trueVal

proc builtinNot(env: var Env, args: seq[Val]): Val =
    numVal(if env.eval(args.getArg(0)).numify() == 0: 1 else: 0)

proc builtinAnd(env: var Env, args: seq[Val]): Val =
    for arg in args:
        if env.eval(arg).numify() == 0:
            return falseVal
    return trueVal

proc builtinOr(env: var Env, args: seq[Val]): Val =
    for arg in args:
        if env.eval(arg).numify() != 0:
            return trueVal
    return falseVal

proc builtinRound(env: var Env, args: seq[Val]): Val =
    numVal env.eval(args.getArg(0)).numify().round()

proc builtinFloor(env: var Env, args: seq[Val]): Val =
    numVal env.eval(args.getArg(0)).numify().floor()

proc builtinCeil(env: var Env, args: seq[Val]): Val =
    numVal env.eval(args.getArg(0)).numify().ceil()

proc builtinCat(env: var Env, args: seq[Val]): Val =
    result = listVal()
    for arg in args:
        result.list &= env.eval(arg).listify()

proc builtinFexpand(env: var Env, args: seq[Val]): Val =
    var
        output = $env.eval(args.getArg(1))
        envx   = newEnv output
    let expanded = envx.expand(readFile $env.eval(args.getArg(0)))
    if output.len == 0:
        stdout.write expanded
    else:
        writeFile output, expanded

proc builtinIgnore(env: var Env, args: seq[Val]): Val = discard

proc builtinRead(env: var Env, args: seq[Val]): Val =
    result = textVal()
    for arg in args:
        result.text &= readFile $env.eval(arg)

proc builtinStrify (env: var Env, args: seq[Val]): Val = textVal $env.eval(args.getArg(0))
proc builtinNumify (env: var Env, args: seq[Val]): Val = numVal  env.eval(args.getArg(0)).numify()
proc builtinListify(env: var Env, args: seq[Val]): Val = listVal env.eval(args.getArg(0)).listify()
proc builtinMapify (env: var Env, args: seq[Val]): Val = mapVal  env.eval(args.getArg(0)).mapify()

proc builtinJoin(env: var Env, args: seq[Val]): Val =
    result = textVal()
    if args.len < 2:
        return

    let sep = $env.eval(args.getArg(0))
    for i, arg in args[1 .. ^1]:
        if result.text.len > 0:
            result.text &= sep
        result.text &= env.eval(arg).listify().join(sep)

proc builtinLen(env: var Env, args: seq[Val]): Val =
    let val = env.eval(args.getArg(0))
    case val.kind
    of ValText: return numVal val.text.len.float64
    of ValNum:  return numVal len($val).float64
    of ValList: return numVal val.list.len.float64
    of ValMap:  return numVal val.map.len.float64

proc builtinKeys(env: var Env, args: seq[Val]): Val =
    result = listVal()
    for key in env.eval(args.getArg(0)).mapify().keys.toSeq():
        result.list &= textVal key

proc at(val: Val, key: Val): Val =
    try:
        case val.kind
        of ValText: return textVal $val.text[key.numify().uint]
        of ValNum:  return textVal $($val)[key.numify().uint]
        of ValList: return val.list[key.numify().uint]
        of ValMap:  return val.map[$key]
    except IndexDefect as e:
        return textVal()
    except KeyError as e:
        return textVal()

proc builtinGet(env: var Env, args: seq[Val]): Val =
    result = env.eval(args.getArg(0))
    if args.len < 2:
        return

    for arg in args[1 .. ^1]:
        result = result.at(arg)

proc builtinSlice(env: var Env, args: seq[Val]): Val =
    let val = env.eval(args.getArg(0))
    var
        start = env.eval(args.getArg(1)).numify().int
        count = env.eval(args.getArg(2)).numify().int
    case val.kind
    of ValText:
        if start < 0:
            start = val.text.len + start + 1
        start = start.clamp(0, val.text.len)
        if count < 0:
            count = val.text.len - start + count + 1
        count = count.clamp(0, val.text.len - start)
        if count > 0:
            return textVal val.text[start ..< start + count]
    of ValNum:
        let str = $val
        if start < 0:
            start = str.len + start + 1
        start = start.clamp(0, str.len)
        if count < 0:
            count = str.len - start + count + 1
        count = count.clamp(0, str.len - start)
        if count > 0:
            return textVal str[start ..< start + count]
    of ValList:
        if start < 0:
            start = val.list.len + start + 1
        start = start.clamp(0, val.list.len)
        if count < 0:
            count = val.list.len - start + count + 1
        count = count.clamp(0, val.list.len - start)
        if count > 0:
            return listVal val.list[start ..< start + count]
        else:
            return listVal()
    of ValMap: return val

proc builtinIn(env: var Env, args: seq[Val]): Val =
    let subject = env.eval(args.getArg(0))
    if args.len < 2:
        return falseVal

    for arg in args[1 .. ^1]:
        let val = env.eval(arg)
        case val.kind
        of ValText:
            if ($subject)[0] in val.text:
                return trueVal
        of ValNum:
            if ($subject)[0] in $val:
                return trueVal
        of ValList:
            if subject in val.list:
                return trueVal
        of Valmap:
            if $subject in val.map:
                return trueVal

    return falseVal

proc builtinNotin(env: var Env, args: seq[Val]): Val =
    return numVal(if env.builtinIn(args).numify() == 0: 1 else: 0)

proc builtinSplit(env: var Env, args: seq[Val]): Val =
    let parts = ($env.eval(args.getArg(1))).split($env.eval(args.getArg(0)))
    result = listVal(newSeq[Val](parts.len))
    for i, str in parts:
        result.list[i] = textVal str

proc builtinUpper(env: var Env, args: seq[Val]): Val =
    result = textVal()
    for arg in args:
        result.text &= ($env.eval(arg)).toUpperAscii()

proc builtinLower(env: var Env, args: seq[Val]): Val =
    result = textVal()
    for arg in args:
        result.text &= ($env.eval(arg)).toLowerAscii()

proc builtinLs(env: var Env, args: seq[Val]): Val =
    var files: seq[string]
    for arg in args:
        for file in walkDir($env.eval(arg), relative = true):
            files &= $file[1]

    result = listVal(newSeq[Val](files.len))
    for i, file in files:
        result.list[i] = textVal $file

proc builtinDexists(env: var Env, args: seq[Val]): Val =
    for arg in args:
        if not dirExists($env.eval(arg)):
            return falseVal
    return trueVal

proc builtinFexists(env: var Env, args: seq[Val]): Val =
    for arg in args:
        if not fileExists($env.eval(arg)):
            return falseVal
    return trueVal

proc builtinNoOutput(env: var Env, args: seq[Val]): Val =
    env.noOutput = if args.len == 0: true else: args[0].numify() != 0

proc newEnv*(output: string): Env =
    proc textSym(text: string): Sym = Sym(kind: SymVal, val: Val(kind: ValText, text: text))
    proc fnSym(fn: Fn): Sym = Sym(kind: SymFn, fn: fn)

    let dt = now()
    return Env(syms: @[{
        "output":    textSym output,
        "date":      textSym &"{dt.month} {dt.monthday} {dt.year}",
        "time":      textSym &"{dt.hour}:{dt.minute}",
        "cwd":       textSym getCurrentDir(),
        "do":        fnSym builtinDo,
        "list":      fnSym builtinList,
        "map":       fnSym builtinMap,
        "int":       fnSym builtinInt,
        "bool":      fnSym builtinBool,
        "exists":    fnSym builtinExists,
        "for":       fnSym builtinFor,
        "each":      fnSym builtinEach,
        "if":        fnSym builtinIf,
        "unless":    fnSym builtinUnless,
        "cond":      fnSym builtinCond,
        "def":       fnSym builtinDef,
        "our":       fnSym builtinOur,
        "my":        fnSym builtinMy,
        "undef":     fnSym builtinUndef,
        "echo":      fnSym builtinEcho,
        "eval":      fnSym builtinEval,
        "inc":       fnSym builtinInc,
        "imp":       fnSym builtinImp,
        "env":       fnSym builtinEnv,
        "+":         fnSym builtinAdd,
        "-":         fnSym builtinSub,
        "*":         fnSym builtinMul,
        "/":         fnSym builtinDiv,
        "mod":       fnSym builtinMod,
        "=":         fnSym builtinEq,
        "/=":        fnSym builtinNeq,
        ">":         fnSym builtinGr,
        "<":         fnSym builtinLe,
        ">=":        fnSym builtinGrEq,
        "<=":        fnSym builtinLeEq,
        "not":       fnSym builtinNot,
        "and":       fnSym builtinAnd,
        "or":        fnSym builtinOr,
        "round":     fnSym builtinRound,
        "floor":     fnSym builtinFloor,
        "ceil":      fnSym builtinCeil,
        "cat":       fnSym builtinCat,
        "fexpand":   fnSym builtinFexpand,
        "#":         fnSym builtinIgnore,
        "read":      fnSym builtinRead,
        "strify":    fnSym builtinStrify,
        "numify":    fnSym builtinNumify,
        "listify":   fnSym builtinListify,
        "mapify":    fnSym builtinMapify,
        "join":      fnSym builtinJoin,
        "len":       fnSym builtinLen,
        "keys":      fnSym builtinKeys,
        "get":       fnSym builtinGet,
        "slice":     fnSym builtinSlice,
        "in":        fnSym builtinIn,
        "notin":     fnSym builtinNotin,
        "split":     fnSym builtinSplit,
        "upper":     fnSym builtinUpper,
        "lower":     fnSym builtinLower,
        "ls":        fnSym builtinLs,
        "dexists":   fnSym builtinDexists,
        "fexists":   fnSym builtinFexists,
        "no-output": fnSym builtinNoOutput,
    }.toTable])

proc expand*(env: var Env, input: string): string =
    for val in input.parse():
        if env.noOutput:
            discard $env.eval(val)
        else:
            result &= $env.eval(val)

    env.expanded &= result
