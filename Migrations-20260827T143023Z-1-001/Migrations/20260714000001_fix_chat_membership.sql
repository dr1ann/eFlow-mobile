-- Update the trigger function sync_task_chat_channel to exclude the task creator (NEW.created_by) from the chat channel members
-- unless they are also explicitly the assignee or a member of the task team.
CREATE OR REPLACE FUNCTION sync_task_chat_channel()
RETURNS TRIGGER AS $$
DECLARE
  v_channel_id UUID;
  v_member_ids UUID[];
BEGIN
  v_member_ids := ARRAY(
    SELECT DISTINCT uid FROM unnest(
      ARRAY[NEW.assigned_to::uuid]
      || COALESCE(NEW.team_member_ids::uuid[], '{}'::uuid[])
    ) AS uid WHERE uid IS NOT NULL
  );

  IF array_length(v_member_ids, 1) IS NULL THEN
    RETURN NEW; -- unassigned task, nobody to chat with yet
  END IF;

  SELECT id INTO v_channel_id FROM chat_channels WHERE task_id = NEW.id;
  IF v_channel_id IS NULL THEN
    INSERT INTO chat_channels (channel_type, task_id, name)
    VALUES ('task', NEW.id, NEW.title)
    RETURNING id INTO v_channel_id;
  ELSE
    UPDATE chat_channels SET name = NEW.title WHERE id = v_channel_id;
  END IF;

  DELETE FROM chat_channel_members
  WHERE channel_id = v_channel_id AND user_id != ALL(v_member_ids);

  INSERT INTO chat_channel_members (channel_id, user_id)
  SELECT v_channel_id, uid FROM unnest(v_member_ids) AS uid
  ON CONFLICT (channel_id, user_id) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
