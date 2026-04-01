// Renders thought/action bubbles above agents showing tool activity icons.
// Phase 3: placeholder visuals (filled rect with border + triangle pointer).
// API is designed for sprite-based rendering when hand-drawn icons are available.

export type BubbleIcon = 'search' | 'edit' | 'terminal' | 'wait' | 'error' | 'done' | 'briefing' | 'reporting';

export interface BubbleState {
  icon: BubbleIcon;
  opacity: number;      // 0.0 to 1.0
  fadePhase: 'in' | 'hold' | 'out';
  timer: number;        // seconds in current phase
  holdDuration: number; // how long at full opacity
}

const FADE_IN_DURATION = 0.15;
const FADE_OUT_DURATION = 0.3;
const DEFAULT_HOLD_DURATION = 2.0;

// Map Claude Code tool names to bubble icons
const TOOL_ICON_MAP: Record<string, BubbleIcon> = {
  Read: 'search',
  Grep: 'search',
  Glob: 'search',
  WebFetch: 'search',
  WebSearch: 'search',
  Edit: 'edit',
  Write: 'edit',
  Bash: 'terminal',
  NotebookEdit: 'terminal',
};

// Placeholder bubble dimensions (will be replaced by sprite dimensions)
const BUBBLE_W = 20;
const BUBBLE_H = 16;
const BUBBLE_RADIUS = 3;
const POINTER_H = 4;
const BUBBLE_OFFSET_Y = 4; // gap above agent head

const ICON_LABELS: Record<BubbleIcon, string> = {
  search: '🔍',
  edit: '✏️',
  terminal: '💻',
  wait: '💭',
  error: '⚠️',
  done: '✅',
  briefing: '📋',
  reporting: '📝',
};

export class BubbleRenderer {
  /**
   * Create a new bubble state that starts fading in.
   */
  static show(icon: BubbleIcon, holdDuration?: number): BubbleState {
    return {
      icon,
      opacity: 0,
      fadePhase: 'in',
      timer: 0,
      holdDuration: holdDuration ?? DEFAULT_HOLD_DURATION,
    };
  }

  /**
   * Advance the bubble's fade state. Returns true if still active, false if done.
   */
  static update(state: BubbleState, dt: number): boolean {
    state.timer += dt;

    switch (state.fadePhase) {
      case 'in':
        state.opacity = Math.min(1, state.timer / FADE_IN_DURATION);
        if (state.timer >= FADE_IN_DURATION) {
          state.fadePhase = 'hold';
          state.timer = 0;
          state.opacity = 1;
        }
        return true;

      case 'hold':
        state.opacity = 1;
        if (state.timer >= state.holdDuration) {
          state.fadePhase = 'out';
          state.timer = 0;
        }
        return true;

      case 'out':
        state.opacity = Math.max(0, 1 - state.timer / FADE_OUT_DURATION);
        if (state.timer >= FADE_OUT_DURATION) {
          state.opacity = 0;
          return false;
        }
        return true;
    }
  }

  /**
   * Draw the bubble above an agent.
   * cx: center X of the agent, topY: top edge of the agent sprite, zoom: render scale.
   * Phase 3 placeholder: white rounded rect with border + triangle pointer.
   * Will be replaced with sprite-based icon drawing when assets are available.
   */
  static draw(
    ctx: CanvasRenderingContext2D,
    state: BubbleState,
    cx: number,
    topY: number,
    zoom: number,
  ): void {
    if (state.opacity <= 0) return;

    const savedAlpha = ctx.globalAlpha;
    ctx.globalAlpha = state.opacity;

    const scale = zoom;
    const w = BUBBLE_W * scale;
    const h = BUBBLE_H * scale;
    const r = BUBBLE_RADIUS * scale;
    const ptrH = POINTER_H * scale;
    const offsetY = BUBBLE_OFFSET_Y * scale;

    // Position: centered above agent, above topY
    const bx = cx - w / 2;
    const by = topY - h - ptrH - offsetY;

    // Draw rounded rect body
    ctx.beginPath();
    ctx.moveTo(bx + r, by);
    ctx.lineTo(bx + w - r, by);
    ctx.arcTo(bx + w, by, bx + w, by + r, r);
    ctx.lineTo(bx + w, by + h - r);
    ctx.arcTo(bx + w, by + h, bx + w - r, by + h, r);
    ctx.lineTo(bx + w / 2 + ptrH, by + h);
    // Triangle pointer
    ctx.lineTo(cx, by + h + ptrH);
    ctx.lineTo(bx + w / 2 - ptrH, by + h);
    ctx.lineTo(bx + r, by + h);
    ctx.arcTo(bx, by + h, bx, by + h - r, r);
    ctx.lineTo(bx, by + r);
    ctx.arcTo(bx, by, bx + r, by, r);
    ctx.closePath();

    ctx.fillStyle = '#ffffff';
    ctx.fill();
    ctx.strokeStyle = '#555555';
    ctx.lineWidth = Math.max(1, scale * 0.5);
    ctx.stroke();

    // Draw placeholder icon label
    const fontSize = Math.round(8 * scale);
    ctx.font = `${fontSize}px sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = '#333333';
    ctx.fillText(ICON_LABELS[state.icon], cx, by + h / 2);

    ctx.globalAlpha = savedAlpha;
  }

  /**
   * Map a Claude Code tool name to a BubbleIcon.
   */
  static iconForTool(toolName: string): BubbleIcon {
    return TOOL_ICON_MAP[toolName] ?? 'terminal';
  }
}
