#!/usr/bin/env bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

# Generates the CmdKind enum, one case per docs/aerospace-<subcommand>.adoc, with its help (the synopsis) and purpose
# Bash string ops instead of sed pipes: build-debug.sh runs this every time, and the processes add up

cases=() help_cases=() purpose_cases=()
for file in docs/aerospace-*.adoc; do
    subcommand="${file#docs/aerospace-}"
    subcommand="${subcommand%.adoc}"
    IFS=- read -ra words <<< "$subcommand"
    kind="${words[0]}"
    for word in "${words[@]:1}"; do kind+="${word^}"; done # balance-sizes -> balanceSizes
    if [[ $kind == true || $kind == false ]]; then kind="_$kind"; fi # Swift keywords

    cases+=("    case $kind = \"$subcommand\"")
    help_cases+=("            case .$kind:" '                """')
    in_synopsis=0
    usage_prefix='USAGE:' # The first `aerospace` line becomes `USAGE:`, the others `   OR:`
    while IFS= read -r line; do
        if [[ $line == ':manpurpose: '* ]]; then
            purpose_cases+=("            case .$kind: \"${line#:manpurpose: }\"")
        elif [[ $line == *tag::synopsis* ]]; then
            in_synopsis=1
        elif [[ $line == *end::synopsis* ]]; then
            break
        elif [[ $in_synopsis == 1 && -n $line ]]; then
            line="${line#   }"
            if [[ $line == aerospace* ]]; then
                line="$usage_prefix${line#aerospace}"
                usage_prefix='   OR:'
            fi
            help_cases+=("                $line")
        fi
    done < "$file"
    help_cases+=('                """')
done

write-if-changed Sources/Common/cmdHelpGenerated.swift << EOF
// FILE IS GENERATED FROM docs/aerospace-*.adoc files
// TO REGENERATE THE FILE RUN generate.sh

public enum CmdKind: String, CaseIterable, Equatable, Sendable {
$(printf '%s\n' "${cases[@]}")

    public var help: String {
        switch self {
$(printf '%s\n' "${help_cases[@]}")
        }
    }

    /// One-line description in the \`aerospace --help\` subcommand list
    public var purpose: String {
        switch self {
$(printf '%s\n' "${purpose_cases[@]}")
        }
    }
}
EOF
