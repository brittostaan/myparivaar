# Team SOP: Release in 3 Steps

## Goal
Move changes through:

1. Dev: dev.myparivaar.ai
2. Preview: preview.myparivaar.ai
3. Production: myparivaar.ai

## Branch Flow
1. develop drives Dev
2. staging drives Preview
3. main drives Production

## What to Say
1. Commit and push changes to dev.
2. Commit and push changes to preview.
3. Commit and push changes to production.

## Approval Rule
1. Only promote to next stage after testing and approval in current stage.

## If You Do Not Like a Change
1. On Dev: Revert the last dev commit and push to develop.
2. Or: Revert commit <commit-id> on develop and push.
3. Same pattern for staging and main.

## Team Safety
1. No direct production pushes without explicit approval.
2. Always promote the same tested commit forward.
3. Confirm correct URL before testing.
