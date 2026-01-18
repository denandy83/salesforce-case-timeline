# Specification: Fix "Cannot specify Id in an insert call" Error in Quick Reply All

## Context
When a user attempts to use the "Quick Reply All" feature from the Case Timeline, the action fails with the error message: `cannot specify id in an insert call`. This suggests that the system is attempting to insert a new record (likely an `EmailMessage` or related object) while inadvertently explicitly setting the `Id` field, which is not allowed for standard Salesforce inserts.

## User Story
As a Support Agent, I want to be able to "Reply All" to an email directly from the timeline without encountering an error, so that I can quickly respond to customers and stakeholders.

## Current Behavior
1.  User clicks "Reply All" on an email item in the timeline.
2.  The application attempts to open the email composer or create a draft.
3.  An error occurs: `cannot specify id in an insert call`.
4.  The action fails, and the user cannot proceed with the reply.

## Expected Behavior
1.  User clicks "Reply All" on an email item.
2.  The system correctly initializes a new email draft or reply object.
    -   The `Id` field should *not* be set for the new record.
    -   Relevant fields like `ToAddress`, `CcAddress`, `Subject`, and `ParentId` (Case Id) should be populated correctly.
3.  The email composer opens successfully (or the draft is created), allowing the user to send the email.

## Technical Analysis (Hypothesis)
The error is likely originating in the Apex controller responsible for handling the "Reply" action or in the LWC JavaScript that constructs the payload for the Apex method.
-   **Potential Cause 1:** The LWC is passing the `Id` of the *original* email message back to the Apex method, and the Apex method is trying to upsert or insert a *new* `EmailMessage` using that same object instance without clearing the `Id`.
-   **Potential Cause 2:** An Apex trigger on `EmailMessage` is improperly handling the insertion context.
-   **Potential Cause 3:** The logic for cloning the original email message is strictly cloning the `Id` field as well.

## Acceptance Criteria
-   [ ] The "Reply All" action opens the email composer/creates a draft without throwing the `cannot specify id in an insert call` error.
-   [ ] The new email correctly associates with the Case.
-   [ ] The original email's recipients are correctly populated in the `To` and `Cc` fields.
