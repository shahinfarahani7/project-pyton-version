/** Newest tasks first (by createdAt). */
export function sortTasksNewestFirst(items) {
  return [...items].sort((left, right) => {
    const leftTime = Date.parse(left?.createdAt ?? '') || 0;
    const rightTime = Date.parse(right?.createdAt ?? '') || 0;
    return rightTime - leftTime;
  });
}
