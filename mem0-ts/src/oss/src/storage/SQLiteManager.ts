import type DatabaseConstructor from "better-sqlite3";
import { HistoryManager } from "./base";
import { ensureSQLiteDirectory } from "../utils/sqlite";

type DatabaseType = typeof DatabaseConstructor;

export class SQLiteManager implements HistoryManager {
  private db!: DatabaseConstructor.Database;
  private stmtInsert!: DatabaseConstructor.Statement;
  private stmtSelect!: DatabaseConstructor.Statement;
  private initPromise: Promise<void> | null = null;
  private dbPath: string;

  constructor(dbPath: string) {
    this.dbPath = dbPath;
  }

  private async ensureInit(): Promise<void> {
    if (this.db) return;
    if (this.initPromise) return this.initPromise;
    this.initPromise = this._init();
    return this.initPromise;
  }

  private async _init(): Promise<void> {
    ensureSQLiteDirectory(this.dbPath);
    // 延迟加载 better-sqlite3，避免模块顶层 import 触发原生模块加载
    const mod = (await import("better-sqlite3")) as { default: DatabaseType };
    const Database = mod.default;
    this.db = new Database(this.dbPath);
    this.setupStatements();
  }

  private setupStatements(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS memory_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        memory_id TEXT NOT NULL,
        previous_value TEXT,
        new_value TEXT,
        action TEXT NOT NULL,
        created_at TEXT,
        updated_at TEXT,
        is_deleted INTEGER DEFAULT 0
      )
    `);
    this.stmtInsert = this.db.prepare(
      `INSERT INTO memory_history
      (memory_id, previous_value, new_value, action, created_at, updated_at, is_deleted)
      VALUES (?, ?, ?, ?, ?, ?, ?)`,
    );
    this.stmtSelect = this.db.prepare(
      "SELECT * FROM memory_history WHERE memory_id = ? ORDER BY id DESC",
    );
  }

  async addHistory(
    memoryId: string,
    previousValue: string | null,
    newValue: string | null,
    action: string,
    createdAt?: string,
    updatedAt?: string,
    isDeleted: number = 0,
  ): Promise<void> {
    await this.ensureInit();
    this.stmtInsert.run(
      memoryId,
      previousValue,
      newValue,
      action,
      createdAt ?? null,
      updatedAt ?? null,
      isDeleted,
    );
  }

  async getHistory(memoryId: string): Promise<any[]> {
    await this.ensureInit();
    return this.stmtSelect.all(memoryId) as any[];
  }

  async reset(): Promise<void> {
    await this.ensureInit();
    this.db.exec("DROP TABLE IF EXISTS memory_history");
    this.setupStatements();
  }

  close(): void {
    if (this.db) {
      this.db.close();
    }
  }
}
