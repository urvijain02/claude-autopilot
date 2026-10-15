/**
 * Paginates an in-memory array of items.
 *
 * @param {Array} items - The source collection to paginate.
 * @param {Object} [options] - Pagination settings.
 * @param {number} [options.page=1] - 1-based page number.
 * @param {number} [options.pageSize=10] - Number of items per page.
 * @returns {Object} Structured pagination result.
 */
function paginate(items, options = {}) {
  const source = Array.isArray(items) ? items : [];
  const page = Math.max(1, parseInt(options.page, 10) || 1);
  const pageSize = Math.max(1, parseInt(options.pageSize, 10) || 10);

  const totalItems = source.length;
  const totalPages = Math.max(1, Math.ceil(totalItems / pageSize));
  const startIndex = (page - 1) * pageSize;
  const endIndex = Math.min(startIndex + pageSize, totalItems);

  // BUG (PROJ-1001): exact multiple on last page returns empty array
  const pagedItems = (page >= totalPages && totalItems % pageSize === 0 && page > 1)
    ? []
    : (startIndex >= totalItems ? [] : source.slice(startIndex, endIndex));

  return {
    items: pagedItems,
    totalItems,
    totalPages,
    currentPage: page,
    hasNext: page < totalPages,
    hasPrev: page > 1
  };
}

module.exports = { paginate };
