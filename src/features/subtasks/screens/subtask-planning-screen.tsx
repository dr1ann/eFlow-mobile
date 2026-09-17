import React from "react";
import { useQuery } from "@tanstack/react-query";
import { Text, View } from "react-native";

import { AppScreen } from "@/components/app-screen";
import { Button } from "@/components/button";
import { FormField } from "@/components/form-field";
import { StatusNotice } from "@/components/status-notice";
import { subtaskStatusLabel, type Subtask } from "@/contracts/subtasks";
import type { Task } from "@/contracts/tasks";
import { useAuth } from "@/features/auth/auth-context";
import { formatTaskDate } from "@/features/tasks/presentation";
import { isTaskLead } from "@/features/tasks/selectors";
import { taskDetailQueryOptions } from "@/features/tasks/query-options";
import { isPhase2CapabilityEnabled } from "@/lib/phase-2/capabilities";
import { SupabaseUserError } from "@/lib/supabase/errors";
import { colors } from "@/theme/colors";
import { tokens } from "@/theme/tokens";

import { subtasksByTaskQueryOptions } from "../query-options";
import {
  EMPTY_SUBTASK_PLANNING_FORM,
  canPlanSubtasks,
  isSubtaskStructureMutable,
  planningCandidatesFromTask,
  reorderedSubtaskIds,
  subtaskDueDateError,
  validateManagedSubtask,
  type SubtaskPlanningCandidate,
  type SubtaskPlanningFormValues
} from "../subtask-planning";
import {
  useAssignManagedSubtaskMutation,
  useCreateManagedSubtaskMutation,
  useReorderManagedSubtasksMutation,
  useSetManagedSubtaskDueDateMutation,
  useSetManagedSubtaskExecutionModeMutation
} from "../use-subtask-planning";

type FormErrors = Partial<Record<keyof SubtaskPlanningFormValues, string>>;

export interface SubtaskPlanningCapabilities {
  create: boolean;
  assign: boolean;
  schedule: boolean;
  reorder: boolean;
  executionRules: boolean;
}

export interface SubtaskPlanningViewProps {
  task: Task;
  subtasks: readonly Subtask[];
  candidates: readonly SubtaskPlanningCandidate[];
  values: SubtaskPlanningFormValues;
  errors: FormErrors;
  capabilities: SubtaskPlanningCapabilities;
  isPending: boolean;
  mutationError: string | null;
  selectedSubtaskId: string | null;
  rescheduleDate: string;
  rescheduleReason: string;
  rescheduleError: string | null;
  onChange<K extends keyof SubtaskPlanningFormValues>(field: K, value: SubtaskPlanningFormValues[K]): void;
  onCreate(): void;
  onAssign(subtaskId: string, assigneeId: string): void;
  onSetExecutionMode(subtaskId: string, isStandalone: boolean): void;
  onMove(subtaskId: string, direction: "up" | "down"): void;
  onSelectSchedule(subtaskId: string): void;
  onRescheduleDateChange(value: string): void;
  onRescheduleReasonChange(value: string): void;
  onSaveSchedule(): void;
}

function capabilityMessage(capabilities: SubtaskPlanningCapabilities): string {
  const unavailable: string[] = [];
  if (!capabilities.create) unavailable.push("create");
  if (!capabilities.assign) unavailable.push("assign");
  if (!capabilities.schedule) unavailable.push("schedule");
  if (!capabilities.reorder) unavailable.push("reorder");
  if (!capabilities.executionRules) unavailable.push("execution rules");
  return unavailable.length === 0
    ? ""
    : `Mobile subtask ${unavailable.join(", ")} actions remain unavailable until their individual deployed-contract probes are recorded.`;
}

function selectedSubtask(subtasks: readonly Subtask[], subtaskId: string | null): Subtask | null {
  return subtaskId ? subtasks.find((subtask) => subtask.id === subtaskId) ?? null : null;
}

