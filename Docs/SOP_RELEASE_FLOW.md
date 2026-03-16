# SOP: Dev to Preview to Production Release Flow

## 1. Purpose
This SOP defines how changes move safely through environments with automatic deployment:

1. Dev: https://dev.myparivaar.ai
2. Preview: https://preview.myparivaar.ai
3. Production: https://myparivaar.ai

## 2. Environment Mapping
### Dev
1. Branch: develop
2. Vercel project: myparivaar-dev
3. Domain: dev.myparivaar.ai
4. Build environment: APP_ENV=dev

### Preview
1. Branch: staging
2. Vercel project: myparivaar-preview
3. Domain: preview.myparivaar.ai
4. Build environment: APP_ENV=preview

### Production
1. Branch: main
2. Vercel project: myparivaar
3. Domain: myparivaar.ai
4. Build environment: APP_ENV=prod

## 3. Release Workflow
### Step 1: Build and test in Dev
1. Request feature change.
2. Instruction: Commit and push changes to dev.
3. Code goes to develop.
4. Auto deploy happens on dev.myparivaar.ai.

### Step 2: Promote to Preview
1. After Dev approval, instruction: Commit and push changes to preview.
2. Code goes to staging.
3. Auto deploy happens on preview.myparivaar.ai.

### Step 3: Promote to Production
1. After Preview approval, instruction: Commit and push changes to production.
2. Code goes to main.
3. Auto deploy happens on myparivaar.ai.

## 4. Revert Process
### If not committed yet
1. Instruction: Discard this feature work and return to last saved state.

### If committed and pushed to Dev
1. Instruction: Revert the last dev commit and push to develop.
2. Alternative: Revert commit <commit-id> on develop and push.

### If committed and pushed to Preview
1. Instruction: Revert commit <commit-id> on staging and push.

### If committed and pushed to Production
1. Instruction: Revert commit <commit-id> on main and push.

## 5. Safety Rules
1. Never push to preview or production unless explicitly approved.
2. Use one-way promotion only: develop to staging to main.
3. Promote the same tested commit forward.
4. Verify deployment status is Ready before testing.
5. Verify you are testing the correct URL.

## 6. Standard Commands
1. Start feature work: <feature description>. Keep it in dev flow only.
2. Commit and push changes to dev.
3. Commit and push changes to preview.
4. Commit and push changes to production.
5. Revert the last dev commit and push to develop.
6. Revert commit <commit-id> on <branch> and push.

## 7. Quick Verification Checklist
1. Target URL opens successfully.
2. Feature works.
3. No obvious regression.
4. Expected environment behavior appears.
5. Deployment source branch and commit are correct.
