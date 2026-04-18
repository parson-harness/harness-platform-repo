#!/usr/bin/env python3
import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_TEMPLATE_FILES = [
    ROOT / ".harness/templates/project_governance_workspace.yaml",
    ROOT / ".harness/templates/project_factory_workspace.yaml",
    ROOT / ".harness/templates/pov_provisioner_eks_workspace.yaml",
    ROOT / ".harness/templates/sandbox_provisioner_asg_workspace.yaml",
]


def normalize_endpoint(endpoint: str) -> str:
    value = endpoint.rstrip("/")
    for suffix in ("/gateway", "/gratis"):
        if value.endswith(suffix):
            value = value[: -len(suffix)]
    return value


def parse_response(raw: bytes):
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"raw": raw.decode(errors="replace")}


def harness_request(method: str, url: str, api_key: str, account_id: str, body=None, content_type: str = "application/json"):
    headers = {
        "x-api-key": api_key,
        "Harness-Account": account_id,
        "Content-Type": content_type,
    }
    data = None
    if body is not None:
        if isinstance(body, (dict, list)):
            data = json.dumps(body).encode()
        elif isinstance(body, str):
            data = body.encode()
        else:
            data = body

    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        response = urllib.request.urlopen(request)
        raw = response.read()
        return parse_response(raw), response.status
    except urllib.error.HTTPError as error:
        raw = error.read()
        return parse_response(raw), error.code


def extract_yaml_scalar(yaml_text: str, key: str) -> str:
    match = re.search(rf'^\s*{re.escape(key)}:\s*(.+?)\s*$', yaml_text, re.MULTILINE)
    if not match:
        raise ValueError(f"Missing required key: {key}")
    value = match.group(1).strip()
    if value.startswith('"') and value.endswith('"'):
        value = value[1:-1]
    return value


def override_scope(yaml_text: str, org_id: str, project_id: str) -> str:
    updated = re.sub(r'^(\s*projectIdentifier:\s*).+$', rf'\1{project_id}', yaml_text, count=1, flags=re.MULTILINE)
    updated = re.sub(r'^(\s*orgIdentifier:\s*).+$', rf'\1{org_id}', updated, count=1, flags=re.MULTILINE)
    return updated


def build_base_query(account_id: str, org_id: str, project_id: str) -> str:
    return urllib.parse.urlencode(
        {
            "accountIdentifier": account_id,
            "orgIdentifier": org_id,
            "projectIdentifier": project_id,
        }
    )


def fetch_template(endpoint: str, account_id: str, org_id: str, project_id: str, api_key: str, template_id: str, version_label: str):
    query = build_base_query(account_id, org_id, project_id)
    url = f"{endpoint}/template/api/templates/{template_id}?{query}&versionLabel={urllib.parse.quote(version_label)}&getMetadataOnly=false"
    return harness_request("GET", url, api_key, account_id)


def is_missing_template_response(status: int, payload) -> bool:
    if status == 404:
        return True
    if status != 400 or not isinstance(payload, dict):
        return False
    if payload.get("code") == "RESOURCE_NOT_FOUND_EXCEPTION":
        return True
    message = str(payload.get("message", ""))
    return "does not exist" in message or "has been deleted" in message


def update_template(endpoint: str, account_id: str, org_id: str, project_id: str, api_key: str, template_id: str, version_label: str, yaml_text: str):
    query = build_base_query(account_id, org_id, project_id)
    candidate_urls = [
        f"{endpoint}/template/api/templates/{template_id}?{query}&versionLabel={urllib.parse.quote(version_label)}&isStableTemplate=true",
        f"{endpoint}/template/api/templates/{template_id}/{urllib.parse.quote(version_label)}?{query}&isStableTemplate=true",
        f"{endpoint}/template/api/templates/update/{template_id}?{query}&versionLabel={urllib.parse.quote(version_label)}&isStableTemplate=true",
        f"{endpoint}/template/api/templates/update/{template_id}/{urllib.parse.quote(version_label)}?{query}&isStableTemplate=true",
        f"{endpoint}/v1/orgs/{org_id}/projects/{project_id}/templates/{template_id}?version={urllib.parse.quote(version_label)}&is_stable=true",
    ]

    attempts = []
    for url in candidate_urls:
        for content_type, body in (
            ("application/json", {"yaml": yaml_text, "isNewTemplate": False}),
            ("application/yaml", yaml_text),
        ):
            payload, status = harness_request("PUT", url, api_key, account_id, body=body, content_type=content_type)
            if status in (200, 201):
                return True, f"updated via {url} ({content_type})"
            attempts.append((url, content_type, status, payload))

    return False, attempts