export function SubtaskPlanningView({
  task,
  subtasks,
  candidates,
  values,
  errors,
  capabilities,
  isPending,
  mutationError,
  selectedSubtaskId,
  rescheduleDate,
  rescheduleReason,
  rescheduleError,
  onChange,
  onCreate,
  onAssign,
  onSetExecutionMode,
  onMove,
  onSelectSchedule,
  onRescheduleDateChange,
  onRescheduleReasonChange,
  onSaveSchedule
}: SubtaskPlanningViewProps) {
  const selected = selectedSubtask(subtasks, selectedSubtaskId);
  const planningOpen = canPlanSubtasks(task);

  return (
    <AppScreen testID="subtask-planning-screen">
      <View style={{ gap: tokens.space.xs }}>
        <Text selectable style={{ color: colors.label, fontSize: tokens.type.display, fontWeight: "800" }}>
          Plan subtasks
        </Text>
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body, lineHeight: 22 }}>
          {task.title}
        </Text>
      </View>

      <StatusNotice>
        Only the effective Task Lead may use these controls. The database validates the relationship, task state, schedule, and execution rules again for every write.
      </StatusNotice>

      {!planningOpen ? (
        <StatusNotice tone="warning">
          This task is not in a planning state. Refresh it after any work or review transition before changing subtask structure.
        </StatusNotice>
      ) : null}

      {capabilityMessage(capabilities) ? <StatusNotice tone="warning">{capabilityMessage(capabilities)}</StatusNotice> : null}

      {capabilities.create && planningOpen ? (
        <PlanningSection title="Add a subtask">
          {candidates.length === 0 ? (
            <StatusNotice tone="warning">
              No assigned task participants are available for this task. Assign the task team through the verified Department Head flow before creating a subtask.
            </StatusNotice>
          ) : (
            <>
              <FormField
                label="Subtask title"
                value={values.title}
                onChangeText={(value) => onChange("title", value)}
                error={errors.title}
                maxLength={160}
                autoCapitalize="sentences"
                returnKeyType="next"
              />
              <ChoiceGroup
                label="Assigned contributor"
                candidates={candidates}
                selectedId={values.assigneeId}
                error={errors.assigneeId}
                onSelect={(id) => onChange("assigneeId", id)}
              />
              <FormField
                label="Due date"
                value={values.dueDate}
                onChangeText={(value) => onChange("dueDate", value)}
                error={errors.dueDate}
                placeholder="YYYY-MM-DD"
                autoCapitalize="none"
                autoCorrect={false}
                keyboardType="numbers-and-punctuation"
                maxLength={10}
              />
              <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, lineHeight: 20 }}>
                Leave the date blank when no individual deadline is required. A supplied date cannot exceed the parent deadline.
              </Text>
              <ExecutionModeChoice
                value={values.executionMode}
                onChange={(executionMode) => onChange("executionMode", executionMode)}
              />
              <Button label="Create subtask" loading={isPending} onPress={onCreate} />
            </>
          )}
        </PlanningSection>
      ) : null}

      {mutationError ? <StatusNotice tone="danger">{mutationError}</StatusNotice> : null}

      <PlanningSection title="Existing subtasks">
        {subtasks.length === 0 ? (
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>
            No subtasks are visible for this task.
          </Text>
        ) : (
          subtasks.map((subtask, index) => {
            const mutable = planningOpen && isSubtaskStructureMutable(subtask);
            return (
              <SubtaskPlanningRow
                key={subtask.id}
                subtask={subtask}
                index={index}
                total={subtasks.length}
                candidates={candidates}
                mutable={mutable}
                canMoveUp={reorderedSubtaskIds(subtasks, subtask.id, "up") !== null}
                canMoveDown={reorderedSubtaskIds(subtasks, subtask.id, "down") !== null}
                capabilities={capabilities}
                isPending={isPending}
                onAssign={onAssign}
                onSetExecutionMode={onSetExecutionMode}
                onMove={onMove}
                onSelectSchedule={onSelectSchedule}
              />
            );
          })
        )}
      </PlanningSection>

      {selected && capabilities.schedule ? (
        <PlanningSection title={`Schedule ${selected.title}`}>
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, lineHeight: 20 }}>
            Current date: {formatTaskDate(selected.dueDate)}. The server records and validates the reason where required.
          </Text>
          <FormField
            label="New due date"
            value={rescheduleDate}
            onChangeText={onRescheduleDateChange}
            error={rescheduleError ?? undefined}
            placeholder="YYYY-MM-DD"
            autoCapitalize="none"
            autoCorrect={false}
            keyboardType="numbers-and-punctuation"
            maxLength={10}
          />
          <FormField
            label="Schedule change reason"
            value={rescheduleReason}
            onChangeText={onRescheduleReasonChange}
            placeholder="Optional reason"
            autoCapitalize="sentences"
            maxLength={500}
            multiline
            textAlignVertical="top"
          />
          <Button label="Save subtask schedule" loading={isPending} onPress={onSaveSchedule} />
        </PlanningSection>
      ) : null}
    </AppScreen>
  );
}

