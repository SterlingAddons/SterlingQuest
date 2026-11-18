#!/bin/bash
# Lists what a Lua file compiles to, without line numbers, addresses or local names.
# Two versions of a file that differ only in formatting (or in local names) give the same listing:
#     diff <(qa/bytecode.sh old/Core.lua) <(qa/bytecode.sh Sterling/Core.lua)
# Needs luac5.1 (Debian/Ubuntu: apt install lua5.1).
luac5.1 -l -l -p "$1" | sed -E 's/^(main|function) <[^>]*>/FUNC/; s/0x[0-9a-f]+//g; s/^\t([0-9]+)\t\[[0-9]+\]/\t\1/' |
    awk '/^locals \(/ { skip = 1; next } /^(constants|upvalues) \(/ { skip = 0 } /^FUNC/ { skip = 0 } !skip'
