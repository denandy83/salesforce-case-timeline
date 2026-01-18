# Implementation Plan - Fix Reply All Error

## Phase 1: Analysis and Reproduction
- [ ] Task: Locate the relevant code responsible for the "Reply All" functionality.
    - [ ] Search for "Reply All" handlers in LWC (`nD_CaseTimeline`).
    - [ ] Search for corresponding Apex methods in `ND_CaseTimelineController` or `ND_EmailCompare`.
- [ ] Task: Create a reproduction test case.
    - [ ] Create an Apex unit test in `ND_TimelineTest_Final` (or a new test class) that attempts to simulate the "Reply All" logic (e.g., calling the method that creates the draft).
    - [ ] Verify that the test fails with the expected error: `cannot specify id in an insert call`.
- [ ] Task: Conductor - User Manual Verification 'Analysis and Reproduction' (Protocol in workflow.md)

## Phase 2: Fix Implementation
- [ ] Task: Modify the Apex Controller/LWC to prevent passing or setting the `Id` on the new record.
    - [ ] **Sub-task:** If the issue is in Apex (cloning), ensure the `Id` is cleared (e.g., `newEmail.Id = null;`) or use `sObject.clone(false, ...)` to perform a deep clone without the Id.
    - [ ] **Sub-task:** If the issue is in LWC, ensure the payload sent to the server does not include the `Id` if the intention is to create a new record.
- [ ] Task: Verify the fix with the unit test.
    - [ ] Run the reproduction test created in Phase 1.
    - [ ] Ensure the test now passes.
- [ ] Task: Conductor - User Manual Verification 'Fix Implementation' (Protocol in workflow.md)

## Phase 3: Verification and Cleanup
- [ ] Task: Run all related tests to ensure no regressions.
    - [ ] Run `sfdx-lwc-jest` for LWC components.
    - [ ] Run all Apex tests in the project.
- [ ] Task: Conductor - User Manual Verification 'Verification and Cleanup' (Protocol in workflow.md)
