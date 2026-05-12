# Design Spec: Typst Math Rendering in FluxMarkdown

**Date:** 2026-05-12
**Status:** Draft
**Context:** FluxMarkdown (macOS QuickLook Extension)

## 1. Objective
Enable high-fidelity Typst math rendering within Markdown previews. The solution must maintain the "Quick" in QuickLook, ensuring minimal impact on initial load time while providing accurate SVG-based math output.

## 2. Architecture Overview
We will implement a hybrid math rendering system that supports both existing KaTeX (for LaTeX syntax) and a new Typst engine for Typst-specific syntax.

### 2.1 Core Components
- **Parser**: A `markdown-it` plugin to detect Typst math delimiters (`$` for inline, `$ $` for block with whitespace).
- **Engine**: A lazy-loaded WASM-based renderer using a subset of `typst.ts` or `wypst`.
- **Bridge**: A TypeScript coordinator that manages WASM lifecycle, font loading, and SVG caching.

## 3. Implementation Details

### 3.1 Detection Strategy
Typst math syntax overlaps with standard dollar-sign math. We will use the official Typst spacing rules to disambiguate:
- **Inline Math**: `$x^2$` (No space after first `$`, no space before last `$`).
- **Display Math**: `$ x^2 $` (At least one space or newline after first `$`, at least one space or newline before last `$`).

Fenced code blocks with the `typst` or `typst-math` identifier will also be supported for explicit rendering.

### 3.2 Performance & Size Management (Critical)
To minimize the impact on the bundle size of `web-renderer`:
- **Asset Separation**: The Typst WASM blob (~5MB compressed) will be kept as a separate file in the app bundle.
- **Lazy Loading**: The WASM module and rendering logic will only be loaded via dynamic `import()` when a Typst math block is first encountered in a file.
- **Caching**: An LRU (Least Recently Used) cache will store rendered SVG outputs keyed by the source string hash. This prevents redundant WASM calls during scrolling or small edits.

### 3.3 Theming
Typst output will be styled via CSS `currentColor`:
- A global preamble will be injected: `#set text(fill: currentColor)`.
- This ensures math symbols automatically switch between black and white based on the macOS system theme (Light/Dark mode) without re-rendering.

### 3.4 Font Handling
- Bundled Fonts: A subsetted version of "New Computer Modern Math" will be embedded in the WASM or loaded as a data URI to ensure consistent cross-platform rendering.

## 4. User Configuration
A new setting will be added to `oh-my-openagent.json` / Settings UI:
- `enableTypstMath`: Boolean (Default: `false` or `true` based on user feedback).
- `mathPreference`: Enum (`katex` | `typst`) - determines which engine handles the ambiguous `$` syntax if both are enabled.

## 5. Success Criteria
- [ ] Typst math blocks render as high-quality SVGs.
- [ ] Initial render time of a standard Markdown file (without Typst) is unchanged.
- [ ] Typst-heavy files render within < 500ms after the initial WASM boot.
- [ ] SVG output respects the system's Light/Dark mode.

## 6. Risks & Mitigations
- **Risk**: WASM boot time. **Mitigation**: Show a subtle loading indicator or fallback to raw text if loading takes > 1s.
- **Risk**: Memory usage in `WKWebView`. **Mitigation**: The QuickLook extension is ephemeral; memory is cleared on window close. For the host app, we will use a capped LRU cache size.
