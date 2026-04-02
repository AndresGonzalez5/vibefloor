// Sprite sheet rendering engine for pixel art characters and office furniture.
// Each char_N.png is 112x96: 7 columns x 3 rows, each frame 16x32.

export type Direction = 'down' | 'up' | 'right' | 'left';

const FRAME_W = 16;
const FRAME_H = 32;
const SHEET_COLS = 7;

const DIRECTION_ROW: Record<Exclude<Direction, 'left'>, number> = {
  down: 0,
  up: 1,
  right: 2,
};

const PALETTE_COUNT = 6;

function assetPath(relative: string): string {
  return `assets/${relative}`;
}

function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error(`Failed to load image: ${src}`));
    img.src = src;
  });
}

// Try to load an image; resolve to null if it fails (optional assets)
function tryLoadImage(src: string): Promise<HTMLImageElement | null> {
  return loadImage(src).catch(() => null);
}

export class SpriteEngine {
  private charSheets: Map<number, HTMLImageElement> = new Map();
  private loaded = false;

  // Floor tiles
  floorTiles: Map<number, HTMLImageElement> = new Map();

  // Furniture images (keyed by name)
  furniture: Map<string, HTMLImageElement> = new Map();

  async loadAll(): Promise<void> {
    if (this.loaded) return;

    // Characters
    const charPromises: Promise<void>[] = [];
    for (let i = 0; i < PALETTE_COUNT; i++) {
      charPromises.push(
        loadImage(assetPath(`characters/char_${i}.png`)).then((img) => {
          this.charSheets.set(i, img);
        }),
      );
    }

    // Floor tiles (0-8)
    const floorPromises: Promise<void>[] = [];
    for (let i = 0; i <= 8; i++) {
      floorPromises.push(
        tryLoadImage(assetPath(`floors/floor_${i}.png`)).then((img) => {
          if (img) this.floorTiles.set(i, img);
        }),
      );
    }

    // Furniture
    const furnitureEntries: [string, string][] = [
      ['desk_front', 'furniture/DESK/DESK_FRONT.png'],
      ['desk_side', 'furniture/DESK/DESK_SIDE.png'],
      ['pc_on', 'furniture/PC/PC_FRONT_ON_1.png'],
      ['pc_off', 'furniture/PC/PC_FRONT_OFF.png'],
      ['pc_side', 'furniture/PC/PC_SIDE.png'],
      ['chair_front', 'furniture/CUSHIONED_CHAIR/CUSHIONED_CHAIR_FRONT.png'],
      ['chair_back', 'furniture/CUSHIONED_CHAIR/CUSHIONED_CHAIR_BACK.png'],
      ['chair_side', 'furniture/CUSHIONED_CHAIR/CUSHIONED_CHAIR_SIDE.png'],
      ['bookshelf', 'furniture/BOOKSHELF/BOOKSHELF.png'],
      ['double_bookshelf', 'furniture/DOUBLE_BOOKSHELF/DOUBLE_BOOKSHELF.png'],
      ['plant', 'furniture/PLANT/PLANT.png'],
      ['large_plant', 'furniture/LARGE_PLANT/LARGE_PLANT.png'],
      ['cactus', 'furniture/CACTUS/CACTUS.png'],
      ['whiteboard', 'furniture/WHITEBOARD/WHITEBOARD.png'],
      ['clock', 'furniture/CLOCK/CLOCK.png'],
      ['coffee', 'furniture/COFFEE/COFFEE.png'],
      ['bin', 'furniture/BIN/BIN.png'],
      ['small_painting', 'furniture/SMALL_PAINTING/SMALL_PAINTING.png'],
      ['large_painting', 'furniture/LARGE_PAINTING/LARGE_PAINTING.png'],
      ['sofa_front', 'furniture/SOFA/SOFA_FRONT.png'],
      ['pot', 'furniture/POT/POT.png'],
      ['plant_2', 'furniture/PLANT_2/PLANT_2.png'],
      ['hanging_plant', 'furniture/HANGING_PLANT/HANGING_PLANT.png'],
      ['small_painting_2', 'furniture/SMALL_PAINTING_2/SMALL_PAINTING_2.png'],
      ['coffee_table', 'furniture/COFFEE_TABLE/COFFEE_TABLE.png'],
      ['small_table_front', 'furniture/SMALL_TABLE/SMALL_TABLE_FRONT.png'],
      ['cushioned_bench', 'furniture/CUSHIONED_BENCH/CUSHIONED_BENCH.png'],
      ['wooden_bench', 'furniture/WOODEN_BENCH/WOODEN_BENCH.png'],
      ['table_front', 'furniture/TABLE_FRONT/TABLE_FRONT.png'],
      ['wall', 'walls/wall_0.png'],
      // Fallback flat files from original location
      ['desk_front_flat', 'furniture/DESK_FRONT.png'],
      ['pc_on_flat', 'furniture/PC_FRONT_ON_1.png'],
    ];

    const furniturePromises = furnitureEntries.map(([key, path]) =>
      tryLoadImage(assetPath(path)).then((img) => {
        if (img) this.furniture.set(key, img);
      }),
    );

    await Promise.all([...charPromises, ...floorPromises, ...furniturePromises]);
    this.loaded = true;
  }

  isLoaded(): boolean {
    return this.loaded;
  }

  getFloorTile(index = 0): HTMLImageElement | null {
    return this.floorTiles.get(index) ?? null;
  }

  getFurniture(name: string): HTMLImageElement | null {
    return this.furniture.get(name) ?? null;
  }

  // Legacy getters for backward compatibility
  getDeskImage(): HTMLImageElement | null {
    return this.getFurniture('desk_front') ?? this.getFurniture('desk_front_flat');
  }

  getPcImage(): HTMLImageElement | null {
    return this.getFurniture('pc_on') ?? this.getFurniture('pc_on_flat');
  }

  drawCharacter(
    ctx: CanvasRenderingContext2D,
    palette: number,
    direction: Direction,
    frameIndex: number,
    x: number,
    y: number,
    zoom: number,
  ): void {
    const sheet = this.charSheets.get(palette);
    if (!sheet) return;

    ctx.imageSmoothingEnabled = false;

    const flipH = direction === 'left';
    const row = DIRECTION_ROW[flipH ? 'right' : direction];
    const col = Math.min(frameIndex, SHEET_COLS - 1);
    const sx = col * FRAME_W;
    const sy = row * FRAME_H;
    const dw = FRAME_W * zoom;
    const dh = FRAME_H * zoom;

    if (flipH) {
      ctx.save();
      ctx.translate(x + dw, y);
      ctx.scale(-1, 1);
      ctx.drawImage(sheet, sx, sy, FRAME_W, FRAME_H, 0, 0, dw, dh);
      ctx.restore();
    } else {
      ctx.drawImage(sheet, sx, sy, FRAME_W, FRAME_H, x, y, dw, dh);
    }
  }

  drawFurniture(
    ctx: CanvasRenderingContext2D,
    image: HTMLImageElement,
    x: number,
    y: number,
    zoom: number,
    mirrored = false,
  ): void {
    ctx.imageSmoothingEnabled = false;
    const dw = image.width * zoom;
    const dh = image.height * zoom;
    if (mirrored) {
      ctx.save();
      ctx.translate(x + dw, y);
      ctx.scale(-1, 1);
      ctx.drawImage(image, 0, 0, dw, dh);
      ctx.restore();
    } else {
      ctx.drawImage(image, x, y, dw, dh);
    }
  }
}
