from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
PIPELINE_PATH = ROOT / ".harness/pipelines/idp_pov_provisioner.yaml"
TEMPLATE_PATH = ROOT / ".harness/templates/project_factory_workspace.yaml"
STACK_VARS_PATH = ROOT / "tofu/stacks/project-factory/variables.tf"
POV_WORKFLOW_PATH = ROOT / ".harness/workflows/pov_provisioner_workflow.yaml"
SE_WORKFLOW_PATH = ROOT / ".harness/workflows/se_sandbox_provisioner.yaml"
EKS_TEMPLATE_PATH = ROOT / ".harness/templates/pov_provisioner_eks_workspace.yaml"
ASG_TEMPLATE_PATH = ROOT / ".harness/templates/sandbox_provisioner_asg_workspace.yaml"

SURFACED_CONTRACT = [
    ("shared_delegate_selector", "project_factory_delegate_selector"),
    ("create_shared_aws_connector", "create_project_shared_aws_connector"),
    ("shared_aws_connector_id", "project_factory_aws_connector_id"),
    ("shared_aws_connector_name", "project_factory_aws_connector_name"),
    ("shared_aws_region", "project_factory_aws_region"),
    ("shared_aws_auth_type", "project_factory_aws_auth_type"),
    ("shared_aws_access_key_ref", "project_factory_aws_access_key_ref"),
    ("shared_aws_secret_key_ref", "project_factory_aws_secret_key_ref"),
    ("shared_enable_cross_account_access", "project_factory_enable_cross_account_access"),
    ("shared_cross_account_role_arn", "project_factory_cross_account_role_arn"),
    ("shared_cross_account_external_id", "project_factory_cross_account_external_id"),
    ("create_shared_github_connector", "create_project_shared_github_connector"),
    ("shared_github_connector_id", "project_factory_github_connector_id"),
    ("shared_github_connector_name", "project_factory_github_connector_name"),
    ("shared_github_url", "project_factory_github_url"),
    ("shared_github_connection_type", "project_factory_github_connection_type"),
    ("shared_github_validation_repo", "project_factory_github_validation_repo"),
    ("shared_github_token_ref", "project_factory_github_token_ref"),
    ("shared_github_username", "project_factory_github_username"),
]

WORKFLOW_SURFACED_INPUTS = [
    "create_project_factory",
    "project_factory_github_token_ref",
    "project_factory_aws_access_key_ref",
    "project_factory_aws_secret_key_ref",
]

REQUIRED_PROJECT_FACTORY_STEP_IDENTIFIERS = [
    "check_project_factory_workspace_exists",
    "create_project_factory_workspace",
    "link_project_factory_workspace_template",
    "reconcile_project_factory_workspace_variables",
]

REQUIRED_TEMPLATE_PREFLIGHT_STEP_IDENTIFIER = "verify_required_workspace_templates"

GOVERNANCE_WORKFLOW_INPUTS = [
    "create_opa_policies",
    "enable_change_governance",
]

INTENTIONALLY_UNSURFACED_STACK_VARS = {
    "shared_aws_connector_description",
}


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def extract_hcl_variable_names(text: str) -> set[str]:
    return set(re.findall(r'variable\s+"([^"]+)"\s*\{', text))


def has_pipeline_input(text: str, name: str) -> bool:
    return re.search(rf'^\s+- name: {re.escape(name)}\s*$', text, re.MULTILINE) is not None


def has_template_binding(text: str, stack_var: str, pipeline_var: str) -> bool:
    anchor = text.find(f"- key: {stack_var}")
    if anchor == -1:
        return False
    window = text[anchor:anchor + 260]
    return f"value: <+pipeline.variables.{pipeline_var}>" in window


def has_create_workspace_binding(text: str, stack_var: str, pipeline_var: str) -> bool:
    anchor = text.find(f'"{stack_var}": {{')
    if anchor == -1:
        return False
    window = text[anchor:anchor + 280]
    return f'"value": "<+pipeline.variables.{pipeline_var}>"' in window


def has_reconcile_binding(text: str, stack_var: str, pipeline_var: str) -> bool:
    line = f'update_tf_var "{stack_var}" "<+pipeline.variables.{pipeline_var}>" "string"'
    return line in text


