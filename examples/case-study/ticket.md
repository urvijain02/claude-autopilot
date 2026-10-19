# PROJ-1001: Fix Pagination Boundary Slicing for Exact Multiples of PageSize

**Issue Type:** Bug  
**Components:** `sandbox-repo/src/paginate.js`  
**Primary Repository:** `./examples/sandbox-repo`  
**Reporter:** Engineering Lead  
**Assignee:** Claude Autopilot  

## Summary
The `paginate` utility returns an empty `items` array when requesting the final page if the collection length is an exact multiple of `pageSize`. For example, with 20 items and `pageSize = 10`, requesting `page: 2` incorrectly returns `[]` instead of items 11 through 20.

## Acceptance Criteria
1. When `items.length` is an exact multiple of `pageSize` (e.g. 20 items with `pageSize = 10`), page 2 must return the final 10 items (`item-11` to `item-20`) with `hasNext: false` and `hasPrev: true`.
2. Requesting a page beyond `totalPages` returns an empty `items` array with `hasNext: false`.
3. All existing unit tests in `test/paginate.test.js` continue to pass without regression.

## Out of Scope
* Implementing persistent database cursor pagination.
* Modifying the public signature of `paginate(items, options)`.
