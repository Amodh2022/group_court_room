/** A WebSocket the tests drive by hand.
 *
 *  jsdom ships a real WebSocket that would try to reach localhost. Tests install
 *  this instead, then push frames at the page exactly as the server would.
 */
export class FakeSocket {
  static instances: FakeSocket[] = [];
  static readonly OPEN = 1;
  static readonly CLOSED = 3;

  readyState = 0;
  sent: Record<string, unknown>[] = [];
  onopen: (() => void) | null = null;
  onmessage: ((event: { data: string }) => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;

  constructor(public url: string) {
    FakeSocket.instances.push(this);
  }

  send(data: string): void {
    this.sent.push(JSON.parse(data));
  }

  close(): void {
    this.readyState = FakeSocket.CLOSED;
    this.onclose?.();
  }

  // --- test controls -------------------------------------------------------

  /** The connection opens; the page authenticates. */
  open(): void {
    this.readyState = FakeSocket.OPEN;
    this.onopen?.();
  }

  /** The server sends a frame. */
  push(frame: Record<string, unknown>): void {
    this.onmessage?.({ data: JSON.stringify(frame) });
  }

  /** The connection drops without the page asking. */
  drop(): void {
    this.readyState = FakeSocket.CLOSED;
    this.onclose?.();
  }

  static get latest(): FakeSocket {
    return FakeSocket.instances[FakeSocket.instances.length - 1];
  }

  static reset(): void {
    FakeSocket.instances = [];
  }
}

export function installFakeSocket(): void {
  FakeSocket.reset();
  (globalThis as unknown as { WebSocket: unknown }).WebSocket = FakeSocket;
}
