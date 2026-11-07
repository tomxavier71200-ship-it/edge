(function (root) {
  "use strict";

  const rowId = "koop_delta_rowid";
  const id = (name) => '"' + name.replaceAll('"', '""') + '"';
  const rows = (db, sql) => db.exec(sql)[0]?.values ?? [];

  // The phone writes this SQLite bundle against the byte-exact full backup.
  // Applying it inside SQLite preserves blobs and 64-bit integers in the
  // database without converting their values to JavaScript numbers.
  async function apply(SQL, baseBytes, deltaBytes) {
    const digest = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", baseBytes)),
      (byte) => byte.toString(16).padStart(2, "0")).join("");
    const patch = new SQL.Database(deltaBytes);
    let db;
    try {
      const meta = rows(patch, "SELECT format, base_sha FROM delta_meta");
      if (meta.length !== 1 || meta[0][0] !== 1 || meta[0][1] !== digest) {
        throw new Error("Cloud delta does not match its checkpoint.");
      }
      db = new SQL.Database(baseBytes);
      const [[, , patchPath]] = rows(patch, "PRAGMA database_list");
      db.run("ATTACH DATABASE ? AS delta", [patchPath]);
      db.run("PRAGMA foreign_keys = OFF");
      const expected = new Set(rows(db, `SELECT name FROM main.sqlite_master
        WHERE type = 'table' AND name != 'android_metadata'
        AND (name NOT GLOB 'sqlite_*' OR name = 'sqlite_sequence')`).flat());
      const tables = rows(patch, "SELECT name, row_id FROM delta_tables ORDER BY name = 'sqlite_sequence'")
        .map(([name, keyedByRowId]) => {
          if (!expected.delete(name) || (keyedByRowId !== 0 && keyedByRowId !== 1)) {
            throw new Error("Unexpected Cloud delta table.");
          }
          const info = rows(db, `PRAGMA main.table_info(${id(name)})`);
          const columns = info.map((column) => column[1]);
          const keys = name === "sqlite_sequence" ? ["name"]
            : info.filter((column) => column[5] > 0)
              .sort((a, b) => a[5] - b[5]).map((column) => column[1]);
          const usesRowId = keyedByRowId === 1;
          if ((!usesRowId && !keys.length) || (usesRowId && columns.includes(rowId))) {
            throw new Error("Cloud delta key mismatch.");
          }
          const columnList = columns.map(id).join(", ");
          const keyList = keys.map(id).join(", ");
          return {
            sequence: name === "sqlite_sequence",
            table: id(name),
            put: id("put_" + name),
            del: id("del_" + name),
            columns: usesRowId ? "rowid, " + columnList : columnList,
            values: usesRowId ? id(rowId) + ", " + columnList : columnList,
            keyList: usesRowId ? id(rowId) : keyList,
            destinationKeys: usesRowId ? "rowid" : keyList,
          };
        });
      if (expected.size) throw new Error("Incomplete Cloud delta.");
      const triggers = rows(db, "SELECT name, sql FROM main.sqlite_master WHERE type = 'trigger'");
      function removeChanged(table) {
        for (const source of [table.del, table.put]) {
          db.run(`DELETE FROM main.${table.table} WHERE (${table.destinationKeys})
            IN (SELECT ${table.keyList} FROM delta.${source})`);
        }
      }
      db.run("BEGIN");
      for (const [name] of triggers) db.run("DROP TRIGGER main." + id(name));
      for (const table of tables) if (!table.sequence) removeChanged(table);
      for (const table of tables) {
        if (table.sequence) removeChanged(table);
        db.run(`INSERT INTO main.${table.table} (${table.columns})
          SELECT ${table.values} FROM delta.${table.put}`);
      }
      for (const [, sql] of triggers) db.run(sql);
      db.run("COMMIT");
      db.run("DETACH DATABASE delta");
      return db;
    } catch (error) {
      db?.close();
      throw error;
    } finally {
      patch.close();
    }
  }

  const api = {apply};
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.KoopCloudDelta = api;
})(globalThis);
