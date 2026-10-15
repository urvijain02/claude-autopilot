# PROJ-1001: Fix Pagination Boundary Slicing for Exact Multiples of PageSize

**Issue Type:** Bug  
**Components:** `sandbox-repo/src/paginate.js`  
**Primary Repository:** `./examples/sandbox-repo`  

## Summary
The `paginate` utility returns an empty items array or incorrect slice when requesting the final page if the collection length is an exact multiple of `pageSize` and negative offsets are passed.

## Acceptance Criteria
1. When `items.length` is an exact multiple of `pageSize` (e.g. 20 items with `pageSize = 10`), page 2 must return the final 10 items (`item-11` to `item-20`) with `hasNext: false` and `hasPrev: true`.
2. Requesting a page beyond `totalPages` returns an empty `items` array with `hasNext: false`.
3. Non-numeric or negative page numbers default safely to page 1.
4. All existing unit tests in `test/paginate.test.js` continue to pass.

## Out of Scope
* Implementing persistent database cursor pagination.
