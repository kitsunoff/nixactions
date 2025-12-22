{ pkgs, lib }:

{ vault, item }:

{
  name = "1password-load";
  deps = [ pkgs._1password ];
  
  bash = ''
    echo "→ Loading secrets from 1Password: ${vault}/${item}"
    
    # Load credentials from 1Password
    eval $(${pkgs._1password}/bin/op item get "${item}" --vault "${vault}" --format json | \
      ${pkgs.jq}/bin/jq -r '.fields[] | select(.label) | "export \(.label)=\(.value)"')
    
    echo "✓ Loaded secrets from 1Password"
  '';
}
