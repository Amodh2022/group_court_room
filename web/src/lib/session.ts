/** Browser-side identity.
 *
 *  Two unrelated things live here. The access token is an account credential.
 *  The juror key is not: it is an anonymous per-device id that lets the server
 *  tell one juror from another without anyone signing in. Neither is a secret
 *  worth defending against someone who already has the device.
 */

const TOKEN_KEY = "gcc.token";
const SUBJECT_KEY = "gcc.subject";
const NAME_KEY = "gcc.name";
const JUROR_KEY = "gcc.juror";
const JUROR_NAME_KEY = "gcc.juror-name";

function read(key: string): string | null {
  try {
    return window.localStorage.getItem(key);
  } catch {
    // Private mode, blocked storage, or an embedded webview. Not fatal: the
    // user signs in again instead of seeing a broken page.
    return null;
  }
}

function write(key: string, value: string): void {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    /* ignore — see read() */
  }
}

function randomId(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export const session = {
  get token(): string | null {
    return read(TOKEN_KEY);
  },

  get displayName(): string | null {
    return read(NAME_KEY);
  },

  /** Stable per-browser account id, minted on first sign-in. */
  subject(): string {
    const existing = read(SUBJECT_KEY);
    if (existing) return existing;
    const subject = `web|${randomId()}`;
    write(SUBJECT_KEY, subject);
    return subject;
  },

  /** Stable per-browser juror id. One device, one ballot. */
  jurorKey(): string {
    const existing = read(JUROR_KEY);
    if (existing) return existing;
    const key = `juror-${randomId()}`;
    write(JUROR_KEY, key);
    return key;
  },

  /** The name a juror asked to be called, remembered across cases on this device. */
  get jurorName(): string | null {
    return read(JUROR_NAME_KEY);
  },

  setJurorName(name: string): void {
    write(JUROR_NAME_KEY, name);
  },

  signIn(token: string, displayName: string): void {
    write(TOKEN_KEY, token);
    write(NAME_KEY, displayName);
  },

  signOut(): void {
    try {
      window.localStorage.removeItem(TOKEN_KEY);
      window.localStorage.removeItem(NAME_KEY);
    } catch {
      /* ignore — see read() */
    }
  },

  get isSignedIn(): boolean {
    return Boolean(read(TOKEN_KEY));
  },
};
