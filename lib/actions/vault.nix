{ pkgs, lib }:

{ path, addr ? "$VAULT_ADDR", token ? null }:

{
  name = "vault-load";
  deps = [ pkgs.vault pkgs.jq ];
  
  bash = ''
    echo "→ Loading secrets from Vault: ${path}"
    
    export VAULT_ADDR="${addr}"
    ${if token != null then ''
      export VAULT_TOKEN="${token}"
    '' else ""}
    
    # Read secrets and export as env vars
    ${pkgs.vault}/bin/vault kv get -format=json ${path} | \
      ${pkgs.jq}/bin/jq -r '.data.data | to_entries | .[] | "export \(.key)=\(.value)"' | \
      while IFS= read -r line; do
        eval "$line"
      done
    
    echo "✓ Loaded secrets from Vault"
  '';
}
