import { describe, expect, it, vi } from 'vitest';
import { WsClient, type WebSocketLike } from '../src/main/ws-client';

class FakeSocket implements WebSocketLike {
  onopen: ((event: unknown) => void) | null = null;
  onmessage: ((event: { readonly data: unknown }) => void) | null = null;
  onerror: ((event: unknown) => void) | null = null;
  onclose: ((event: unknown) => void) | null = null;
  readonly sent: string[] = [];

  send(data: string): void {
    this.sent.push(data);
  }

  close(): void {}

  open(): void {
    this.onopen?.({});
  }

  message(value: unknown): void {
    this.onmessage?.({ data: JSON.stringify(value) });
  }

  closeUnexpectedly(): void {
    this.onclose?.({});
  }
}

describe('WsClient', () => {
  it('authenticates one connection and de-duplicates event subscriptions', () => {
    const sockets: FakeSocket[] = [];
    const client = new WsClient({
      webSocketFactory: (url) => {
        expect(url).toBe('wss://example.com/ws?token=secret-token');
        const socket = new FakeSocket();
        sockets.push(socket);
        return socket;
      },
    });
    const listener = vi.fn();
    client.on('chat.message', listener);
    client.on('chat.message', listener);

    client.connect('https://example.com/', 'secret-token');
    client.connect('https://example.com', 'secret-token');
    expect(sockets).toHaveLength(1);
    sockets[0]?.open();
    expect(client.state).toBe('connecting');
    expect(() => client.send('heartbeat')).toThrow('尚未连接');
    sockets[0]?.message({ event: 'connected' });
    expect(client.state).toBe('connected');
    sockets[0]?.message({ event: 'chat.message', payload: { id: 1 } });
    client.send('heartbeat');

    expect(listener).toHaveBeenCalledTimes(1);
    expect(sockets[0]?.sent[0]).toContain('"event":"heartbeat"');
    expect(sockets[0]?.sent[0]).not.toContain('secret-token');
    client.disconnect();
  });

  it('uses bounded exponential reconnect attempts', () => {
    vi.useFakeTimers();
    const sockets: FakeSocket[] = [];
    const client = new WsClient({
      webSocketFactory: () => {
        const socket = new FakeSocket();
        sockets.push(socket);
        return socket;
      },
      maxReconnectAttempts: 2,
      reconnectBaseDelayMs: 10,
      reconnectMaxDelayMs: 100,
    });

    client.connect('https://example.com', 'secret-token');
    sockets[0]?.closeUnexpectedly();
    vi.advanceTimersByTime(9);
    expect(sockets).toHaveLength(1);
    vi.advanceTimersByTime(1);
    expect(sockets).toHaveLength(2);
    sockets[1]?.closeUnexpectedly();
    vi.advanceTimersByTime(19);
    expect(sockets).toHaveLength(2);
    vi.advanceTimersByTime(1);
    expect(sockets).toHaveLength(3);
    sockets[2]?.closeUnexpectedly();
    vi.advanceTimersByTime(100);
    expect(sockets).toHaveLength(3);

    client.disconnect();
    vi.useRealTimers();
  });

  it('sends one heartbeat timer only after connected and stops after disconnect', () => {
    vi.useFakeTimers();
    const sockets: FakeSocket[] = [];
    const client = new WsClient({
      webSocketFactory: () => {
        const socket = new FakeSocket();
        sockets.push(socket);
        return socket;
      },
      heartbeatIntervalMs: 30,
    });

    client.connect('https://example.com', 'secret-token');
    sockets[0]?.open();
    vi.advanceTimersByTime(100);
    expect(sockets[0]?.sent).toHaveLength(0);

    sockets[0]?.message({ event: 'connected' });
    vi.advanceTimersByTime(29);
    expect(sockets[0]?.sent).toHaveLength(0);
    vi.advanceTimersByTime(1);
    expect(JSON.parse(sockets[0]?.sent[0] ?? '{}')).toMatchObject({
      event: 'heartbeat',
    });
    vi.advanceTimersByTime(60);
    expect(sockets[0]?.sent).toHaveLength(3);

    client.disconnect();
    vi.advanceTimersByTime(100);
    expect(sockets[0]?.sent).toHaveLength(3);
    vi.useRealTimers();
  });

  it('requires a positive heartbeat interval', () => {
    expect(() => new WsClient({ heartbeatIntervalMs: 0 })).toThrow(
      '重连参数无效',
    );
    expect(() => new WsClient({ heartbeatIntervalMs: -1 })).toThrow(
      '重连参数无效',
    );
  });

  it('reconnects after the business connected watchdog expires', () => {
    vi.useFakeTimers();
    const sockets: FakeSocket[] = [];
    const client = new WsClient({
      webSocketFactory: () => {
        const socket = new FakeSocket();
        sockets.push(socket);
        return socket;
      },
      maxReconnectAttempts: 1,
      reconnectBaseDelayMs: 10,
      reconnectMaxDelayMs: 10,
      connectTimeoutMs: 20,
    });

    client.connect('https://example.com', 'secret-token');
    sockets[0]?.open();
    expect(client.state).toBe('connecting');
    vi.advanceTimersByTime(19);
    expect(sockets).toHaveLength(1);
    vi.advanceTimersByTime(1);
    expect(client.state).toBe('disconnected');
    vi.advanceTimersByTime(9);
    expect(sockets).toHaveLength(1);
    vi.advanceTimersByTime(1);
    expect(sockets).toHaveLength(2);
    expect(client.state).toBe('connecting');
    vi.advanceTimersByTime(20);
    vi.advanceTimersByTime(10);
    expect(sockets).toHaveLength(2);

    client.disconnect();
    vi.useRealTimers();
  });

  it('does not reconnect after explicit disconnect', () => {
    vi.useFakeTimers();
    const sockets: FakeSocket[] = [];
    const client = new WsClient({
      webSocketFactory: () => {
        const socket = new FakeSocket();
        sockets.push(socket);
        return socket;
      },
      reconnectBaseDelayMs: 10,
    });

    client.connect('https://example.com', 'secret-token');
    client.disconnect();
    sockets[0]?.closeUnexpectedly();
    vi.advanceTimersByTime(1_000);

    expect(sockets).toHaveLength(1);
    expect(client.state).toBe('disconnected');
    vi.useRealTimers();
  });
});
