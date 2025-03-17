import std/[tables, parseutils, sequtils, strutils]

type
    ValKind* = enum
        ValText
        ValNum
        ValList
        ValMap

    Map* = OrderedTable[string, Val]
    Val* = object
        case kind*: ValKind
        of ValText: text*: string
        of ValNum:  num*:  float64
        of ValList: list*: seq[Val]
        of ValMap:  map*:  Map

proc textVal*(text = ""):            Val = Val(kind: ValText, text: text)
proc numVal* (num  = 0.float64):     Val = Val(kind: ValNum,  num:  num)
proc listVal*(list = seq[Val](@[])): Val = Val(kind: ValList, list: list)
proc mapVal* (map  = Map()):         Val = Val(kind: ValMap,  map:  map)

const
    trueVal*  = numVal 1
    falseVal* = numVal 0

proc `$`*(val: Val): string

proc `$`*(val: Val): string =
    case val.kind
    of ValText: return val.text
    of ValNum:  return $val.num
    of ValList: return val.list.join("")
    of ValMap:  return val.map.values.toSeq().join("")

proc `==`*(a, b: Val): bool = a.kind == b.kind and $a == $b
proc `!=`*(a, b: Val): bool = a.kind != b.kind or  $a != $b

proc numify*(val: Val): float64 =
    case val.kind
    of ValText:
        var num: BiggestFloat
        if val.text.parseBiggestFloat(num) == 0:
            return 0
        return num.float64
    of ValNum:  return val.num
    of ValList: return textVal($val).numify()
    of ValMap:  return textVal($val).numify()

proc listify*(val: Val): seq[Val] =
    case val.kind
    of ValText:
        for ch in val.text:
            result &= textVal $ch
    of ValNum:  return textVal($val).listify()
    of ValList: return val.list
    of ValMap:  return val.map.values.toSeq()

proc mapify*(val: Val): Map =
    if val.kind == ValMap:
        return val.map
