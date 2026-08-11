import { readFileSync } from 'node:fs';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { App } from '../src/renderer/App';

const appSource = readFileSync(new URL('../src/renderer/App.tsx', import.meta.url), 'utf8');
const stylesSource = readFileSync(new URL('../src/renderer/styles.css', import.meta.url), 'utf8');
const playerSource = readFileSync(new URL('../src/renderer/live-player.ts', import.meta.url), 'utf8');

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

  it('keeps stream ingress management in the room side panel', () => {
    expect(appSource).toContain('listRoomIngresses');
    expect(appSource).toContain('createRoomIngress');
    expect(appSource).toContain('deleteRoomIngress');
    expect(appSource).toContain('aria-label="推流入口"');
    expect(appSource).toContain('publishUrl');
  });

  it('keeps VLAN controls and Peer state in the room side panel', () => {
    expect(appSource).toContain('aria-label="房间 VLAN"');
    expect(appSource).toContain('启用 VLAN');
    expect(appSource).toContain('vlanSnapshot');
    expect(appSource).toContain('刷新 Peer');
    expect(appSource).toContain('navigator.clipboard.writeText');
    expect(appSource).toContain('虚拟 IPv4');
    expect(appSource).toContain('await client.leaveVlan()');
    expect(stylesSource).toContain('.vlan-section');
    expect(stylesSource).toContain('.vlan-status--connected');
  });

  it('cleans VLAN before room, account, and local-data lifecycle exits', () => {
    expect(appSource).toContain('await client.leaveVlan(roomId)');
    expect(appSource).toContain('await client.leaveVlan();');
    expect(appSource).toContain('await storage.clearData()');
  });

  it('cleans the old VLAN before clearing kicked or disbanded room UI', () => {
    expect(appSource).toContain('cleanupVlan(currentRoomId);');
    expect(appSource).toContain('cleanupVlan(selectedRoomIdRef.current);');
    expect(appSource.indexOf('cleanupVlan(currentRoomId);')).toBeLessThan(
      appSource.indexOf('setSelectedRoomId(null);', appSource.indexOf('cleanupVlan(currentRoomId);')),
    );
    expect(appSource.indexOf('cleanupVlan(selectedRoomIdRef.current);')).toBeLessThan(
      appSource.indexOf('setSelectedRoomId(null);', appSource.indexOf('cleanupVlan(selectedRoomIdRef.current);')),
    );
  });

  it('clears copied VLAN IP errors when the selected room changes', () => {
    expect(appSource).toContain('setVlanCopyError(null);');
  });

  it('shows an independent default-audible player with protocol controls', () => {
    expect(appSource).toContain('直播静音');
    expect(appSource).toContain('刷新播放');
    expect(appSource).toContain('关闭播放');
    expect(appSource).toContain('点击恢复播放');
    expect(playerSource).toContain('this.video.muted = false');
    expect(playerSource).toContain("protocol: 'webrtc'");
    expect(playerSource).toContain("protocol: 'flv'");
    expect(playerSource).toContain('FLV_RETRY_DELAYS_MS');
  });
});
