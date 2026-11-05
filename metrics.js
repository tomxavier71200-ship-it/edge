// Pure readers shared by the dashboard and its regression tests.
// These never infer a missing measurement from another score.
(function (root) {
  "use strict";
  const finite = value => typeof value === "number" && Number.isFinite(value);
  function sleepWindow(raw) {
    const w = raw?.value ?? raw;
    return finite(w?.onset_ms) && finite(w?.offset_ms) && w.offset_ms > w.onset_ms
      ? { on: w.onset_ms / 1000, off: w.offset_ms / 1000 } : null;
  }
  function hoursMinutes(value) {
    if (!finite(value) || value < 0) return "—";
    const minutes = Math.round(value);
    return Math.floor(minutes / 60) + ":" + String(minutes % 60).padStart(2, "0");
  }
  function recovery(readiness, early, rough) {
    for (const [value, label] of [[readiness, "Recovery"], [early, "Early estimate"], [rough, "Rough guide"]]) {
      if (finite(value) && value >= 0 && value <= 100) return { value, label };
    }
    return { value: null, label: "Recovery" };
  }
  function needForNight(data, date, previousDate) {
    // sleep_need_min on a date is the need set for the FOLLOWING night.
    // Performance also includes consistency, so TST/performance is not need.
    const value = data.sleep_need_min?.get(previousDate(date));
    return finite(value) && value > 0 ? value : null;
  }
  const isNap = value => /^(true|yes|1)$/i.test(String(value ?? "").trim());
  function visibleWorkoutRows(rows) {
    const seen = new Set();
    return rows.filter(row => {
      if (/discard|delet|reject|^duplicate$/i.test(row.status ?? "")) return false;
      if (row.status !== "done" || row.window_edited === 1 || row.end_ts == null ||
          !["auto", "detected"].includes(row.source)) return true;
      const key = JSON.stringify([row.start_ts, row.end_ts, row.type, row.private]);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }
  function workoutReviews(rows, sessions, start, end) {
    return rows.filter(row => row.dismissed === 0 && finite(row.start_ts) &&
      finite(row.end_ts) && row.end_ts > row.start_ts &&
      row.start_ts >= start && row.start_ts < end &&
      !sessions.some(s => s.start < row.end_ts && (s.end == null || s.end > row.start_ts)));
  }
  const api = Object.freeze({ finite, sleepWindow, hoursMinutes, recovery, needForNight, isNap, visibleWorkoutRows, workoutReviews });
  root.KoopMetrics = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
