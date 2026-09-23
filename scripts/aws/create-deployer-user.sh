#!/usr/bin/env bash
set -euo pipefail

export AWS_PAGER=""

policy_file="${1:-./maplebridge-deployer-policy.json}"
user_name="${MAPLEBRIDGE_IAM_USER:-maplebridge-deployer}"
policy_name="${MAPLEBRIDGE_IAM_POLICY:-MapleBridgeDeployer}"
credential_file="${HOME}/maplebridge-access-key.json"

if [[ ! -f "${policy_file}" ]]; then
  echo "Policy file not found: ${policy_file}" >&2
  exit 2
fi

if [[ ! "${user_name}" =~ ^[A-Za-z0-9+=,.@_-]{1,64}$ ]]; then
  echo "Invalid IAM user name: ${user_name}" >&2
  exit 2
fi

account_id="$(aws sts get-caller-identity --query Account --output text)"
policy_arn="arn:aws:iam::${account_id}:policy/${policy_name}"

if ! aws iam get-user --user-name "${user_name}" >/dev/null 2>&1; then
  aws iam create-user \
    --user-name "${user_name}" \
    --path /maplebridge/ \
    --tags Key=Project,Value=MapleBridge >/dev/null
  echo "Created IAM user ${user_name}."
else
  echo "IAM user ${user_name} already exists."
fi

if ! aws iam get-policy --policy-arn "${policy_arn}" >/dev/null 2>&1; then
  aws iam create-policy \
    --policy-name "${policy_name}" \
    --description "Deployment and operations permissions for MapleBridge" \
    --policy-document "file://${policy_file}" \
    --tags Key=Project,Value=MapleBridge >/dev/null
  echo "Created customer managed policy ${policy_name}."
else
  mapfile -t old_versions < <(
    aws iam list-policy-versions \
      --policy-arn "${policy_arn}" \
      --query 'sort_by(Versions[?IsDefaultVersion==`false`], &CreateDate)[].VersionId' \
      --output text | tr '\t' '\n' | sed '/^$/d'
  )

  total_versions="$(( ${#old_versions[@]} + 1 ))"
  while (( total_versions >= 5 )); do
    aws iam delete-policy-version \
      --policy-arn "${policy_arn}" \
      --version-id "${old_versions[0]}"
    old_versions=("${old_versions[@]:1}")
    total_versions="$((total_versions - 1))"
  done

  aws iam create-policy-version \
    --policy-arn "${policy_arn}" \
    --policy-document "file://${policy_file}" \
    --set-as-default >/dev/null
  echo "Updated customer managed policy ${policy_name}."
fi

aws iam attach-user-policy \
  --user-name "${user_name}" \
  --policy-arn "${policy_arn}"
echo "Attached ${policy_name} to ${user_name}."

key_count="$(aws iam list-access-keys --user-name "${user_name}" --query 'length(AccessKeyMetadata)' --output text)"
if (( key_count > 0 )); then
  echo "No key was created because ${user_name} already has ${key_count} access key(s)." >&2
  echo "Use an existing key or explicitly remove/rotate it before rerunning this script." >&2
  exit 4
fi

if [[ -e "${credential_file}" ]]; then
  echo "Refusing to overwrite ${credential_file}. Move or securely remove it first." >&2
  exit 3
fi

temporary_file="$(mktemp "${HOME}/maplebridge-access-key.XXXXXX")"
trap 'rm -f "${temporary_file}"' EXIT
chmod 600 "${temporary_file}"
aws iam create-access-key --user-name "${user_name}" > "${temporary_file}"
mv "${temporary_file}" "${credential_file}"
trap - EXIT

echo "Created one access key and wrote it to ${credential_file} with mode 600."
echo "The secret was not printed. Download the file, configure the local profile, then securely delete both copies."
