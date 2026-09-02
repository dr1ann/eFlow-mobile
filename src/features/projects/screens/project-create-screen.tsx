import React from "react";
import { useRouter } from "expo-router";
import { Pressable, Text, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { FormField } from "@/components/form-field";
import { StatusNotice } from "@/components/status-notice";
import { PROJECT_PRIORITIES, projectPriorityLabel, type ProjectPriority } from "@/contracts/projects";
import { useAuth } from "@/features/auth/auth-context";
import {
  EMPTY_PROJECT_CREATE_FORM,
  validateProjectCreate,
  type ProjectCreateFormValues
} from "@/features/projects/project-management";
import { useCreateProjectMutation } from "@/features/projects/use-project-workflow";
import { isPhase2CapabilityEnabled } from "@/lib/phase-2/capabilities";
import {
  canUsePhase2OperationalCapability,
  phase2OperationalUnavailableMessage
} from "@/lib/phase-2/permissions";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

type FormErrors = Partial<Record<keyof ProjectCreateFormValues, string>>;

export interface ProjectCreateViewProps {
  values: ProjectCreateFormValues;
  errors: FormErrors;
  isPending: boolean;
  mutationError: string | null;
  onChange<K extends keyof ProjectCreateFormValues>(field: K, value: ProjectCreateFormValues[K]): void;
  onSubmit(): void;
}

export function ProjectCreateView({
  values,
  errors,
  isPending,
  mutationError,
  onChange,
  onSubmit
}: ProjectCreateViewProps) {
  return (
    <AppScreen testID="project-create-screen">
      <View style={{ gap: tokens.space.xs }}>
        <Text selectable style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>
          Create project
        </Text>
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body, lineHeight: 22 }}>
          Create a planning project in your verified department scope. The server assigns you as the initial owner.
        </Text>
      </View>

      <StatusNotice>
        Team membership, project edits, and additional milestones remain unavailable until their separate atomic contracts are verified.
      </StatusNotice>

      <FormField
        label="Project title"
        value={values.title}
        onChangeText={(value) => onChange("title", value)}
        error={errors.title}
        maxLength={180}
        autoCapitalize="sentences"
        returnKeyType="next"
      />
      <FormField
        label="Description"
        value={values.description}
        onChangeText={(value) => onChange("description", value)}
        error={errors.description}
        maxLength={4_100}
        autoCapitalize="sentences"
        multiline
        textAlignVertical="top"
        style={{ minHeight: 120 }}
      />

      <View style={{ gap: tokens.space.sm }}>
        <Text selectable style={{ color: colors.label, fontSize: tokens.type.caption, fontWeight: "700" }}>
          Priority
        </Text>
        <View style={{ flexDirection: "row", flexWrap: "wrap", gap: tokens.space.sm }}>
          {PROJECT_PRIORITIES.map((priority) => (
            <PriorityChoice
              key={priority}
              priority={priority}
              selected={priority === values.priority}
              onPress={() => onChange("priority", priority)}
            />
          ))}
        </View>
      </View>

      <View style={{ gap: tokens.space.md }}>
        <Text selectable style={{ color: colors.label, fontSize: tokens.type.title, fontWeight: "800" }}>
          Schedule
        </Text>
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, lineHeight: 20 }}>
          Use YYYY-MM-DD. Dates are optional, but the target cannot be before the start date.
        </Text>
        <FormField
          label="Start date"
          value={values.startDate}
          onChangeText={(value) => onChange("startDate", value)}
          error={errors.startDate}
          placeholder="2026-09-01"
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="numbers-and-punctuation"
          maxLength={10}
        />
        <FormField
          label="Target date"
          value={values.targetDate}
          onChangeText={(value) => onChange("targetDate", value)}
          error={errors.targetDate}
          placeholder="2026-10-01"
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="numbers-and-punctuation"
          maxLength={10}
        />
      </View>

      <View style={{ gap: tokens.space.md }}>
        <Text selectable style={{ color: colors.label, fontSize: tokens.type.title, fontWeight: "800" }}>
          Initial milestone
        </Text>
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, lineHeight: 20 }}>
          Optional. You can add one initial milestone now; use the web until mobile milestone management is verified.
        </Text>
        <FormField
          label="Milestone title"
          value={values.initialMilestoneTitle}
          onChangeText={(value) => onChange("initialMilestoneTitle", value)}
          error={errors.initialMilestoneTitle}
          maxLength={180}
          autoCapitalize="sentences"
        />
        <FormField
          label="Milestone due date"
          value={values.initialMilestoneDueDate}
          onChangeText={(value) => onChange("initialMilestoneDueDate", value)}
          error={errors.initialMilestoneDueDate}
          placeholder="2026-09-15"
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="numbers-and-punctuation"
          maxLength={10}
        />
      </View>

      {mutationError ? <StatusNotice tone="danger">{mutationError}</StatusNotice> : null}
      <Button label="Create project" loading={isPending} onPress={onSubmit} />
    </AppScreen>
  );
}

function PriorityChoice({
  priority,
  selected,
  onPress
}: {
  priority: ProjectPriority;
  selected: boolean;
  onPress(): void;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`Set project priority to ${projectPriorityLabel(priority)}`}
      accessibilityState={{ selected }}
      onPress={onPress}
      style={({ pressed }) => ({
        minHeight: tokens.touchTarget,
        justifyContent: "center",
        paddingHorizontal: tokens.space.md,
        borderRadius: tokens.radius.pill,
        borderCurve: "continuous",
        borderWidth: 1,
        borderColor: selected ? colors.primary : colors.separator,
        backgroundColor: selected ? colors.primary : colors.surface,
        opacity: pressed ? 0.78 : 1
      })}
    >
      <Text style={{ color: selected ? colors.onPrimary : colors.label, fontWeight: "700" }}>
        {projectPriorityLabel(priority)}
      </Text>
    </Pressable>
  );
}

export function ProjectCreateScreen() {
  const { state } = useAuth();
  const router = useRouter();
  const [values, setValues] = React.useState<ProjectCreateFormValues>(EMPTY_PROJECT_CREATE_FORM);
  const [errors, setErrors] = React.useState<FormErrors>({});
  const mutation = useCreateProjectMutation();

  if (state.kind !== "authorized") return null;

  const enabled = canUsePhase2OperationalCapability(
    state.profile,
    "projects.create",
    "projectCreate",
    isPhase2CapabilityEnabled
  );
  if (!enabled) {
    return (
      <AppScreen testID="project-create-gated">
        <StatusNotice tone="warning">{phase2OperationalUnavailableMessage(state.profile)}</StatusNotice>
      </AppScreen>
    );
  }

  const change = <K extends keyof ProjectCreateFormValues>(
    field: K,
    value: ProjectCreateFormValues[K]
  ): void => {
    setValues((current) => ({ ...current, [field]: value }));
    setErrors((current) => ({ ...current, [field]: undefined }));
  };

  const submit = (): void => {
    const validation = validateProjectCreate(values);
    setErrors(validation.errors);
    if (!validation.payload) return;

    mutation.mutate(validation.payload, {
      onSuccess: (project) => {
        router.replace({
          pathname: "/projects/[project-id]",
          params: { "project-id": project.id }
        });
      }
    });
  };

  return (
    <ProjectCreateView
      values={values}
      errors={errors}
      isPending={mutation.isPending}
      mutationError={mutation.error instanceof Error ? mutation.error.message : null}
      onChange={change}
      onSubmit={submit}
    />
  );
}
