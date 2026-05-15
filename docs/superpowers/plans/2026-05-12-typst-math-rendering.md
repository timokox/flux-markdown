# Typst Math Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Status

- **State:** Completed and released.
- **Release:** [v1.32.427](https://github.com/xykong/flux-markdown/releases/tag/v1.32.427)
- **Issue:** [#36 Adding typst support](https://github.com/xykong/flux-markdown/issues/36), reported by [@Killer545537](https://github.com/Killer545537)
- **Implementation commits:** `7c51959`, `79e7c24`, `41d5052`, `af263bc`, `d97a26a`
- **Verification evidence:** `web-renderer/test/typst-rendering.test.ts` passed 10/10 targeted tests, and `web-renderer` production build passed via `npm run build` during post-release documentation cleanup.

**Goal:** Add Typst math block rendering to FluxMarkdown — lightweight transpilation in QuickLook, full WASM compiler in Host App, both lazy-loaded.

**Architecture:** Two-tier approach driven by `options.context`:
- **QuickLook/Finder** (`context != "app"`): `tex2typst` library transpiles Typst→LaTeX, reuses existing KaTeX. ~10KB added.
- **Host App** (`context == "app"`): `typst.ts` WASM compiler renders Typst→SVG natively. ~12MB WASM loaded on demand.

Both tiers share the same markdown-it fence detection for ` ```typst ` and ` ```typst-math ` code blocks. The renderer selection happens at render time based on context.

**Tech Stack:** TypeScript, Vite, `tex2typst` (transpiler), `@myriaddreamin/typst.ts` + `typst-ts-web-compiler` + `typst-ts-renderer` (WASM), markdown-it custom fence rule.

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `web-renderer/package.json` | Modify | Add `tex2typst`, `@myriaddreamin/typst.ts`, `@myriaddreamin/typst-ts-web-compiler`, `@myriaddreamin/typst-ts-renderer` deps |
| `web-renderer/src/typst-renderer.ts` | Create | Typst rendering module — exports `renderTypstBlock(code, context)` with dual-path logic |
| `web-renderer/src/styles/typst.css` | Create | Styling for Typst math blocks (display math centering, error states, loading indicator) |
| `web-renderer/src/index.ts` | Modify | Add `enableTypst` option handling, register typst/typst-math fence in `buildMd()` highlight function, call `renderTypstBlock` post-render |
| `web-renderer/vite.config.ts` | Modify | Add WASM file handling, manual chunk for typst WASM |
| `web-renderer/test/typst-rendering.test.ts` | Create | Unit tests for Typst transpilation and fence detection |
| `Sources/Shared/AppearancePreference.swift` | Modify | Add `enableTypst` preference (mirrors `enableKatex` pattern) |
| `Sources/Shared/SharedPreferenceStore.swift` | Modify | Add `"enableTypst"` to migration keys |
| `Sources/Markdown/MarkdownWebView.swift` | Modify | Add `enableTypst` prop, pass in options dict |
| `Sources/Markdown/MarkdownApp.swift` | Modify | Pass `preference.enableTypst` to `MarkdownWebView` |
| `Sources/Markdown/SettingsView.swift` | Modify | Add Typst toggle in Features section |
| `Sources/Markdown/CLIExporter.swift` | Modify | Add `"enableTypst": true` to CLI export options |

---

### Task 1: Add npm Dependencies

**Files:**
- Modify: `web-renderer/package.json`

- [x] **Step 1: Install tex2typst (transpiler for QuickLook path)**

```bash
cd web-renderer && npm install tex2typst
```

- [x] **Step 2: Install typst.ts ecosystem (WASM for App path)**

```bash
cd web-renderer && npm install @myriaddreamin/typst.ts @myriaddreamin/typst-ts-web-compiler @myriaddreamin/typst-ts-renderer
```

- [x] **Step 3: Verify both installed correctly**

Run: `cd web-renderer && node -e "require('tex2typst'); console.log('tex2typst OK')"`
Expected: `tex2typst OK`

- [x] **Step 4: Commit**

```bash
git add web-renderer/package.json web-renderer/package-lock.json
git commit -m "feat(typst): add tex2typst and typst.ts dependencies"
```

---

### Task 2: Create Typst Renderer Module

**Files:**
- Create: `web-renderer/src/typst-renderer.ts`

- [x] **Step 1: Write failing test for transpilation path**

Create `web-renderer/test/typst-rendering.test.ts`:

```typescript
/**
 * @jest-environment jsdom
 */

import { transpileTypstToLatex } from '../src/typst-renderer';

describe('Typst transpilation (QuickLook path)', () => {
    test('transpiles basic fraction', () => {
        const result = transpileTypstToLatex('a/b');
        expect(result).toContain('\\frac');
    });

    test('transpiles sum notation', () => {
        const result = transpileTypstToLatex('sum_(i=1)^n i');
        expect(result).toContain('\\sum');
    });

    test('transpiles Greek letters', () => {
        const result = transpileTypstToLatex('alpha + beta');
        expect(result).toContain('\\alpha');
        expect(result).toContain('\\beta');
    });

    test('transpiles sqrt', () => {
        const result = transpileTypstToLatex('sqrt(x)');
        expect(result).toContain('\\sqrt');
    });

    test('returns error info on invalid input', () => {
        // typst2tex may throw or return partial result — we handle gracefully
        expect(() => transpileTypstToLatex('')).not.toThrow();
    });
});
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd web-renderer && npx jest test/typst-rendering.test.ts --no-cache`
Expected: FAIL with "Cannot find module '../src/typst-renderer'"

- [x] **Step 3: Implement typst-renderer.ts**

Create `web-renderer/src/typst-renderer.ts`:

```typescript
/**
 * Typst math rendering module.
 *
 * Two-tier architecture:
 * - QuickLook/Finder: transpile Typst→LaTeX via tex2typst, render with KaTeX
 * - Host App: compile Typst→SVG via typst.ts WASM (lazy-loaded)
 */

import { typst2tex } from 'tex2typst';

// --- Transpilation path (QuickLook) ---

export function transpileTypstToLatex(typstCode: string): string {
    return typst2tex(typstCode, { blockMathMode: true });
}

/**
 * Render a Typst math block using transpilation → KaTeX.
 * Used in QuickLook/Finder context where bundle size matters.
 */
export async function renderTypstViaTranspilation(
    typstCode: string
): Promise<string> {
    const katexModule = await import('katex');
    const katex = (katexModule as any).default ?? katexModule;
    const latex = transpileTypstToLatex(typstCode);
    return katex.renderToString(latex, {
        displayMode: true,
        throwOnError: false,
        output: 'htmlAndMathml',
    });
}

// --- Native WASM path (Host App) ---

let typstInitPromise: Promise<any> | null = null;

async function getTypstInstance(): Promise<any> {
    if (!typstInitPromise) {
        typstInitPromise = (async () => {
            const { $typst } = await import(
                '@myriaddreamin/typst.ts/dist/esm/contrib/snippet.mjs'
            );
            const compilerWasmUrl = new URL(
                '@myriaddreamin/typst-ts-web-compiler/pkg/typst_ts_web_compiler_bg.wasm',
                import.meta.url
            ).href;
            const rendererWasmUrl = new URL(
                '@myriaddreamin/typst-ts-renderer/pkg/typst_ts_renderer_bg.wasm',
                import.meta.url
            ).href;
            $typst.setCompilerInitOptions({ getModule: () => compilerWasmUrl });
            $typst.setRendererInitOptions({ getModule: () => rendererWasmUrl });
            return $typst;
        })();
    }
    return typstInitPromise;
}

/**
 * Render a Typst math block natively to SVG via WASM.
 * Used in Host App context where full fidelity is desired.
 */
export async function renderTypstViaNative(
    typstCode: string
): Promise<string> {
    const $typst = await getTypstInstance();
    const mainContent = `#set page(width: auto, height: auto, margin: 0pt)\n$ ${typstCode} $`;
    const svg = await $typst.svg({ mainContent });
    return `<div class="typst-math-block typst-native">${svg}</div>`;
}

// --- Public API ---

/**
 * Render a Typst math block. Strategy depends on context:
 * - context === "app" → native WASM (high fidelity)
 * - otherwise → transpilation to KaTeX (lightweight)
 *
 * Falls back to transpilation if WASM fails.
 */
export async function renderTypstBlock(
    typstCode: string,
    context: string
): Promise<string> {
    if (context === 'app') {
        try {
            return await renderTypstViaNative(typstCode);
        } catch (err) {
            // Fallback to transpilation if WASM fails to load
            console.warn('Typst WASM failed, falling back to transpilation:', err);
        }
    }
    try {
        const html = await renderTypstViaTranspilation(typstCode);
        return `<div class="typst-math-block typst-transpiled">${html}</div>`;
    } catch (err) {
        return `<div class="typst-math-block typst-error">
            <div class="typst-error-title">⚠️ Typst Render Error</div>
            <pre class="typst-error-source">${typstCode}</pre>
            <pre class="typst-error-message">${String(err)}</pre>
        </div>`;
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `cd web-renderer && npx jest test/typst-rendering.test.ts --no-cache`
Expected: All 5 tests PASS

- [x] **Step 5: Commit**

```bash
git add web-renderer/src/typst-renderer.ts web-renderer/test/typst-rendering.test.ts
git commit -m "feat(typst): add dual-path typst renderer (transpile + WASM)"
```

---

### Task 3: Create Typst CSS Styles

**Files:**
- Create: `web-renderer/src/styles/typst.css`

- [x] **Step 1: Create typst.css**

```css
/* Typst math block styling */
.typst-math-block {
    display: flex;
    justify-content: center;
    align-items: center;
    margin: 1em 0;
    overflow-x: auto;
}

.typst-math-block.typst-transpiled .katex-display {
    margin: 0;
}

.typst-math-block.typst-native svg {
    max-width: 100%;
    height: auto;
}

/* Adapt SVG color to theme */
[data-theme="dark"] .typst-math-block.typst-native svg {
    filter: invert(1) hue-rotate(180deg);
}

/* Error state */
.typst-math-block.typst-error {
    display: block;
    background-color: #fff5f5;
    border: 1px solid #feb2b2;
    border-radius: 6px;
    padding: 16px;
}

[data-theme="dark"] .typst-math-block.typst-error {
    background-color: #2d1b1b;
    border-color: #742a2a;
}

.typst-error-title {
    color: #c53030;
    font-weight: 600;
    margin-bottom: 8px;
}

[data-theme="dark"] .typst-error-title {
    color: #feb2b2;
}

.typst-error-source {
    background-color: #fed7d7;
    color: #742a2a;
    padding: 12px;
    border-radius: 4px;
    overflow-x: auto;
    font-size: 13px;
    margin: 0 0 8px 0;
    white-space: pre-wrap;
}

[data-theme="dark"] .typst-error-source {
    background-color: #3b1a1a;
    color: #feb2b2;
}

.typst-error-message {
    font-size: 12px;
    color: #718096;
    margin: 0;
    white-space: pre-wrap;
}

/* Loading placeholder */
.typst-loading {
    display: flex;
    justify-content: center;
    padding: 1em;
    color: #718096;
    font-style: italic;
}
```

- [x] **Step 2: Commit**

```bash
git add web-renderer/src/styles/typst.css
git commit -m "feat(typst): add CSS styles for typst math blocks"
```

---

### Task 4: Integrate Typst into markdown-it Pipeline

**Files:**
- Modify: `web-renderer/src/index.ts`

This is the core integration. Typst blocks (`language-typst`, `language-typst-math`) are detected during `md.render()` via the highlight function, then post-rendered asynchronously (same pattern as Mermaid/Graphviz).

- [x] **Step 1: Add typst.css import**

In `web-renderer/src/index.ts`, after the existing CSS imports (around line 93), add:

```typescript
import './styles/typst.css';
```

- [x] **Step 2: Update buildMd() highlight function to tag typst blocks**

In the `highlight` function inside `buildMd()` (around line 287-298), add typst/typst-math detection **before** the hljs fallback:

```typescript
highlight: function (str: string, lang: string): string {
    const resolvedLang = resolveLanguage(lang);

    // Typst math blocks — render as placeholder, post-processed async
    if (lang === 'typst' || lang === 'typst-math') {
        return '<div class="typst-placeholder" data-typst-source="' +
            str.replace(/"/g, '&quot;').replace(/\n/g, '&#10;') +
            '"><div class="typst-loading">Rendering Typst…</div></div>';
    }

    if (resolvedLang && hljs.getLanguage(resolvedLang)) {
        // ... existing hljs logic
```

- [x] **Step 3: Add enableTypst option handling in renderMarkdown**

After the `enableKatex` block (around line 758), add:

```typescript
const enableTypst = options.enableTypst !== false;
```

- [x] **Step 4: Add async Typst post-render after Graphviz**

After `await renderGraphvizDiagrams(outputDiv);` (around line 858), add:

```typescript
// Render Typst math blocks
if (enableTypst) {
    const typstPlaceholders = outputDiv.querySelectorAll('.typst-placeholder');
    if (typstPlaceholders.length > 0) {
        try {
            const { renderTypstBlock } = await import('./typst-renderer');
            const context = options.context || 'quicklook';
            for (const placeholder of typstPlaceholders) {
                const source = placeholder.getAttribute('data-typst-source') || '';
                const decodedSource = source
                    .replace(/&quot;/g, '"')
                    .replace(/&#10;/g, '\n')
                    .replace(/&amp;/g, '&');
                try {
                    const rendered = await renderTypstBlock(decodedSource, context);
                    placeholder.innerHTML = rendered;
                } catch (err) {
                    logToSwift(`JS Typst render error: ${err}`);
                    placeholder.innerHTML = `<div class="typst-math-block typst-error">
                        <div class="typst-error-title">⚠️ Typst Render Error</div>
                        <pre class="typst-error-source">${escapeHtml(decodedSource)}</pre>
                    </div>`;
                }
            }
        } catch (err) {
            logToSwift('JS Error loading typst-renderer: ' + err);
        }
    }
}
```

- [x] **Step 5: Run build to verify compilation**

Run: `cd web-renderer && npm run build`
Expected: Build succeeds (exit code 0)

- [x] **Step 6: Commit**

```bash
git add web-renderer/src/index.ts
git commit -m "feat(typst): integrate typst fence detection and async rendering into pipeline"
```

---

### Task 5: Update Vite Config for WASM Support

**Files:**
- Modify: `web-renderer/vite.config.ts`

- [x] **Step 1: Add typst WASM handling and chunking**

Update `vite.config.ts`:

```typescript
import { defineConfig } from 'vite';
import path from 'path';

export default defineConfig({
  base: './',
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    sourcemap: false,
    emptyOutDir: true,
    rollupOptions: {
      input: {
        main: path.resolve(__dirname, 'index.html'),
      },
      output: {
        manualChunks: {
          mermaid: ['mermaid'],
          'typst-wasm': [
            '@myriaddreamin/typst.ts',
            '@myriaddreamin/typst-ts-web-compiler',
            '@myriaddreamin/typst-ts-renderer',
          ],
        },
      },
    },
    chunkSizeWarningLimit: 2000,
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
  assetsInclude: ['**/*.wasm'],
  define: {
    'process.env': {},
  },
});
```

Key changes: added `typst-wasm` manual chunk and `assetsInclude: ['**/*.wasm']`.

- [x] **Step 2: Run build to verify WASM bundling works**

Run: `cd web-renderer && npm run build`
Expected: Build succeeds. WASM files appear in `dist/assets/`.

- [x] **Step 3: Commit**

```bash
git add web-renderer/vite.config.ts
git commit -m "feat(typst): configure Vite for WASM bundling and typst chunking"
```

---

### Task 6: Add Swift Preferences and Settings UI

**Files:**
- Modify: `Sources/Shared/AppearancePreference.swift`
- Modify: `Sources/Shared/SharedPreferenceStore.swift`
- Modify: `Sources/Markdown/MarkdownWebView.swift`
- Modify: `Sources/Markdown/MarkdownApp.swift`
- Modify: `Sources/Markdown/SettingsView.swift`
- Modify: `Sources/Markdown/CLIExporter.swift`

- [x] **Step 1: Add enableTypst to AppearancePreference.swift**

After `private let enableEmojiKey = "enableEmoji"` (line 114), add:

```swift
private let enableTypstKey = "enableTypst"
```

After the `enableEmoji` property (after line 175), add:

```swift
public var enableTypst: Bool {
    get {
        guard sharedStore.object(forKey: enableTypstKey) != nil else { return true }
        return sharedStore.bool(forKey: enableTypstKey)
    }
    set {
        objectWillChange.send()
        sharedStore.set(newValue, forKey: enableTypstKey)
        scheduleSyncToSharedStore()
    }
}
```

- [x] **Step 2: Add to SharedPreferenceStore migration keys**

In `SharedPreferenceStore.swift`, add `"enableTypst"` to the migration keys array (after `"enableEmoji"` around line 101):

```swift
"enableEmoji",
"enableTypst",
```

- [x] **Step 3: Add enableTypst to MarkdownWebView.swift**

After `var enableEmoji: Bool = true` (line 20), add:

```swift
var enableTypst: Bool = true
```

In the `render()` call chain and `executeRender()`, add `enableTypst` parameter alongside `enableEmoji`. In `executeRender()`'s options dict (after line 414), add:

```swift
options["enableTypst"] = enableTypst
```

- [x] **Step 4: Add enableTypst to MarkdownApp.swift**

After `enableEmoji: preference.enableEmoji,` (line 85), add:

```swift
enableTypst: preference.enableTypst,
```

- [x] **Step 5: Add Typst toggle to SettingsView.swift**

After the Emoji toggle section (after line 309), add a new toggle:

```swift
Divider().padding(.leading, 52)
FeatureToggleRow(
    title: NSLocalizedString("Typst Math", comment: "Typst toggle title"),
    subtitle: NSLocalizedString("Typst math expressions in ```typst code blocks", comment: "Typst toggle subtitle"),
    icon: "x.squareroot",
    isOn: Binding(get: { preference.enableTypst }, set: { preference.enableTypst = $0 })
)
```

- [x] **Step 6: Add to CLIExporter.swift**

After `"enableEmoji": true,` (line 134), add:

```swift
"enableTypst":        true,
```

- [x] **Step 7: Build the Xcode project to verify Swift compilation**

Run: `make generate && make app`
Expected: Build succeeds

- [x] **Step 8: Commit**

```bash
git add Sources/
git commit -m "feat(typst): add enableTypst preference and Settings toggle"
```

---

### Task 7: End-to-End Integration Test

**Files:**
- Modify: `web-renderer/test/typst-rendering.test.ts`

- [x] **Step 1: Add integration test for fence detection**

Append to `web-renderer/test/typst-rendering.test.ts`:

```typescript
import MarkdownIt from 'markdown-it';

describe('Typst fence detection in markdown-it', () => {
    test('typst code block produces placeholder div', () => {
        // Simulate the highlight function behavior
        const md = new MarkdownIt({
            highlight: function (str: string, lang: string): string {
                if (lang === 'typst' || lang === 'typst-math') {
                    return '<div class="typst-placeholder" data-typst-source="' +
                        str.replace(/"/g, '&quot;').replace(/\n/g, '&#10;') +
                        '"><div class="typst-loading">Rendering Typst…</div></div>';
                }
                return '';
            }
        });

        const input = '```typst\nsum_(i=1)^n i = (n(n+1))/2\n```';
        const html = md.render(input);
        expect(html).toContain('typst-placeholder');
        expect(html).toContain('data-typst-source');
        expect(html).toContain('sum_(i=1)^n');
    });

    test('typst-math alias also works', () => {
        const md = new MarkdownIt({
            highlight: function (str: string, lang: string): string {
                if (lang === 'typst' || lang === 'typst-math') {
                    return '<div class="typst-placeholder" data-typst-source="' +
                        str.replace(/"/g, '&quot;').replace(/\n/g, '&#10;') +
                        '"></div>';
                }
                return '';
            }
        });

        const input = '```typst-math\nalpha + beta\n```';
        const html = md.render(input);
        expect(html).toContain('typst-placeholder');
    });

    test('regular code blocks are not affected', () => {
        const md = new MarkdownIt({
            highlight: function (str: string, lang: string): string {
                if (lang === 'typst' || lang === 'typst-math') {
                    return '<div class="typst-placeholder"></div>';
                }
                return '';
            }
        });

        const input = '```javascript\nconsole.log("hello")\n```';
        const html = md.render(input);
        expect(html).not.toContain('typst-placeholder');
    });
});
```

- [x] **Step 2: Run all tests**

Run: `cd web-renderer && npm test`
Expected: All tests PASS

- [x] **Step 3: Run full build**

Run: `cd web-renderer && npm run build`
Expected: Build succeeds

- [x] **Step 4: Commit**

```bash
git add web-renderer/test/typst-rendering.test.ts
git commit -m "test(typst): add integration tests for fence detection and transpilation"
```

---

### Task 8: Manual Verification

- [x] **Step 1: Create a test markdown file**

Create `/tmp/typst-test.md`:

```markdown
# Typst Math Test

## Basic fraction (transpiled via KaTeX)

```typst
a/b + c/d
```

## Sum notation

```typst
sum_(i=1)^n i = (n(n+1))/2
```

## Matrix

```typst
mat(1, 2; 3, 4)
```

## Integral

```typst
integral_0^1 x^2 dif x
```

## Mixed with LaTeX

Regular LaTeX still works: $E = mc^2$

$$\int_0^1 x^2 dx = \frac{1}{3}$$
```

- [x] **Step 2: Build and install locally**

Run: `make install` (builds renderer, generates project, builds app, installs, clears QL cache)

- [x] **Step 3: Verify QuickLook rendering**

Open Finder, navigate to `/tmp/typst-test.md`, press Space.
Expected: Typst math blocks render as formatted equations (via KaTeX transpilation). Existing LaTeX math still works.

- [x] **Step 4: Verify Host App rendering**

Open FluxMarkdown app, open `/tmp/typst-test.md`.
Expected: Typst math blocks render (via WASM if loaded, or transpilation fallback). Check console for any WASM loading errors.

- [x] **Step 5: Verify Settings toggle**

Open FluxMarkdown Settings (Cmd+,) → Features. Toggle "Typst Math" off. Reload preview.
Expected: Typst blocks render as plain code when disabled.