def has_workflow_parameter(text: str, name: str) -> bool:
    return f"        {name}:" in text


def has_workflow_inputset_binding(text: str, name: str) -> bool:
    return f"          {name}: ${{{{ parameters.{name} }}}}" in text


def get_step_window(text: str, identifier: str, window: int = 5000) -> str:
    anchor = text.find(f"identifier: {identifier}")
    if anchor == -1:
        return ""
    start = max(0, anchor - 200)
    next_step = text.find("\n              - step:", anchor + 1)
    next_stage = text.find("\n    - stage:", anchor + 1)

    candidates = [position for position in (next_step, next_stage) if position != -1]
    if candidates:
        end = min(candidates)
    else:
        end = min(len(text), anchor + window)

    return text[start:end]


def step_contains(text: str, identifier: str, expected: str) -> bool:
    return expected in get_step_window(text, identifier)


def count_matches(text: str, pattern: str) -> int:
    return len(re.findall(pattern, text, re.DOTALL))


def has_literal_template_binding(text: str, key: str, value: str) -> bool:
    anchor = text.find(f"- key: {key}")
    if anchor == -1:
        return False
    window = text[anchor:anchor + 220]
    return f"value: {value}" in window


def main() -> int:
    pipeline_text = read_text(PIPELINE_PATH)
    template_text = read_text(TEMPLATE_PATH)
    stack_vars_text = read_text(STACK_VARS_PATH)
    pov_workflow_text = read_text(POV_WORKFLOW_PATH)
    se_workflow_text = read_text(SE_WORKFLOW_PATH)
    eks_template_text = read_text(EKS_TEMPLATE_PATH)
    asg_template_text = read_text(ASG_TEMPLATE_PATH)

    stack_vars = extract_hcl_variable_names(stack_vars_text)
    surfaced_stack_vars = {stack_var for stack_var, _ in SURFACED_CONTRACT}
    candidate_stack_vars = {
        name
        for name in stack_vars
        if name.startswith("shared_") or name.startswith("create_shared_")
    }

    errors: list[str] = []

    for stack_var, pipeline_var in SURFACED_CONTRACT:
        if stack_var not in stack_vars:
            errors.append(f"Stack variable missing: {stack_var}")
        if not has_pipeline_input(pipeline_text, pipeline_var):
            errors.append(f"Pipeline input missing: {pipeline_var}")
        if not has_template_binding(template_text, stack_var, pipeline_var):
            errors.append(f"Template binding missing: {stack_var} <- {pipeline_var}")
        if not has_reconcile_binding(pipeline_text, stack_var, pipeline_var):
            errors.append(f"Project-factory reconcile binding missing: {stack_var} <- {pipeline_var}")

    if not has_pipeline_input(pipeline_text, "create_project_factory"):
        errors.append("Pipeline input missing: create_project_factory")

    if f"identifier: {REQUIRED_TEMPLATE_PREFLIGHT_STEP_IDENTIFIER}" not in pipeline_text:
        errors.append("Required template preflight step missing: verify_required_workspace_templates")

    for identifier in REQUIRED_PROJECT_FACTORY_STEP_IDENTIFIERS:
        if f"identifier: {identifier}" not in pipeline_text:
            errors.append(f"Project-factory lifecycle step missing: {identifier}")

    if not step_contains(
        pipeline_text,
        "verify_required_workspace_templates",
        'verify_template "$TARGET_TEMPLATE_ID"',
    ):
        errors.append("Template preflight step does not verify the target workload workspace template")

    if not step_contains(
        pipeline_text,
        "verify_required_workspace_templates",
        'verify_template "Project_Governance"',
    ):
        errors.append("Template preflight step does not verify Project_Governance when governance bootstrap is enabled")

    if not step_contains(
        pipeline_text,
        "verify_required_workspace_templates",
        'verify_template "Project_Factory"',
    ):
        errors.append("Template preflight step does not verify Project_Factory when project factory bootstrap is enabled")

    if not step_contains(
        pipeline_text,
        "verify_required_workspace_templates",
        '/template/api/templates/${template_id}?accountIdentifier=${ACCOUNT_ID}&orgIdentifier=${ORG_ID}&projectIdentifier=${PROJECT_ID}&versionLabel=1.0&getMetadataOnly=true',
    ):
        errors.append("Template preflight step is not pinned to the expected Harness template GET endpoint")

    if not step_contains(
        pipeline_text,
        "create_project_factory_workspace",
        '"repository_path": "tofu/stacks/project-factory"',
    ):
        errors.append("Project-factory create step is not pinned to repository_path=tofu/stacks/project-factory")

    if not step_contains(
        pipeline_text,
        "create_project_factory_workspace",
        '"identifier": "<+pipeline.variables.harness_project_id>_factory"',
    ):
        errors.append("Project-factory create step is not pinned to the expected workspace identifier")

    if not step_contains(
        pipeline_text,
        "link_project_factory_workspace_template",
        '"template_id": "Project_Factory"',
    ):
        errors.append("Project-factory template link step is not pinned to template_id=Project_Factory")

    if not step_contains(
        pipeline_text,
        "link_project_factory_workspace_template",
        '"workspace_id": "<+pipeline.variables.harness_project_id>_factory"',
    ):
        errors.append("Project-factory template link step is not pinned to the expected workspace identifier")

    if step_contains(
        pipeline_text,
        "link_project_factory_workspace_template",
        "type: MarkAsSuccess",
    ):
        errors.append("Project-factory template link step still masks all linkage failures with MarkAsSuccess")

    if step_contains(
        pipeline_text,
        "link_governance_workspace_template",
        "type: MarkAsSuccess",
    ):
        errors.append("Governance template link step still masks all linkage failures with MarkAsSuccess")

    if step_contains(
        pipeline_text,
        "link_workspace_template",
        "type: MarkAsSuccess",
    ):
        errors.append("EKS workload template link step still masks all linkage failures with MarkAsSuccess")

    if step_contains(
        pipeline_text,
        "link_workspace_template_asg",
        "type: MarkAsSuccess",
    ):
        errors.append("ASG workload template link step still masks all linkage failures with MarkAsSuccess")

    if not step_contains(
        pipeline_text,
        "resolve_shared_connector_refs",
        'RESOLVED_SHARED_AWS_CONNECTOR_REF="${PROJECT_ID}_aws_reference_architecture"',
    ):
        errors.append("Shared connector resolution no longer falls back to the predictable project-factory AWS connector ID")

    if not step_contains(
        pipeline_text,
        "resolve_shared_connector_refs",
        'RESOLVED_SHARED_GITHUB_CONNECTOR_REF="${PROJECT_ID}_github_reference_architecture"',
    ):
        errors.append("Shared connector resolution no longer falls back to the predictable project-factory GitHub connector ID")

    unexpected_stack_vars = sorted(candidate_stack_vars - surfaced_stack_vars - INTENTIONALLY_UNSURFACED_STACK_VARS)
    if unexpected_stack_vars:
        errors.append(
            "New project-factory stack variables need an explicit control-plane decision: "
            + ", ".join(unexpected_stack_vars)
        )

    for workflow_name, workflow_text in (("pov_provisioner_workflow", pov_workflow_text), ("se_sandbox_provisioner", se_workflow_text)):
        for name in WORKFLOW_SURFACED_INPUTS:
            if not has_workflow_parameter(workflow_text, name):
                errors.append(f"Workflow parameter missing in {workflow_name}: {name}")
            if not has_workflow_inputset_binding(workflow_text, name):
                errors.append(f"Workflow inputset binding missing in {workflow_name}: {name}")
        for name in GOVERNANCE_WORKFLOW_INPUTS:
            if not has_workflow_parameter(workflow_text, name):
                errors.append(f"Governance workflow parameter missing in {workflow_name}: {name}")
            if not has_workflow_inputset_binding(workflow_text, name):
                errors.append(f"Governance workflow inputset binding missing in {workflow_name}: {name}")

    if not has_pipeline_input(pipeline_text, "enable_change_governance"):
        errors.append("Pipeline input missing: enable_change_governance")

    if 'value: <+input>.default(har).allowedValues(har)' not in pipeline_text:
        errors.append("Pipeline input artifact_registry_type is not locked to HAR-only")

    if 'value: <+input>.default(true).allowedValues(true)' not in pipeline_text:
        errors.append("Pipeline input create_dockerhub_upstream is not locked to true-only")

    if not has_template_binding(eks_template_text, "enable_change_governance", "enable_change_governance"):
        errors.append("EKS template binding missing: enable_change_governance <- enable_change_governance")

    if not has_template_binding(asg_template_text, "enable_change_governance", "enable_change_governance"):
        errors.append("ASG template binding missing: enable_change_governance <- enable_change_governance")

    if not has_literal_template_binding(eks_template_text, "artifact_registry_type", "har"):
        errors.append("EKS template is not locked to artifact_registry_type=har")

    if not has_literal_template_binding(eks_template_text, "create_dockerhub_upstream", '"true"'):
        errors.append("EKS template is not locked to create_dockerhub_upstream=true")

    if not has_literal_template_binding(asg_template_text, "artifact_registry_type", "har"):
        errors.append("ASG template is not locked to artifact_registry_type=har")

    if not has_literal_template_binding(asg_template_text, "create_dockerhub_upstream", '"true"'):
        errors.append("ASG template is not locked to create_dockerhub_upstream=true")

    if not has_literal_template_binding(eks_template_text, "use_harness_code", '"true"'):
        errors.append("EKS template is not locked to use_harness_code=true")

    if not has_literal_template_binding(asg_template_text, "use_harness_code", '"true"'):
        errors.append("ASG template is not locked to use_harness_code=true")

    har_payload_matches = count_matches(
        pipeline_text,
        r'"artifact_registry_type"\s*:\s*\{[^}]*"value"\s*:\s*"har"',
    )
    if har_payload_matches < 2:
        errors.append(f"Expected HAR to be stamped in all EKS create/recreate payloads, found {har_payload_matches} bindings")

    dockerhub_payload_matches = count_matches(
        pipeline_text,
        r'"create_dockerhub_upstream"\s*:\s*\{[^}]*"value"\s*:\s*"true"',
    )
    if dockerhub_payload_matches < 2:
        errors.append(
            f"Expected create_dockerhub_upstream=true to be stamped in all EKS create/recreate payloads, found {dockerhub_payload_matches} bindings"
        )

    if '<+pipeline.variables.artifact_registry_type>' in pipeline_text and '"artifact_registry_type"' in pipeline_text:
        errors.append("Legacy artifact registry pipeline binding remains in a workload payload or status message")

    if '<+pipeline.variables.create_dockerhub_upstream>' in pipeline_text:
        errors.append("Legacy DockerHub upstream pipeline binding remains in a workload payload or status message")

    governance_payload_matches = count_matches(
        pipeline_text,
        r'"enable_change_governance"\s*:\s*\{[^}]*"value"\s*:\s*"<\+pipeline\.variables\.enable_change_governance>"',
    )
    if governance_payload_matches < 4:
        errors.append(
            f"Expected enable_change_governance to be passed in all workload create/recreate payloads, found {governance_payload_matches} bindings"
        )

    legacy_governance_payload_matches = count_matches(
        pipeline_text,
        r'"enable_change_governance"\s*:\s*\{[^}]*"value"\s*:\s*"<\+pipeline\.variables\.create_opa_policies>"',
    )
    if legacy_governance_payload_matches != 0:
        errors.append("Legacy governance coupling remains: enable_change_governance still references create_opa_policies in a workload payload")

    reconcile_matches = count_matches(
        pipeline_text,
        r'update_tf_var "enable_change_governance" "\$ENABLE_CHANGE_GOVERNANCE" "string"',
    )
    if reconcile_matches < 2:
        errors.append(f"Expected enable_change_governance reconcile updates for both workload targets, found {reconcile_matches}")

    if errors:
        print("Provisioner contract validation failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print("Provisioner contract validation passed.")
    print(
        f"Validated {len(SURFACED_CONTRACT)} surfaced project-factory stack variables, "
        f"{len(WORKFLOW_SURFACED_INPUTS)} project-factory workflow inputs, and "
        f"{len(GOVERNANCE_WORKFLOW_INPUTS)} governance workflow inputs."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
