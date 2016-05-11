source /etc/environment

# Authorize and unseal
vault auth
vault unseal

mkdir --parents ./certs

echo "Do you want to generate certs?"
echo "WARNING: If certs have already been generated this will break existing uses!"
read -n 1 -p "(y/n)? => " -r && echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
  # Mount Root and Generate Cert
  vault mount -path pki-root pki
  vault mount-tune -max-lease-ttl=87600h pki-root
  vault write -format=json pki-root/root/generate/exported common_name="kube-ca" ttl=87600h | | tee >(jq -r .data.certificate > ca.pem) >(jq -r .data.issuing_ca > issuing_ca.pem) >(jq -r .data.private_key > ca-key.pem)

  # Mount Intermediate and set cert
  vault mount -path pki-intermediate pki
  vault mount-tune -max-lease-ttl=87600h pki-intermediate
  vault write -format=json pki-intermediate/intermediate/generate/exported common_name="kube-intermediate-ca" ip_sans="${COREOS_PRIVATE_IPV4}" ttl=87600h | tee >(jq -r .data.csr > kube-intermediate-ca.csr) >(jq -r .data.private_key > kube-intermediate-ca.pem)

  # Sign the intermediate certificate and set it
  vault write -format=json pki-root/root/sign-intermediate csr=@kube-intermediate-ca.csr ttl=8670h common_name="kube-intermediate-ca" ip_sans="${COREOS_PRIVATE_IPV4}" ttl=87600h | tee >(jq -r .data.certificate > kube-intermediate-ca.cert) >(jq -r .data.issuing_ca > kube-intermediate-ca_issuing_ca.pem)
  vault write pki-intermediate/intermediate/set-signed certificate=@kube-intermediate-ca.cert

  # Generate the roles
  vault write pki-intermediate/roles/kube-apiserver
  vault write pki-intermediate/roles/kube-worker

  echo "Do you want to cleanup the created directories on this machine?"
  read -n 1 -p "(y/n)? => " -r && echo
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    rm -rf ./certs;
  else
    echo "this machine contains a copy of the keys, you may want to clean this up!"
  fi

fi
