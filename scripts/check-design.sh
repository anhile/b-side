#!/bin/sh
# Fails when screen code carries raw colours, fonts or spacing instead of
# tokens from Sources/BSide/Design/Theme.swift. See DESIGN.md, Enforcement.
# Settings keeps the system look on purpose and is not checked.
cd "$(dirname "$0")/.." || exit 1
files=$(find Sources/BSide/Views -name '*.swift' | grep -v '/Settings/' | sort)
status=0
check() {
    pattern=$1; message=$2
    hits=$(grep -nE "$pattern" $files | grep -v '// tokens-ok')
    if [ -n "$hits" ]; then
        echo "$message:"; echo "$hits" | sed 's/^/  /'; status=1
    fi
}
check '#[0-9A-Fa-f]{6}|Color\(|Color\.[a-z]|\.(primary|secondary|tertiary|quaternary|tint)\b' "Raw colour (use Theme.Colors)"
check '\.font\(\.(largeTitle|title|title2|title3|headline|body|callout|subheadline|footnote|caption)|\.system\(size: ?[0-9]' "Raw font (use Theme.Text)"
check '(padding|spacing|cornerRadius|lineSpacing)\(?:? ?[1-9]' "Raw spacing or radius (use Theme.Space, Theme.Radius)"
check 'frame\((width|height|minWidth|maxWidth|minHeight|maxHeight): [0-9]' "Raw size (use Theme.Size)"
if [ $status -eq 0 ]; then echo "check-design: clean"; fi
exit $status
