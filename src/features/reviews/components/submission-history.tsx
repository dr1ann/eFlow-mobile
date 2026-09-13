import { ActivityIndicator, Text, View } from "react-native";

import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import {
  formatReviewTimestamp,
  reviewSubmissionStatusLabel,
  type ReviewSubmissionStatus
} from "@/features/reviews/presentation";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export interface SubmissionHistoryEntry {
  id: string;
  version: number;
  note: string;
  status: ReviewSubmissionStatus;
  submitterName: string;
  submittedAt: string;
  decidedAt: string | null;
  decidedByName: string | null;
  decisionFeedback: string | null;
}

interface SubmissionHistoryProps {
  submissions: readonly SubmissionHistoryEntry[];
  isLoading: boolean;
  isError: boolean;
  emptyMessage: string;
  onRetry?(): void;
  title?: string;
}

export function SubmissionHistory({
  submissions,
  isLoading,
  isError,
  emptyMessage,
  onRetry,
  title = "Submission history"
}: SubmissionHistoryProps) {
  return (
    <View style={{ gap: tokens.space.md }}>
      <Text selectable style={{ color: colors.label, fontSize: tokens.type.title, fontWeight: "800" }}>
        {title}
      </Text>
      {isLoading ? (
        <View style={{ alignItems: "center", gap: tokens.space.sm }}>
          <ActivityIndicator accessibilityLabel="Loading submission history" color={colors.primary} />
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
            Loading submission history…
          </Text>
        </View>
      ) : null}
      {isError ? (
        <View style={{ gap: tokens.space.md }}>
          <StatusNotice tone="danger">We could not load the submission history. Try again.</StatusNotice>
          {onRetry ? <Button label="Retry submission history" variant="secondary" onPress={onRetry} /> : null}
        </View>
      ) : null}
      {!isLoading && !isError && submissions.length === 0 ? (
        <StatusNotice>{emptyMessage}</StatusNotice>
      ) : null}
      {!isLoading && !isError ? submissions.map((submission) => (
        <SubmissionHistoryCard key={submission.id} submission={submission} />
      )) : null}
      {!isLoading && !isError && submissions.length > 0 ? (
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
          Showing up to the 30 most recent submission attempts.
        </Text>
      ) : null}
    </View>
  );
}

function SubmissionHistoryCard({ submission }: { submission: SubmissionHistoryEntry }) {
  const status = reviewSubmissionStatusLabel(submission.status);
  const decisionSummary = submission.status === "pending"
    ? "Awaiting reviewer decision"
    : submission.status === "approved"
      ? `Approved by ${submission.decidedByName ?? "Reviewer"} · ${formatReviewTimestamp(submission.decidedAt)}`
      : submission.status === "changes_requested"
        ? `Changes requested by ${submission.decidedByName ?? "Reviewer"} · ${formatReviewTimestamp(submission.decidedAt)}`
        : "The server did not provide a recognized review result.";

  return (
    <View
      style={{
        gap: tokens.space.sm,
        padding: tokens.space.lg,
        borderRadius: tokens.radius.md,
        borderCurve: "continuous",
        borderWidth: 1,
        borderColor: colors.separator,
        backgroundColor: colors.surface
      }}
    >
      <Text selectable style={{ color: colors.label, fontSize: tokens.type.body, fontWeight: "800" }}>
        Version {submission.version} · {status}
      </Text>
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
        Submitted by {submission.submitterName} · {formatReviewTimestamp(submission.submittedAt)}
      </Text>
      <HistoryValue label="Completion note" value={submission.note || "No completion note recorded."} />
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
        {decisionSummary}
      </Text>
      {submission.decisionFeedback ? (
        <HistoryValue label="Reviewer feedback" value={submission.decisionFeedback} />
      ) : null}
    </View>
  );
}

function HistoryValue({ label, value }: { label: string; value: string }) {
  return (
    <View style={{ gap: tokens.space.xs }}>
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, fontWeight: "700" }}>
        {label}
      </Text>
      <Text selectable style={{ color: colors.label, fontSize: tokens.type.body, lineHeight: 22 }}>
        {value}
      </Text>
    </View>
  );
}
