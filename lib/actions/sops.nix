{ pkgs, lib }:

{ file, format ? "yaml" }:

{
  name = "sops-load";
  deps = [ pkgs.sops pkgs.yq pkgs.jq ];
  
  bash = ''
    echo "→ Loading secrets from ${toString file}"
    
    # Export all keys from SOPS file
    ${if format == "dotenv" then ''
      # .env format - direct export
      export $(${pkgs.sops}/bin/sops -d ${toString file} | xargs)
    '' else if format == "yaml" then ''
      # YAML - convert to env vars
      eval $(${pkgs.sops}/bin/sops -d ${toString file} | ${pkgs.yq}/bin/yq -r 'to_entries | .[] | "export \(.key)=\(.value)"')
    '' else if format == "json" then ''
      # JSON - convert to env vars
      eval $(${pkgs.sops}/bin/sops -d ${toString file} | ${pkgs.jq}/bin/jq -r 'to_entries | .[] | "export \(.key)=\(.value)"')
    '' else
      throw "Unknown format: ${format}"
    }
    
    echo "✓ Loaded secrets"
  '';
}