function PlanningSection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
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
      <Text selectable style={{ color: colors.label, fontSize: tokens.type.title, fontWeight: "800" }}>
        {title}
      </Text>
      {children}
    </View>
  );
}

function ChoiceGroup({
  label,
  candidates,
  selectedId,
  error,
  onSelect
}: {
  label: string;
  candidates: readonly SubtaskPlanningCandidate[];
  selectedId: string;
  error?: string;
  onSelect(id: string): void;
}) {
  return (
    <View style={{ gap: tokens.space.sm }}>
      <Text selectable style={{ color: colors.label, fontSize: tokens.type.caption, fontWeight: "700" }}>
        {label}
      </Text>
      <View style={{ gap: tokens.space.sm }}>
        {candidates.map((candidate) => (
          <Button
            key={candidate.id}
            label={candidate.label}
            variant={candidate.id === selectedId ? "primary" : "secondary"}
            onPress={() => onSelect(candidate.id)}
          />
        ))}
      </View>
      {error ? <Text selectable style={{ color: colors.danger, fontSize: tokens.type.caption }}>{error}</Text> : null}
    </View>
  );
}

function ExecutionModeChoice({
  value,
  onChange
}: {
  value: SubtaskPlanningFormValues["executionMode"];
  onChange(value: SubtaskPlanningFormValues["executionMode"]): void;
}) {
  return (
    <View style={{ gap: tokens.space.sm }}>
      <Text selectable style={{ color: colors.label, fontSize: tokens.type.caption, fontWeight: "700" }}>
        Execution mode
      </Text>
      <Button
        label="Sequential"
        variant={value === "sequential" ? "primary" : "secondary"}
        onPress={() => onChange("sequential")}
      />
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, lineHeight: 20 }}>
        Sequential work waits for earlier regular steps to be approved.
      </Text>
      <Button
        label="Standalone"
        variant={value === "standalone" ? "primary" : "secondary"}
        onPress={() => onChange("standalone")}
      />
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, lineHeight: 20 }}>
        Standalone work is genuinely independent and can run in parallel.
      </Text>
    </View>
  );
}

