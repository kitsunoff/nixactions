{ pkgs, lib }:

{ itemId }:

{
  name = "bitwarden-load";
  deps = [ pkgs.bitwarden-cli pkgs.jq ];
  
  bash = ''
    echo "→ Loading secrets from Bitwarden: ${itemId}"
    
    # Load credentials from Bitwarden
    eval $(${pkgs.bitwarden-cli}/bin/bw get item ${itemId} | \
      ${pkgs.jq}/bin/jq -r '.fields[] | select(.name) | "export \(.name)=\(.value)"')
    
    echo "✓ Loaded secrets from Bitwarden"
  '';
}
