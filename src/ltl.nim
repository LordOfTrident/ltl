import std/strformat, cligen, noise

import envs

const
    ver   = "0.1.0"
    usage = """
LTL - A Lisp-like template language
(https://github.com/lordoftrident/ltl)

Usage: ${command} ${args}
Options:
${options}
If no input is provided, the REPL will start.
"""

proc repl(env: var Env) =
    echo &"LTL v{ver} REPL"
    echo "Press CTRL+D or CTRL+C to exit."
    echo "Use --help flag to see usage.\n"

    var
        n = 0
        noise = Noise.init()
    while true:
        inc n
        noise.setPrompt(&"({n}) ")
        if not noise.readLine():
            break

        let line = noise.getLine()
        when promptHistory:
            if line.len > 0:
                noise.historyAdd(line)

        echo env.expand(line)

proc ltl(version = false, file = "", output = "", line = "") =
    if version:
        echo &"LTL v{ver}"
        quit QuitSuccess

    var env = newEnv output
    try:
        if file.len > 0:
            env.expand(readFile file)
        elif line.len > 0:
            env.expand(line)
        else:
            env.repl()
            return

        if output.len > 0:
            writeFile output, env.expanded
        else:
            stdout.write env.expanded
    except IOError as e:
        stderr.writeLine e.msg
        quit QuitFailure

when isMainModule:
    dispatch ltl, noHdr = true, usage = usage, help = {
        "file":    "Input file",
        "output":  "Output file",
        "line":    "Command line input",
        "version": "LTL version",
    }
