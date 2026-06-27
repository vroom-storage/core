#!/bin/bash
set -e

scriptdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cluster_url="http://localhost:8080"
root_access_key="${VRM_ROOT_ACCESS_KEY:-0555b35654ad1656d804}"
root_secret_key="${VRM_ROOT_SECRET_KEY:-h7GhxuBLTrlhVUyxSPUKUV8r/2EI4ngqJxD7iBdBYLhwluN30JaT3Q==}"

usage() {
    echo "Usage: $(basename "$0") [--cluster-url URL]" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cluster-url) cluster_url="$2"; shift 2 ;;
        *) usage ;;
    esac
done

echo "Checking cluster at $cluster_url..."
if ! curl -so /dev/null --max-time 5 "$cluster_url" 2>/dev/null; then
    echo "error: cluster not reachable at $cluster_url" >&2
    exit 1
fi

# Parse host, port, and scheme from the URL
if [[ "$cluster_url" =~ ^(https?)://([^/:]+)(:([0-9]+))? ]]; then
    cluster_scheme="${BASH_REMATCH[1]}"
    cluster_host="${BASH_REMATCH[2]}"
    cluster_port="${BASH_REMATCH[4]}"
    if [[ -z "$cluster_port" ]]; then
        [[ "$cluster_scheme" == "https" ]] && cluster_port=443 || cluster_port=80
    fi
    [[ "$cluster_scheme" == "https" ]] && is_secure=True || is_secure=False
else
    echo "error: cannot parse cluster URL: $cluster_url" >&2
    exit 1
fi

export AWS_ACCESS_KEY_ID="$root_access_key"
export AWS_SECRET_ACCESS_KEY="$root_secret_key"
export AWS_DEFAULT_REGION="us-east-1"
aws_cmd=(aws --endpoint-url "$cluster_url" --no-verify-ssl)

create_user() {
    local username="$1"
    "${aws_cmd[@]}" iam create-user --user-name "$username" > /dev/null
    "${aws_cmd[@]}" iam create-access-key --user-name "$username"
}

echo "Creating test users..."
alt_keys=$(create_user "alt")
alt_access_key=$(jq -r '.AccessKey.AccessKeyId' <<< "$alt_keys")
alt_secret_key=$(jq -r '.AccessKey.SecretAccessKey' <<< "$alt_keys")

tenant_keys=$(create_user "tenant")
tenant_access_key=$(jq -r '.AccessKey.AccessKeyId' <<< "$tenant_keys")
tenant_secret_key=$(jq -r '.AccessKey.SecretAccessKey' <<< "$tenant_keys")

iam_keys=$(create_user "iam")
iam_access_key=$(jq -r '.AccessKey.AccessKeyId' <<< "$iam_keys")
iam_secret_key=$(jq -r '.AccessKey.SecretAccessKey' <<< "$iam_keys")

conf_file=$(mktemp /tmp/s3tests.XXXXXX.conf)
trap "rm -f $conf_file" EXIT

cat > "$conf_file" <<EOF
[DEFAULT]
host = $cluster_host
port = $cluster_port
is_secure = $is_secure
ssl_verify = False

[fixtures]
bucket prefix = yournamehere-{random}-
iam name prefix = s3-tests-
iam path prefix = /s3-tests/

[s3 main]
display_name = M. Tester
user_id = testid
email = tester@test.com
api_name = default
access_key = $root_access_key
secret_key = $root_secret_key

[s3 alt]
display_name = john.doe
email = john.doe@example.com
user_id = 56789abcdef0123456789abcdef0123456789abcdef0123456789abcdef01234
access_key = $alt_access_key
secret_key = $alt_secret_key

[s3 tenant]
display_name = testx\$tenanteduser
user_id = testx\$9876543210abcdef0123456789abcdef0123456789abcdef0123456789abcdef
access_key = $tenant_access_key
secret_key = $tenant_secret_key
email = tenanteduser@example.com
tenant = testx

[iam]
email = s3@example.com
user_id = 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
access_key = $iam_access_key
secret_key = $iam_secret_key
display_name = youruseridhere

[iam root]
access_key = AAAAAAAAAAAAAAAAAAaa
secret_key = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
user_id = RGW11111111111111111
email = account1@ceph.com

[iam alt root]
access_key = BBBBBBBBBBBBBBBBBBbb
secret_key = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
user_id = RGW22222222222222222
email = account2@ceph.com

[webidentity]
token = <access_token>
aud = <obtained after introspecting token>
sub = <obtained after introspecting token>
azp = <obtained after introspecting token>
user_token = <access token for a user, with attribute Department=[Engineering, Marketing>]
thumbprint = <obtained from x509 certificate>
kc_realm = <name of the realm>
EOF

export S3TEST_CONF="$conf_file"

deselect_args=()
skip_list="$scriptdir/s3tests_skip.txt"
if [ -f "$skip_list" ]; then
    while IFS= read -r test_id; do
        [[ -z "$test_id" || "$test_id" == \#* ]] && continue
        deselect_args+=(--deselect "$test_id")
    done < "$skip_list"
fi

(cd "$scriptdir" && pytest "s3-tests/s3tests/functional/test_s3.py" "${deselect_args[@]}")
