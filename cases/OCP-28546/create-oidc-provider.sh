#!/bin/bash
set -ex

export S3_BUCKET=xxia-oidc-provider
export AWS_REGION=ap-northeast-1

PKCS_KEY="sa-signer.pub"
oc get cm bound-sa-token-signing-certs -n openshift-kube-apiserver -o jsonpath="{.data.service-account-001\.pub}" > $PKCS_KEY
# Create the bucket if it doesn't exist
_bucket_name=$(aws s3api list-buckets  --query "Buckets[?Name=='$S3_BUCKET'].Name | [0]" --out text)
if [ $_bucket_name == "None" ]; then
    aws s3api create-bucket --bucket $S3_BUCKET --create-bucket-configuration LocationConstraint=$AWS_REGION
fi
echo "export S3_BUCKET=$S3_BUCKET"
export HOSTNAME=s3-$AWS_REGION.amazonaws.com
export ISSUER_HOSTPATH=$HOSTNAME/$S3_BUCKET

cat <<EOF > discovery.json
{
    "issuer": "https://$ISSUER_HOSTPATH/",
    "jwks_uri": "https://$ISSUER_HOSTPATH/keys.json",
    "authorization_endpoint": "urn:kubernetes:programmatic_authorization",
    "response_types_supported": [
        "id_token"
    ],
    "subject_types_supported": [
        "public"
    ],
    "id_token_signing_alg_values_supported": [
        "RS256"
    ],
    "claims_supported": [
        "sub",
        "iss"
    ]
}
EOF

self-hosted -key $PKCS_KEY  | jq '.keys += [.keys[0]] | .keys[1].kid = ""' > keys.json

aws s3 cp --acl public-read ./discovery.json s3://$S3_BUCKET/.well-known/openid-configuration
aws s3 cp --acl public-read ./keys.json s3://$S3_BUCKET/keys.json

sleep 10 # need wait a moment
curl https://$ISSUER_HOSTPATH/.well-known/openid-configuration
curl https://$ISSUER_HOSTPATH/keys.json
