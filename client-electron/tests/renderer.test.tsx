import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { App } from '../src/renderer/App';

describe('renderer shell', () => {
  it('renders the four client regions without a server connection', () => {
    const markup = renderToStaticMarkup(<App />);

    expect(markup).toContain('class="title-bar"');
    expect(markup).toContain('aria-label="Primary navigation"');
    expect(markup).toContain('aria-label="Workspace"');
    expect(markup).toContain('aria-label="Room information"');
    expect(markup).toContain('Workspace ready');
    expect(markup).toContain('No room selected');
    expect(markup).toContain('data-theme="dark"');
  });
});
