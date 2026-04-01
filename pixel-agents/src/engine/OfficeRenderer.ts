// Main render loop: draws a compact office scene sized for a ~200px tall panel.

import type { AgentManager } from './AgentManager';
import type { SpriteEngine } from './SpriteEngine';

const ZOOM = 3;
const TILE_SIZE = 16;
const LABEL_FONT = '10px monospace';
const LABEL_COLOR = '#e0e0e0';
const LABEL_SHADOW = '#000000';

// Wall: just 1 tile row to save vertical space
const WALL_ROWS = 1;
const WALL_COLOR = '#3a3a5c';

// Floor tile
const FLOOR_TILE_INDEX = 2;

// Layout: designed for ~200px panel height
// Wall = 48px, then content starts
const CONTENT_TOP = TILE_SIZE * ZOOM * WALL_ROWS; // 48px

// Character position: start just below wall, label above
const CHAR_Y = CONTENT_TOP + 20;         // ~68px from top
const CHAR_SITTING_Y = CONTENT_TOP + 14; // slightly higher when at desk

// Desk position: overlaps lower half of character (occludes legs)
const DESK_Y = CHAR_Y + 52;  // ~120px from top — desk top aligns with character waist

// PC sits on desk surface
const PC_Y = DESK_Y - 28; // above desk top

// Chair behind character when sitting
const CHAIR_Y = CHAR_SITTING_Y - 16;

// Workstation spacing
const MAX_WORKSTATIONS = 5;
const WORKSTATION_SPACING = 160;
const WORKSTATION_BASE_X = 80;

export class OfficeRenderer {
  private canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D;
  private sprites: SpriteEngine;
  private agentManager: AgentManager;
  private rafId: number | null = null;
  private lastTime = 0;
  private running = false;