function SubtaskPlanningRow({
  subtask,
  index,
  total,
  candidates,
  mutable,
  canMoveUp,
  canMoveDown,
  capabilities,
  isPending,
  onAssign,
  onSetExecutionMode,
  onMove,
  onSelectSchedule
}: {
  subtask: Subtask;
  index: number;
  total: number;
  candidates: readonly SubtaskPlanningCandidate[];
  mutable: boolean;
  canMoveUp: boolean;
  canMoveDown: boolean;
  capabilities: SubtaskPlanningCapabilities;
  isPending: boolean;
  onAssign(subtaskId: string, assigneeId: string): void;
  onSetExecutionMode(subtaskId: string, isStandalone: boolean): void;
  onMove(subtaskId: string, direction: "up" | "down"): void;
  onSelectSchedule(subtaskId: string): void;
}) {
  return (
    <View style={{ gap: tokens.space.sm, paddingTop: tokens.space.sm, borderTopWidth: 1, borderColor: colors.separator }}>
      <Text selectable style={{ color: colors.label, fontSize: tokens.type.body, fontWeight: "800" }}>
        {subtask.title}
      </Text>
      <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
        {subtaskStatusLabel(subtask.status)} · {subtask.percentComplete}% · {subtask.isStandalone ? "Standalone" : "Sequential"} · {formatTaskDate(subtask.dueDate)}
      </Text>
      {!mutable ? (
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption }}>
          Started, submitted, or completed work keeps its existing planning structure.
        </Text>
      ) : null}

      {mutable && capabilities.assign ? (
        <View style={{ gap: tokens.space.xs }}>
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.caption, fontWeight: "700" }}>
            Reassign contributor
          </Text>
          {candidates.map((candidate) => (
            <Button
              key={candidate.id}
              label={`Assign to ${candidate.label}`}
              variant="secondary"
              disabled={isPending || candidate.id === subtask.assignedTo}
              onPress={() => onAssign(subtask.id, candidate.id)}
            />
          ))}
        </View>
      ) : null}

      {mutable && capabilities.executionRules ? (
        <Button
          label={subtask.isStandalone ? "Make sequential" : "Make standalone"}
          variant="secondary"
          disabled={isPending}
          onPress={() => onSetExecutionMode(subtask.id, !subtask.isStandalone)}
        />
      ) : null}

      {mutable && capabilities.schedule ? (
        <Button label="Change due date" variant="secondary" disabled={isPending} onPress={() => onSelectSchedule(subtask.id)} />
      ) : null}

      {mutable && capabilities.reorder ? (
        <View style={{ flexDirection: "row", gap: tokens.space.sm }}>
          <View style={{ flex: 1 }}>
            <Button label="Move up" variant="secondary" disabled={isPending || index === 0 || !canMoveUp} onPress={() => onMove(subtask.id, "up")} />
          </View>
          <View style={{ flex: 1 }}>
            <Button label="Move down" variant="secondary" disabled={isPending || index === total - 1 || !canMoveDown} onPress={() => onMove(subtask.id, "down")} />
          </View>
        </View>
      ) : null}
    </View>
  );
}

function mutationMessage(error: unknown): string | null {
  if (!error) return null;
  if (error instanceof SupabaseUserError) return error.message;
  return "We could not save this subtask plan. Refresh the task to confirm its current state before trying again.";
}

