# Team SOP: Release in 2 Steps

## Goal
Move changes through:

1. Preview: preview.myparivaar.ai
2. Production: myparivaar.ai

## Branch Flow
1. staging drives Preview
2. main drives Production

## What to Say
1. Commit and push changes to preview.
2. Commit and push changes to production.

## Approval Rule
1. Only promote to production after testing and approval in preview.

## If You Do Not Like a Change
1. On Preview: Revert commit <commit-id> on staging and push.
2. On Production: Revert commit <commit-id> on main and push.

## Team Safety
1. No direct production pushes without explicit approval.
2. Always promote the same tested commit forward.
3. Confirm correct URL before testing.
