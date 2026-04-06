#!/usr/bin/env python3
"""
Bootstrap helper: push acm_cert_arn into the POV_Provisioner IACM workspace
template's terraform_variables so every workspace provisioned from that template
automatically receives the correct cert ARN — no manual copy needed.

Usage (called by Terraform local-exec):
  python3 update_harness_template.py \
    <harness_endpoint> <account_id> <org_id> <project_id> \
    <api_key> <template_id> <cert_arn>
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request


def harness_request(method, url, api_key, body=None):
    headers = {"x-api-key": api_key, "Content-Type": "application/json"}
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req)
        raw = resp.read()
        result = json.loads(raw) if raw else {}
        return result, resp.status
    except urllib.error.HTTPError as e:
        raw = e.read()
        print(f"HTTP {e.code} from {method} {url}", file=sys.stderr)
        print(f"Response body: {raw.decode(errors='replace')[:500]}", file=sys.stderr)
        try:
            return json.loads(raw), e.code
        except json.JSONDecodeError:
            return {"raw": raw.decode(errors="replace")}, e.code


def build_var_block(key, value, value_type="string", type_label="String"):
    return (
        f"      - key: {key}\n"
        f"        value: \"{value}\"\n"
        f"        value_type: {value_type}\n"
        f"        status: manual\n"
        f"        locked: false\n"
        f"        canEditKey: true\n"
        f"        canEditValue: true\n"
        f"        canEditValueType: true\n"
        f"        canDelete: true\n"
        f"        type: {type_label}"
    )


def upsert_tf_var(yaml_str, key, value, value_type="string", type_label="String"):
    block = build_var_block(key, value, value_type=value_type, type_label=type_label)
    pattern = re.compile(
        rf'^      - (?:id: [^\n]+\n        )?key: {re.escape(key)}\n(?:        .*\n)*?(?=^      - (?:id: [^\n]+\n        )?key: |^    terraform_variable_files:)',
        re.MULTILINE,
    )

    if pattern.search(yaml_str):
        yaml_str = pattern.sub(block + "\n", yaml_str, count=1)
        print(f"Updated existing {key} → {value}")
        return yaml_str

    if "    terraform_variable_files:" not in yaml_str:
        print("ERROR: could not find insertion point in template YAML")
        sys.exit(1)

    yaml_str = yaml_str.replace(
        "    terraform_variable_files:",
        block + "\n    terraform_variable_files:",
        1,
    )
    print(f"Added {key} = {value} to template")
    return yaml_str


def main():
    if len(sys.argv) != 8:
        print("Usage: update_harness_template.py <endpoint> <account_id> <org_id> "
              "<project_id> <api_key> <template_id> <cert_arn>")
        sys.exit(1)

    endpoint, account_id, org_id, project_id, api_key, template_id, cert_arn = sys.argv[1:]

    if not api_key:
        print("No harness_api_key provided — skipping template update")
        sys.exit(0)

    base_params = (f"accountIdentifier={account_id}"
                   f"&orgIdentifier={org_id}"
                   f"&projectIdentifier={project_id}")

    # GET current template YAML
    get_url = (f"{endpoint}/template/api/templates/{template_id}"
               f"?{base_params}&versionLabel=1.0&getMetadataOnly=false")
    print(f"Fetching template {template_id}...")
    data, status = harness_request("GET", get_url, api_key)
    if status != 200:
        print(f"Failed to GET template: HTTP {status}: {data}")
        sys.exit(1)

    yaml_str = data["data"]["yaml"]

    coverage_bucket_name = os.environ.get("COVERAGE_BUCKET_NAME", "")
    coverage_bucket_region = os.environ.get("COVERAGE_BUCKET_REGION", "")
    coverage_artifact_path_prefix = os.environ.get("COVERAGE_ARTIFACT_PATH_PREFIX", "")

    yaml_str = upsert_tf_var(yaml_str, "acm_cert_arn", cert_arn)

    if coverage_bucket_name:
        yaml_str = upsert_tf_var(yaml_str, "publish_coverage_report_artifact", "true")
        yaml_str = upsert_tf_var(yaml_str, "coverage_report_artifact_bucket", coverage_bucket_name)

    if coverage_bucket_region:
        yaml_str = upsert_tf_var(yaml_str, "coverage_report_artifact_region", coverage_bucket_region)

    if coverage_artifact_path_prefix:
        yaml_str = upsert_tf_var(yaml_str, "coverage_report_artifact_path_prefix", coverage_artifact_path_prefix)

    # Verify the YAML looks sane
    if "key: acm_cert_arn" not in yaml_str:
        print("ERROR: acm_cert_arn not found in YAML after modification")
        sys.exit(1)
    print(f"YAML snippet around managed variables:")
    for i, line in enumerate(yaml_str.splitlines()):
        if any(key in line for key in [
            "acm_cert_arn",
            "publish_coverage_report_artifact",
            "coverage_report_artifact_bucket",
            "coverage_report_artifact_region",
            "coverage_report_artifact_path_prefix",
        ]):
            print(f"  {line}")

    # Try several known Harness template update endpoint variants
    candidate_urls = [
        (f"{endpoint}/template/api/templates/{template_id}"
         f"?{base_params}&versionLabel=1.0&isStableTemplate=true"),
        (f"{endpoint}/template/api/templates/update/{template_id}"
         f"?{base_params}&versionLabel=1.0&isStableTemplate=true"),
        (f"{endpoint}/v1/orgs/{org_id}/projects/{project_id}/templates/{template_id}"
         f"?version=1.0&is_stable=true"),
    ]

    succeeded = False
    for put_url in candidate_urls:
        print(f"Trying PUT: {put_url}")
        hdrs_json = {"x-api-key": api_key, "Content-Type": "application/json",
                     "Harness-Account": account_id}
        hdrs_yaml = {"x-api-key": api_key, "Content-Type": "application/yaml",
                     "Harness-Account": account_id}
        for hdrs, body_data in [
            (hdrs_json, json.dumps({"yaml": yaml_str, "isNewTemplate": False}).encode()),
            (hdrs_yaml, yaml_str.encode()),
        ]:
            req = urllib.request.Request(put_url, data=body_data, headers=hdrs, method="PUT")
            try:
                resp = urllib.request.urlopen(req)
                if resp.status in (200, 201):
                    print(f"Template updated successfully via {put_url} (HTTP {resp.status})")
                    succeeded = True
                    break
            except urllib.error.HTTPError as e:
                raw = e.read()
                print(f"  HTTP {e.code}: {raw.decode(errors='replace')[:200]}", file=sys.stderr)
        if succeeded:
            break

    if not succeeded:
        print(
            "\nWARNING: Could not auto-update the Harness template via REST API.\n"
            f"The template '{template_id}' must be updated manually.\n"
            f"Add this terraform variable:\n"
            f"  key: acm_cert_arn\n"
            f"  value: {cert_arn}\n"
            f"  value_type: string\n"
            "Or re-run: python3 update_harness_template.py ... (see SETUP.md)\n",
            file=sys.stderr,
        )
        sys.exit(0)  # Non-fatal — tofu apply should still succeed


if __name__ == "__main__":
    main()
