# Emerald

Syntax highlighting, language configuration, snippets, the Emerald Dark theme, and extension icon for Emerald `.ems` files.

Author: **DragonRex & Emerald**

## Features

- TextMate syntax highlighting for Emerald language constructs
- Screenshot-style Emerald Dark theme with purple keywords, green types, teal annotations, blue calls, yellow strings, and muted comments
- Highlighting for namespaces, imports, macros, quote/unquote, concurrency, STDLib names, member calls, macro AST helpers, and built-in types
- Bracket and comment configuration
- Snippets for classes, interfaces, methods, Option, Result, Collections, Console, HTTP, and TCP

## Use the Emerald Dark theme

After installing the extension, open the command palette and choose:

```txt
Preferences: Color Theme
```

Then select:

```txt
Emerald Dark
```

The grammar still works with any VSCode theme, but the bundled theme is what makes Emerald files look like the reference screenshots.

## Install from source

Copy this folder into your VSCode extensions directory.

Linux:

```sh
mkdir -p ~/.vscode/extensions/emerald-language-support
cp -R compiler/tools/vscode-emerald/* ~/.vscode/extensions/emerald-language-support/
```

Windows PowerShell:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.vscode\extensions\emerald-language-support"
Copy-Item -Recurse -Force "compiler\tools\vscode-emerald\*" "$env:USERPROFILE\.vscode\extensions\emerald-language-support\"
```

Restart VSCode after copying.

## Member calls

The grammar gives chained calls their own member-call scopes, so expressions like:

```ems
result.isSuccess()
file.readText()
this.items.add(value)
```

are colored with the bright method-call color in Emerald Dark.

## Font

The extension sets a language-specific Emerald default font stack:

```json
"editor.fontFamily": "'JetBrains Mono', 'Fira Code', 'Cascadia Code', Consolas, monospace",
"editor.fontLigatures": true
```

VSCode will use the first installed font from that list. User settings still win, so you can override it globally or just for Emerald.

## Scope

This extension is intentionally syntax-only. A language server can be added later without changing the `.ems` file association.


## Icon

The extension uses `Icon.png`, based on the Emerald landing palette and pentagon mark.
