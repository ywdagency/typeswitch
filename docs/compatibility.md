# TypeSwitch Compatibility Matrix

This matrix records observed behavior during internal testing. Do not trust app-specific auto-fix behavior based on assumptions; update this file from real test results.

Statuses:

- `untested`: no result yet.
- `supported`: dictionary auto-fix works and refusal behavior is understood.
- `partial`: some flows work, but auto-fix or selection behavior is not safe enough.
- `blocked`: TypeSwitch intentionally refuses.
- `unsafe`: risky behavior observed; do not continue compatibility widening until fixed.

## Expected Classification

| Context | Expected v1 classification | Notes |
| --- | --- | --- |
| Controlled host AppKit editable controls | supported | First required rewrite gate before third-party apps. |
| Controlled host SwiftUI editable controls | supported | First required SwiftUI range-behavior gate. |
| Controlled host secure field | blocked | Must refuse without rewrite or layout switch. |
| Controlled host read-only field | blocked | Must refuse without fallback. |
| Native AppKit text field | supported | Primary controlled host for first test. |
| SwiftUI text field | supported | Verify AX range behavior before trusting auto-fix. |
| Safari textarea | partial | Manual first; auto-fix only if AX behavior is stable. |
| Safari web input | partial | Manual first; auto-fix only if AX behavior is stable. |
| Chrome textarea | partial | Manual first; auto-fix only if AX behavior is stable. |
| Chrome web input | partial | Manual first; auto-fix only if AX behavior is stable. |
| Notes | untested | Classify before trusting auto-fix. |
| Mail compose | untested | Classify before trusting auto-fix. |
| Slack/Electron | untested | AX-first; bounded fallback is eligible after a recoverable AX text-model failure. |
| ChatGPT desktop composer (`com.openai.codex` / `com.openai.chat`) | partial | `AXTextArea` is inspection-only; use the bounded fallback without an AX text mutation, then confirm replacement and input-source switch. Other control roles remain AX-first. |
| Chrome/WebView empty AX input | partial | AX-first; bounded fallback is expected after a recoverable text-model failure. |
| Telegram | untested | Ignore the app if compatibility testing finds risky behavior. |
| Terminal | blocked | Must refuse. |
| iTerm2 | blocked | Must refuse. |
| Password field | blocked | Must refuse. |
| Secure input enabled context | blocked | Must refuse. |
| SSH/sudo-like context | blocked | Must refuse or remain unsupported. |

## Internal Test Results

| App | Control | Flow | Expected | Actual | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| TypeSwitch Test Host | AppKit `NSTextField` | Dictionary auto-fix | Rewrite `ghbdtn ` to `привет ` | Not run | untested | First controlled single-line target. |
| TypeSwitch Test Host | AppKit `NSTextView` | Dictionary auto-fix | Rewrite `ghbdtn ` to `привет ` | Not run | untested | First controlled multiline target. |
| TypeSwitch Test Host | SwiftUI `TextField` | Dictionary auto-fix | Rewrite `ghbdtn ` to `привет ` | Not run | untested | Confirm caret remains after delimiter. |
| TypeSwitch Test Host | SwiftUI `TextEditor` | Dictionary auto-fix | Rewrite `ghbdtn ` to `привет ` | Not run | untested | Confirm caret remains after delimiter. |
| TypeSwitch Test Host | SwiftUI `SecureField` | Dictionary auto-fix | Refuse | Not run | untested | Must not rewrite or switch future layout. |
| TypeSwitch Test Host | Read-only `NSTextField` | Dictionary auto-fix | Refuse | Not run | untested | Must not invoke bounded fallback. |
| TextEdit | Plain text document | Dictionary auto-fix | Rewrite a known wrong-layout word at boundary | Not run | untested | First controlled native target. |
| Safari | Textarea | Dictionary auto-fix | Rewrite through AX or bounded fallback | Not run | untested | Ignore the app immediately if risky behavior appears. |
| Chrome | Textarea | Dictionary auto-fix | AX safety inspection followed directly by bounded fallback; caret remains after delimiter | Awaiting retest after direct-fallback fix | untested | Chrome's writable `AXSelectedText` produced an inconsistent post-write model, so every AX text mutation is forbidden. |
| ChatGPT desktop app | `AXTextArea` composer | Dictionary auto-fix | Rewrite `ghbdtn ` to `привет ` through bounded fallback without AX mutation | Not run | untested | Confirm exact replacement and target input source. |
| Codex desktop app (`com.openai.codex`) | Composer with empty `AXGroup` text model | Dictionary auto-fix through bounded fallback | Rewrite `lfkmit ` to `дальше ` | User confirmed `дальше` on 2026-10-12 after the event fix; previously reported `ДАЛЬШЕ` and `ДаЛьшЕ` | partial | Events now carry explicit flags and Unicode payload. Lowercase replacement was manually confirmed; title/uppercase delivery and the wider compatibility matrix remain unverified. |
| Codex desktop app (`com.openai.codex`) | Composer | Esc undo and permanent exception | Restore original word/layout, retain delimiter, save the exact spelling/layout immediately without a prompt | User confirmed Esc restored the word on 2026-10-12 in the previous confirmation-based build; immediate exception saving awaits manual retest | partial | Automated tests cover successful undo persistence, refused undo without persistence, removal, filtering, expiry, and case/layout matching. Exact delimiter/caret preservation, normal Backspace, and refusal cases still need manual verification. |
| Chrome | DuckDuckGo search field | Dictionary auto-fix with fallback | Rewrite `ghbdtn ` to `привет ` after AX rewrite fails | Not run | untested | Confirm exact token and delimiter preservation. |
| Terminal | Shell input | Dictionary auto-fix | Refuse | Not run | untested | Must not rewrite. |
| iTerm2 | Shell input | Dictionary auto-fix | Refuse | Not run | untested | Must not rewrite. |
| Password field | Secure text field | Dictionary auto-fix | Refuse | Not run | untested | Must not rewrite. |
