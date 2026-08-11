import { useState, type ReactElement } from 'react';
import type { RuntimeInfo } from '../shared/preload-api';

type Theme = 'dark' | 'light';

const navigationItems = [
  { label: 'Rooms', description: 'Shared spaces' },
  { label: 'Friends', description: 'People you know' },
  { label: 'Streams', description: 'Live activity' },
  { label: 'Settings', description: 'Client preferences' },
] as const;

const browserRuntime: RuntimeInfo = {
  platform: 'browser',
  electron: 'preview',
  chrome: 'preview',
};

function readRuntimeInfo(): RuntimeInfo {
  if (typeof window === 'undefined') {
    return browserRuntime;
  }
  return window.nexusroom?.getRuntimeInfo() ?? browserRuntime;
}

export function App(): ReactElement {
  const [theme, setTheme] = useState<Theme>('dark');
  const runtime = readRuntimeInfo();
  const nextTheme: Theme = theme === 'dark' ? 'light' : 'dark';

  return (
    <div className="app-shell" data-theme={theme}>
      <header className="title-bar">
        <div className="title-bar__identity">
          <span className="brand-mark" aria-hidden="true">NR</span>
          <div>
            <p className="eyebrow">Desktop client</p>
            <h1>NexusRoom</h1>
          </div>
        </div>
        <div className="title-bar__actions">
          <span className="runtime-label" title="Provided by the isolated preload bridge">
            {runtime.platform} · Electron {runtime.electron}
          </span>
          <button
            className="theme-toggle"
            type="button"
            aria-label={`Switch to ${nextTheme} theme`}
            onClick={() => setTheme(nextTheme)}
          >
            {nextTheme === 'light' ? 'Light mode' : 'Dark mode'}
          </button>
        </div>
      </header>

      <div className="app-body">
        <nav className="sidebar" aria-label="Primary navigation">
          <div className="sidebar__heading">
            <p className="eyebrow">Navigate</p>
            <span className="sidebar__status"><span className="status-dot" aria-hidden="true" />Local shell</span>
          </div>
          <div className="nav-list">
            {navigationItems.map((item, index) => (
              <a
                className={`nav-item${index === 0 ? ' nav-item--active' : ''}`}
                href={`#${item.label.toLowerCase()}`}
                key={item.label}
                aria-current={index === 0 ? 'page' : undefined}
              >
                <span>{item.label}</span>
                <small>{item.description}</small>
              </a>
            ))}
          </div>
          <div className="sidebar__footer">
            <p className="eyebrow">Runtime</p>
            <p className="muted-copy">Chromium {runtime.chrome}</p>
          </div>
        </nav>

        <main className="workspace" aria-label="Workspace">
          <div className="workspace__header">
            <div>
              <p className="eyebrow">Overview</p>
              <h2>Workspace ready</h2>
            </div>
            <span className="status-chip">Foundation</span>
          </div>
          <section className="empty-state" aria-label="Empty workspace">
            <div className="empty-state__line" aria-hidden="true" />
            <p className="eyebrow">No active room</p>
            <h3>Select a room to begin</h3>
            <p className="muted-copy">This shell is ready for the future room experience.</p>
          </section>
        </main>

        <aside className="room-info" aria-label="Room information">
          <div className="room-info__header">
            <p className="eyebrow">Room panel</p>
            <h2>Room info</h2>
          </div>
          <div className="room-info__empty">
            <span className="room-info__marker" aria-hidden="true" />
            <h3>No room selected</h3>
            <p className="muted-copy">Members, voice, and stream details will appear here.</p>
          </div>
          <div className="room-info__footer">
            <span className="muted-copy">Secure renderer boundary</span>
            <span className="security-badge">Isolated</span>
          </div>
        </aside>
      </div>
    </div>
  );
}