export function SubtaskPlanningScreen({ taskId }: { taskId: string }) {
  const { state } = useAuth();
  const taskQuery = useQuery(taskDetailQueryOptions(taskId));
  const subtasksQuery = useQuery({
    ...subtasksByTaskQueryOptions(taskId),
    enabled: taskQuery.isSuccess && taskQuery.data !== null
  });
  const createMutation = useCreateManagedSubtaskMutation();
  const assignMutation = useAssignManagedSubtaskMutation();
  const executionMutation = useSetManagedSubtaskExecutionModeMutation();
  const scheduleMutation = useSetManagedSubtaskDueDateMutation();
  const reorderMutation = useReorderManagedSubtasksMutation();
  const [values, setValues] = React.useState<SubtaskPlanningFormValues>(EMPTY_SUBTASK_PLANNING_FORM);
  const [errors, setErrors] = React.useState<FormErrors>({});
  const [selectedSubtaskId, setSelectedSubtaskId] = React.useState<string | null>(null);
  const [rescheduleDate, setRescheduleDate] = React.useState("");
  const [rescheduleReason, setRescheduleReason] = React.useState("");
  const [rescheduleError, setRescheduleError] = React.useState<string | null>(null);

  if (taskQuery.isLoading || subtasksQuery.isLoading) {
    return (
      <AppScreen testID="subtask-planning-loading">
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: tokens.type.body }}>Loading task plan…</Text>
      </AppScreen>
    );
  }

  if (taskQuery.isError || subtasksQuery.isError || !taskQuery.data) {
    return (
      <AppScreen testID="subtask-planning-unavailable">
        <StatusNotice tone="danger">This task is unavailable or its subtask plan could not be loaded.</StatusNotice>
      </AppScreen>
    );
  }

  if (state.kind !== "authorized") return null;
  const task = taskQuery.data;
  const isLead = isTaskLead(task, state.profile.id);
  if (!isLead) {
    return (
      <AppScreen testID="subtask-planning-forbidden">
        <StatusNotice tone="danger">Only the effective Task Lead can manage this subtask plan.</StatusNotice>
      </AppScreen>
    );
  }

  const capabilities: SubtaskPlanningCapabilities = {
    create: isPhase2CapabilityEnabled("subtaskCreate"),
    assign: isPhase2CapabilityEnabled("subtaskAssign"),
    schedule: isPhase2CapabilityEnabled("subtaskDeadline"),
    reorder: isPhase2CapabilityEnabled("subtaskReorder"),
    executionRules: isPhase2CapabilityEnabled("subtaskExecutionRules")
  };
  const subtasks = subtasksQuery.data ?? [];
  const candidates = planningCandidatesFromTask(task);
  const isPending = createMutation.isPending || assignMutation.isPending || executionMutation.isPending || scheduleMutation.isPending || reorderMutation.isPending;
  const mutationError = mutationMessage(
    createMutation.error ?? assignMutation.error ?? executionMutation.error ?? scheduleMutation.error ?? reorderMutation.error
  );

  const change = <K extends keyof SubtaskPlanningFormValues>(
    field: K,
    value: SubtaskPlanningFormValues[K]
  ): void => {
    setValues((current) => ({ ...current, [field]: value }));
    setErrors((current) => ({ ...current, [field]: undefined }));
  };

  const create = (): void => {
    const validation = validateManagedSubtask(values, task, candidates, state.profile.id, subtasks);
    setErrors(validation.errors);
    if (!validation.payload) return;
    createMutation.mutate(validation.payload, { onSuccess: () => setValues(EMPTY_SUBTASK_PLANNING_FORM) });
  };

  const selectSchedule = (subtaskId: string): void => {
    const selected = subtasks.find((subtask) => subtask.id === subtaskId);
    setSelectedSubtaskId(subtaskId);
    setRescheduleDate(selected?.dueDate?.slice(0, 10) ?? "");
    setRescheduleReason("");
    setRescheduleError(null);
  };

  const saveSchedule = (): void => {
    const selected = selectedSubtask(subtasks, selectedSubtaskId);
    const dateError = subtaskDueDateError(task, rescheduleDate);
    if (!selected || dateError) {
      setRescheduleError(dateError ?? "Use a valid date in YYYY-MM-DD format.");
      return;
    }
    scheduleMutation.mutate(
      { taskId, subtaskId: selected.id, dueDate: rescheduleDate, reason: rescheduleReason },
      { onSuccess: () => setSelectedSubtaskId(null) }
    );
  };

  return (
    <SubtaskPlanningView
      task={task}
      subtasks={subtasks}
      candidates={candidates}
      values={values}
      errors={errors}
      capabilities={capabilities}
      isPending={isPending}
      mutationError={mutationError}
      selectedSubtaskId={selectedSubtaskId}
      rescheduleDate={rescheduleDate}
      rescheduleReason={rescheduleReason}
      rescheduleError={rescheduleError}
      onChange={change}
      onCreate={create}
      onAssign={(subtaskId, assigneeId) => assignMutation.mutate({ taskId, subtaskId, assigneeId })}
      onSetExecutionMode={(subtaskId, isStandalone) => executionMutation.mutate({ taskId, subtaskId, isStandalone })}
      onMove={(subtaskId, direction) => {
        const orderedIds = reorderedSubtaskIds(subtasks, subtaskId, direction);
        if (orderedIds) reorderMutation.mutate({ taskId, orderedIds });
      }}
      onSelectSchedule={selectSchedule}
      onRescheduleDateChange={(value) => {
        setRescheduleDate(value);
        setRescheduleError(null);
      }}
      onRescheduleReasonChange={setRescheduleReason}
      onSaveSchedule={saveSchedule}
    />
  );
}
