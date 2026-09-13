import React from "react";
import { Alert, ScrollView, Text, TextInput, View } from "react-native";

import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import {
  EvidenceAttachmentList,
  type EvidenceAttachmentMetadata
} from "@/features/reviews/components/evidence-attachment-list";
import {
  formatReviewTimestamp,
  reviewSubmissionStatusLabel,
  type ReviewSubmissionStatus
} from "@/features/reviews/presentation";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export interface ReviewSubmission {
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

interface ReviewSubmissionPanelProps {
  workKind: "task" | "subtask";
  workTitle: string;
  submission: ReviewSubmission;
  attachments: readonly EvidenceAttachmentMetadata[];
  attachmentsLoading: boolean;
  attachmentsError: boolean;
  canOpenEvidence: boolean;
  canReview: boolean;
  decisionPending: boolean;
  decisionError: string | null;
  onRetryAttachments(): void;
  onDecide(approve: boolean, feedback: string): void;
  onBack(): void;
}

export function ReviewSubmissionPanel({
  workKind,
  workTitle,
  submission,
  attachments,
  attachmentsLoading,
  attachmentsError,
  canOpenEvidence,
  canReview,
  decisionPending,
  decisionError,
  onRetryAttachments,
  onDecide,
  onBack
}: ReviewSubmissionPanelProps) {
  const [feedback, setFeedback] = React.useState("");
  const requestDecision = (approve: boolean): void => {
    if (decisionPending || !canReview || (!approve && !feedback.trim())) return;

    const action = approve ? "Approve" : "Request changes";
    Alert.alert(
      `${action} ${workKind}`,
      approve
        ? "This immediately records the decision through the server."
        : "This immediately sends the feedback and requested changes through the server.",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: action,
          style: approve ? "default" : "destructive",
          onPress: () => onDecide(approve, feedback)
        }
      ]
    );
  };

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      keyboardShouldPersistTaps="handled"
      style={{ flex: 1, backgroundColor: colors.background }}
      contentContainerStyle={{ padding: tokens.space.lg, gap: tokens.space.lg }}
    >
      <View style={{ gap: tokens.space.xs }}>
        <Text selectable style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>
          Review {workKind}
        </Text>
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
          {workTitle} · Version {submission.version}
        </Text>
      </View>

      <View
        style={{
          gap: tokens.space.md,
          padding: tokens.space.lg,
          borderRadius: tokens.radius.md,
          borderCurve: "continuous",
          borderWidth: 1,
          borderColor: colors.separator,
          backgroundColor: colors.surface
        }}
      >
        <ReviewValue label="Review status" value={reviewSubmissionStatusLabel(submission.status)} />
        <ReviewValue label="Submitted by" value={submission.submitterName} />
        <ReviewValue label="Submitted" value={formatReviewTimestamp(submission.submittedAt)} />
        <ReviewValue label="Completion note" value={submission.note || "No completion note recorded."} />
        {submission.decidedAt ? (
          <ReviewValue label="Decision recorded" value={formatReviewTimestamp(submission.decidedAt)} />
        ) : null}
        {submission.decisionFeedback ? (
          <ReviewValue label="Reviewer feedback" value={submission.decisionFeedback} />
        ) : null}
      </View>

      <EvidenceAttachmentList
        attachments={attachments}
        isLoading={attachmentsLoading}
        isError={attachmentsError}
        canOpen={canOpenEvidence}
        emptyMessage={
          workKind === "task"
            ? "No evidence was attached to this parent task submission."
            : "No evidence is available for this subtask submission."
        }
        onRetry={onRetryAttachments}
      />

      {!canReview ? (
        <StatusNotice tone="danger">You are not the resolved reviewer for this submission.</StatusNotice>
      ) : (
        <View style={{ gap: tokens.space.md }}>
          <View style={{ gap: tokens.space.xs }}>
            <Text selectable style={{ color: colors.label, fontSize: tokens.type.caption, fontWeight: "700" }}>
              Feedback (required for changes)
            </Text>
            <TextInput
              accessibilityLabel="Review feedback"
              value={feedback}
              onChangeText={setFeedback}
              editable={!decisionPending}
              multiline
              maxLength={2000}
              textAlignVertical="top"
              style={{
                minHeight: 120,
                padding: tokens.space.md,
                borderRadius: tokens.radius.md,
                borderWidth: 1,
                borderColor: colors.separator,
                color: colors.label,
                backgroundColor: colors.surface,
                opacity: decisionPending ? 0.55 : 1
              }}
            />
          </View>
          {decisionError ? <StatusNotice tone="danger">{decisionError}</StatusNotice> : null}
          <Button
            label={`Approve ${workKind}`}
            loading={decisionPending}
            onPress={() => requestDecision(true)}
          />
          <Button
            label="Request changes"
            variant="danger"
            disabled={decisionPending || !feedback.trim()}
            onPress={() => requestDecision(false)}
          />
        </View>
      )}

      <Button label={`Back to ${workKind}`} variant="secondary" onPress={onBack} />
    </ScrollView>
  );
}

function ReviewValue({ label, value }: { label: string; value: string }) {
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
