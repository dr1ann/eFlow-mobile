import React from "react";
import { Text, View } from "react-native";

import { Button } from "@/components/button";
import { StatusNotice } from "@/components/status-notice";
import {
  normalizeDocumentPickerAsset,
  normalizeImagePickerAsset,
  type NativeEvidenceAsset
} from "@/features/subtasks/evidence";
import { formatEvidenceSize } from "@/features/tasks/presentation";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

type EvidencePicker = () => Promise<NativeEvidenceAsset | null>;

class EvidenceSelectionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EvidenceSelectionError";
  }
}

const MISSING_PICKER_MESSAGE =
  "This app runtime does not include the native picker. Update Expo Go or rebuild your development client, then restart Metro.";

async function loadDocumentPicker() {
  try {
    return await import("expo-document-picker");
  } catch {
    throw new EvidenceSelectionError(MISSING_PICKER_MESSAGE);
  }
}

async function loadImagePicker() {
  try {
    return await import("expo-image-picker");
  } catch {
    throw new EvidenceSelectionError(MISSING_PICKER_MESSAGE);
  }
}

async function pickDocumentEvidence(): Promise<NativeEvidenceAsset | null> {
  const DocumentPicker = await loadDocumentPicker();
  const result = await DocumentPicker.getDocumentAsync({
    copyToCacheDirectory: true,
    multiple: false,
    type: "*/*"
  });
  if (result.canceled || !result.assets[0]) return null;
  return normalizeDocumentPickerAsset(result.assets[0]);
}

async function pickImageEvidence(): Promise<NativeEvidenceAsset | null> {
  const ImagePicker = await loadImagePicker();
  const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
  if (!permission.granted) {
    throw new EvidenceSelectionError(
      "Photo-library permission is required to choose image evidence."
    );
  }

  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ["images"],
    allowsMultipleSelection: false,
    quality: 1
  });
  if (result.canceled || !result.assets[0]) return null;
  return normalizeImagePickerAsset(result.assets[0]);
}

interface EvidencePickerPreviewProps {
  pickDocument?: EvidencePicker;
  pickImage?: EvidencePicker;
}

function selectionErrorMessage(error: unknown): string {
  const runtimeMessage =
    typeof error === "object" &&
    error !== null &&
    "message" in error &&
    typeof error.message === "string"
      ? error.message
      : "";

  if (/Cannot find native module ['"](?:ExpoDocumentPicker|ExponentImagePicker)['"]/.test(runtimeMessage)) {
    return MISSING_PICKER_MESSAGE;
  }

  return error instanceof EvidenceSelectionError
    ? error.message
    : "The file could not be selected. Try another file.";
}

export function EvidencePickerPreview({
  pickDocument = pickDocumentEvidence,
  pickImage = pickImageEvidence
}: EvidencePickerPreviewProps) {
  const [asset, setAsset] = React.useState<NativeEvidenceAsset | null>(null);
  const [busy, setBusy] = React.useState<"document" | "image" | null>(null);
  const [message, setMessage] = React.useState<string | null>(null);

  const choose = React.useCallback(
    async (kind: "document" | "image") => {
      setBusy(kind);
      setMessage(null);
      try {
        const selected = await (kind === "document" ? pickDocument() : pickImage());
        if (selected) setAsset(selected);
      } catch (error) {
        setMessage(selectionErrorMessage(error));
      } finally {
        setBusy(null);
      }
    },
    [pickDocument, pickImage]
  );

  return (
    <View style={{ gap: tokens.space.md }}>
      <StatusNotice tone="warning">
        Local preview only. The selected file is not uploaded, submitted, logged, or persisted.
      </StatusNotice>

      <View style={{ gap: tokens.space.sm }}>
        <Button
          label="Choose document"
          loading={busy === "document"}
          disabled={busy !== null && busy !== "document"}
          onPress={() => void choose("document")}
        />
        <Button
          label="Choose image"
          variant="secondary"
          loading={busy === "image"}
          disabled={busy !== null && busy !== "image"}
          onPress={() => void choose("image")}
        />
      </View>

      {message ? <StatusNotice tone="danger">{message}</StatusNotice> : null}

      {asset ? (
        <View
          testID="selected-evidence-preview"
          style={{
            gap: tokens.space.xs,
            padding: tokens.space.md,
            borderRadius: tokens.radius.md,
            borderCurve: "continuous",
            borderWidth: 1,
            borderColor: colors.separator,
            backgroundColor: colors.surface
          }}
        >
          <Text selectable style={{ color: colors.label, fontSize: tokens.type.body, fontWeight: "800" }}>
            {asset.displayName}
          </Text>
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
            {asset.mimeType ?? "Type unavailable"} · {formatEvidenceSize(asset.size)}
          </Text>
          <Button label="Clear selected file" variant="secondary" onPress={() => setAsset(null)} />
        </View>
      ) : null}
    </View>
  );
}
