---
name: openapi-contract
description: 'Answer "what is the contract of this endpoint" from a local OpenAPI/Swagger dump, and optionally confirm it with a live request on a non-production environment. Use when the user says "check the swagger", "what does this endpoint accept or return", "try this payload and see what comes back", "update the spec", asks to inspect an OpenAPI document, or wants to verify a request or response DTO against a running backend. Russian triggers: "сходи в сваггер", "какой формат у эндпоинта", "что принимает/отдаёт ручка", "проверь ручку вживую", "обновить спеку".'
---

# OpenAPI contract

Goal: answer "what is the contract of endpoint X" quickly and reliably from a local copy of the spec. Go to the network only when there is no copy or the contract has changed.

## Project settings

Identify these in the project's instructions, or ask:

- **`API_BASE`:** a **non-production** API URL. If you cannot tell whether a host is production, treat it as production and ask.
- **`SPEC_DIR`:** where spec dumps are kept (for example `.local/openapi/`). It must be ignored by git: a spec can reveal internal structure.
- **Cleanup marker:** the text that marks test records (for example `ZZ-TEST`), so they can be found and removed.

## 0. Never point this at production

- Do not run any request in this skill, including reads, against production.
- Set the host explicitly. Do not rely on an application's environment variables: an empty value may fall back to a default host you did not intend to use.
- Check that the environment enforces the contract. A lenient host that accepts any JSON tells you nothing about the format.

## 1. Check the local dump first

```bash
ls -la "<spec-dir>"
```

If the file is there and the contract has not changed, **read it and stay off the network** (step 3). The file's date tells you how old it is. If it may be out of date, say so in your answer or refresh it.

## 2. Download or refresh the spec

**The spec may be split up.** One backend can serve several services through an aggregator. If so, `GET /v3/api-docs/swagger-config` usually lists them in `urls[]`, and each service has its own document. This path is the springdoc default; other frameworks use others, so check the project's Swagger UI if it returns 404.

**The spec itself may require auth.** Do not assume a spec endpoint is public: a 401 on the config or the docs is a normal answer, not proof that the URL is wrong. A connection failure is a different problem: check the host and the network.

**The user runs token commands, not the agent.** Tokens must stay out of the agent's context. Do not ask for a token in chat and do not put one in a command you run. Fill in the settings and give the user this block to paste into **a separate terminal**. Do not use a shell-passthrough such as Claude Code's `!`: its output joins the conversation, and it may not have a terminal for the hidden prompt.

```bash
(
API_BASE='<non-production-url>'; SPEC_DIR='<spec-dir>'; SPEC_PATH='/v3/api-docs'; SPEC_NAME='api-docs.json'
printf 'Token: ' >&2; IFS= read -rs TOKEN; echo >&2
mkdir -p "$SPEC_DIR" && TMP=$(mktemp "$SPEC_DIR/.download.XXXXXX") && {
  if printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -fsS -K - "$API_BASE$SPEC_PATH" -o "$TMP" \
    && python3 -I -m json.tool "$TMP" >/dev/null; then
    mv "$TMP" "$SPEC_DIR/$SPEC_NAME"; ls -la "$SPEC_DIR/$SPEC_NAME"
  else
    echo 'Download failed. The existing spec, if any, was not changed.' >&2; rm -f "$TMP"
  fi
}
)
```

Keep the outer parentheses and paste the block whole. They make the shell read all of it before anything runs, so `read` waits for the typed token instead of taking the next pasted line, and the token ends with the subshell. Wait for `Token:` before typing: anything typed earlier could reach the shell as a command.

The token goes to `curl` through stdin, so it does not appear in the process list or shell history. A failed request or a response that is not JSON leaves the old file in place and says so. A token containing `"` or `\` breaks this curl config line; a JWT never does. Ask the user to tell you whether it succeeded, then parse the file locally.

## 3. Parse it locally

Specs are large, and web-fetch tools may truncate them. Save the spec to a file and parse it with a script.

List the endpoints whose path contains a substring:

```bash
python3 -I - "<spec-dir>/api-docs.json" "SUBSTRING" <<'PY'
import json, sys
spec = json.load(open(sys.argv[1], encoding="utf-8"))
METHODS = {"get", "put", "post", "delete", "patch", "head", "options", "trace"}
for path, item in sorted(spec.get("paths", {}).items()):
    if sys.argv[2] in path:
        print(path, sorted(m.upper() for m in item if m in METHODS))
