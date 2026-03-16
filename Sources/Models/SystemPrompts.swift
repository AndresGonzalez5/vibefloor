// ABOUTME: System prompts injected into claude sessions based on settings.
// ABOUTME: Written to ~/.ff/prompts/ and referenced via --system-prompt-file.

import Foundation

enum SystemPrompts {
    static let autoRenameBranchPrompt = """
        When the user presents their first request: \
        1) Generate a short descriptive git branch name summarizing the task. \
        2) Rename the current branch using `git branch -m <new-name>`. \
        3) Keep the existing branch prefix (everything before the last `/`). \
        4) Use kebab-case and keep the descriptive part under 6 words. \
        5) After renaming, continue with the task normally. \
        If the branch already has a meaningful descriptive name (not a random generated name), do nothing. \
        Example: if the branch is `ff/scan-deep-thr` and the user asks to "fix the login timeout bug", \
        rename it to `ff/fix-login-timeout-bug`.
        """
}
