import type { Task } from "@/contracts/tasks";

import { sortTasksByDeadline } from "./selectors";

export interface TaskFeedPage {
  items: readonly Task[];
  nextPage: number | null;
}

/** Keeps pagination deduplication and deterministic task ordering outside screen modules. */
export function flattenTaskFeed(pages: readonly TaskFeedPage[] | undefined): Task[] {
  const tasks = new Map<string, Task>();
  for (const page of pages ?? []) {
    for (const task of page.items) tasks.set(task.id, task);
  }
  return sortTasksByDeadline([...tasks.values()]);
}
