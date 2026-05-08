jest.mock('mermaid', () => ({
  initialize: jest.fn(),
  render: jest.fn().mockResolvedValue({ svg: '<svg>mocked</svg>' }),
}));

import '../src/index';

describe('pinch-to-zoom: ctrlKey+wheel → pinchZoom messageHandler → Swift setMagnification', () => {
  let pinchZoomSpy: jest.Mock;

  beforeEach(() => {
    document.body.innerHTML = '<div id="markdown-preview"></div>';
    pinchZoomSpy = jest.fn();
    (window as any).webkit = {
      messageHandlers: {
        pinchZoom: { postMessage: pinchZoomSpy },
      },
    };
  });

  afterEach(() => {
    delete (window as any).webkit;
  });

  test('ctrlKey+wheel calls preventDefault', () => {
    const e = new WheelEvent('wheel', { ctrlKey: true, deltaY: 100, cancelable: true, bubbles: true });
    const spy = jest.spyOn(e, 'preventDefault');
    document.dispatchEvent(e);
    expect(spy).toHaveBeenCalled();
  });

  test('ctrlKey+wheel (zoom in: negative deltaY) posts positive delta to pinchZoom', () => {
    document.dispatchEvent(new WheelEvent('wheel', { ctrlKey: true, deltaY: -100, cancelable: true, bubbles: true }));
    expect(pinchZoomSpy).toHaveBeenCalledTimes(1);
    expect(pinchZoomSpy.mock.calls[0][0]).toBeGreaterThan(0);
  });

  test('ctrlKey+wheel (zoom out: positive deltaY) posts negative delta to pinchZoom', () => {
    document.dispatchEvent(new WheelEvent('wheel', { ctrlKey: true, deltaY: 100, cancelable: true, bubbles: true }));
    expect(pinchZoomSpy).toHaveBeenCalledTimes(1);
    expect(pinchZoomSpy.mock.calls[0][0]).toBeLessThan(0);
  });

  test('ctrlKey+wheel delta is proportional to deltaY', () => {
    document.dispatchEvent(new WheelEvent('wheel', { ctrlKey: true, deltaY: -100, cancelable: true, bubbles: true }));
    expect(pinchZoomSpy).toHaveBeenCalledWith(expect.closeTo(1.0, 5));
  });

  test('non-ctrl wheel does NOT post to pinchZoom', () => {
    document.dispatchEvent(new WheelEvent('wheel', { ctrlKey: false, deltaY: -100, cancelable: true, bubbles: true }));
    expect(pinchZoomSpy).not.toHaveBeenCalled();
  });

  test('ctrlKey+wheel without webkit bridge does not throw', () => {
    delete (window as any).webkit;
    expect(() => {
      document.dispatchEvent(new WheelEvent('wheel', { ctrlKey: true, deltaY: -100, cancelable: true, bubbles: true }));
    }).not.toThrow();
  });
});