def create_template(endpoint: str, account_id: str, org_id: str, project_id: str, api_key: str, yaml_text: str):
    query = build_base_query(account_id, org_id, project_id)
    base_url = f"{endpoint}/template/api/templates?{query}&storeType=INLINE&setDefaultTemplate=false"
    candidate_calls = [
        (f"{base_url}&isNewTemplate=true", "application/yaml", yaml_text),
        (f"{base_url}&isNewTemplate=false", "application/yaml", yaml_text),
        (f"{base_url}&isNewTemplate=true", "application/json", {"yaml": yaml_text, "isNewTemplate": True}),
        (f"{base_url}&isNewTemplate=false", "application/json", {"yaml": yaml_text, "isNewTemplate": False}),
    ]

    attempts = []
    for url, content_type, body in candidate_calls:
        payload, status = harness_request("POST", url, api_key, account_id, body=body, content_type=content_type)
        if status in (200, 201):
            return True, f"created via {url} ({content_type})"
        attempts.append((url, content_type, status, payload))

    return False, attempts


def sync_template(endpoint: str, account_id: str, org_id: str, project_id: str, api_key: str, template_path: Path):
    original_yaml = template_path.read_text(encoding="utf-8")
    scoped_yaml = override_scope(original_yaml, org_id, project_id)
    template_id = extract_yaml_scalar(scoped_yaml, "identifier")
    version_label = extract_yaml_scalar(scoped_yaml, "versionLabel")
    template_name = extract_yaml_scalar(scoped_yaml, "name")

    payload, status = fetch_template(endpoint, account_id, org_id, project_id, api_key, template_id, version_label)
    if status == 200:
        updated, detail = update_template(endpoint, account_id, org_id, project_id, api_key, template_id, version_label, scoped_yaml)
        if updated:
            return f"UPDATED {template_id}@{version_label} ({template_name}) - {detail}"
        raise RuntimeError(format_attempts(template_id, version_label, "update", detail))

    if is_missing_template_response(status, payload):
        created, detail = create_template(endpoint, account_id, org_id, project_id, api_key, scoped_yaml)
        if created:
            return f"CREATED {template_id}@{version_label} ({template_name}) - {detail}"
        raise RuntimeError(format_attempts(template_id, version_label, "create", detail))

    raise RuntimeError(f"Failed to fetch template {template_id}@{version_label}: HTTP {status}: {payload}")


def format_attempts(template_id: str, version_label: str, action: str, attempts) -> str:
    lines = [f"Failed to {action} template {template_id}@{version_label}."]
    for url, content_type, status, payload in attempts:
        lines.append(f"- {status} {content_type} {url}")
        lines.append(f"  response: {payload}")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("harness_endpoint")
    parser.add_argument("harness_account_id")
    parser.add_argument("harness_org_id")
    parser.add_argument("harness_project_id")
    parser.add_argument("harness_api_key")
    parser.add_argument("template_files", nargs="*")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.harness_api_key:
        print("No harness_api_key provided.", file=sys.stderr)
        return 1

    endpoint = normalize_endpoint(args.harness_endpoint)
    template_files = [Path(path).resolve() for path in args.template_files] if args.template_files else DEFAULT_TEMPLATE_FILES

    failures = []
    for template_path in template_files:
        if not template_path.exists():
            failures.append(f"Template file not found: {template_path}")
            continue
        try:
            result = sync_template(
                endpoint,
                args.harness_account_id,
                args.harness_org_id,
                args.harness_project_id,
                args.harness_api_key,
                template_path,
            )
            print(result)
        except Exception as error:
            failures.append(f"{template_path}: {error}")

    if failures:
        print("Template sync failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("Template sync complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
