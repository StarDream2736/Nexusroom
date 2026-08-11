import { readFileSync } from 'node:fs';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { App } from '../src/renderer/App';

const appSource = readFileSync(new URL('../src/renderer/App.tsx', import.meta.url), 'utf8');
const stylesSource = readFileSync(new URL('../src/renderer/styles.css', import.meta.url), 'utf8');

describe('renderer shell', () => {
  it('renders the title, navigation, workspace, and room information regions', () => {
    const markup = renderToStaticMarkup(<App />);

    expect(markup).toContain('class="title-bar"');
    expect(markup).toContain('aria-label="Primary navigation"');
    expect(markup).toContain('aria-label="Workspace"');
    expect(markup).toContain('aria-label="Room information"');
    expect(markup).toContain('data-theme="dark"');
    expect(markup).toContain('data-authenticated="false"');
  });

  it('shows a direct Chinese login form and no decorative emoji', () => {
    const markup = renderToStaticMarkup(<App />);

    expect(markup).toContain('id="login-title"');
    expect(markup).toContain('服务器地址');
    expect(markup).toContain('账号');
    expect(markup).toContain('密码');
    expect(markup).toContain('登录');
    expect(markup).not.toMatch(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u);
  });

  it('keeps theme switching and member presence on shared neutral tokens', () => {
    const markup = renderToStaticMarkup(<App />);

    expect(markup).toContain('切换到浅色主题');
    expect(stylesSource).toContain('.member-presence');
    expect(stylesSource).toContain('background: var(--text-subtle)');
    expect(stylesSource).toContain('[data-theme="light"]');
  });

  it('routes clear data through the storage bridge without file deletion', () => {
    expect(appSource).toContain('await storage.clearData()');
    expect(appSource).not.toMatch(/(?:unlink|rmdir|rmSync|delete\s+data|dataDirectory)/i);
  });

  it('keeps login and room failures visible through one alert path', () => {
    expect(appSource).toContain('className="error-banner" role="alert"');
    expect(appSource).toContain('setError(errorMessage(loginError))');
    expect(appSource).toContain('setError(errorMessage(roomError))');
  });

  it('routes leaving the selected room through the NexusRoomClient', () => {
    expect(appSource).toContain('await client.leaveRoom(roomId)');
    expect(appSource).toContain('退出房间');
    expect(appSource).toContain('disabled={leavingRoom}');
  });

  it('exposes immediate microphone state and voice-scoped member presence', () => {
    expect(appSource).toContain('data-microphone-state={voiceSnapshot.microphone}');
    expect(appSource).toContain('aria-busy={voiceSnapshot.microphone === \'enabling\' || voiceSnapshot.microphone === \'disabling\'}');
    expect(appSource).toContain('data-presence={isVoiceOnline ? (isSpeaking ? \'speaking\' : \'online\') : \'offline\'}');
    expect(appSource).toContain('voiceSnapshot.participants');
    expect(stylesSource).toContain('.member-presence--speaking');
    expect(stylesSource).toContain('@keyframes voice-presence-breathe');
    expect(stylesSource).toContain('prefers-reduced-motion');
  });
});