PY
```

Print one operation with its `$ref`s expanded:

```bash
python3 -I - "<spec-dir>/api-docs.json" post "/example/path/{id}" <<'PY'
import json, sys
spec = json.load(open(sys.argv[1], encoding="utf-8"))

def expand(node, seen=()):
    if isinstance(node, list):
        return [expand(item, seen) for item in node]
    if not isinstance(node, dict):
        return node
    ref = node.get("$ref")
    if ref:
        if not ref.startswith("#/"):
            return {"$ref": ref, "note": "external reference, not expanded"}
        if ref in seen:
            return {"$ref": ref, "note": "cycle"}
        target = spec
        for part in ref[2:].split("/"):
            target = target[part.replace("~1", "/").replace("~0", "~")]
        return expand(target, seen + (ref,))
    return {key: expand(value, seen) for key, value in node.items()}

item = spec["paths"][sys.argv[3]]
operation = item[sys.argv[2].lower()]
print(json.dumps(expand({
    "parameters": item.get("parameters", []) + operation.get("parameters", []),
    "requestBody": operation.get("requestBody"),
    "responses": operation.get("responses"),
}), ensure_ascii=False, indent=2))
PY
```

When reading the output, pay attention to the `required` list, `readOnly`, and whether a reference field is a scalar id or an object. A field that is not in `required` may still be required by server-side validation, which is what the next step checks.

## 4. Confirm it live

Do this when you need to know that the backend really behaves this way, not just what the schema says. Use `API_BASE` only.

**Safety rules:**

- **GET is free to use.** It is the first choice for "what does it return".
- **POST, PUT, PATCH and DELETE change real data, even on a test environment.** Before each one, show the user the method, URL and payload and get confirmation.
- **Mark every test record** with the cleanup marker in a text field, and delete what you created when possible. Otherwise tell the user what is left.
- **The user runs anything that needs a token,** in a separate terminal as in step 2. The response goes to a file, not to the conversation. Response headers are not saved, so `Set-Cookie` is not captured. The user reads the body and pastes back only what is needed. Do not read that file unless the user tells you to.

Read:

```bash
(
API_BASE='<non-production-url>'; REQUEST_PATH='/example/path/123'
OUT=$(mktemp); printf 'Token: ' >&2; IFS= read -rs TOKEN; echo >&2
printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -sS -K - \
  -o "$OUT" -w 'HTTP %{http_code}\n' "$API_BASE$REQUEST_PATH"
echo "Response body: $OUT"
)
```

Write, only after confirmation:

```bash
(
API_BASE='<non-production-url>'; REQUEST_PATH='/example/path/123'
OUT=$(mktemp); printf 'Token: ' >&2; IFS= read -rs TOKEN; echo >&2
printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -sS -K - -X POST \
  -H 'Content-Type: application/json' -d '{"name":"ZZ-TEST contract check"}' \
  -o "$OUT" -w 'HTTP %{http_code}\n' "$API_BASE$REQUEST_PATH"
echo "Response body: $OUT"
)
```

Have the user delete the response file when finished.

How to read the answer:

- **2xx:** the payload was accepted. That does not prove every field was saved, so read the record back.
- **400 or 422:** the format is wrong; the body usually says what is missing.
- **401:** no valid session. **403:** a missing permission or, on many backends, a missing CSRF header. Neither says anything about the format.

To settle "scalar or object", send one payload in both forms (`typeId: 2` and `type: {"id": 2}`), then read the record back to see which one the backend really stored. A 200 can hide an ignored field.

## 5. Answer and record

- Answer concretely: required fields, types, scalar or object, read-only fields.
- Say what your answer rests on: a dump (and how old it is) or a live response.
- If the spec and the live behavior differ, report that as a finding. The live response is what clients actually get.
- Refresh the dump if the contract has changed. Record any non-obvious fact in the project's notes, so nobody has to rediscover it.
