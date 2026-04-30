// Grid-based tile map with BFS pathfinding for the office layout.

export type TileCoord = [number, number]; // [col, row]

export class TileMap {
  cols: number;
  readonly rows: number;
  private tileSize: number;
  private zoom: number;
  private blocked: Set<string> = new Set();

  constructor(cols: number, rows: number, tileSize: number, zoom: number) {
    this.cols = cols;
    this.rows = rows;
    this.tileSize = tileSize;
    this.zoom = zoom;
  }

  private key(col: number, row: number): string {
    return `${col},${row}`;
  }

  setCols(cols: number): void {
    this.cols = cols;
  }

  clearBlocks(): void {
    this.blocked.clear();
  }

  block(col: number, row: number): void {
    this.blocked.add(this.key(col, row));
  }

  unblock(col: number, row: number): void {
    this.blocked.delete(this.key(col, row));
  }

  isWalkable(col: number, row: number): boolean {
    if (col < 0 || row < 0 || col >= this.cols || row >= this.rows) return false;
    return !this.blocked.has(this.key(col, row));
  }

  tileToPixel(col: number, row: number): { x: number; y: number } {
    return {
      x: col * this.tileSize * this.zoom,
      y: row * this.tileSize * this.zoom,
    };
  }

  pixelToTile(x: number, y: number): TileCoord {
    const step = this.tileSize * this.zoom;
    return [Math.floor(x / step), Math.floor(y / step)];
  }

  findPath(from: TileCoord, to: TileCoord): TileCoord[] {
    const [fc, fr] = from;
    const [tc, tr] = to;

    // Early exits
    if (!this.isWalkable(fc, fr) || !this.isWalkable(tc, tr)) return [];
    if (fc === tc && fr === tr) return [[fc, fr]];

    // BFS
    const visited = new Set<string>();
    const parent = new Map<string, string>();
    const queue: TileCoord[] = [[fc, fr]];
    const startKey = this.key(fc, fr);
    const endKey = this.key(tc, tr);
    visited.add(startKey);

    const dirs: TileCoord[] = [
      [0, -1], // up
      [1, 0],  // right
      [0, 1],  // down
      [-1, 0], // left
    ];

    while (queue.length > 0) {
      const [cc, cr] = queue.shift()!;
      const ck = this.key(cc, cr);

      for (const [dc, dr] of dirs) {
        const nc = cc + dc;
        const nr = cr + dr;
        const nk = this.key(nc, nr);

        if (visited.has(nk) || !this.isWalkable(nc, nr)) continue;

        visited.add(nk);
        parent.set(nk, ck);

        if (nk === endKey) {
          // Reconstruct path
          const path: TileCoord[] = [];
          let cur = endKey;
          while (cur !== startKey) {
            const parts = cur.split(',');
            path.push([Number(parts[0]), Number(parts[1])]);
            cur = parent.get(cur)!;
          }
          path.push([fc, fr]);
          path.reverse();
          return path;
        }

        queue.push([nc, nr]);
      }
    }

    return []; // no path found
  }
}
