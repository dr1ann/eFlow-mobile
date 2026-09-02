import { fireEvent, render } from "@testing-library/react-native";

import {
  EMPTY_PROJECT_CREATE_FORM,
  type ProjectCreateFormValues
} from "@/features/projects/project-management";
import { ProjectCreateView } from "@/features/projects/screens/project-create-screen";

describe("ProjectCreateView", () => {
  it("collects a mobile-safe project draft and exposes accessible priority choices", async () => {
    const onChange = jest.fn();
    const onSubmit = jest.fn();
    const view = await render(
      <ProjectCreateView
        values={EMPTY_PROJECT_CREATE_FORM}
        errors={{}}
        isPending={false}
        mutationError={null}
        onChange={onChange}
        onSubmit={onSubmit}
      />
    );

    await fireEvent.changeText(view.getByLabelText("Project title"), "Records modernization");
    await fireEvent.press(view.getByLabelText("Set project priority to High"));
    await fireEvent.press(view.getByLabelText("Create project"));

    expect(onChange).toHaveBeenCalledWith("title", "Records modernization");
    expect(onChange).toHaveBeenCalledWith("priority", "high");
    expect(onSubmit).toHaveBeenCalledTimes(1);
  });

  it("renders validation and server failures without claiming the project was created", async () => {
    const values: ProjectCreateFormValues = { ...EMPTY_PROJECT_CREATE_FORM, title: "Delivery" };
    const view = await render(
      <ProjectCreateView
        values={values}
        errors={{ targetDate: "The target date cannot be before the start date." }}
        isPending={false}
        mutationError="You do not have access to complete this action."
        onChange={jest.fn()}
        onSubmit={jest.fn()}
      />
    );

    expect(view.getByText(/target date cannot/i)).toBeTruthy();
    expect(view.getByText(/do not have access/i)).toBeTruthy();
    expect(view.queryByText(/project created/i)).toBeNull();
  });
});
