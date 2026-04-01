// MatrixEffect: column-by-column pixel reveal/hide effect for agent spawn/despawn.
// Works on 16x32 pixel character sprites.

import type { SpriteEngine } from './SpriteEngine';
import type { Agent } from './AgentManager';

const CHAR_W = 16;
const CHAR_H = 32;
const DEFAULT_DURATION = 0.3;
const TOTAL_COLUMNS = 16;

// Green tint for the leading edge columns (#00FF41 at 50% mix)
const TINT_R = 0x00;
const TINT_G = 0xff;
const TINT_B = 0x41;
const TINT_MIX = 0.5;

export interface MatrixState {
  type: 'reveal' | 'hide';
  progress: number; // 0.0 to 1.0
  duration: number; // seconds
  columnsRevealed: number; // 0-16
}

// Reusable offscreen canvas (created lazily)
let offscreenCanvas: OffscreenCanvas | null = null;
let offscreenCtx: OffscreenCanvasRenderingContext2D | null = null;

function getOffscreenCanvas(): {
  canvas: OffscreenCanvas;
  ctx: OffscreenCanvasRenderingContext2D;
} {
  if (!offscreenCanvas || !offscreenCtx) {
    offscreenCanvas = new OffscreenCanvas(CHAR_W, CHAR_H);
    offscreenCtx = offscreenCanvas.getContext('2d')!;
  }
  return { canvas: offscreenCanvas, ctx: offscreenCtx };
}

export class MatrixEffect {
  static createReveal(duration?: number): MatrixState {
    return {
      type: 'reveal',
      progress: 0,
      duration: duration ?? DEFAULT_DURATION,
      columnsRevealed: 0,
    };
  }

  static createHide(duration?: number): MatrixState {
    return {
      type: 'hide',
      progress: 0,
      duration: duration ?? DEFAULT_DURATION,
      columnsRevealed: TOTAL_COLUMNS,
    };
  }

  /** Advance the effect. Returns true if still active, false if complete. */
  static update(state: MatrixState, dt: number): boolean {
    state.progress = Math.min(state.progress + dt / state.duration, 1.0);

    if (state.type === 'reveal') {
      state.columnsRevealed = Math.round(state.progress * TOTAL_COLUMNS);
    } else {
      // Hide: columns go from 16 down to 0
      state.columnsRevealed = Math.round((1 - state.progress) * TOTAL_COLUMNS);
    }

    return state.progress < 1.0;
  }

  /**
   * Draw a character with the matrix effect applied.
   * Uses an offscreen canvas to manipulate pixel data per-column.
   */
  static draw(
    ctx: CanvasRenderingContext2D,
    sprites: SpriteEngine,
    agent: Agent,
    zoom: number,
  ): void {
    const state = agent.matrixState;
    if (!state) return;

    const { canvas: offCanvas, ctx: offCtx } = getOffscreenCanvas();
    const sm = agent.stateMachine;

    // Clear and draw sprite to offscreen canvas at 1:1 scale
    offCtx.clearRect(0, 0, CHAR_W, CHAR_H);
    sprites.drawCharacter(
      offCtx as unknown as CanvasRenderingContext2D,
      agent.palette,
      sm.direction,
      sm.getCurrentFrame(),
      0,
      0,
      1, // zoom=1 for offscreen
    );

    // Get pixel data and apply column effects
    const imageData = offCtx.getImageData(0, 0, CHAR_W, CHAR_H);
    const data = imageData.data;
    const cols = state.columnsRevealed;

    for (let y = 0; y < CHAR_H; y++) {
      for (let x = 0; x < CHAR_W; x++) {
        const idx = (y * CHAR_W + x) * 4;

        if (x >= cols) {
          // Column not yet revealed (or already hidden) — make invisible
          data[idx + 3] = 0;
        } else if (x >= cols - 2 && x < cols) {
          // Leading edge: apply green tint (#00FF41 at 50% mix)
          if (data[idx + 3] > 0) {
            data[idx] = Math.round(data[idx] * (1 - TINT_MIX) + TINT_R * TINT_MIX);
            data[idx + 1] = Math.round(
              data[idx + 1] * (1 - TINT_MIX) + TINT_G * TINT_MIX,
            );
            data[idx + 2] = Math.round(
              data[idx + 2] * (1 - TINT_MIX) + TINT_B * TINT_MIX,
            );
          }
        }
        // Columns left of the leading edge: fully visible (no changes needed)
      }
    }

    offCtx.putImageData(imageData, 0, 0);

    // Draw the modified offscreen canvas to the main canvas with zoom
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(
      offCanvas,
      agent.pixelX,
      agent.pixelY,
      CHAR_W * zoom,
      CHAR_H * zoom,
    );
  }
}
