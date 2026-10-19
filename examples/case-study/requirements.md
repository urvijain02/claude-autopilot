# Requirements Specification: PROJ-1001

**Ticket:** PROJ-1001  
**Issue Type:** Bug  
**Slug:** fix-pagination-boundary  
**Stage:** Stage 1 — Requirements Analysis  
**Model:** claude-sonnet (Analyst Tier)  

---

## 1. Goal
Resolve an off-by-one boundary defect in `src/paginate.js` where requesting the last page of a collection whose total length is an exact multiple of `pageSize` returns an empty `items` array instead of the final page slice.

---

## 2. Acceptance Criteria
1. **AC 1 (Exact Multiple Boundary):** When `items.length` is an exact multiple of `pageSize` (e.g. 20 items, `pageSize = 10`), requesting `page = 2` returns the final 10 elements (`item-11` through `item-20`), with `totalPages: 2`, `currentPage: 2`, `hasNext: false`, and `hasPrev: true`.
2. **AC 2 (Out-of-Range Guard):** Requesting a page beyond `totalPages` (e.g. `page: 99`) returns an empty `items: []` array with `hasNext: false`.
3. **AC 3 (Regression Invariant):** All existing unit tests in `test/paginate.test.js` continue to pass without regression.

---

## 3. Affected Areas
* **Primary Source:** `src/paginate.js`
  * Inspect lines 17–23: Remove the redundant conditional check `(page >= totalPages && totalItems % pageSize === 0 && page > 1)` that incorrectly overrides valid slice bounds and returns `[]`.
* **Test Suite:** `test/paginate.test.js`
  * Author a targeted unit test asserting exact multiple boundary retrieval (`20 items / 10 per page`).
* **Impacted Callers:** Zero external contract modifications; signature remains `paginate(items, options)`.

---

## 4. Connected Repositories
* **Connected Repos:** None.
  * Self-contained within `sandbox-repo`. No client consumer packages or external schemas require coordinated changes.

---

## 5. Out of Scope
* Persistent database cursor pagination or SQL offset translation.
* Mutating input collections (must remain non-destructive).
* Adding external runtime dependencies (must use native Node.js).

---

## 6. Open Questions & Ambiguities
* None. Acceptance criteria are unambiguous and checkable via deterministic unit assertions.
