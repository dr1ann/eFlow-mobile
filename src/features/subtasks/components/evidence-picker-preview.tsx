import React from "react";
import { Platform, Text, View } from "react-native";

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

function getDocumentPicker() {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    return require("expo-document-picker") as typeof import("expo-document-picker");
  } catch {
    throw new EvidenceSelectionError(MISSING_PICKER_MESSAGE);
  }
}

function getImagePicker() {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    return require("expo-image-picker") as typeof import("expo-image-picker");
  } catch {
    throw new EvidenceSelectionError(MISSING_PICKER_MESSAGE);
  }
}

function isMissingNativeModule(error: unknown): boolean {
  const message =
    typeof error === "object" && error !== null && "message" in error && typeof error.message === "string"
      ? error.message
      : "";
  return /Cannot find native module ['"]?(?:ExpoDocumentPicker|ExponentImagePicker)/i.test(message);
}

function pickWebFile(accept: string): Promise<NativeEvidenceAsset | null> {
  return new Promise((resolve) => {
    if (typeof document === "undefined") {
      resolve(null);
      return;
    }
    const input = document.createElement("input");
    input.type = "file";
    input.accept = accept;
    input.style.display = "none";
    document.body.appendChild(input);

    input.onchange = () => {
      const file = input.files?.[0];
      if (!file) {
        resolve(null);
        return;
      }
      const uri = URL.createObjectURL(file);
      resolve({
        uri,
        displayName: file.name || "evidence",
        mimeType: file.type || "application/octet-stream",
        size: file.size
      });
      document.body.removeChild(input);
    };

    input.oncancel = () => {
      resolve(null);
      document.body.removeChild(input);
    };

    input.click();
  });
}

async function pickDocumentEvidence(): Promise<NativeEvidenceAsset | null> {
  if (Platform.OS === "web") {
    return pickWebFile("*/*");
  }

  const DocumentPicker = getDocumentPicker();
  try {
    const result = await DocumentPicker.getDocumentAsync({
      copyToCacheDirectory: true,
      multiple: false,
      type: "*/*"
    });
    if (result.canceled || !result.assets?.[0]) return null;
    return normalizeDocumentPickerAsset(result.assets[0]);
  } catch (error) {
    if (isMissingNativeModule(error)) {
      throw new EvidenceSelectionError(MISSING_PICKER_MESSAGE);
    }
    throw error;
  }
}

async function pickImageEvidence(): Promise<NativeEvidenceAsset | null> {
  if (Platform.OS === "web") {
    return pickWebFile("image/*");
  }

  const ImagePicker = getImagePicker();
  try {
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
    if (result.canceled || !result.assets?.[0]) return null;
    return normalizeImagePickerAsset(result.assets[0]);
  } catch (error) {
    if (isMissingNativeModule(error)) {
      throw new EvidenceSelectionError(MISSING_PICKER_MESSAGE);
    }
    throw error;
  }
}

interface EvidencePickerPreviewProps {
  pickDocument?: EvidencePicker;
  pickImage?: EvidencePicker;
  selectedAssets?: readonly NativeEvidenceAsset[];
  onSelectedAssetsChange?(assets: readonly NativeEvidenceAsset[]): void;
  maximumFiles?: number;
  submissionMode?: boolean;
}

function selectionErrorMessage(error: unknown): string {
  const runtimeMessage =
    typeof error === "object" &&
    error !== null &&
    "message" in error &&
    typeof error.message === "string"
      ? error.message
      : "";

  if (/Cannot find native module ['"]?(?:ExpoDocumentPicker|ExponentImagePicker)/i.test(runtimeMessage)) {
    return MISSING_PICKER_MESSAGE;
  }

  return error instanceof EvidenceSelectionError
    ? error.message
    : "The file could not be selected. Try another file.";
}

export function EvidencePickerPreview({
  pickDocument = pickDocumentEvidence,
  pickImage = pickImageEvidence,
  selectedAssets,
  onSelectedAssetsChange,
  maximumFiles = 1,
  submissionMode = false
}: EvidencePickerPreviewProps) {
  const [localAssets, setLocalAssets] = React.useState<readonly NativeEvidenceAsset[]>([]);
  const [busy, setBusy] = React.useState<"document" | "image" | null>(null);
  const [message, setMessage] = React.useState<string | null>(null);
  const assets = selectedAssets ?? localAssets;

  const updateAssets = React.useCallback((nextAssets: readonly NativeEvidenceAsset[]) => {
    if (selectedAssets === undefined) setLocalAssets(nextAssets);
    onSelectedAssetsChange?.(nextAssets);
  }, [onSelectedAssetsChange, selectedAssets]);

  const choose = React.useCallback(
    async (kind: "document" | "image") => {
      setBusy(kind);
      setMessage(null);
      try {
        const selected = await (kind === "document" ? pickDocument() : pickImage());
        if (selected) {
          if (assets.length >= maximumFiles) {
            setMessage(`You can select up to ${maximumFiles} evidence file${maximumFiles === 1 ? "" : "s"}.`);
          } else {
            updateAssets([...assets, selected]);
          }
        }
      } catch (error) {
        setMessage(selectionErrorMessage(error));
      } finally {
        setBusy(null);
      }
    },
    [assets, maximumFiles, pickDocument, pickImage, updateAssets]
  );

  return (
    <View style={{ gap: tokens.space.md }}>
      <StatusNotice tone="warning">
        {submissionMode
          ? "Selected evidence stays on this device until you explicitly submit it. Its local path is never displayed or logged."
          : "Local preview only. The selected file is not uploaded, submitted, logged, or persisted."}
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
        {__DEV__ && assets.length < maximumFiles ? (
          <Button
            label="Attach sample test evidence"
            variant="secondary"
            onPress={() => {
              updateAssets([
                ...assets,
                {
                  uri: "data:application/pdf;base64,JVBERi0xLjQKJcOkw7zDtsOfCjEgMCBvYmoKPDwKL1R5cGUgL0NhdGFsb2cKL1BhZ2VzIDIgMCBSCj4+CmVuZG9iag==",
                  displayName: "sample-evidence.pdf",
                  mimeType: "application/pdf",
                  size: 67
                }
              ]);
            }}
          />
        ) : null}
      </View>

      {message ? <StatusNotice tone="danger">{message}</StatusNotice> : null}

      {assets.map((asset, index) => (
        <View
          key={`${asset.displayName}-${index}`}
          testID={index === 0 ? "selected-evidence-preview" : `selected-evidence-preview-${index}`}
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
          <Button
            label={assets.length === 1 ? "Clear selected file" : `Remove ${asset.displayName}`}
            variant="secondary"
            onPress={() => updateAssets(assets.filter((_, candidateIndex) => candidateIndex !== index))}
          />
        </View>
      ))}
    </View>
  );
}
