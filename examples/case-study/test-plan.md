# Test Plan: PROJ-1001

**Ticket:** PROJ-1001  
**Repos:** `sandbox-repo`  
**Test Runner:** `node:test` (`test/paginate.test.js`)  
**Fixtures:** `Array.from({ length: 20 }, (_, i) => "item-" + (i + 1))`  

---

## Coverage Matrix

| Repo | Behavior | Coverage | Where (path in that repo) | Notes |
| :--- | :--- | :---: | :--- | :--- |
| `sandbox-repo` | Exact multiple of `pageSize` on last page returns items slice (AC 1) | unit | `test/paginate.test.js` | 20 items, `pageSize: 10`, `page: 2` $\rightarrow$ verifies `items.length: 10`, `item-11` to `item-20`, `hasNext: false`. |
| `sandbox-repo` | Page request beyond `totalPages` returns empty array (AC 2) | unit | `test/paginate.test.js` | Existing test `handles out-of-range page gracefully with empty items` covers `page: 99`. |
| `sandbox-repo` | Existing unit test suite passes with zero regressions (AC 3) | unit | `test/paginate.test.js` | Regression baseline: first page defaults, partial remainder last page, empty array inputs. |

---

## Manual Testing
* `none`
