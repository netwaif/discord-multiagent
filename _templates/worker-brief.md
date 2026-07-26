# Brief — [worker-role] / [작업명]

<!-- HARD LIMIT: 1200자 한글 / 240단어 영문 (wc -m / wc -w). 파일 내용 inline 금지. 경로만 전달. -->
<!-- worker가 추론할 수 있는 것은 쓰지 말 것. -->

## Execution Context (codex-main / codex-critic 필수)

```yaml
target_repo: /absolute/path/to/repo    # 작업 대상 절대 경로 (없으면 N/A)
write_scope: none             # none | tasks-only | "src/**, tests/**" 등 패턴
                              # 외부 repo 쓰기는 task.md workers_approved에 별도 승인 필요
```

## Objective

한 문장. 이 worker가 완료해야 하는 것.

## Input

```
# 파일 경로로만 참조. 내용을 여기에 붙여넣지 말 것.
task:    tasks/<task-name>/task.md
context: tasks/<task-name>/context.md
sources: tasks/<task-name>/sources/<file>
```

## Constraints

- 제약 1
- 제약 2

## Output Format

결과물 형식을 정확히 명시:
- 파일 위치: `tasks/<task-name>/workers/<role>/result.md`
- 형식: Markdown | JSON | Code | Diff
- 구조: (예: 섹션명 또는 코드 블록 형식)

## Do NOT

- 하지 말아야 할 것 1
- 하지 말아야 할 것 2

## Prior Results (해당 시)

```
# 선행 worker 결과가 있으면 경로만 명시
claude-main result: tasks/<task-name>/workers/claude-main/result.md
```