  constructor(
    canvas: HTMLCanvasElement,
    sprites: SpriteEngine,
    agentManager: AgentManager,
  ) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d')!;
    this.sprites = sprites;
    this.agentManager = agentManager;
  }

  start(): void {
    if (this.running) return;
    this.running = true;
    this.lastTime = performance.now();
    this.resize();
    this.rafId = requestAnimationFrame((t) => this.loop(t));
  }

  stop(): void {
    this.running = false;
    if (this.rafId !== null) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }
  }

  resize(): void {
    const dpr = window.devicePixelRatio || 1;
    const parent = this.canvas.parentElement;
    const w = parent ? parent.clientWidth : window.innerWidth;
    const h = parent ? parent.clientHeight : window.innerHeight;
    this.canvas.width = w * dpr;
    this.canvas.height = h * dpr;
    this.canvas.style.width = `${w}px`;
    this.canvas.style.height = `${h}px`;
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  private loop(time: number): void {
    if (!this.running) return;
    const dt = Math.min((time - this.lastTime) / 1000, 0.1);
    this.lastTime = time;
    this.agentManager.updateAll(dt);
    this.draw();
    this.rafId = requestAnimationFrame((t) => this.loop(t));
  }

  private draw(): void {
    const ctx = this.ctx;
    const parent = this.canvas.parentElement;
    const w = parent ? parent.clientWidth : window.innerWidth;
    const h = parent ? parent.clientHeight : window.innerHeight;

    ctx.fillStyle = '#2a2a3e';
    ctx.fillRect(0, 0, w, h);

    this.drawWall(w);
    this.drawFloor(w, h);

    // Wall decorations (compact — only small items that fit in 1 row)
    this.drawWallDecorations(w);

    // Draw workstations
    const agents = this.agentManager.getAgents();
    const numStations = Math.max(agents.length, 1);

    for (let i = 0; i < Math.min(numStations, MAX_WORKSTATIONS); i++) {
      const sx = WORKSTATION_BASE_X + i * WORKSTATION_SPACING;
      const agent = agents[i];
      const isWorking = agent && (agent.stateMachine.state === 'type' || agent.stateMachine.state === 'read');

      // Layer 1: Chair (behind character)
      if (isWorking) {
        const chairImg = this.sprites.getFurniture('chair_back');
        if (chairImg) {
          this.sprites.drawFurniture(ctx, chairImg, sx + 8, CHAIR_Y, ZOOM);
        }
      }

      // Layer 2: PC on desk (behind character, to the right side)
      if (isWorking) {
        const pcImg = this.sprites.getPcImage();
        if (pcImg) {
          this.sprites.drawFurniture(ctx, pcImg, sx + 40, PC_Y, ZOOM);
        }
      }

      // Layer 3: Character (in front of PC)
      if (agent) {
        const sm = agent.stateMachine;
        const cy = isWorking ? CHAR_SITTING_Y : CHAR_Y;

        this.sprites.drawCharacter(ctx, agent.palette, sm.direction, sm.getCurrentFrame(), sx, cy, ZOOM);

        // Label above character
        this.drawLabel(ctx, agent.name, sx + (16 * ZOOM) / 2, cy - 4);
      }

      // Layer 4: Desk (always visible, in front of character legs)
      const deskImg = this.sprites.getDeskImage();
      if (deskImg) {
        this.sprites.drawFurniture(ctx, deskImg, sx - 8, DESK_Y, ZOOM);
      }
    }

    // Floor decorations (only small items that fit)
    this.drawFloorDecorations(w, h);
  }

  private drawWall(w: number): void {
    const ctx = this.ctx;
    const wallTile = this.sprites.getFurniture('wall');
    const wallH = CONTENT_TOP;

    if (wallTile) {
      ctx.imageSmoothingEnabled = false;
      const tw = wallTile.width * ZOOM;
      const th = wallTile.height * ZOOM;
      for (let y = 0; y < wallH; y += th) {
        for (let x = 0; x < w; x += tw) {
          ctx.drawImage(wallTile, x, y, tw, th);
        }
      }
    } else {
      ctx.fillStyle = WALL_COLOR;
      ctx.fillRect(0, 0, w, wallH);
    }

    // Baseboard
    ctx.fillStyle = '#555577';
    ctx.fillRect(0, wallH - 2, w, 2);
  }

  private drawFloor(w: number, h: number): void {
    const tile = this.sprites.getFloorTile(FLOOR_TILE_INDEX) ?? this.sprites.getFloorTile(0);
    if (!tile) return;

    const ctx = this.ctx;
    ctx.imageSmoothingEnabled = false;
    const tw = tile.width * ZOOM;
    const th = tile.height * ZOOM;

    for (let y = CONTENT_TOP; y < h; y += th) {
      for (let x = 0; x < w; x += tw) {
        ctx.drawImage(tile, x, y, tw, th);
      }
    }
  }

  private drawWallDecorations(w: number): void {
    const ctx = this.ctx;
    // Small decorations that fit in 1 tile row (48px)
    const clock = this.sprites.getFurniture('clock');
    if (clock) {
      this.sprites.drawFurniture(ctx, clock, 16, CONTENT_TOP - clock.height * ZOOM + 4, ZOOM);
    }

    const smallPainting = this.sprites.getFurniture('small_painting');
    if (smallPainting) {
      this.sprites.drawFurniture(ctx, smallPainting, w / 2 - (smallPainting.width * ZOOM) / 2, CONTENT_TOP - smallPainting.height * ZOOM + 4, ZOOM);
    }
  }

  private drawFloorDecorations(w: number, _h: number): void {
    const ctx = this.ctx;
    // Small plants that don't overwhelm the compact space
    const cactus = this.sprites.getFurniture('cactus');
    if (cactus) {
      this.sprites.drawFurniture(ctx, cactus, w - 50, CONTENT_TOP + 4, ZOOM);
    }

    const pot = this.sprites.getFurniture('pot');
    if (pot) {
      this.sprites.drawFurniture(ctx, pot, 16, CONTENT_TOP + 50, ZOOM);
    }
  }

  private drawLabel(ctx: CanvasRenderingContext2D, text: string, cx: number, y: number): void {
    ctx.font = LABEL_FONT;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'bottom';
    ctx.fillStyle = LABEL_SHADOW;
    ctx.fillText(text, cx + 1, y + 1);
    ctx.fillStyle = LABEL_COLOR;
    ctx.fillText(text, cx, y);
  }
}
