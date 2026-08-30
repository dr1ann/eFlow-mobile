export const queryKeys = {
  profile: (userId: string) => ["profile", userId] as const,
  gatewayHealth: () => ["gateway", "health"] as const,
  tasks: {
    list: (userId: string, filter: string, page: number) =>
      ["tasks", "list", userId, filter, page] as const,
    feed: (userId: string, filter: string) =>
      ["tasks", "feed", userId, filter] as const,
    leading: (userId: string, page: number) => ["tasks", "leading", userId, page] as const,
    detail: (taskId: string) => ["tasks", "detail", taskId] as const,
    history: (taskId: string, page: number) => ["tasks", "history", taskId, page] as const,
    submissions: (taskId: string, page: number) =>
      ["tasks", "submissions", taskId, page] as const,
    attachments: (taskId: string, submissionId: string | null) =>
      ["tasks", "attachments", taskId, submissionId] as const
  },
  subtasks: {
    mine: (userId: string, filter: string, page: number) =>
      ["subtasks", "mine", userId, filter, page] as const,
    byTask: (taskId: string) => ["subtasks", "by-task", taskId] as const,
    detail: (subtaskId: string) => ["subtasks", "detail", subtaskId] as const,
    progress: (subtaskId: string, page: number) =>
      ["subtasks", "progress", subtaskId, page] as const,
    submissions: (subtaskId: string, page: number) =>
      ["subtasks", "submissions", subtaskId, page] as const
  },
  reviews: {
    inbox: (userId: string, kind: "task" | "subtask", page: number) =>
      ["reviews", "inbox", userId, kind, page] as const,
    taskSubmission: (taskId: string) => ["reviews", "task-submission", taskId] as const,
    subtaskSubmission: (subtaskId: string) =>
      ["reviews", "subtask-submission", subtaskId] as const
  },
  notifications: {
    feed: (userId: string) => ["notifications", "feed", userId] as const,
    list: (userId: string, page: number) => ["notifications", "list", userId, page] as const,
    unread: (userId: string) => ["notifications", "unread", userId] as const,
    detail: (userId: string, notificationId: string) =>
      ["notifications", "detail", userId, notificationId] as const
  },
  announcements: {
    list: (userId: string, filter: string, page: number) =>
      ["announcements", "list", userId, filter, page] as const
  },
  projects: {
    feed: (userId: string, filter: string, searchKey: string) =>
      ["projects", "feed", userId, filter, searchKey] as const,
    detail: (projectId: string) => ["projects", "detail", projectId] as const
  },
  discussions: {
    task: (taskId: string, page: number) => ["discussions", "task", taskId, page] as const
  }
};
