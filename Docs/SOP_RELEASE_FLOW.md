# SOP: Preview to Production Release Flow

## 1. Purpose
This SOP defines how changes move safely through environments with automatic deployment:

1. Preview: https://preview.myparivaar.ai
2. Production: https://myparivaar.ai

## 2. Environment Mapping
### Preview
1. Branch: staging
2. Vercel project: myparivaar (preview environment)
3. Domain: preview.myparivaar.ai
4. Build environment: APP_ENV=preview

### Production
1. Branch: main
2. Vercel project: myparivaar (production environment)
3. Domain: myparivaar.ai
4. Build environment: APP_ENV=prod

## 3. Release Workflow
### Step 1: Build and test in Preview
1. Request feature change.
2. Instruction: Commit and push changes to preview.
3. Code goes to staging.
4. Auto deploy happens on preview.myparivaar.ai.

### Step 2: Promote to Production
1. After Preview approval, instruction: Commit and push changes to production.
2. Code goes to main.
3. Auto deploy happens on myparivaar.ai.

## 4. Revert Process
### If not committed yet
1. Instruction: Discard this feature work and return to last saved state.

### If committed and pushed to Preview
1. Instruction: Revert commit <commit-id> on staging and push.

### If committed and pushed to Production
1. Instruction: Revert commit <commit-id> on main and push.

## 5. Safety Rules
1. Never push to production unless explicitly approved.
2. Use one-way promotion only: staging to main.
3. Promote the same tested commit forward.
4. Verify deployment status is Ready before testing.
5. Verify you are testing the correct URL.

## 6. Standard Commands
1. Start feature work: <feature description>. Keep it in preview flow only.
2. Commit and push changes to preview.
3. Commit and push changes to production.
4. Revert commit <commit-id> on <branch> and push.

## 7. Quick Verification Checklist
1. Target URL opens successfully.
2. Feature works.
3. No obvious regression.
4. Expected environment behavior appears.
5. Deployment source branch and commit are correct.
