# iTermPlex

## Setup
This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen). `project.yml` is the source of truth for the Xcode project; `itermplex.xcodeproj/` is generated and gitignored.

After cloning, or whenever `project.yml` or the source file layout changes, regenerate the project:

```sh
brew install xcodegen   # once
xcodegen generate
```

Build and test from the command line:

```sh
xcodebuild -scheme itermplex -destination 'platform=macOS' build
xcodebuild -scheme itermplex -destination 'platform=macOS' test
```

## Documentation
The `documentation/` folder must stay in sync with the code it describes. Whenever you change something a document covers, update that document in the same change. For example, `documentation/AsciiScreens/` holds one ASCII layout per SwiftUI view (`WorkspaceCardView.md`, `SidebarHeaderView.md`, and so on), so editing a view means updating its matching file (and adding a new file when you add a view worth documenting).

## General
Do not tell me I am right all the time. Be critical. We're equals. Try to be neutral and objective.
Do not excessively use emojis.

## Using GitHub
For questions about GitHub, use the gh tool Never mention Claude Code in PR descriptions, PR comments, or issue comments Do not include a "Test plan" section in PR descriptions

## Git
use /create-commit to create a commit message
use /create-pr to create a pr message
Never mention Claude Code in PR descriptions, PR comments, or issue comments
