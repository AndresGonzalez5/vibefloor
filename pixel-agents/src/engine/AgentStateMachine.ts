// Per-agent state machine managing animation state and transitions.

import type { Direction } from './SpriteEngine';

export type AgentState = 'idle' | 'type' | 'read' | 'walk' | 'wait';

// Animation frame sequences and timing per state
const ANIM_FRAMES: Record<AgentState, number[]> = {
  walk: [0, 1, 2, 1],
  type: [3, 4],
  read: [5, 6],
  idle: [1],
  wait: [1, 1, 0, 1],
};

const FRAME_DURATION: Record<AgentState, number> = {
  walk: 0.15,
  type: 0.3,
  read: 0.3,
  idle: 1.0,
  wait: 0.8,
};

// Map tool names to agent states
const TOOL_STATE_MAP: Record<string, AgentState> = {
  Read: 'read',
  Grep: 'read',
  Glob: 'read',
  WebFetch: 'read',
  WebSearch: 'read',
  Edit: 'type',
  Write: 'type',
  Bash: 'type',
  NotebookEdit: 'type',
};

export function toolToState(toolName: string): AgentState {
  return TOOL_STATE_MAP[toolName] ?? 'type';
}

export class AgentStateMachine {
  state: AgentState = 'idle';
  direction: Direction = 'down';
  private frameIndex = 0;
  private frameTimer = 0;

  update(dt: number): void {
    const frames = ANIM_FRAMES[this.state];
    if (frames.length <= 1) return;

    this.frameTimer += dt;
    const duration = FRAME_DURATION[this.state];
    if (this.frameTimer >= duration) {
      this.frameTimer -= duration;
      this.frameIndex = (this.frameIndex + 1) % frames.length;
    }
  }

  transition(newState: AgentState): void {
    this.state = newState;
    this.frameIndex = 0;
    this.frameTimer = 0;

    // Set a sensible direction for desk activities
    if (newState === 'type' || newState === 'read') {
      this.direction = 'down';
    }
  }

  getCurrentFrame(): number {
    const frames = ANIM_FRAMES[this.state];
    return frames[this.frameIndex % frames.length];
  }
}
