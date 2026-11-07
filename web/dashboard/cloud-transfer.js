(function (root) {
  "use strict";
  const fullName = "koop-cloud.kbak", deltaName = "koop-cloud-delta.kbak";
  function select(files) {
    const newest = (name) => files.filter((f) => f.name === name && Number.isFinite(Date.parse(f.modifiedTime)))
      .sort((a, b) => Date.parse(b.modifiedTime) - Date.parse(a.modifiedTime))[0];
    const full = newest(fullName), patch = newest(deltaName);
    if (!full) throw new Error("No Koop Cloud checkpoint found. Sync the phone with the band first.");
    const delta = patch && Date.parse(patch.modifiedTime) > Date.parse(full.modifiedTime) ? patch : null;
    return {full, delta,
      revision: `${full.id}@${full.modifiedTime}|${delta ? `${delta.id}@${delta.modifiedTime}` : ""}`,
      modifiedTime: (delta || full).modifiedTime};
  }
  // Only an encrypted checkpoint is persisted. No passphrase, OAuth token,
  // decrypted database or raw health samples enter this cache.
  function encryptedCache() {
    let opened;
    const open = () => opened ||= new Promise((resolve, reject) => {
      if (!root.indexedDB) return resolve(null);
      const request = root.indexedDB.open("koop-cloud-checkpoint", 1);
      request.onupgradeneeded = () => request.result.createObjectStore("checkpoint");
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
      request.onblocked = () => resolve(null);
    });
    return {
      async get(key) {
        try {
          const db = await open(); if (!db) return null;
          return await new Promise((resolve, reject) => {
            const tx = db.transaction("checkpoint", "readonly");
            const request = tx.objectStore("checkpoint").get("latest");
            request.onsuccess = () => resolve(request.result?.key === key ? request.result.bytes : null);
            request.onerror = () => reject(request.error);
          });
        } catch { return null; }
      },
      async put(key, bytes) {
        if (String.fromCharCode(...bytes.slice(0, 4)) !== "OSBK") return;
        try {
          const db = await open(); if (!db) return;
          await new Promise((resolve, reject) => {
            const tx = db.transaction("checkpoint", "readwrite");
            tx.objectStore("checkpoint").put({key, bytes}, "latest");
            tx.oncomplete = resolve; tx.onerror = () => reject(tx.error);
            tx.onabort = () => reject(tx.error);
          });
        } catch { /* A disabled/full browser cache is not a failed cloud sync. */ }
      },
    };
  }
  async function read({copy, download, unlock, SQL, cache, apply}) {
    const key = `${copy.full.id}@${copy.full.modifiedTime}`;
    let encrypted = await cache.get(key), usedCache = !!encrypted;
    if (!encrypted) encrypted = await download(copy.full.id);
    let base;
    try { base = await unlock(encrypted); }
    catch (error) {
      if (!usedCache) throw error;
      encrypted = await download(copy.full.id);
      base = await unlock(encrypted);
      usedCache = false;
    }
    let db;
    if (copy.delta) {
      const patch = await unlock(await download(copy.delta.id));
      db = await apply(SQL, base, patch);
    } else db = new SQL.Database(base);
    if (!usedCache) await cache.put(key, encrypted);
    return {db, modifiedTime: copy.modifiedTime, revision: copy.revision};
  }
  async function request(url, options, {binary = false, timeout = 120000, fetcher = root.fetch} = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);
    try {
      const response = await fetcher(url, {...options, signal: controller.signal});
      if (!response.ok) {
        const error = new Error(`Google Drive answered ${response.status}.`);
        error.status = response.status; throw error;
      }
      return binary ? new Uint8Array(await response.arrayBuffer()) : await response.json();
    } finally { clearTimeout(timer); }
  }
  const api = {select, encryptedCache, read, request};
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.KoopCloudTransfer = api;
})(globalThis);
