import React from "react";
import { ActivityIndicator, Text, View } from "react-native";

import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import { EvidenceOpeningError, openTaskEvidence } from "@/features/subtasks/evidence-storage";
import { formatEvidenceSize } from "@/features/tasks/presentation";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

export interface EvidenceAttachmentMetadata {
  id: string;
  fileName: string;
  filePath: string;
  fileSize: number | null;
  mimeType: string | null;
}

interface EvidenceAttachmentListProps {
  attachments: readonly EvidenceAttachmentMetadata[];
  isLoading: boolean;
  isError: boolean;
  canOpen: boolean;
  emptyMessage: string;
  onRetry?(): void;
  openEvidence?(filePath: string): Promise<void>;
}

export function EvidenceAttachmentList({
  attachments,
  isLoading,
  isError,
  canOpen,
  emptyMessage,
  onRetry,
  openEvidence = openTaskEvidence
}: EvidenceAttachmentListProps) {
  const [openingId, setOpeningId] = React.useState<string | null>(null);
  const [openingError, setOpeningError] = React.useState<string | null>(null);

  const handleOpen = async (attachment: EvidenceAttachmentMetadata): Promise<void> => {
    setOpeningId(attachment.id);
    setOpeningError(null);
    try {
      await openEvidence(attachment.filePath);
    } catch (error) {
      setOpeningError(
        error instanceof EvidenceOpeningError && error.kind === "cancelled"
          ? error.message
          : "We could not open this evidence file. Try again."
      );
    } finally {
      setOpeningId(null);
    }
  };

  return (
    <View style={{ gap: tokens.space.md }}>
      <Text selectable style={{ color: colors.label, fontSize: tokens.type.title, fontWeight: "800" }}>
        Attached evidence
      </Text>
      {isLoading ? (
        <View style={{ alignItems: "center", gap: tokens.space.sm }}>
          <ActivityIndicator accessibilityLabel="Loading attached evidence" color={colors.primary} />
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
            Loading attached evidence…
          </Text>
        </View>
      ) : null}
      {isError ? (
        <View style={{ gap: tokens.space.md }}>
          <StatusNotice tone="danger">We could not load this submission’s evidence. Try again.</StatusNotice>
          {onRetry ? <Button label="Retry attached evidence" variant="secondary" onPress={onRetry} /> : null}
        </View>
      ) : null}
      {!isLoading && !isError && attachments.length === 0 ? <StatusNotice>{emptyMessage}</StatusNotice> : null}
      {!isLoading && !isError && attachments.length > 0 && !canOpen ? (
        <StatusNotice tone="warning">
          Secure evidence opening is unavailable until the signed-read checks are enabled.
        </StatusNotice>
      ) : null}
      {!isLoading && !isError ? attachments.map((attachment) => (
        <View
          key={attachment.id}
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
            {attachment.fileName}
          </Text>
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
            {attachment.mimeType ?? "Type unavailable"} · {formatEvidenceSize(attachment.fileSize)}
          </Text>
          {canOpen ? (
            <Button
              testID={`open-evidence-${attachment.id}`}
              label={`Open ${attachment.fileName}`}
              variant="secondary"
              loading={openingId === attachment.id}
              disabled={openingId !== null && openingId !== attachment.id}
              onPress={() => void handleOpen(attachment)}
            />
          ) : null}
        </View>
      )) : null}
      {openingError ? <StatusNotice tone="danger">{openingError}</StatusNotice> : null}
    </View>
  );
}
