# Development Notes

To build/install from sources do the following:
1. Install dependencies
2. Create codesign certificate in `Keychain Access.app`
3. Run one of the entry point scripts to build/install from sources

If you struggle to build AeroSpace locally, you can also refer to [builds in GitHub Actions](https://github.com/nikitabobko/AeroSpace/actions?query=branch%3Amain)

## Definitions

**SPM.** Swift package manager and Swift build tool. In other words, `swift` CLI tool

## 1. Install dependencies

1.  Install Xcode from App Store https://apps.apple.com/us/app/xcode/id497799835
2.  Install [swiftly](https://github.com/swiftlang/swiftly).
    Swiftly is a Swift toolchain manager that will make sure that you use the same swift version as written in `.swift-version` file.
    `brew install swiftly`
3.  If you want to build shell completion, install rust, bash and fish
    -   Install Rust using rustup. https://www.rust-lang.org/tools/install
    -   `brew install bash fish`
4.  If you want to build man pages, install Ruby >= 3.0. I recommend using [rbenv](https://github.com/rbenv/rbenv).
    -   `rbenv install 3.3.4` (or whatever 3.x version)
    -   Install asciidoctor using Ruby `bundler`. `cd AeroSpace && bundler install`
5.  Install optional `xcbeautify` to make Xcode build logs readable. `brew install xcbeautify`

## 2. Create codesign certificate

If you want to run AeroSpace as App Bundle (AeroSpace.app) you need to create self-signed certificate that will be used to codesign AeroSpace.
Release artifact is built as App Bundle.
If you only plan to build the debug version of AeroSpace, you can run it from the terminal and custom certificate is not required.

1.  Open `Keychain Access.app`
2.  Menu -> `Keychain Access` -> `Certificate Assistance` -> `Create a Certificate...`
    -   Name: `aerospace-codesign-certificate`
    -   Identity Type: `Self-Signed Root`
    -   Certificate Type: `Code Signing`

## 3. Entry point scripts

**Debug build**
-   `build-debug.sh` - Build debug build to `.debug` dir by using SPM. (Xcode is not involved)
-   `test.sh` - Run tests.
-   `swiftformat.sh` - Format the code.
-   `run-debug.sh` - Run AeroSpace.app debug build.
-   `run-cli.sh` - Run `aerospace` in CLI. Arguments are forwarded to `aerospace` binary.
-   `build-docs.sh` - Build the site and man pages to `.site` and `.man` dirs respectively.
-   `build-shell-completion.sh` - Build shell completion to `.shell-completion`.
    You can test that the completion works properly by sourcing the file `source ./.shell-completion/zsh/_aerospace`
-   `generate.sh` - Regenerate generated project files. `xcode/AeroSpace.xcodeproj` is generated, and some of the source files
    (the source files have `Generated` suffix in their names).

**Release build**
-   `build-release.sh` - Build release build to `.release` dir by using Xcode.
-   `install-from-sources.sh` - Build release build from sources and install it as `aerospace-dev` brew cask.
    This script is "work in progress".
    Use it on your own risk.

## Code style

-   4-space indent, `case` indented inside `switch`, trailing commas, `if let x` shorthand, lowercase `// todo`.
    `./format.sh` and SwiftLint enforce most of it.
-   `orDie()` instead of force unwrapping with `!`, `check()` for invariants.
-   Tests use Swift Testing. Check equality with `expectEqual(actual, expected)`, and other conditions with `#expect`.

**Explicit types where the type checker works hard.**
The type checker is fast when types are known, and slow when it has to infer them through overloads, literals and generics.
Debug builds pay for that on most edits: Swift Build recompiles every AppBundleTests file after any change to AppBundle's interface.
-   Give globals and stored properties that other files use an explicit type, unless the initializer is a literal:
    `var world: World = World()`. Without it, every compile job type-checks the initializer to learn the type.
-   Give `@Test(arguments:)` tables of tuples their element type: `] as [(String, CmdOutput)])`.
-   Give multi-statement closures and closures in long chains a signature: `{ (mode: String) -> [String] in ... }`.
    Write `.map { String($0) }`, not `.map(String.init)`.
-   Turn long `||`/`==` chains over enum cases into a `switch` or an array lookup.
    Split operator-heavy expressions with typed `let`s.
-   `expectEqual(a, b)` instead of `#expect(a == b)`: the macro type-checks `==` twice, against many overloads.
-   Don't annotate the trivial cases: `let x = f()` in a function body costs nothing.

`script/typecheck-hotspots.sh` lists the function bodies and expressions that take longest to type-check.
Build with Swift Build, SwiftPM's default. Don't use `--build-system native`: it is deprecated.

## IDE

-   You can obviously [open the project in Xcode](#xcode).
-   You can use your editor of choice (Neovim, Vim, Emacs, Sublime, VS Code) by using [sourcekit-lsp LSP](https://github.com/apple/sourcekit-lsp).
    I only tested it in Neovim
-   AppCode. The initial codebase was written in AppCode and the IDE was pretty solid.
    But AppCode was unfortunately sunsetted, and it started falling apart.
    Last time I checked it, it didn't support Swift 5.9 features, and I couldn't make it reliably import the project.
    RIP

## Xcode

Even if you use LSP and another text editor, Xcode is still useful to attach debugger (though you can use `lldb` in CLI).

1.  To open the project in Xcode: File -> Open -> Choose `Package.swift` file instead of `xcode/AeroSpace.xcodeproj`.
    It's better to open `Package.swift`, because SPM project is more lightweight.
    `xcode/AeroSpace.xcodeproj` is only used in `*release*.sh` build scripts.
2.  After you opened the project in Xcode.
    Edit Scheme... -> Options -> Console -> Choose `Terminal`.
    This way Accessibility permission will be requested from Terminal.
    If you don't change Console to `Terminal`, Accessibility permission will be requested on every rebuild, because the debug binary is unsigned.

## Tips

- Use built-in "Accessibility Inspector.app" to inspect accessibility properties of windows
- Use [DeskPad](https://github.com/Stengo/DeskPad) or [BetterDisplay 2](https://github.com/waydabber/BetterDisplay) to emulate several monitors
- You can use `script/clean-project.sh` to clean the project when something goes wrong.
