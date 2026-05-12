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

    test('handles empty input gracefully', () => {
        expect(() => transpileTypstToLatex('')).not.toThrow();
    });
});
