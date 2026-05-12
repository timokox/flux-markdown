# Typst Math Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Typst math rendering into FluxMarkdown using a lazy-loaded WASM engine.

**Architecture:** Use a custom `markdown-it` rule to detect Typst math delimiters, which then triggers a dynamic import of a WASM-backed `wypst` renderer with SVG caching.

**Tech Stack:** TypeScript, Vite, wypst (WASM), markdown-it.

---

## File Structure
- `web-renderer/src/typst-renderer.ts`: WASM lifecycle manager, lazy loader, and SVG cache.
- `web-renderer/src/index.ts`: Entry point; integrates the Typst math parser into the `markdown-it` instance.
- `web-renderer/src/styles/typst.css`: Visual styling for rendered math blocks and loading states.

---

### Task 1: Dependency Setup and Type Definitions

**Files:**
- Modify: `web-renderer/package.json`
- Create: `web-renderer/src/typst-types.d.ts`

- [ ] **Step 1: Add wypst dependency**
```bash
npm install wypst
```

- [ ] **Step 2: Add type definitions for wypst**
Create `web-renderer/src/typst-types.d.ts`:
```typescript
declare module 'wypst' {
    export function initialize(wasmUrl?: string): Promise<void>;
    export function renderToString(content: string): string;
}
```

- [ ] **Step 3: Commit**
```bash
git add web-renderer/package.json web-renderer/package-lock.json web-renderer/src/typst-types.d.ts
git commit -m "chore: add wypst dependency and types"
```

---

### Task 2: Implement Lazy-Loaded Typst Renderer

**Files:**
- Create: `web-renderer/src/typst-renderer.ts`
- Test: `web-renderer/test/typst-renderer.test.ts`

- [ ] **Step 1: Write failing test for renderer**
Create `web-renderer/test/typst-renderer.test.ts`:
```typescript
import { TypstRenderer } from '../src/typst-renderer';

describe('TypstRenderer', () => {
    it('should return raw code if not initialized', async () => {
        const renderer = new TypstRenderer();
        const result = renderer.render('x^2');
        expect(result).toContain('x^2');
    });
});
```

- [ ] **Step 2: Run test to verify failure**
Run: `npm test web-renderer/test/typst-renderer.test.ts`
Expected: FAIL (TypstRenderer not found)

- [ ] **Step 3: Implement TypstRenderer with lazy initialization**
Create `web-renderer/src/typst-renderer.ts`:
```typescript
import wypst from 'wypst';

export class TypstRenderer {
    private initialized = false;
    private cache = new Map<string, string>();
    private initPromise: Promise<void> | null = null;

    async ensureInitialized() {
        if (this.initialized) return;
        if (!this.initPromise) {
            // In Vite, ?url imports give us the path to the asset
            const wasmUrl = (await import('wypst/dist/wypst.wasm?url')).default;
            this.initPromise = wypst.initialize(wasmUrl).then(() => {
                this.initialized = true;
            });
        }
        return this.initPromise;
    }

    render(content: string, isBlock = false): string {
        const cacheKey = `${isBlock}:${content}`;
        if (this.cache.has(cacheKey)) return this.cache.get(cacheKey)!;

        if (!this.initialized) {
            return `<span class="typst-math-loading">${content}</span>`;
        }

        try {
            // Typst math requires $ delimiters for the engine to recognize math mode
            const wrapped = isBlock ? `$ ${content} $` : `$${content}$`;
            const svg = wypst.renderToString(wrapped);
            this.cache.set(cacheKey, svg);
            return svg;
        } catch (e) {
            console.error('Typst render error:', e);
            return `<span class="typst-math-error">${content}</span>`;
        }
    }
}
```

- [ ] **Step 4: Run test to verify pass**
Run: `npm test web-renderer/test/typst-renderer.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add web-renderer/src/typst-renderer.ts web-renderer/test/typst-renderer.test.ts
git commit -m "feat: implement TypstRenderer with lazy loading"
```

---

### Task 3: Integrate Typst Parser into Markdown-it

**Files:**
- Modify: `web-renderer/src/index.ts`

- [ ] **Step 1: Add Typst parser rule**
Modify `web-renderer/src/index.ts` to add a new rule for Typst math detection:
```typescript
import { TypstRenderer } from './typst-renderer';
const typstRenderer = new TypstRenderer();

function typstMathPlugin(md: MarkdownIt) {
    // We reuse the logic for dollar-delimited math but check for Typst spacing
    const originalInline = md.renderer.rules.math_inline;
    md.renderer.rules.math_inline = (tokens, idx, options, env, self) => {
        const content = tokens[idx].content;
        // If Typst is explicitly enabled or content matches Typst-specific spacing
        if (options.mathPreference === 'typst') {
            typstRenderer.ensureInitialized(); // Trigger lazy load
            return typstRenderer.render(content, false);
        }
        return originalInline ? originalInline(tokens, idx, options, env, self) : content;
    };

    // Handle block math
    const originalBlock = md.renderer.rules.math_block;
    md.renderer.rules.math_block = (tokens, idx, options, env, self) => {
        const content = tokens[idx].content;
        if (options.mathPreference === 'typst') {
            typstRenderer.ensureInitialized();
            return `<div class="typst-math-block">${typstRenderer.render(content, true)}</div>`;
        }
        return originalBlock ? originalBlock(tokens, idx, options, env, self) : content;
    };
}
```

- [ ] **Step 2: Update renderMarkdown to support mathPreference**
Modify `window.renderMarkdown` in `web-renderer/src/index.ts` to accept `mathPreference`.

- [ ] **Step 3: Commit**
```bash
git add web-renderer/src/index.ts
git commit -m "feat: integrate Typst math plugin into markdown-it"
```

---

### Task 4: Styling and Accessibility

**Files:**
- Create: `web-renderer/src/styles/typst.css`
- Modify: `web-renderer/src/index.ts`

- [ ] **Step 1: Create Typst styles**
Create `web-renderer/src/styles/typst.css`:
```css
.typst-math-loading {
    color: #888;
    font-style: italic;
}
.typst-math-error {
    color: #d73a49;
    border-bottom: 1px dotted #d73a49;
}
.typst-math-block {
    display: flex;
    justify-content: center;
    margin: 1em 0;
}
/* Ensure SVG uses currentColor for theme adaptation */
.typst-math-block svg, .typst-math-inline svg {
    fill: currentColor;
    color: inherit;
}
```

- [ ] **Step 2: Import styles**
Add `import './styles/typst.css';` to `web-renderer/src/index.ts`.

- [ ] **Step 3: Commit**
```bash
git add web-renderer/src/styles/typst.css web-renderer/src/index.ts
git commit -m "style: add styles for Typst math"
```
