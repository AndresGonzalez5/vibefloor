import { getRuntime, simulateEvent } from './vibefloorBridge';
import type { AgentEvent } from './types';

const TOOLS = ['Read', 'Edit', 'Write', 'Bash', 'Grep', 'Glob'] as const;

const AGENT_PRESETS = [
  { name: 'Alice', palette: 0 },
  { name: 'Bob', palette: 2 },
  { name: 'Charlie', palette: 4 },
  { name: 'Diana', palette: 1 },
  { name: 'Eve', palette: 3 },
  { name: 'Frank', palette: 5 },
];

const activeAgents = new Map<string, string>(); // id -> name
const busyAgents = new Set<string>(); // agents currently using a tool
const pendingTimeouts: ReturnType<typeof setTimeout>[] = [];

let toolCycleInterval: ReturnType<typeof setInterval> | null = null;
let running = false;

function randomItem<T>(arr: readonly T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

function randomBetween(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

let nextAgentId = 1;

function createAgent(name?: string, palette?: number, parentAgentId?: string): string {
  const id = `dev-agent-${nextAgentId++}`;
  const preset =
    name && palette !== undefined
      ? { name, palette }
      : randomItem(AGENT_PRESETS);

  activeAgents.set(id, preset.name);

  const event: AgentEvent = {
    type: 'agentCreated',
    agentId: id,
    name: preset.name,
    palette: preset.palette,
    parentAgentId,
  };
  simulateEvent(event);
  console.log(`[dev-mode] created agent ${preset.name} (${id})${parentAgentId ? ` as subagent of ${parentAgentId}` : ''}`);
  return id;
}

function removeAgent(agentId: string): void {
  const name = activeAgents.get(agentId);
  activeAgents.delete(agentId);
  busyAgents.delete(agentId);

  simulateEvent({ type: 'agentRemoved', agentId });
  console.log(`[dev-mode] removed agent ${name ?? agentId}`);
}

function startToolCycle(): void {
  if (activeAgents.size === 0) return;

  // Pick a random non-busy agent
  const available = [...activeAgents.keys()].filter(
    (id) => !busyAgents.has(id),
  );
  if (available.length === 0) return;

  const agentId = randomItem(available);
  const tool = randomItem(TOOLS);

  busyAgents.add(agentId);
  simulateEvent({ type: 'agentToolStart', agentId, tool });
  console.log(`[dev-mode] ${activeAgents.get(agentId)} using tool: ${tool}`);

  // Complete the tool after 1-3 seconds
  const duration = randomBetween(1000, 3000);
  const tid = setTimeout(() => {
    if (!running) return;
    busyAgents.delete(agentId);
    simulateEvent({ type: 'agentToolDone', agentId, tool });
  }, duration);
  pendingTimeouts.push(tid);
}

function schedule(delayMs: number, fn: () => void): void {
  const tid = setTimeout(() => {
    if (!running) return;
    fn();
  }, delayMs);
  pendingTimeouts.push(tid);
}

/**
 * Start dev mode with mock agent simulation.
 * Demonstrates all pixel-agents-alive features:
 *   - Main agent creation with matrix spawn effect
 *   - Subagent creation with parent choreography (walk to spawn, briefing bubble)
 *   - Tool-specific bubbles (search, edit, terminal)
 *   - Idle micro-behaviors (head turn, fidget, wander) after >5s idle
 *   - Subagent removal with reporting choreography (walk to parent, reporting bubble, matrix despawn)
 *   - Full cycle repeat
 */
export function startDevMode(): void {
  if (getRuntime() !== 'browser') {
    console.log('[dev-mode] skipped -- not in browser runtime');
    return;
  }

  if (running) {
    console.log('[dev-mode] already running');
    return;
  }

  running = true;
  console.log('[dev-mode] starting pixel-agents-alive demo');

  // 1. Create the main agent (no parentAgentId) — triggers matrix spawn reveal
  const mainId = createAgent('Alice', 0);

  // 2. After 3s, create a subagent — triggers spawn choreography on parent
  //    (parent walks to spawn, matrix reveal, briefing bubble, both walk to seats)
  schedule(3000, () => {
    console.log('[dev-mode] creating subagent — triggers spawn choreography');
    createAgent('Bob', 2, mainId);
  });

  // 3. After 6s, cycle through tools on main agent to show tool-specific bubbles
  schedule(6000, () => {
    console.log('[dev-mode] cycling tools on Alice (search tools → search bubble)');
    simulateEvent({ type: 'agentToolStart', agentId: mainId, tool: 'Grep' });
    schedule(2000, () => {
      simulateEvent({ type: 'agentToolDone', agentId: mainId, tool: 'Grep' });
    });
  });

  schedule(9000, () => {
    const bobId = 'dev-agent-2';
    console.log('[dev-mode] cycling tools on Bob (Edit → edit bubble)');
    simulateEvent({ type: 'agentToolStart', agentId: bobId, tool: 'Edit' });
    schedule(2000, () => {
      simulateEvent({ type: 'agentToolDone', agentId: bobId, tool: 'Edit' });
    });
  });

  schedule(12000, () => {
    console.log('[dev-mode] Alice using Bash (terminal bubble)');
    simulateEvent({ type: 'agentToolStart', agentId: mainId, tool: 'Bash' });
    schedule(2000, () => {
      simulateEvent({ type: 'agentToolDone', agentId: mainId, tool: 'Bash' });
    });
  });

  // 4. Let agents idle for >5s so micro-behaviors trigger (head turns, fidgets, wanders)
  //    This happens naturally between 14s-20s since no tool events are sent
  schedule(15000, () => {
    console.log('[dev-mode] agents should now be idle — watch for micro-behaviors (head turns, fidgets, wanders)');
  });

  // 5. After ~20s, remove the subagent — triggers reporting choreography
  //    (walk to parent, reporting bubble, matrix despawn)
  schedule(20000, () => {
    const bobId = 'dev-agent-2';
    if (activeAgents.has(bobId)) {
      console.log('[dev-mode] removing subagent Bob — triggers reporting choreography');
      removeAgent(bobId);
    }
  });

  // 6. After ~25s, create another subagent to show the cycle again
  schedule(25000, () => {
    console.log('[dev-mode] creating second subagent — demonstrating full cycle repeat');
    createAgent('Charlie', 4, mainId);
  });

  // 7. Start tool usage cycles every 3-5 seconds for ongoing activity
  schedule(28000, () => {
    console.log('[dev-mode] starting continuous tool cycle');
    toolCycleInterval = setInterval(
      () => startToolCycle(),
      randomBetween(3000, 5000),
    );
  });
}

/**
 * Stop dev mode and clean up all intervals and timeouts.
 */
export function stopDevMode(): void {
  if (!running) return;

  running = false;
  console.log('[dev-mode] stopping mock agent simulation');

  if (toolCycleInterval) {
    clearInterval(toolCycleInterval);
    toolCycleInterval = null;
  }

  // Clear all scheduled timeouts
  for (const tid of pendingTimeouts) {
    clearTimeout(tid);
  }
  pendingTimeouts.length = 0;

  // Remove all simulated agents
  for (const agentId of [...activeAgents.keys()]) {
    removeAgent(agentId);
  }
}
