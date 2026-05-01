#!/usr/bin/env bash
set -euo pipefail

: "${ZAI_API_KEY:?ZAI_API_KEY is required}"
: "${BASE_SHA:?BASE_SHA is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${REPO:?REPO is required (owner/name)}"

MODEL="${ZAI_MODEL:-glm-4.7}"
ENDPOINT="${ZAI_ENDPOINT:-https://api.z.ai/api/paas/v4/chat/completions}"
PROMPT_FILE="${ZAI_PROMPT_FILE:-.github/zai-review-prompt.md}"
MAX_DIFF_BYTES="${ZAI_MAX_DIFF_BYTES:-120000}"
REVIEW_BODY_FILE="${REVIEW_BODY_FILE:-/tmp/zai-review.md}"

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "::error::prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi
SYSTEM_PROMPT="$(cat "$PROMPT_FILE")"

EXCLUDES=(
  ':(exclude)*.lock'
  ':(exclude)Package.resolved'
  ':(exclude)*.xcodeproj/**'
  ':(exclude).build/**'
  ':(exclude).swiftpm/**'
  ':(exclude)artifacts/**'
  ':(exclude)TestFixtures/FakeRFBServer/Fixtures/*.hex'
)

CHANGED_FILES="$(git diff --name-only "$BASE_SHA..$HEAD_SHA" -- "${EXCLUDES[@]}" || true)"
DIFF="$(git diff "$BASE_SHA..$HEAD_SHA" -- "${EXCLUDES[@]}" || true)"

if [[ -z "$DIFF" ]]; then
  echo "No reviewable diff after filters; approving with empty-diff note."
  printf '<!-- zai-code-review head_sha=%s -->\nAPPROVE\n\nZ.ai 리뷰: 변경된 리뷰 대상 파일 없음 (lock/generated/fixture 제외 후 빈 diff).\n\n<sub>Reviewed by Z.ai GLM-4.7</sub>\n' \
    "$HEAD_SHA" > "$REVIEW_BODY_FILE"
  gh pr review "$PR_NUMBER" --repo "$REPO" --approve --body-file "$REVIEW_BODY_FILE"
  exit 0
fi

DIFF_SIZE=${#DIFF}
TRUNCATED_NOTE=""
if (( DIFF_SIZE > MAX_DIFF_BYTES )); then
  DIFF="${DIFF:0:$MAX_DIFF_BYTES}"
  TRUNCATED_NOTE=$'\n\n[diff truncated to '"$MAX_DIFF_BYTES"' bytes for review; original was '"$DIFF_SIZE"' bytes]'
fi

USER_MSG="아래 메타데이터와 git diff를 위 시스템 프롬프트의 원칙에 따라 리뷰하세요.

REPO: $REPO
HEAD_SHA: $HEAD_SHA
BASE_SHA: $BASE_SHA
PR_NUMBER: $PR_NUMBER

## Changed files
$CHANGED_FILES

## Diff
\`\`\`diff
$DIFF
\`\`\`$TRUNCATED_NOTE

위 시스템 프롬프트의 출력 규칙을 그대로 따르세요. 본문 첫 줄에 마커, 두 번째 줄에 판단,
끝부분에 \`VERDICT: APPROVE\` 또는 \`VERDICT: REQUEST_CHANGES\` 한 줄, 마지막에 푸터를
정확히 포함하세요."

PAYLOAD="$(jq -n \
  --arg model "$MODEL" \
  --arg sys "$SYSTEM_PROMPT" \
  --arg usr "$USER_MSG" \
  '{
    model: $model,
    messages: [
      { role: "system", content: $sys },
      { role: "user",   content: $usr }
    ],
    temperature: 0.2,
    stream: false
  }')"

HTTP_RESPONSE_FILE="$(mktemp)"
HTTP_STATUS="$(curl -sS -o "$HTTP_RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$ENDPOINT" \
  -H "Authorization: Bearer $ZAI_API_KEY" \
  -H "Content-Type: application/json" \
  --data-binary "$PAYLOAD" || echo '000')"

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "::error::Z.ai API call failed (HTTP $HTTP_STATUS)" >&2
  cat "$HTTP_RESPONSE_FILE" >&2 || true
  exit 1
fi

REVIEW_TEXT="$(jq -r '.choices[0].message.content // ""' < "$HTTP_RESPONSE_FILE")"
rm -f "$HTTP_RESPONSE_FILE"

if [[ -z "$REVIEW_TEXT" ]]; then
  echo "::error::Z.ai returned empty content" >&2
  exit 1
fi

VERDICT_LINE="$(printf '%s\n' "$REVIEW_TEXT" | grep -E '^VERDICT:[[:space:]]*(APPROVE|REQUEST_CHANGES)$' | tail -1 || true)"
case "$VERDICT_LINE" in
  *REQUEST_CHANGES*) GH_FLAG="--request-changes" ;;
  *APPROVE*)         GH_FLAG="--approve" ;;
  *)
    echo "::warning::No clear VERDICT line found; defaulting to APPROVE per house rule (no COMMENT verdicts)." >&2
    GH_FLAG="--approve"
    ;;
esac

# Strip the bare VERDICT line from the posted body (it's a parser signal, not for humans).
printf '%s\n' "$REVIEW_TEXT" | grep -vE '^VERDICT:[[:space:]]*(APPROVE|REQUEST_CHANGES)$' > "$REVIEW_BODY_FILE"

gh pr review "$PR_NUMBER" --repo "$REPO" "$GH_FLAG" --body-file "$REVIEW_BODY_FILE"
echo "Posted Z.ai review with $GH_FLAG."
