import "@testing-library/jest-dom/vitest";
import { beforeEach } from "vitest";

import { installFakeSocket } from "./test-socket";

// Every test gets a socket it controls. Nothing reaches a real network.
beforeEach(() => installFakeSocket());
